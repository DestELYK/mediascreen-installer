#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/../lib/common.sh"; then
    echo "ERROR: Failed to load common library"
    echo "Please ensure MediaScreen installer components are properly installed."
    exit 1
fi

<<comment
    MediaScreen Network Configuration Script
    
    This script configures network settings including Wi-Fi connections,
    system time zone, and basic connectivity tests.
    
    Usage:
        sudo bash configure-network.sh
        sudo bash configure-network.sh -y
        
    Options:
        -y, --auto    Run in automatic mode (non-interactive)
        -h, --help    Show help message
    
    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-22-2025 - Modernized to use common library
comment

# Initialize common library
init_common "network-config"

# System checks
check_debian
check_root

# Parse command line arguments using common library
parse_common_args "$@" || {
    if [[ $? -eq 2 ]]; then
        # Help was shown, exit gracefully
        exit 0
    fi
    exit 1
}

trap exit_prompt SIGINT

# Check if NetworkManager is available
check_network_manager() {
    if command -v nmcli >/dev/null 2>&1; then
        return 0
    else
        log "WARNING: NetworkManager not found. Installing..."
        apt update -qq
        apt install -y network-manager
        systemctl enable NetworkManager
        systemctl start NetworkManager
    fi
}

# Get available network interfaces
get_wifi_interface() {
    local interfaces
    interfaces=$(ip link show | grep -E "wl[a-z0-9]+:" | cut -d: -f2 | tr -d ' ' | head -1)
    
    if [[ -z "$interfaces" ]]; then
        log "ERROR: No WiFi interface found"
        return 1
    fi
    
    echo "$interfaces"
}

# Validate SSID format
validate_ssid() {
    local ssid="$1"
    if [[ ${#ssid} -lt 1 || ${#ssid} -gt 32 ]]; then
        log "ERROR: SSID must be between 1 and 32 characters"
        return 1
    fi
    return 0
}

# Test internet connectivity using common library function
# (test_connectivity function replaced with check_internet from common library)

reconfigure_wifi() {
    log "Starting WiFi reconfiguration..."
    
    check_network_manager
    
    local wifi_interface
    wifi_interface=$(get_wifi_interface) || {
        log "ERROR: Cannot proceed without WiFi interface"
        exit 1
    }
    
    log "Using WiFi interface: $wifi_interface"
    
    local attempts=0
    local max_attempts=3
    
    while [[ $attempts -lt $max_attempts ]]; do
        attempts=$((attempts + 1))
        log "WiFi configuration attempt $attempts/$max_attempts"
        
        # Scan for available networks
        log "Scanning for available networks..."
        nmcli device wifi rescan || true
        sleep 2
        
        if [[ "$AUTO_INSTALL" != "true" ]]; then
            echo "Available networks:"
            nmcli device wifi list | head -10
            echo
        fi
        
        # Get SSID
        local ssid
        if [[ "$AUTO_INSTALL" == "true" ]]; then
            log "ERROR: Auto mode requires pre-configured network settings"
            exit 1
        else
            while true; do
                read -p "Enter the SSID: " ssid
                if validate_ssid "$ssid"; then
                    break
                fi
            done
        fi
        
        # Get password securely
        local password
        echo -n "Enter the password: "
        read -s password
        echo
        
        if [[ ${#password} -lt 8 ]]; then
            log "WARNING: Password should be at least 8 characters for security"
        fi
        
        # Connect using NetworkManager
        log "Connecting to network: $ssid"
        if nmcli device wifi connect "$ssid" password "$password" 2>/dev/null; then
            log "Connection command successful, testing connectivity..."
            sleep 5
            
            if check_internet; then
                log "Successfully connected to WiFi network: $ssid"
                return 0
            else
                log "Connected to WiFi but no internet access"
            fi
        else
            log "Failed to connect to network: $ssid"
        fi
        
        if [[ $attempts -lt $max_attempts ]]; then
            read -p "Try again? (y/n): " retry
            if [[ ! $retry =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    done
    
    log "ERROR: Failed to establish WiFi connection after $max_attempts attempts"
    exit 1
}

display_connections() {
    display_ip_addresses "interfaces" "true"
}

configure_timezone() {
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log "Skipping timezone configuration in auto mode"
        return 0
    fi
    
    log "Configuring timezone..."
    echo "Current timezone: $(timedatectl show --property=Timezone --value)"
    
    read -p "Would you like to reconfigure the timezone? (y/n): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        if command -v timedatectl >/dev/null 2>&1; then
            echo "Available timezones (showing first 20):"
            timedatectl list-timezones | head -20
            echo "... (use 'timedatectl list-timezones' to see all)"
            echo
            
            while true; do
                read -p "Enter timezone (e.g., America/New_York): " timezone
                if timedatectl list-timezones | grep -q "^$timezone$"; then
                    timedatectl set-timezone "$timezone"
                    log "Timezone set to: $timezone"
                    break
                else
                    echo "Invalid timezone. Please try again."
                fi
            done
        else
            # Fallback to dpkg-reconfigure
            dpkg-reconfigure tzdata
        fi
    fi
}

# Main execution
main() {
    log "Starting network configuration script"
    
    # Check initial connectivity
    log "Checking initial internet connection..."
    if check_internet; then
        log "Already connected to the internet"
        display_connections
        
        if [[ "$AUTO_INSTALL" != "true" ]]; then
            read -p "You are already connected! Would you like to reconfigure the WiFi connection? (y/n): " choice
            if [[ $choice =~ ^[Yy]$ ]]; then
                reconfigure_wifi
            fi
        else
            log "Auto mode: Skipping WiFi reconfiguration (already connected)"
        fi
    else
        log "Not connected to the internet, starting WiFi configuration"
        reconfigure_wifi
    fi
    
    display_connections
    configure_timezone
    
    log "Network configuration completed successfully"
}

# Run main function
main