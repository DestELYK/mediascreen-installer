#!/bin/bash

# MediaScreen Installer Common Library
# Author: DestELYK
# Updated: 07-21-2025

# Strict error handling
set -euo pipefail

# Common variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/mediascreen-$$"
readonly GITHUB_BASE_REPO="https://raw.githubusercontent.com/DestELYK/mediascreen-installer"
GITHUB_BRANCH="main"
GITHUB_BASE_URL="${GITHUB_BASE_REPO}/${GITHUB_BRANCH}"
CUSTOM_GITHUB_URL=""

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARNING: $*"
}

log_error() {
    log "ERROR: $*"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG: $*"
    fi
}

# System checks
check_debian() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "System is not using Debian. This script only supports Debian-based systems."
        exit 1
    fi
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script requires root privileges. Please run as root or with sudo."
        exit 1
    fi
}

check_internet() {
    local attempts=0
    local max_attempts=3
    
    while [[ $attempts -lt $max_attempts ]]; do
        attempts=$((attempts + 1))
        log_debug "Testing internet connectivity (attempt $attempts/$max_attempts)..."
        
        if ping -q -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log_debug "Internet connectivity confirmed"
            return 0
        fi
        
        if [[ $attempts -lt $max_attempts ]]; then
            sleep 2
        fi
    done
    
    log_warn "No internet connectivity detected"
    return 1
}

