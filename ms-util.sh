#!/bin/bash

# MediaScreen Utility Script
# Author: DestELYK
# Updated: 07-22-2025
# Description: Interactive menu system for MediaScreen installer components

# Strict error handling
set -euo pipefail

# Check if the system is using Debian
if [[ ! -f /etc/debian_version ]]; then
    echo "ERROR: System is not using Debian. Exiting..."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root"
    exit 1
fi

# Configuration and script directories
CONFIG_DIR="/etc/mediascreen"
INSTALLER_DIR="/usr/local/bin/mediascreen-installer"
SCRIPTS_DIR="$INSTALLER_DIR/scripts"
COMMON_LIB="$INSTALLER_DIR/lib/common.sh"

# Load common library if available
if [[ -f "$COMMON_LIB" ]]; then
    source "$COMMON_LIB"
    init_common "ms-util"
else
    # Fallback logging if common library not available
    LOG_FILE="/var/log/mediascreen-util.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    }
    
    log_debug() {
        if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
            log "DEBUG: $*"
        fi
    }
    
    function exit_prompt() {
        echo
        read -p "Do you want to exit? (y/n): " EXIT
        if [[ $EXIT =~ ^[Yy]$ ]]; then
            log "Exiting at user request"
            exit 130
        fi
    }
    
    trap exit_prompt SIGINT
fi

# Parse command line arguments
LOCAL_ONLY=false
USE_DEV=false
DEBUG_MODE=false
CUSTOM_GITHUB_URL=""

# Check if common library is available and use its argument parsing
if [[ -f "$COMMON_LIB" ]]; then
    # Use common library argument parsing
    parse_common_args "$@" || {
        if [[ $? -eq 2 ]]; then
            # Help was shown, exit gracefully
            exit 0
        fi
        exit 1
    }
    
    # Get values from common library exports
    DEBUG_MODE="${DEBUG:-false}"
    
    # Set local variables from exports if they exist
    if [[ -n "${GITHUB_BRANCH:-}" && "$GITHUB_BRANCH" == "dev" ]]; then
        USE_DEV=true
    fi
    
    if [[ -n "${CUSTOM_GITHUB_URL:-}" ]]; then
        CUSTOM_GITHUB_URL="$CUSTOM_GITHUB_URL"
    fi
else
    # Fallback argument parsing if common library not available
    for arg in "$@"; do
        case $arg in
            -h|--help)
                echo "MediaScreen Utility (ms-util)"
                echo
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --local-only          Use local scripts instead of downloading"
                echo "  --dev                 Use development branch instead of main"
                echo "  --debug               Enable debug logging"
                echo "  --github-url=URL      Use custom GitHub repository URL"
                echo "  -h, --help            Show this help message"
                echo
                echo "Examples:"
                echo "  # Interactive menu"
                echo "  sudo $0"
                echo
                echo "  # Use development branch"
                echo "  sudo $0 --dev --debug"
                echo
                echo "  # Use custom repository"
                echo "  sudo $0 --github-url=https://raw.githubusercontent.com/user/repo/main"
                echo
                echo "Features:"
                echo "  - Interactive menu for running individual scripts"
                echo "  - Full installation option"
                echo "  - Script update functionality"
                echo "  - System reboot option"
                echo
                echo "Note: Run 'sudo install.sh' first to install the MediaScreen components."
                exit 0
                ;;
            --local-only)
                LOCAL_ONLY=true
                ;;
            --dev)
                USE_DEV=true
                ;;
            --debug)
                DEBUG_MODE=true
                ;;
            --github-url=*)
                CUSTOM_GITHUB_URL="${arg#*=}"
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
fi

# Check if MediaScreen is installed
if [[ ! -f "$CONFIG_DIR/menu_config.txt" ]] || [[ ! -d "$SCRIPTS_DIR" ]]; then
    echo "ERROR: MediaScreen installer components not found."
    echo "Please run 'sudo install.sh' first to install the components."
    echo
    echo "Expected locations:"
    echo "  Configuration: $CONFIG_DIR/menu_config.txt"
    echo "  Scripts: $SCRIPTS_DIR/"
    exit 1
fi

# Validate configuration file - use common library function if available
if [[ -f "$COMMON_LIB" ]] && command -v validate_config >/dev/null 2>&1; then
    # Use common library validation
    validate_config "$CONFIG_DIR/menu_config.txt" || exit 1
