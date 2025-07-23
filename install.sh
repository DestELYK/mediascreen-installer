#!/bin/bash

# Strict error handling
set -euo pipefail

<<comment
    MediaScreen Installer Script
    
    This script installs all MediaScreen components including scripts, configuration,
    and the utility menu system (ms-util) to the system.

    This script requires root privileges. Please run as root.

    Command Usage:
        - Install all components:
            sudo bash install.sh
        - Install with development branch:
            sudo bash install.sh --dev
        - Install with custom repository:
            sudo bash install.sh --github-url=https://raw.githubusercontent.com/user/repo/main
        - Use local scripts (for testing):
            sudo bash install.sh --local-only
        - Enable debug logging:
            sudo bash install.sh --debug

    After installation, use 'ms-util' command to access the menu system.

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-22-2025 - Separated installation from menu system
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

# Base URL for scripts and configuration file
base_repo_url="https://raw.githubusercontent.com/DestELYK/mediascreen-installer"
branch="main"
base_url="${base_repo_url}/${branch}"
config_url="${base_url}/menu_config.txt"

# Parse command line arguments early to check for local-only mode and other options
LOCAL_ONLY=false
USE_DEV=false
DEBUG_MODE=false
CUSTOM_GITHUB_URL=""
AUTOLAUNCH=false

# Check for help first, before any other processing
for arg in "$@"; do
    case $arg in
        -h|--help)
            echo "MediaScreen Installer"
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
            echo "  # Install all components"
            echo "  sudo $0"
            echo
            echo "  # Use development branch"
            echo "  sudo $0 --dev --debug"
            echo
            echo "  # Use custom repository"
            echo "  sudo $0 --github-url=https://raw.githubusercontent.com/user/repo/main"
            echo
            echo "  # Local testing"
            echo "  sudo $0 --local-only --debug"
            echo
            echo "Installation Structure:"
            echo "  Scripts are installed to: /usr/local/bin/mediascreen-installer/"
            echo "  Utility script created: /usr/local/bin/ms-util"
            echo "  Configuration stored in: /etc/mediascreen/"
            echo "  Logs written to: /var/log/mediascreen-installer.log"
            echo
            echo "After installation, use 'ms-util' to access the menu system."
            exit 0
            ;;
    esac
done

# Parse other arguments
for arg in "$@"; do
    case $arg in
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
        -h|--help)
            # Already handled above
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Update base URL based on arguments
if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
    base_url="$CUSTOM_GITHUB_URL"
    log "Using custom GitHub URL: $base_url"
elif [[ "$USE_DEV" == "true" ]]; then
    branch="dev"
    base_url="${base_repo_url}/${branch}"
    log "Using development branch for downloads"
fi

# Update config URL with new base URL
config_url="${base_url}/menu_config.txt"

# Check internet connectivity before proceeding (unless local-only mode)
if [[ "$LOCAL_ONLY" != "true" ]]; then
    check_internet || exit 1
fi

# Temporary directory for downloads
tmp_dir=$(mktemp -d)
log "Using temporary directory: $tmp_dir"

# Save original working directory for local-only mode
ORIGINAL_PWD="$PWD"

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
        log "Using existing configuration: $local_config"
    elif [[ -f "menu_config.txt" ]]; then
        local_config="menu_config.txt"
        log "Using local configuration: $local_config"
        cp "$local_config" "$CONFIG_DIR/menu_config.txt"
    elif [[ -f "../menu_config.txt" ]]; then
        local_config="../menu_config.txt"
        log "Using local configuration: $local_config"
        cp "$local_config" "$CONFIG_DIR/menu_config.txt"
    else
        log "ERROR: Local configuration file not found. Expected locations:"
        log "  - $CONFIG_DIR/menu_config.txt"
        log "  - ./menu_config.txt"
        log "  - ../menu_config.txt"
        exit 1
    fi
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
    
    # Look for local common library in multiple locations
    local_common=""
    if [[ -f "$ORIGINAL_PWD/lib/common.sh" ]]; then
        local_common="$ORIGINAL_PWD/lib/common.sh"
    elif [[ -f "lib/common.sh" ]]; then
        local_common="lib/common.sh"
    elif [[ -f "../lib/common.sh" ]]; then
        local_common="../lib/common.sh"
    elif [[ -f "$INSTALLER_DIR/lib/common.sh" ]]; then
        local_common="$INSTALLER_DIR/lib/common.sh"
        echo "Using existing common library: $local_common"
        # Don't copy if it's already in the right place
    else
        echo "ERROR: Local common library not found. Expected locations:"
        echo "  - $ORIGINAL_PWD/lib/common.sh"
        echo "  - ./lib/common.sh"
        echo "  - ../lib/common.sh"
        echo "  - $INSTALLER_DIR/lib/common.sh"
        exit 1
    fi
    
    if [[ -n "$local_common" && "$local_common" != "$INSTALLER_DIR/lib/common.sh" ]]; then
        echo "Using local common library: $local_common"
        cp "$local_common" "$INSTALLER_DIR/lib/common.sh"
        chmod 644 "$INSTALLER_DIR/lib/common.sh"
    fi
