#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

<<comment
    This script configures the firewall to allow only specified IP subnets.
    
    The script installs ufw and configures the firewall to allow only specified IP subnets.
    It automatically detects local network subnets and allows the user to configure access.
    
    This script requires root privileges. Please run as root.

    Command Line Usage:
        - Interactive mode:
            sudo ./firewall-setup.sh
        - Auto mode (allows all local subnets):
            sudo ./firewall-setup.sh -y
        - Custom subnet configuration:
            sudo ./firewall-setup.sh --subnet=192.168.1.0/24

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added common library, improved subnet detection, and security enhancements
comment

# Initialize common functionality
init_common "firewall-setup"

# System checks
check_debian
check_root

# Parse arguments
CUSTOM_SUBNETS=()
for arg in "$@"; do
    case $arg in
        --subnet=*)
            CUSTOM_SUBNETS+=("${arg#*=}")
            ;;
        *)
            # Let common library handle other args
            ;;
    esac
done

if ! parse_common_args "$@"; then
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
fi

# Validate subnet format
validate_subnet() {
    local subnet="$1"
    
    # Check for CIDR notation (e.g., 192.168.1.0/24)
    if [[ $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    
    # Check for simple subnet (e.g., 192.168.1.0)
    if [[ $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    
    log_error "Invalid subnet format: $subnet"
    return 1
}

# Get local network subnets
get_local_subnets() {
    local subnets=()
    
    log_info "Detecting local network subnets..."
    
    # Get all IPv4 addresses except localhost and docker
    while read -r ip interface; do
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            # Extract network address
            local network_addr
            network_addr=$(ip route | grep "$interface" | grep -E "proto kernel" | awk '{print $1}' | head -1)
            
            if [[ -n "$network_addr" && ! " ${subnets[*]} " =~ " ${network_addr} " ]]; then
                subnets+=("$network_addr")
                log_debug "Found subnet: $network_addr on interface $interface"
            fi
        fi
    done < <(ip addr show | grep "inet " | grep -v "127.0.0.1" | grep -v "docker" | awk '{print $2, $NF}')
    
    printf '%s\n' "${subnets[@]}"
}

# Check if UFW rule already exists
rule_exists() {
    local subnet="$1"
    
    if ufw status numbered | grep -q "ALLOW.*$subnet"; then
        return 0
    fi
    return 1
}

# Install and configure UFW
install_ufw() {
    log_info "Installing UFW (Uncomplicated Firewall)..."
    
    # Update package cache and install UFW
    update_package_cache || {
        log_error "Failed to update package cache"
        return 1
    }
    
    install_package "ufw" "UFW firewall" || {
        log_error "Failed to install UFW"
        return 1
    }
    
    log_info "UFW installed successfully"
}

# Configure basic firewall rules
configure_basic_rules() {
    log_info "Configuring basic firewall rules..."
    
    # Set default policies
    ufw --force default deny incoming || {
        log_error "Failed to set default deny incoming"
        return 1
    }
    
    ufw --force default allow outgoing || {
        log_error "Failed to set default allow outgoing"
        return 1
    }
    
    # Allow localhost
    ufw allow in on lo || {
        log_warn "Failed to allow localhost traffic"
    }
    
    log_info "Basic firewall rules configured"
}

# Add subnet rule
add_subnet_rule() {
    local subnet="$1"
    local description="${2:-Custom subnet}"
    
    if rule_exists "$subnet"; then
        log_info "Rule for subnet $subnet already exists, skipping"
        return 0
    fi
    
    log_info "Adding firewall rule for subnet: $subnet"
    
    if ufw allow from "$subnet" comment "$description"; then
        log_info "Successfully added rule for subnet: $subnet"
        return 0
    else
        log_error "Failed to add rule for subnet: $subnet"
        return 1
    fi
}

# Show current firewall status
show_firewall_status() {
    log_info "Current firewall status:"
    echo "=================================="
    ufw status numbered
    echo "=================================="
}

# Configure subnet access
configure_subnet_access() {
    local subnets_to_configure=()
    
    # Use custom subnets if provided
    if [[ ${#CUSTOM_SUBNETS[@]} -gt 0 ]]; then
        log_info "Using custom subnets from command line"
        for subnet in "${CUSTOM_SUBNETS[@]}"; do
            if validate_subnet "$subnet"; then
                subnets_to_configure+=("$subnet")
            else
                log_error "Invalid custom subnet: $subnet"
                return 1
            fi
        done
    else
        # Auto-detect local subnets
        log_info "Auto-detecting local network subnets..."
        local detected_subnets
        mapfile -t detected_subnets < <(get_local_subnets)
        
        if [[ ${#detected_subnets[@]} -eq 0 ]]; then
            log_warn "No local subnets detected"
            if [[ "$AUTO_INSTALL" != "true" ]]; then
                read -p "Enter subnet manually (e.g., 192.168.1.0/24): " manual_subnet
                if [[ -n "$manual_subnet" ]] && validate_subnet "$manual_subnet"; then
                    subnets_to_configure+=("$manual_subnet")
                fi
            fi
        else
            log_info "Detected ${#detected_subnets[@]} local subnet(s)"
            
            if [[ "$AUTO_INSTALL" == "true" ]]; then
                # In auto mode, add all detected subnets
                subnets_to_configure=("${detected_subnets[@]}")
                log_info "Auto mode: Adding all detected subnets"
            else
                # Interactive mode: ask for each subnet
                for subnet in "${detected_subnets[@]}"; do
                    echo
                    log_info "Found subnet: $subnet"
                    if prompt_yes_no "Allow access from subnet $subnet?" "y"; then
                        subnets_to_configure+=("$subnet")
                    fi
                done
            fi
        fi
    fi
    
    # Add the subnet rules
    if [[ ${#subnets_to_configure[@]} -eq 0 ]]; then
        log_warn "No subnets to configure"
        return 0
    fi
    
    log_info "Configuring ${#subnets_to_configure[@]} subnet rule(s)..."
    
    for subnet in "${subnets_to_configure[@]}"; do
        add_subnet_rule "$subnet" "Local network access" || {
            log_error "Failed to add rule for $subnet"
            return 1
        }
    done
    
    log_info "Subnet configuration completed"
}

# Enable firewall
enable_firewall() {
    log_info "Enabling UFW firewall..."
    
    # Check if we're in an SSH session
    if [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]]; then
        log_warn "SSH session detected - ensuring SSH access before enabling firewall"
        
        # Get SSH client IP
        local ssh_client_ip
        ssh_client_ip=$(echo "${SSH_CLIENT}" | awk '{print $1}')
        
        if [[ -n "$ssh_client_ip" ]]; then
            log_info "Adding SSH access rule for your IP: $ssh_client_ip"
            ufw allow from "$ssh_client_ip" to any port 22 comment "SSH access for installer"
        fi
        
        # Also allow SSH port in general (limited by subnet rules)
        ufw allow ssh comment "SSH service"
    fi
    
    if ufw --force enable; then
        log_info "Firewall enabled successfully"
        return 0
    else
        log_error "Failed to enable firewall"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting firewall setup configuration..."
    
    # Install UFW
    install_ufw || report_failure "UFW installation"
    
    # Configure basic rules
    configure_basic_rules || report_failure "Basic firewall rules configuration"
    
    # Configure subnet access
    configure_subnet_access || report_failure "Subnet access configuration"
    
    # Enable firewall
    enable_firewall || report_failure "Firewall activation"
    
    # Show final status
    show_firewall_status
    
    report_success "Firewall setup configuration"
    
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        echo
        echo "Firewall configuration completed!"
        echo "- Default policy: Deny incoming, Allow outgoing"
        echo "- Configured subnets have been allowed access"
        echo "- Firewall is now active and monitoring"
        echo
        echo "To modify firewall rules later, use: sudo ufw status numbered"
        echo "To disable firewall: sudo ufw disable"
        echo
    fi
}

# Run main function
main