else
    # Fallback validation function
    validate_config() {
        local config_file="$1"
        local line_count
        
        if [[ ! -f "$config_file" ]]; then
            log "ERROR: Configuration file not found: $config_file"
            return 1
        fi
        
        line_count=$(wc -l < "$config_file")
        if [[ $line_count -eq 0 ]]; then
            log "ERROR: Configuration file is empty"
            return 1
        fi
        
        # Check for proper CSV format with 5 fields: menu_order,run_order,name,description,filename
        # run_order can be numeric or contain _ for manual-only items
        while IFS="" read -r line || [ -n "$line" ]; do
            if [[ -n "$line" && ! "$line" =~ ^[0-9]+,([0-9]+|[0-9]*_[0-9]*|_),[^,]+,[^,]+,[^,]+$ ]]; then
                log "ERROR: Invalid configuration line format: $line"
                log "Expected format: menu_order,run_order,name,description,filename"
                log "run_order can be numeric (1,2,3...) or contain _ for manual-only items (_,1_,_2,etc.)"
                return 1
            fi
        done < "$config_file"
        
        log "Configuration file validated successfully ($line_count entries)"
        return 0
    }
    
    validate_config "$CONFIG_DIR/menu_config.txt" || exit 1
fi

# Read the configuration file and generate menu options
declare -a menu_orders
declare -a run_orders
declare -a menu_names
declare -a menu_descriptions
declare -a script_filenames

while IFS="" read -r line || [ -n "$line" ]; do
    IFS=',' read -r menu_order run_order name description filename <<< "$line"
    
    filename=$(echo "$filename" | tr -d '\r') # Remove carriage return

    menu_orders+=("$menu_order")
    run_orders+=("$run_order")
    menu_names+=("$name")
    menu_descriptions+=("$description")
    script_filenames+=("$filename")
done < "$CONFIG_DIR/menu_config.txt"