# User management
validate_username() {
    local username="$1"
    
    if [[ ! $username =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]]; then
        log_error "Invalid username format. Use only alphanumeric characters, underscores, and hyphens."
        return 1
    fi
    
    if [[ ${#username} -gt 32 ]]; then
        log_error "Username too long. Maximum 32 characters allowed."
        return 1
    fi
    
    return 0
}

# Configuration file validation
validate_config() {
    local config_file="$1"
    local line_count
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    line_count=$(wc -l < "$config_file")
    if [[ $line_count -eq 0 ]]; then
        log_error "Configuration file is empty"
        return 1
    fi
    
    # Check for proper CSV format with 5 fields: menu_order,run_order,name,description,filename
    # run_order can be numeric or contain _ for manual-only items
    while IFS="" read -r line || [ -n "$line" ]; do
        if [[ -n "$line" && ! "$line" =~ ^[0-9]+,([0-9]+|[0-9]*_[0-9]*|_),[^,]+,[^,]+,[^,]+$ ]]; then
            log_error "Invalid configuration line format: $line"
            log_error "Expected format: menu_order,run_order,name,description,filename"
            log_error "run_order can be numeric (1,2,3...) or contain _ for manual-only items (_,1_,_2,etc.)"
            return 1
        fi
    done < "$config_file"
    
    log_info "Configuration file validated successfully ($line_count entries)"
    return 0
}

create_user_if_not_exists() {
    local username="$1"
    
    if ! validate_username "$username"; then
        return 1
    fi
    
    if ! id "$username" >/dev/null 2>&1; then
        log_info "Creating user: $username"
        useradd -m -s /bin/bash -p '*' "$username"
        log_info "User $username created successfully"
    else
        log_debug "User $username already exists"
    fi
}

# Package management
update_package_cache() {
    log_info "Updating package cache..."
    apt update -qq || {
        log_error "Failed to update package cache"
        return 1
    }
}

install_package() {
    local package="$1"
    local description="${2:-$package}"
    
    if ! dpkg -l | grep -q "^ii  $package "; then
        log_info "Installing $description..."
        apt install -y "$package" || {
            log_error "Failed to install $package"
            return 1
        }
        log_info "$description installed successfully"
    else
        log_debug "$description is already installed"
    fi
}

# File operations
download_file() {
    local url="$1"
    local output_file="$2"
    local description="${3:-file}"
    
    log_info "Downloading $description..."
    
    local download_success=false
    local http_code=""
    
    if command -v curl >/dev/null 2>&1; then
        http_code=$(curl -fsSL -w "%{http_code}" "$url" -o "$output_file" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            download_success=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "$url" -O "$output_file" 2>/dev/null; then
            download_success=true
            http_code="200"
        else
            # Try to get HTTP status from wget
            http_code=$(wget --spider -S "$url" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}' || echo "000")
        fi
    else
        log_error "Neither curl nor wget is available for downloading"
        return 1
    fi
    
    if [[ "$download_success" == "true" ]]; then
        log_info "$description downloaded successfully"
        return 0
    else
        # Handle specific error cases
        if [[ "$http_code" == "404" ]]; then
            log_error "File not found (404): $url"
            handle_404_error "$url"
        else
            log_error "Failed to download $description from $url (HTTP: $http_code)"
        fi
        return 1
    fi
}

# Handle 404 errors with helpful guidance
handle_404_error() {
    local failed_url="$1"
    
    log_error "The requested file was not found on GitHub."
    echo
    echo "This could happen for several reasons:"
    echo "1. The repository or branch doesn't exist"
    echo "2. The file path has changed"
    echo "3. You're using a fork with different structure"
    echo
    
    if [[ "${AUTO_INSTALL:-false}" == "true" ]]; then
        log_error "Running in auto mode - cannot prompt for custom URL"
        echo "To fix this, run the script manually with:"
        echo "  --github-url=https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/YOUR_BRANCH"
        return 1
    fi
    
    # Only suggest custom URL if not already using one
    if [[ -z "$CUSTOM_GITHUB_URL" ]]; then
        echo "You can specify a custom GitHub repository URL using:"
        echo "  --github-url=https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/YOUR_BRANCH"
        echo
        
        if prompt_yes_no "Do you want to continue with a custom GitHub URL?" "n"; then
            echo
            read -p "Enter the custom GitHub base URL: " custom_url
            if [[ -n "$custom_url" ]]; then
                GITHUB_BASE_URL="$custom_url"
                CUSTOM_GITHUB_URL="$custom_url"
                export GITHUB_BASE_URL
                export CUSTOM_GITHUB_URL
                log_info "Updated GitHub base URL to: $custom_url"
                echo "Please restart the script or try the operation again."
                return 0
            fi
        fi
    else
        log_error "Already using custom GitHub URL: $CUSTOM_GITHUB_URL"
        echo "The custom URL may be incorrect or the file may not exist."
    fi
    
    return 1
}

# Backup and restore
backup_file() {
    local file="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"
    
    if [[ -f "$file" ]]; then
        local backup_file="${file}${backup_suffix}"
        cp "$file" "$backup_file"
        log_info "Backed up $file to $backup_file"
        echo "$backup_file"
    fi
}

# Service management
enable_and_start_service() {
    local service="$1"
    
    log_info "Enabling and starting service: $service"
    systemctl enable "$service" || {
        log_error "Failed to enable service: $service"
        return 1
    }
    
    systemctl start "$service" || {
        log_error "Failed to start service: $service"
        return 1
    }
    
    log_info "Service $service is now running"
}

restart_service() {
    local service="$1"
    
    log_info "Restarting service: $service"
    systemctl restart "$service" || {
        log_error "Failed to restart service: $service"
        return 1
    }
}

# Argument parsing helpers
strip_quotes() {
    local value="$1"
    # Strip surrounding double quotes
    value="${value%\"}"
    value="${value#\"}"
    # Strip surrounding single quotes
    value="${value%\'}"
    value="${value#\'}"
    echo "$value"
}

# Argument parsing
parse_common_args() {
    local auto_install=false
    local username=""
    local url=""
    local debug=false
    local use_dev=false
    local github_url=""
    
    for arg in "$@"; do
        case $arg in
            -y|--auto)
                auto_install=true
                ;;
            --username=*)
                username="$(strip_quotes "${arg#*=}")"
                ;;
            --url=*)
                url="$(strip_quotes "${arg#*=}")"
                ;;
            --github-url=*)
                github_url="$(strip_quotes "${arg#*=}")"
                ;;
            --debug)
                debug=true
                export DEBUG=true
                ;;
            --dev)
                use_dev=true
                ;;
            -h|--help)
                echo "Common options:"
                echo "  -y, --auto        Run in automatic mode (non-interactive)"
                echo "  --username=USER   Specify username for operations"
                echo "  --url=URL         Specify URL for operations"
                echo "  --github-url=URL  Use custom GitHub repository URL for downloads"
                echo "  --debug           Enable debug logging"
                echo "  --dev             Use development branch instead of main"
                echo "  -h, --help        Show help message"
                return 2  # Special return code to indicate help was shown
                ;;
        esac
    done
    
    # Set GitHub base URL based on options
    if [[ -n "$github_url" ]]; then
        GITHUB_BASE_URL="$github_url"
        CUSTOM_GITHUB_URL="$github_url"
        log_info "Using custom GitHub URL: $github_url"
    elif [[ "$use_dev" == "true" ]]; then
        GITHUB_BRANCH="dev"
        GITHUB_BASE_URL="${GITHUB_BASE_REPO}/${GITHUB_BRANCH}"
        log_info "Using development branch for downloads"
    fi
    
    # Export variables for use in calling script
    export AUTO_INSTALL="$auto_install"
    export USERNAME="$username"
    export URL="$url"
    export DEBUG="$debug"
    export GITHUB_BASE_URL
    export CUSTOM_GITHUB_URL
    export GITHUB_BRANCH
}

