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
AUTO_REBOOT_TIME="20"  # Default auto-reboot time in seconds

# Load common library - required for operation
if [[ -f "$COMMON_LIB" ]]; then
    source "$COMMON_LIB"
    init_common "ms-util"
else
    echo "ERROR: Common library not found at $COMMON_LIB"
    echo "Please ensure MediaScreen installer components are properly installed."
    echo "Run 'sudo install.sh' first to install the components."
    exit 1
fi

# Parse command line arguments
LOCAL_ONLY=false
USE_DEV=false
DEBUG_MODE=false
CUSTOM_GITHUB_URL=""
FULL_INSTALL=false
AUTO_BROWSER_USERS=""
AUTO_MENU_TTY=""

# Parse common arguments using common library
parse_common_args "$@" || {
    if [[ $? -eq 2 ]]; then
        # Help was shown, exit gracefully
        echo
        echo "MediaScreen Utility additional options:"
        echo "  --full-install        Run automatic full installation (non-interactive)"
        echo "  --browser-users=LIST  Browser users configuration (user:tty:url,user:tty:url,...)"
        echo "  --menu-tty=TTY        TTY for menu autologin (default: tty12)"
        echo
        echo "Examples:"
        echo "  # Automatic full installation with single browser"
        echo "  sudo $0 --full-install --browser-users='mediauser:tty1:https://example.com'"
        echo
        echo "  # Multiple browser configuration"
        echo "  sudo $0 --full-install --browser-users='user:tty1:https://site1.com,user:tty2:https://site2.com'"
        echo
        echo "Features:"
        echo "  - Interactive menu for running individual scripts"
        echo "  - Full installation option"
        echo "  - Automatic non-interactive installation"
        echo "  - Script update functionality"
        echo "  - System reboot option"
        echo
        echo "Note: Run 'sudo install.sh' first to install the MediaScreen components."
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

# Parse additional arguments specific to ms-util
for arg in "$@"; do
    case $arg in
        --full-install)
            FULL_INSTALL=true
            ;;
        --browser-users=*)
            AUTO_BROWSER_USERS="$(strip_quotes "${arg#*=}")"
            ;;
        --menu-tty=*)
            AUTO_MENU_TTY="$(strip_quotes "${arg#*=}")"
            ;;
        *)
            # Common library handles other args
            ;;
    esac
done

# Validate full install mode arguments
if [[ "$FULL_INSTALL" == "true" ]]; then
    # Validate required browser-users
    if [[ -z "$AUTO_BROWSER_USERS" ]]; then
        echo "ERROR: --browser-users is required when using --full-install"
        echo "Format: user:tty:url,user:tty:url,..."
        echo "Example: --browser-users='mediauser:tty1:https://example.com,mediauser:tty2:https://site2.com'"
        echo "Use --help for usage information"
        exit 1
    fi
    
    # Set default menu TTY if not provided
    if [[ -z "$AUTO_MENU_TTY" ]]; then
        AUTO_MENU_TTY="tty12"
    fi
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

# Validate configuration file using common library
validate_config "$CONFIG_DIR/menu_config.txt" || exit 1

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

# Function to log to both console and log file
log_both() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local log_message="$timestamp $message"
    
    # Display to console
    echo "$log_message"
    
    # Create log directory if it doesn't exist
    local log_dir="/var/log/mediascreen"
    mkdir -p "$log_dir"
    
    # Write to log file
    local log_file="$log_dir/ms-util-install.log"
    echo "$log_message" >> "$log_file"
}

# Function to execute script with logging
execute_script_with_logging() {
    local script_path="$1"
    shift
    local script_args="$@"
    local log_file="/var/log/mediascreen/ms-util-install.log"
    
    # Execute script and capture both stdout and stderr
    # Use a temporary file to capture the output
    local temp_output="/tmp/script_output_$$"
    
    # Run the script and tee output to both console and temp file
    if bash "$script_path" $script_args 2>&1 | tee "$temp_output"; then
        # Append the captured output to the log file with timestamps
        while IFS= read -r line; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCRIPT: $line" >> "$log_file"
        done < "$temp_output"
        rm -f "$temp_output"
        return 0
    else
        # Append the captured output to the log file with timestamps even on failure
        while IFS= read -r line; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCRIPT: $line" >> "$log_file"
        done < "$temp_output"
        rm -f "$temp_output"
        return 1
    fi
}