# Full installation function
full_install() {
    echo "Running full install..."
    echo
    
    # Get username with validation
    local username=""
    while [[ -z "$username" ]]; do
        read -p "Enter the username for MediaScreen: " username
        
        # Validate username using common library if available
        if [[ -f "$COMMON_LIB" ]] && command -v validate_username >/dev/null 2>&1; then
            if ! validate_username "$username"; then
                username=""
                echo "Please try again with a valid username."
                continue
            fi
        else
            # Fallback validation
            if [[ ! $username =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]]; then
                echo "ERROR: Invalid username format. Use only alphanumeric characters, underscores, and hyphens."
                username=""
                continue
            fi
            
            if [[ ${#username} -gt 32 ]]; then
                echo "ERROR: Username too long. Maximum 32 characters allowed."
                username=""
                continue
            fi
        fi
    done

    echo "Starting full MediaScreen installation for user: $username"

    # Create user using common library if available
    if [[ -f "$COMMON_LIB" ]] && command -v create_user_if_not_exists >/dev/null 2>&1; then
        if ! create_user_if_not_exists "$username"; then
            echo "ERROR: Failed to create user: '$username'"
            echo "Press Enter to continue..."
            read
            return 1
        fi
    else
        # Fallback user creation
        if ! id "$username" >/dev/null 2>&1; then
            echo "Creating user: $username"
            if useradd -m -s /bin/bash -p '*' "$username"; then
                echo "User $username created successfully."
            else
                echo "ERROR: Failed to create user: '$username'"
                echo "Press Enter to continue..."
                read
                return 1
            fi
        else
            echo "User $username already exists."
        fi
    fi

    # Prepare common arguments for all scripts
    local common_args="-y --username='$username'"
    
    # Add debug mode if enabled
    if [[ "$DEBUG_MODE" == "true" ]]; then
        common_args+=" --debug"
    fi
    
    # Add dev branch if enabled
    if [[ "$USE_DEV" == "true" ]]; then
        common_args+=" --dev"
    fi
    
    # Add custom GitHub URL if provided
    if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
        common_args+=" --github-url='$CUSTOM_GITHUB_URL'"
    fi

    # Create array of scripts sorted by run order, excluding items marked with _
    declare -a sorted_scripts
    declare -a sorted_orders
    
    # Build arrays for sorting, skip items with _ in run_order
    for i in "${!run_orders[@]}"; do
        local run_order="${run_orders[$i]}"
        
        # Skip items with _ in run_order (manual only items)
        if [[ "$run_order" == *"_"* ]]; then
            log_debug "Skipping script in auto install (marked with _): ${script_filenames[$i]}"
            continue
        fi
        
        # Validate run_order is numeric
        if [[ "$run_order" =~ ^[0-9]+$ ]]; then
            sorted_orders+=("${run_orders[$i]}:$i")
        else
            log_debug "Skipping script with non-numeric run_order: ${script_filenames[$i]} (run_order: $run_order)"
        fi
    done
    
    # Sort by run order
    IFS=$'\n' sorted_orders=($(sort -n <<< "${sorted_orders[*]}"))
    unset IFS
    
    # Execute scripts in run order
    for order_index in "${sorted_orders[@]}"; do
        local index="${order_index#*:}"
        local script="${script_filenames[$index]}"
        
        if [[ -f "$SCRIPTS_DIR/$script" ]]; then
            echo "Running script: $script (run order: ${run_orders[$index]})"
            
            # Use different argument patterns for different scripts
            case "$script" in
                "configure-network.sh")
                    bash "$SCRIPTS_DIR/$script" $common_args || {
                        echo "Failed to run script: $script. Continuing with remaining scripts..."
                        sleep 3
                    }
                    ;;
                "autologin-setup.sh")
                    # Autologin setup now includes browser functionality - ask for multiple browsers
                    echo
                    echo "=== Browser Configuration ==="
                    
                    # Ask how many browsers to configure
                    local num_browsers=0
                    while [[ $num_browsers -lt 1 || $num_browsers -gt 11 ]]; do
                        read -p "How many browser instances would you like to configure? (1-11, tty12 reserved for menu): " num_browsers
                        
                        if [[ ! "$num_browsers" =~ ^[0-9]+$ ]] || [[ $num_browsers -lt 1 || $num_browsers -gt 11 ]]; then
                            echo "Please enter a number between 1 and 11 (tty12 is reserved for menu)."
                            num_browsers=0
                        fi
                    done
                    
                    echo "Setting up $num_browsers browser instance(s) for user: $username..."
                    
                    # Build browser users string
                    local browser_users=""
                    local current_tty=1
                    
                    # Configure each browser
                    for ((i=1; i<=num_browsers; i++)); do
                        echo
                        echo "=== Browser $i of $num_browsers ==="
                        
                        local browser_tty="tty$current_tty"
                        local browser_url=""
                        
                        # Skip tty12 (reserved for menu)
                        if [[ $current_tty -eq 12 ]]; then
                            echo "ERROR: Cannot assign more than 11 browsers (tty12 is reserved for menu)"
                            echo "Press Enter to continue..."
                            read
                            return 1
                        fi
                        
                        echo "User '$username' will be assigned to $browser_tty"
                        
                        # Get URL
                        while [[ -z "$browser_url" ]]; do
                            read -p "Enter URL for $username on $browser_tty (e.g., https://example.com): " browser_url
                            
                            if [[ -z "$browser_url" ]]; then
                                echo "URL cannot be empty. Please try again."
                                continue
                            fi
                            
                            if [[ ! $browser_url =~ ^https?://[a-zA-Z0-9.-]+([:/][^[:space:]]*)?$ ]]; then
                                echo "Invalid URL format. URL must start with http:// or https://"
                                browser_url=""
                            fi
                        done
                        
                        # Add to browser users string
                        if [[ -n "$browser_users" ]]; then
                            browser_users+=","
                        fi
                        browser_users+="$username:$browser_tty:$browser_url"
                        
                        echo "✓ Added: $username on $browser_tty -> $browser_url"
                        
                        # Increment TTY for next browser
                        current_tty=$((current_tty + 1))
                    done
                    
                    # Ask for menu TTY
                    echo
                    echo "=== Menu Configuration ==="
                    local menu_tty="tty12"  # Always use tty12 for menu
                    read -p "Configure menu autologin on tty12? (y/n): " setup_menu
                    
                    if [[ ! "$setup_menu" =~ ^[Yy]$ ]]; then
                        menu_tty=""  # Clear menu_tty if user doesn't want menu
                    fi
                    
                    # Show configuration summary
                    echo
                    echo "=== Configuration Summary ==="
                    echo "Browser autologins:"
                    IFS=',' read -ra BROWSER_PAIRS <<< "$browser_users"
                    for pair in "${BROWSER_PAIRS[@]}"; do
                        IFS=':' read -ra PARTS <<< "$pair"
                        echo "  ${PARTS[0]} -> ${PARTS[1]} -> ${PARTS[2]}"
                    done
                    
                    if [[ -n "$menu_tty" ]]; then
                        echo "Menu autologin: root -> $menu_tty"
                    fi
                    
                    echo
                    read -p "Proceed with this configuration? (y/n): " proceed
                    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
                        echo "Configuration cancelled."
                        echo "Press Enter to continue..."
                        read
                        return
                    fi
                    
                    # Build arguments for autologin-setup.sh
                    local autologin_args="$common_args --browser-users='$browser_users'"
                    if [[ -n "$menu_tty" ]]; then
                        autologin_args+=" --menu-tty='$menu_tty'"
                    fi
                    
                    bash "$SCRIPTS_DIR/$script" $autologin_args || {
                        echo "Failed to run script: $script. Exiting in 10 seconds..."
                        sleep 10
                        exit 1
                    }
                    ;;
                *)
                    # Run other scripts with common arguments
                    bash "$SCRIPTS_DIR/$script" $common_args || {
                        echo "Failed to run script: $script. Continuing with remaining scripts..."
                        sleep 3
                    }
                    ;;
            esac
        else
            echo "Warning: Script $script not found, skipping..."
        fi
    done
    
    echo "Full installation completed successfully!"
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
}

# Function to display the menu
show_menu() {
    clear

    echo "                                MediaScreen Utility                                   "
    echo "                                                                                      "
    echo "0) Full Install"
    
    # Create array of menu items sorted by menu order
    declare -a sorted_menu_items
    
    # Build arrays for sorting by menu order
    for i in "${!menu_orders[@]}"; do
        sorted_menu_items+=("${menu_orders[$i]}:$i")
    done
    
    # Sort by menu order
    IFS=$'\n' sorted_menu_items=($(sort -n <<< "${sorted_menu_items[*]}"))
    unset IFS
    
    # Display menu items in menu order
    for order_index in "${sorted_menu_items[@]}"; do
        local index="${order_index#*:}"
        local menu_num="${menu_orders[$index]}"
        echo "$menu_num) ${menu_names[$index]} - ${menu_descriptions[$index]}"
    done
    
    echo "                                                                                      "
    echo "                      u - Update | r - Reboot | b - Bash Terminal | q - Exit"
    echo "                                                                                      "
}

# Function to run a selected script
run_option() {
    case $1 in
        0)
            full_install
            ;;
        [0-9]*)
            # Find the script by menu order
            local selected_menu_order="$1"
            local script_index=""
            
            # Find the index for the selected menu order
            for i in "${!menu_orders[@]}"; do
                if [[ "${menu_orders[$i]}" == "$selected_menu_order" ]]; then
                    script_index="$i"
                    break
                fi
            done
            
            if [[ -n "$script_index" ]]; then
                local script="${script_filenames[$script_index]}"
                local script_path="$SCRIPTS_DIR/$script"
                
                if [[ -f "$script_path" ]]; then
                    echo "Running script: $script"
                    
                    # Interactive mode for individual scripts
                    local script_args=""
                    
                    # Add debug mode if enabled
                    if [[ "$DEBUG_MODE" == "true" ]]; then
                        script_args+=" --debug"
                    fi
                    
                    # Add dev branch if enabled
                    if [[ "$USE_DEV" == "true" ]]; then
                        script_args+=" --dev"
                    fi
                    
                    # Add custom GitHub URL if provided
                    if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
                        script_args+=" --github-url='$CUSTOM_GITHUB_URL'"
                    fi
                    
                    bash "$script_path" $script_args || {
                        echo "Failed to run script: $script. Press Enter to continue..."
                        read
                    }
                else
                    echo "Script not found: $script"
                    echo "Press Enter to continue..."
                    read
                fi
            else
                echo "Invalid menu option: $1"
                echo "Press Enter to continue..."
                read
            fi
            ;;
        u|update)
            echo "Updating MediaScreen installer..."
            echo "Running install.sh to update components..."
            
            # Build update arguments
            local update_args=""
            if [[ "$USE_DEV" == "true" ]]; then
                update_args+=" --dev"
            fi
            if [[ "$DEBUG_MODE" == "true" ]]; then
                update_args+=" --debug"
            fi
            if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
                update_args+=" --github-url='$CUSTOM_GITHUB_URL'"
            fi
            
            # Run install.sh to update
            if [[ -f "$INSTALLER_DIR/install.sh" ]]; then
                bash "$INSTALLER_DIR/install.sh" $update_args || {
                    echo "Update failed. Please check the logs and try again."
                    echo "Press Enter to continue..."
                    read
                    return 1
                }
            else
                echo "Install script not found. Cannot update."
                echo "Please reinstall MediaScreen manually."
                echo "Press Enter to continue..."
                read
                return 1
            fi
            
            echo "Update completed successfully!"
            echo "Press Enter to continue..."
            read
            ;;
        r|reboot)
            echo "Rebooting in 10 seconds..."
            sleep 10
            reboot
            ;;
        b|bash|shell)
            echo "Starting bash terminal..."
            echo
            echo "=== MediaScreen Bash Terminal ==="
            echo "Type 'exit' to return to the menu"
            echo
            /bin/bash
            ;;
        q|quit|exit)
            echo "Exiting..."
            exit
            ;;
        *)
            echo "Invalid option. Please try again."
            return
            ;;
    esac
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    run_option "$choice"
done
