#!/bin/bash

# Strict error handling
set -euo pipefail

<<comment
    This script installs the required scripts for the MediaScreen system.

    The script downloads the configuration file and required scripts from the GitHub repository.
    The user can choose to run a specific script or run the full installation.

    This script requires root privileges. Please run as root.

    Command Usage:
        - To run the full installation:
            sudo bash install.sh --full-install
        - To run the full installation and autolaunch with specific username:
            sudo bash install.sh --full-install --username=<username>
        - To run menu and select a specific script:
            sudo bash install.sh
        - To use local scripts without downloading (for testing):
            sudo bash install.sh --local-only
        - To run full install with local scripts:
            sudo bash install.sh --full-install --local-only --username=<username>

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added improved error handling and logging
comment

# Logging setup
LOG_FILE="/var/log/mediascreen-installer.log"
mkdir -p "$(dirname "$LOG_FILE")"
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

function exit_prompt() {
    if [[ "${AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Exiting due to interrupt"
        exit 130
    fi
    echo
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        log "Exiting at user request"
        exit 130
    fi
}

trap exit_prompt SIGINT

# Network connectivity check
check_internet() {
    log "Checking internet connectivity..."
    if ! ping -q -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR: No internet connection detected. Please check your network."
        return 1
    fi
    log "Internet connectivity confirmed"
    return 0
}

# Validate downloaded configuration
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
    while IFS="" read -r line || [ -n "$line" ]; do
        if [[ -n "$line" && ! "$line" =~ ^[0-9]+,[0-9]+,[^,]+,[^,]+,[^,]+$ ]]; then
            log "ERROR: Invalid configuration line format: $line"
            log "Expected format: menu_order,run_order,name,description,filename"
            return 1
        fi
    done < "$config_file"
    
    log "Configuration file validated successfully ($line_count entries)"
    return 0
}

# Base URL for scripts and configuration file
base_url="https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main"
config_url="${base_url}/menu_config.txt"

# Parse command line arguments early to check for local-only mode
LOCAL_ONLY=false
for arg in "$@"; do
    case $arg in
        --local-only)
            LOCAL_ONLY=true
            ;;
    esac
done

# Check internet connectivity before proceeding (unless local-only mode)
if [[ "$LOCAL_ONLY" != "true" ]]; then
    check_internet || exit 1
fi

# Temporary directory for downloads
tmp_dir=$(mktemp -d)
log "Using temporary directory: $tmp_dir"
cd "$tmp_dir"

# System configuration directory
CONFIG_DIR="/etc/mediascreen"
mkdir -p "$CONFIG_DIR"

# MediaScreen installer directory structure
INSTALLER_DIR="/usr/local/bin/mediascreen-installer"
SCRIPTS_DIR="$INSTALLER_DIR/scripts"
mkdir -p "$SCRIPTS_DIR"

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    cd /
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

# Download the configuration file
if [[ "$LOCAL_ONLY" == "true" ]]; then
    log "Local-only mode: Using local configuration file..."
    
    # Look for local config file in config directory or fallback locations
    local_config=""
    if [[ -f "$CONFIG_DIR/menu_config.txt" ]]; then
        local_config="$CONFIG_DIR/menu_config.txt"
    else
        log "ERROR: Local configuration file not found. Expected locations:"
        log "  - $CONFIG_DIR/menu_config.txt"
        exit 1
    fi
    
    log "Using local configuration: $local_config"
    cp "$local_config" "$CONFIG_DIR/menu_config.txt"
else
    log "Downloading configuration file..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${config_url}" -o "$CONFIG_DIR/menu_config.txt" || {
            log "ERROR: Failed to download configuration file using curl"
            exit 1
        }
    else
        wget -q "${config_url}" -O "$CONFIG_DIR/menu_config.txt" || {
            log "ERROR: Failed to download configuration file using wget"
            exit 1
        }
    fi
fi

# Validate configuration file
validate_config "$CONFIG_DIR/menu_config.txt" || exit 1

# Read the configuration file and generate menu options
declare -a menu_orders
declare -a run_orders
declare -a menu_names
declare -a menu_descriptions
declare -a script_filenames

# Create lib directory for common library
mkdir -p "$INSTALLER_DIR/lib"

# Download or copy common library
if [[ "$LOCAL_ONLY" == "true" ]]; then
    echo "Local-only mode: Using local common library..."
    
    # Look for local common library
    local_common=""
    if [[ -f "scripts/lib/common.sh" ]]; then
        local_common="scripts/lib/common.sh"
    elif [[ -f "../scripts/lib/common.sh" ]]; then
        local_common="../scripts/lib/common.sh"
    else
        echo "ERROR: Local common library not found. Expected locations:"
        echo "  - ./scripts/lib/common.sh"
        echo "  - ../scripts/lib/common.sh"
        exit 1
    fi
    
    echo "Using local common library: $local_common"
    cp "$local_common" "$INSTALLER_DIR/lib/common.sh"
    chmod 644 "$INSTALLER_DIR/lib/common.sh"
else
    echo "Downloading common library..."
    wget -q "${base_url}/scripts/lib/common.sh" -O "common.sh" || {
        echo "Failed to download common library. Exiting..."
        exit 1
    }
    mv "common.sh" "$INSTALLER_DIR/lib/common.sh"
    chmod 644 "$INSTALLER_DIR/lib/common.sh"
