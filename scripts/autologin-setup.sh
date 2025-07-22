#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

<<comment
    This script sets up autologin for a user on tty1.

    The script creates a user if it does not exist, sets up autologin for the user on tty1, 
    and updates the number of virtual terminals in logind.conf.

    This script requires root privileges. Please run as root.

    Command line usage:
        - To set up autologin for a specific user:
            sudo ./autologin-setup.sh --username=<username>
        - Auto mode:
            sudo ./autologin-setup.sh -y --username=<username>

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added common library, improved error handling, and security enhancements
comment

# Initialize common functionality
init_common "autologin-setup"

# System checks
check_debian
check_root

# Parse arguments
if ! parse_common_args "$@"; then
    case $? in
        2) exit 0 ;;  # Help was shown
        *) exit 1 ;;  # Parse error
    esac
fi

get_username() {
    if [[ -n "$USERNAME" ]]; then
        echo "$USERNAME"
        return 0
    fi
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log_error "Auto mode requires --username parameter"
        exit 1
    fi
    
    while true; do
        read -p "Enter the username for autologin: " username
        
        if validate_username "$username"; then
            echo "$username"
            return 0
        fi
        
        echo "Please try again with a valid username."
    done
}

create_systemd_override() {
    local tty="$1"
    local username="$2"
    local service_dir="/etc/systemd/system/getty@${tty}.service.d"
    local override_file="$service_dir/override.conf"
    
    log_info "Creating systemd override for $tty with user: $username"
    
    # Backup existing override if it exists
    if [[ -f "$override_file" ]]; then
        backup_file "$override_file"
    fi
    
    # Create service directory
    mkdir -p "$service_dir" || {
        log_error "Failed to create directory: $service_dir"
        return 1
    }
    
    # Create override configuration
    cat > "$override_file" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $username --noclear %I \$TERM
EOF
    
    log_info "Created systemd override: $override_file"
}

setup_tty1() {
    local username
    username=$(get_username)
    
    log_info "Setting up autologin for $username on tty1..."
    
    # Create user if needed
    create_user_if_not_exists "$username" || {
        log_error "Failed to create user: $username"
        return 1
    }
    
    # Create systemd override for tty1
    create_systemd_override "tty1" "$username" || {
        log_error "Failed to create systemd override for tty1"
        return 1
    }
    
    # Download and setup browser autologin profile
    local profile_file="/home/$username/.bash_profile"
    local temp_file="$TEMP_DIR/browser_profile"
    
    download_file "$GITHUB_BASE_URL/autologin/browser" "$temp_file" "browser autologin profile" || {
        log_error "Failed to download browser autologin profile"
        return 1
    }
    
    # Backup existing profile if it exists
    if [[ -f "$profile_file" ]]; then
        backup_file "$profile_file"
    fi
    
    # Install the profile
    cp "$temp_file" "$profile_file"
    chown "$username:$username" "$profile_file"
    chmod 644 "$profile_file"
    
    # Create .hushlogin to suppress login messages
    local hushlogin_file="/home/$username/.hushlogin"
    touch "$hushlogin_file"
    chown "$username:$username" "$hushlogin_file"
    chmod 644 "$hushlogin_file"
    
    log_info "Browser autologin setup completed for $username"
}

setup_tty2() {
    log_info "Setting up autologin for root on tty2 (menu access)..."
    
    # Create systemd override for tty2
    create_systemd_override "tty2" "root" || {
        log_error "Failed to create systemd override for tty2"
        return 1
    }
    
    # Download and setup menu autologin profile
    local profile_file="/root/.bash_profile"
    local temp_file="$TEMP_DIR/menu_profile"
    
    download_file "$GITHUB_BASE_URL/autologin/menu" "$temp_file" "menu autologin profile" || {
        log_error "Failed to download menu autologin profile"
        return 1
    }
    
    # Backup existing profile if it exists
    if [[ -f "$profile_file" ]]; then
        backup_file "$profile_file"
    fi
    
    # Install the profile
    cp "$temp_file" "$profile_file"
    chmod 644 "$profile_file"
    
    log_info "Menu autologin setup completed for root"
}

configure_virtual_terminals() {
    local logind_conf="/etc/systemd/logind.conf"
    local backup_conf
    
    log_info "Configuring virtual terminals..."
    
    # Backup logind.conf
    backup_conf=$(backup_file "$logind_conf")
    
    # Update NAutoVTs setting
    if grep -q "^#NAutoVTs=" "$logind_conf"; then
        sed -i 's/^#NAutoVTs=.*/NAutoVTs=2/' "$logind_conf"
    elif grep -q "^NAutoVTs=" "$logind_conf"; then
        sed -i 's/^NAutoVTs=.*/NAutoVTs=2/' "$logind_conf"
    else
        echo "NAutoVTs=2" >> "$logind_conf"
    fi
    
    log_info "Virtual terminals configured (limited to 2)"
}

reload_systemd_and_restart_getty() {
    log_info "Reloading systemd and restarting getty services..."
    
    systemctl daemon-reload || {
        log_error "Failed to reload systemd daemon"
        return 1
    }
    
    # Restart getty services
    systemctl restart getty@tty1.service || {
        log_warn "Failed to restart getty@tty1.service"
    }
    
    systemctl restart getty@tty2.service || {
        log_warn "Failed to restart getty@tty2.service"
    }
    
    # Restart logind to apply virtual terminal changes
    systemctl restart systemd-logind || {
        log_warn "Failed to restart systemd-logind"
    }
    
    log_info "Services restarted successfully"
}

# Main execution
main() {
    log_info "Starting autologin configuration..."
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        if [[ -z "$USERNAME" ]]; then
            log_error "Auto mode requires --username parameter"
            exit 1
        fi
        
        log_info "Running in auto mode with username: $USERNAME"
        
        # Setup both TTYs
        setup_tty1 || report_failure "TTY1 autologin setup"
        setup_tty2 || report_failure "TTY2 autologin setup"
        
    else
        # Interactive mode
        echo "AutoLogin Setup Options:"
        echo "1) Setup TTY1 (Browser autologin)"
        echo "2) Setup TTY2 (Menu autologin)"
        echo "3) Setup both TTY1 and TTY2"
        echo "4) Exit"
        
        while true; do
            read -p "Choose an option (1-4): " choice
            case $choice in
                1)
                    setup_tty1 || report_failure "TTY1 autologin setup"
                    break
                    ;;
                2)
                    setup_tty2 || report_failure "TTY2 autologin setup"
                    break
                    ;;
                3)
                    setup_tty1 || report_failure "TTY1 autologin setup"
                    setup_tty2 || report_failure "TTY2 autologin setup"
                    break
                    ;;
                4)
                    log_info "Exiting without changes"
                    exit 0
                    ;;
                *)
                    echo "Invalid choice. Please select 1-4."
                    ;;
            esac
        done
    fi
    
    # Configure virtual terminals
    configure_virtual_terminals || report_failure "Virtual terminal configuration"
    
    # Reload systemd and restart services
    reload_systemd_and_restart_getty || log_warn "Some services failed to restart"
    
    report_success "Autologin configuration"
    
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        echo
        echo "Autologin has been configured. The changes will take effect after reboot."
        echo "TTY1: User autologin for browser"
        echo "TTY2: Root autologin for menu access"
        echo
        
        if prompt_yes_no "Would you like to reboot now to activate autologin?" "n"; then
            log_info "Rebooting system..."
            reboot
        fi
    fi
}

# Run main function
main