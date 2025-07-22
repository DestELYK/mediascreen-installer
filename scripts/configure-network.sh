#!/bin/bash

# Strict error handling
set -euo pipefail

<<comment
    This script is used to reconfigure the WiFi connection and timezone settings.

    The script checks the internet connection and prompts the user to reconfigure the WiFi connection if not connected. It also reconfigures the timezone settings.

    This script requires root privileges. Please run as root.

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added improved error handling, modern network management, and security improvements
comment

# Logging setup
LOG_FILE="/var/log/mediascreen-network.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check if the system is using Debian
if [[ ! -f /etc/debian_version ]]; then
    log "ERROR: System is not using Debian. Exiting..."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    log "ERROR: Please run as root"
    exit 1
fi

# Parse command line arguments
auto_install=false
for arg in "$@"; do
    case $arg in
        -y|--auto)
            auto_install=true
            ;;
        -h|--help)
            echo "Usage: $0 [-y|--auto] [-h|--help]"
            echo "  -y, --auto    Run in automatic mode (non-interactive)"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            log "WARNING: Unknown argument: $arg"
            ;;
    esac
done

function exit_prompt() {
    if [[ "$auto_install" == "true" ]]; then
        exit 1
    fi
    echo
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        exit 1
    fi
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

# Test internet connectivity
test_connectivity() {
    local attempts=0
    local max_attempts=3
    
    while [[ $attempts -lt $max_attempts ]]; do
        attempts=$((attempts + 1))
        log "Testing connectivity (attempt $attempts/$max_attempts)..."
        
        if ping -q -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log "Internet connectivity confirmed"
            return 0
        fi
        
        sleep 2
    done
    
    log "No internet connectivity detected"
    return 1
}

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
        
        if [[ "$auto_install" != "true" ]]; then
            echo "Available networks:"
            nmcli device wifi list | head -10
            echo
        fi
        
        # Get SSID
        local ssid
        if [[ "$auto_install" == "true" ]]; then
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
            
            if test_connectivity; then
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
    log "Displaying network connections..."
    echo "=== Network Interface Information ==="
    
    # Show active connections
    if command -v nmcli >/dev/null 2>&1; then
        echo "Active connections:"
        nmcli connection show --active | grep -v "DEVICE" | while read -r line; do
            echo "  $line"
        done
        echo
    fi
    
    # Show IP addresses
    echo "IP addresses:"
    ip addr show | grep "inet " | grep -v "127.0.0.1" | while read -r line; do
        interface=$(echo "$line" | awk '{print $NF}')
        ip=$(echo "$line" | awk '{print $2}')
        echo "  $interface: $ip"
    done
    echo "=================================="
}

configure_timezone() {
    if [[ "$auto_install" == "true" ]]; then
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
    if test_connectivity; then
        log "Already connected to the internet"
        display_connections
        
        if [[ "$auto_install" != "true" ]]; then
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