fi

while IFS="" read -r line || [ -n "$line" ]; do
    IFS=',' read -r menu_order run_order name description filename <<< "$line"
    
    filename=$(echo "$filename" | tr -d '\r') # Remove carriage return

    menu_orders+=("$menu_order")
    run_orders+=("$run_order")
    menu_names+=("$name")
    menu_descriptions+=("$description")
    script_filenames+=("$filename")
    
    # Download or copy the script file
    if [[ "$LOCAL_ONLY" == "true" ]]; then
        echo "Local-only mode: Using local script: ${filename}"
        
        # Look for local script file
        local_script=""
        if [[ -f "scripts/${filename}" ]]; then
            local_script="scripts/${filename}"
        elif [[ -f "../scripts/${filename}" ]]; then
            local_script="../scripts/${filename}"
        else
            echo "WARNING: Local script not found: ${filename}"
            echo "Expected locations:"
            echo "  - ./scripts/${filename}"
            echo "  - ../scripts/${filename}"
            
            # Check if script already exists in scripts directory
            if [[ -f "$SCRIPTS_DIR/${filename}" ]]; then
                echo "Using existing script in $SCRIPTS_DIR/${filename}"
                continue
            else
                echo "Skipping missing script: ${filename}"
                continue
            fi
        fi
        
        echo "Using local script: $local_script"
        cp "$local_script" "${filename}"
    else
        echo "Downloading script: ${filename}"
        wget -q "${base_url}/scripts/${filename}" -O "${filename}" || {
            echo "Failed to download script: ${filename}. Exiting..."
            exit 1
        }
    fi
    
    chmod +x "$filename"
    chown ${SUDO_USER}:${SUDO_USER} "$filename"
    
    # Move the script file to the scripts directory
    mv "${filename}" "$SCRIPTS_DIR/${filename}"
done < "$CONFIG_DIR/menu_config.txt"

if [[ "$LOCAL_ONLY" == "true" ]]; then
    echo "Finished copying local scripts"
else
    echo "Finished downloading required scripts"
fi

# Copy/move install.sh to the installer directory
if [[ "$0" != "$INSTALLER_DIR/install.sh" ]]; then
    echo "Installing main script to $INSTALLER_DIR/install.sh"
    cp "$0" "$INSTALLER_DIR/install.sh"
    chmod +x "$INSTALLER_DIR/install.sh"
fi

# Create symbolic link for easy access
ln -sf "$INSTALLER_DIR/install.sh" "/usr/local/bin/ms-util"
echo "Created symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/install.sh"

sleep 1

full_install() {
    echo "Running full install..."
    
    # Check if username is provided as argument
    if [ -n "$1" ]; then
        username="$1"
    else
        read -p "Enter the username: " username
    fi

    # Check if user exists
    if ! id "$username" >/dev/null 2>&1; then
        # Create user with no password
        useradd -m -s /bin/bash -p '*' "$username"
        echo "User $username created with no password."
    fi

    # Prepare common arguments for all scripts
    local common_args="-y --username='$username'"
    
    # Add URL if provided
    if [ -n "$2" ]; then
        common_args+=" --url='$2'"
    fi

    # Create array of scripts sorted by run order
    declare -a sorted_scripts
    declare -a sorted_orders
    
    # Build arrays for sorting
    for i in "${!run_orders[@]}"; do
        sorted_orders+=("${run_orders[$i]}:$i")
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
                "browser-setup.sh")
                    # Browser setup needs the URL parameter
                    bash "$SCRIPTS_DIR/$script" $common_args || {
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

    echo "+-----------------------------------------------------------------------------------------+"
    echo "|                                 MediaScreen Installer                               |"
    echo "+-----------------------------------------------------------------------------------------+"
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
    echo "                            u - Update | r - Reboot | q - Exit"
    echo "==========================================================================================="
}

# Function to run a selected script
run_option() {
    case $1 in
        0)
            full_install
            ;;
        [1-9]*)
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
                    bash "$script_path" || {
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
            echo "Updating..."
            wget -q "${base_url}/install.sh" -O install.sh || {
                echo "Download failed. Please enter the URL:"
                read -r new_url
                wget -q "$new_url" -O install.sh || {
                    echo "Download failed again. Please check the URL and try again later."
                    return 1
                }
            }
            chmod +x install.sh
            mv install.sh "$INSTALLER_DIR/install.sh"
            ln -sf "$INSTALLER_DIR/install.sh" "/usr/local/bin/ms-util"
            echo "Updated successfully. This script will now exit."
            exit
            ;;
        r|reboot)
            echo "Rebooting in 10 seconds..."
            sleep 10
            reboot
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

FULL_INSTALL=false

for arg in "$@"; do
    case $arg in
        --full-install)
            FULL_INSTALL=true
        ;;
        --username=*)
            USERNAME="${arg#*=}"
        ;;
        --url=*)
            URL="${arg#*=}"
        ;;
        --local-only)
            # Already parsed above, just acknowledge it here
            ;;
    esac
done

# Check for argument "--full-install"
if [[ "$@" == *"--full-install"* ]]; then
    full_install "$USERNAME" "$URL"
    exit
fi

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    run_option "$choice"
done