# Interactive prompts
prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        if [[ "$default" == "y" ]]; then
            log_info "Auto mode: Answering 'yes' to: $question"
            return 0
        else
            log_info "Auto mode: Answering 'no' to: $question"
            return 1
        fi
    fi
    
    local prompt="$question"
    if [[ "$default" == "y" ]]; then
        prompt="$question [Y/n]: "
    else
        prompt="$question [y/N]: "
    fi
    
    while true; do
        read -p "$prompt" answer
        case ${answer:-$default} in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Parse and validate browser-users configuration
parse_browser_users() {
    local browser_users_string="$1"
    local -n parsed_users_ref=$2  # Reference to associative array
    local -n usernames_ref=$3     # Reference to array of usernames
    
    if [[ -z "$browser_users_string" ]]; then
        log_error "Browser users string is empty"
        return 1
    fi
    
    # Clear the arrays
    for key in "${!parsed_users_ref[@]}"; do
        unset parsed_users_ref["$key"]
    done
    usernames_ref=()
    
    local browser_count=0
    local seen_usernames=()
    
    # Parse comma-separated browser configurations
    IFS=',' read -ra BROWSER_PAIRS <<< "$browser_users_string"
    for pair in "${BROWSER_PAIRS[@]}"; do
        IFS=':' read -ra PARTS <<< "$pair"
        if [[ ${#PARTS[@]} -ne 3 ]]; then
            log_error "Invalid browser-users format: $pair"
            log_error "Expected format: user:tty:url"
            return 1
        fi
        
        local user="${PARTS[0]}"
        local tty="${PARTS[1]}"
        local url="${PARTS[2]}"
        
        # Validate username format
        if [[ ! $user =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]]; then
            log_error "Invalid username format: $user (use only alphanumeric characters, underscores, and hyphens)"
            return 1
        fi
        
        if [[ ${#user} -gt 32 ]]; then
            log_error "Username too long: $user (maximum 32 characters allowed)"
            return 1
        fi
        
        # Validate TTY format
        if [[ ! $tty =~ ^tty[0-9]+$ ]]; then
            log_error "Invalid TTY format: $tty (expected format: tty1, tty2, etc.)"
            return 1
        fi
        
        # Validate URL format
        if [[ ! $url =~ ^https?://[a-zA-Z0-9.-]+([:/][^[:space:]]*)?$ ]]; then
            log_error "Invalid URL format: $url (must start with http:// or https://)"
            return 1
        fi
        
        # Check if TTY is tty12 (reserved for menu)
        if [[ "$tty" == "tty12" ]]; then
            log_error "tty12 is reserved for menu. Use tty1-tty11 for browsers."
            return 1
        fi
        
        # Check for duplicate TTYs
        if [[ -n "${parsed_users_ref[$tty]:-}" ]]; then
            log_error "Duplicate TTY assignment: $tty"
            return 1
        fi
        
        # Store the configuration
        parsed_users_ref["$tty"]="$user:$url"
        
        # Track unique usernames
        if [[ ! " ${seen_usernames[*]} " =~ " $user " ]]; then
            seen_usernames+=("$user")
            usernames_ref+=("$user")
        fi
        
        browser_count=$((browser_count + 1))
        log_debug "Parsed browser config: $user -> $tty -> $url"
    done
    
    if [[ $browser_count -gt 11 ]]; then
        log_error "Too many browsers configured ($browser_count). Maximum 11 browsers allowed (tty12 is reserved for menu)."
        return 1
    fi
    
    log_info "Successfully parsed $browser_count browser configuration(s) for ${#usernames_ref[@]} unique user(s)"
    return 0
}

# Exit handling
setup_exit_handler() {
    function exit_prompt() {
        if [[ "${AUTO_INSTALL:-false}" == "true" ]]; then
            log_info "Auto mode: Exiting due to interrupt"
            exit 130
        fi
        
        echo
        if prompt_yes_no "Do you want to exit?"; then
            log_info "Exiting at user request"
            exit 130
        fi
    }
    
    trap exit_prompt SIGINT
}

# Cleanup
cleanup_temp_files() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary files in $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Setup cleanup on exit
trap cleanup_temp_files EXIT

# Initialization function
init_common() {
    local script_name="$1"
    
    setup_exit_handler
    mkdir -p "$TEMP_DIR"
    
    log_info "Starting $script_name"
    log_debug "Temporary directory: $TEMP_DIR"
}

# Success/failure reporting
report_success() {
    local operation="$1"
    log_info "$operation completed successfully"
}

report_failure() {
    local operation="$1"
    local exit_code="${2:-1}"
    log_error "$operation failed"
    exit "$exit_code"
}