# Full installation function (supports both interactive and automatic modes)
full_install() {
    local auto_mode="${1:-false}"
    local username=""
    local browser_users=""
    local menu_tty=""
    
    if [[ "$auto_mode" == "true" ]]; then
        # Check if the log file exists and remove it
        log_file="/var/log/mediascreen/ms-util-install.log"
        if [[ -f "$log_file" ]]; then
            rm -f "$log_file"
            echo "Existing log file removed: $log_file"
        fi

        log_both "Starting automatic full installation..."
        log_both "Installation log: /var/log/mediascreen/ms-util-install.log"
        echo
        
        # Validate and parse browser configuration using common library
        declare -A parsed_browsers
        declare -a unique_usernames
        
        if ! parse_browser_users "$AUTO_BROWSER_USERS" parsed_browsers unique_usernames; then
            log_both "ERROR: Browser-users validation failed"
            exit 1
        fi
        
        # Get the first username and browser count from parsed results
        username="${unique_usernames[0]}"
        browser_count="${#parsed_browsers[@]}"
        
        log_both "INFO: Full install configuration:"
        log_both "  Usernames: ${username[@]}"
        log_both "  Browser configurations ($browser_count):"
        for tty in "${!parsed_browsers[@]}"; do
            config="${parsed_browsers[$tty]}"
            user="${config%%:*}"  # Everything before first colon
            url="${config#*:}"    # Everything after first colon
            log_both "    $user -> $tty -> $url"
        done
        log_both "  Menu: root -> $AUTO_MENU_TTY"
        echo
        
        # Use the predefined browser configuration
        browser_users="$AUTO_BROWSER_USERS"
        menu_tty="$AUTO_MENU_TTY"
    else
        echo "Running interactive full install..."
        echo
        
        # Get username with validation
        while [[ -z "$username" ]]; do
            read -p "Enter the username for MediaScreen: " username
            
            # Validate username using common library
            if ! validate_username "$username"; then
                username=""
                echo "Please try again with a valid username."
                continue
            fi
        done

        echo "Starting full MediaScreen installation for user: $username"

        # Interactive browser configuration
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
        browser_users=""
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
            
            echo "Added: $username on $browser_tty -> $browser_url"
            
            # Increment TTY for next browser
            current_tty=$((current_tty + 1))
        done
        
        # Ask for menu TTY
        echo
        echo "=== Menu Configuration ==="
        menu_tty="tty12"  # Always use tty12 for menu
        read -p "Configure menu autologin on tty12? (y/n): " setup_menu
        
        if [[ ! "$setup_menu" =~ ^[Yy]$ ]]; then
            menu_tty=""  # Clear menu_tty if user doesn't want menu
        fi
        
        # Show configuration summary
        echo
        echo "=== Configuration Summary ==="
        echo "Browser autologins:"
        
        # Parse browser configuration using common library
        declare -A summary_browsers
        declare -a summary_usernames
        
        if parse_browser_users "$browser_users" summary_browsers summary_usernames; then
            for tty in "${!summary_browsers[@]}"; do
                # Format: user:url (where url may contain colons)
                local config="${summary_browsers[$tty]}"
                local user="${config%%:*}"  # Everything before first colon
                local url="${config#*:}"    # Everything after first colon
                echo "  $user -> $tty -> $url"
            done
        else
            echo "  Error parsing browser configuration"
        fi
        
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
    fi

    # Create user using common library
    if ! create_user_if_not_exists "$username"; then
        log_both "ERROR: Failed to create user: '$username'"
        if [[ "$auto_mode" == "true" ]]; then
            exit 1
        else
            echo "Press Enter to continue..."
            read
            return 1
        fi
    fi

    log_both "Starting MediaScreen installation with username: $username"

    # Prepare common arguments for all scripts
    local common_args="-y"
    
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

    log_both "Common script arguments: $common_args"

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
    
    log_both "Executing ${#sorted_orders[@]} scripts in run order..."
    
    # Execute scripts in run order
    for order_index in "${sorted_orders[@]}"; do
        local index="${order_index#*:}"
        local script="${script_filenames[$index]}"
        
        if [[ -f "$SCRIPTS_DIR/$script" ]]; then
            log_both "Running script: $script (run order: ${run_orders[$index]})"
            
            # Use different argument patterns for different scripts
            case "$script" in
                "configure-network.sh")
                    execute_script_with_logging "$SCRIPTS_DIR/$script" $common_args || {
                        log_both "Failed to run script: $script. Continuing with remaining scripts..."
                        sleep 3
                    }
                    ;;
                "autologin-setup.sh")
                    if [[ "$auto_mode" == "true" ]]; then
                        # Automatic autologin setup with predefined browser configuration
                        log_both "Setting up autologin with predefined configuration..."
                    fi
                    
                    # Build arguments for autologin-setup.sh
                    local autologin_args="$common_args --browser-users='$browser_users'"
                    if [[ -n "$menu_tty" ]]; then
                        autologin_args+=" --menu-tty='$menu_tty'"
                    fi
                    
                    log_both "Autologin arguments: $autologin_args"
                    
                    execute_script_with_logging "$SCRIPTS_DIR/$script" $autologin_args || {
                        log_both "Failed to run script: $script."
                        if [[ "$auto_mode" == "true" ]]; then
                            log_both "Exiting..."
                            exit 1
                        else
                            echo "Exiting in 10 seconds..."
                            sleep 10
                            exit 1
                        fi
                    }
                    ;;
                "msm-client-setup.sh")
                    # Run MSM client setup with common arguments
                    execute_script_with_logging "$SCRIPTS_DIR/$script" install $common_args || {
                        log_both "Failed to run script: $script. Continuing with remaining scripts..."
                        sleep 3
                    }
                    ;;
                *)
                    # Run other scripts with common arguments
                    execute_script_with_logging "$SCRIPTS_DIR/$script" $common_args || {
                        log_both "Failed to run script: $script. Continuing with remaining scripts..."
                        sleep 3
                    }
                    ;;
            esac
            
            log_both "Completed script: $script"
        else
            log_both "Warning: Script $script not found, skipping..."
        fi
    done
    
    echo
    log_both "=========================================="
    log_both "     MediaScreen Installation Complete!"
    log_both "=========================================="
    echo
    log_both "Configuration Summary:"
    log_both "  Username: $username"
    log_both "  Browser configurations:"
    
    # Parse browser configuration using common library
    declare -A install_browsers
    declare -a install_usernames
    
    if parse_browser_users "$browser_users" install_browsers install_usernames; then
        for tty in "${!install_browsers[@]}"; do
            # Format: user:url (where url may contain colons)
            local config="${install_browsers[$tty]}"
            local user="${config%%:*}"  # Everything before first colon
            local url="${config#*:}"    # Everything after first colon
            log_both "    $user -> $tty -> $url"
        done
    else
        log_both "    Error parsing browser configuration"
    fi
    
    if [[ -n "$menu_tty" ]]; then
        log_both "  Menu autologin: root -> $menu_tty"
    fi
    
    echo
    log_both "Network Information:"
    log_both "Available IP addresses:"
    
    # Display all available IP addresses using common library
    if ! display_ip_addresses "detailed"; then
        log_both "  No network interfaces configured"
    fi
    
    echo
    log_both "You can access MediaScreen using any of the above IP addresses."
    log_both "The system is ready to use after reboot."
    echo
    log_both "Full installation completed successfully!"
    echo
    
    if [[ "$auto_mode" == "true" ]]; then
        log_both "Rebooting in $AUTO_REBOOT_TIME seconds..."
        echo -n "Rebooting in "
        for i in $(seq $AUTO_REBOOT_TIME -1 1); do
            echo -n "$i..."
            sleep 1
        done
        echo
        log_both "Rebooting now!"
        reboot
    else
        read -p "Press Enter to reboot the system..."
        reboot
    fi
}