else
    echo "Downloading common library..."
    wget -q "${base_url}/lib/common.sh" -O "common.sh" || {
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
        if [[ -f "$ORIGINAL_PWD/scripts/${filename}" ]]; then
            local_script="$ORIGINAL_PWD/scripts/${filename}"
        elif [[ -f "scripts/${filename}" ]]; then
            local_script="scripts/${filename}"
        elif [[ -f "../scripts/${filename}" ]]; then
            local_script="../scripts/${filename}"
        else
            echo "WARNING: Local script not found: ${filename}"
            echo "Expected locations:"
            echo "  - $ORIGINAL_PWD/scripts/${filename}"
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

# Install ms-util.sh utility script
if [[ "$LOCAL_ONLY" == "true" ]]; then
    echo "Local-only mode: Using local ms-util.sh..."
    
    # Look for local ms-util.sh
    local_ms_util=""
    if [[ -f "$ORIGINAL_PWD/ms-util.sh" ]]; then
        local_ms_util="$ORIGINAL_PWD/ms-util.sh"
    elif [[ -f "ms-util.sh" ]]; then
        local_ms_util="ms-util.sh"
    elif [[ -f "../ms-util.sh" ]]; then
        local_ms_util="../ms-util.sh"
    else
        echo "WARNING: Local ms-util.sh not found. Expected locations:"
        echo "  - $ORIGINAL_PWD/ms-util.sh"
        echo "  - ./ms-util.sh"
        echo "  - ../ms-util.sh"
        echo "Creating symbolic link to install.sh as fallback..."
        ln -sf "$INSTALLER_DIR/install.sh" "/usr/local/bin/ms-util"
        echo "Created symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/install.sh"
    fi
    
    if [[ -n "$local_ms_util" ]]; then
        echo "Using local ms-util: $local_ms_util"
        cp "$local_ms_util" "$INSTALLER_DIR/ms-util.sh"
        chmod +x "$INSTALLER_DIR/ms-util.sh"
        ln -sf "$INSTALLER_DIR/ms-util.sh" "/usr/local/bin/ms-util"
        echo "Created symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/ms-util.sh"
    fi
else
    echo "Downloading ms-util.sh..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${base_url}/ms-util.sh" -o "$INSTALLER_DIR/ms-util.sh" || {
            echo "Failed to download ms-util.sh using curl. Creating fallback link..."
            ln -sf "$INSTALLER_DIR/install.sh" "/usr/local/bin/ms-util"
            echo "Created fallback symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/install.sh"
        }
    else
        wget -q "${base_url}/ms-util.sh" -O "$INSTALLER_DIR/ms-util.sh" || {
            echo "Failed to download ms-util.sh using wget. Creating fallback link..."
            ln -sf "$INSTALLER_DIR/install.sh" "/usr/local/bin/ms-util"
            echo "Created fallback symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/install.sh"
        }
    fi
    
    if [[ -f "$INSTALLER_DIR/ms-util.sh" ]]; then
        chmod +x "$INSTALLER_DIR/ms-util.sh"
        ln -sf "$INSTALLER_DIR/ms-util.sh" "/usr/local/bin/ms-util"
        echo "Created symbolic link: /usr/local/bin/ms-util -> $INSTALLER_DIR/ms-util.sh"
    fi
fi

# Copy/move install.sh to the installer directory
# Only copy if we have a valid script file (not when piped from curl/wget)
if [[ "$0" != "$INSTALLER_DIR/install.sh" && "$0" != "bash" && "$0" != "sh" && -f "$0" ]]; then
    echo "Installing main script to $INSTALLER_DIR/install.sh"
    cp "$0" "$INSTALLER_DIR/install.sh"
    chmod +x "$INSTALLER_DIR/install.sh"
elif [[ "$0" == "bash" || "$0" == "sh" || ! -f "$0" ]]; then
    # Script was piped from curl/wget, download it separately
    if [[ "$LOCAL_ONLY" != "true" ]]; then
        echo "Installing main script to $INSTALLER_DIR/install.sh"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "${base_url}/install.sh" -o "$INSTALLER_DIR/install.sh" || {
                echo "Warning: Failed to download install.sh using curl"
            }
        else
            wget -q "${base_url}/install.sh" -O "$INSTALLER_DIR/install.sh" || {
                echo "Warning: Failed to download install.sh using wget"
            }
        fi
        
        if [[ -f "$INSTALLER_DIR/install.sh" ]]; then
            chmod +x "$INSTALLER_DIR/install.sh"
        fi
    else
        echo "Local-only mode: Cannot install main script when piped from stdin"
    fi
fi

echo "Installation complete!"
echo "Use 'ms-util' command to access the MediaScreen utility menu."

# Autolaunch ms-util if requested
if [[ "$AUTOLAUNCH" == "true" ]]; then
    echo
    echo "Launching MediaScreen utility menu..."
    sleep 2
    
    # Check if ms-util was successfully installed
    if [[ -f "/usr/local/bin/ms-util" ]]; then
        # Pass through debug and dev options if they were used
        local autolaunch_args=""
        if [[ "$DEBUG_MODE" == "true" ]]; then
            autolaunch_args+=" --debug"
        fi
        if [[ "$USE_DEV" == "true" ]]; then
            autolaunch_args+=" --dev"
        fi
        if [[ -n "$CUSTOM_GITHUB_URL" ]]; then
            autolaunch_args+=" --github-url='$CUSTOM_GITHUB_URL'"
        fi
        
        # Execute ms-util with arguments
        exec /usr/local/bin/ms-util $autolaunch_args
    else
        echo "ERROR: ms-util was not installed properly. Cannot autolaunch."
        exit 1
    fi
fi