# Function to display the menu
show_menu() {
    clear

    echo "+--------------------------------------------------------------------------------------+"
    echo "|                                MediaScreen Utility                                   |"
    echo "+--------------------------------------------------------------------------------------+"
    
    # Calculate padding for consistent line length (86 characters total)
    local branch_text="Branch: $(if [[ "$USE_DEV" == "true" ]]; then echo "dev"; else echo "main"; fi)"
    local branch_padding=$((84 - ${#branch_text}))
    printf "| %s%*s |\n" "$branch_text" $branch_padding ""
    
    local debug_text="Debug Mode: $(if [[ "$DEBUG_MODE" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    local debug_padding=$((84 - ${#debug_text}))
    printf "| %s%*s |\n" "$debug_text" $debug_padding ""
    
    if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
        local url_text="Custom GitHub URL: $CUSTOM_GITHUB_URL"
        local url_padding=$((84 - ${#url_text}))
        printf "| %s%*s |\n" "$url_text" $url_padding ""
    fi
    
    local ip_list
    if ip_list=$(display_ip_addresses "list" 2>/dev/null); then
        local ip_text="IP Addresses: $ip_list"
        local ip_padding=$((84 - ${#ip_text}))
        printf "| %s%*s |\n" "$ip_text" $ip_padding ""
    else
        local no_ip_text="IP Addresses: No network interfaces configured"
        local no_ip_padding=$((84 - ${#no_ip_text}))
        printf "| %s%*s |\n" "$no_ip_text" $no_ip_padding ""
    fi
    
    echo "+--------------------------------------------------------------------------------------+"
    echo 
    
    echo "Menu Options:"
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
    
    echo "==========================================================================================="
    echo "                      u - Update | r - Reboot | b - Bash Terminal | q - Exit"
    echo "==========================================================================================="
}

# Function to run a selected script
run_option() {
    case $1 in
        0)
            full_install false
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
            echo "Relaunching ms-util with updated components..."
            sleep 2
            
            # Build relaunch arguments to preserve current settings
            local relaunch_args=""
            if [[ "$DEBUG_MODE" == "true" ]]; then
                relaunch_args+=" --debug"
            fi
            if [[ "$USE_DEV" == "true" ]]; then
                relaunch_args+=" --dev"
            fi
            if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
                relaunch_args+=" --github-url='$CUSTOM_GITHUB_URL'"
            fi
            
            # Relaunch ms-util with updated components
            exec /usr/local/bin/ms-util $relaunch_args
            ;;
        r|reboot)
            echo "Rebooting in 10 seconds..."
            sleep 10
            reboot
            ;;
        b|bash|shell)
            clear
            echo "Opening a bash shell..."
            echo "To return to the MediaScreen menu, type 'exit' or press Ctrl+D"
            echo "Prompting for user login..."
            /usr/bin/login
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

# Main execution
if [[ "$FULL_INSTALL" == "true" ]]; then
    # Run automatic full installation
    full_install true
else
    # Run interactive menu loop
    while true; do
        show_menu
        read -p "Enter your choice: " choice
        run_option "$choice"
    done
fi
