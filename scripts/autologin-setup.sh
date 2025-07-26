#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/../lib/common.sh"; then
    echo "ERROR: Failed to load common library from $SCRIPT_DIR/../lib/common.sh"
    echo "Please ensure the common library is installed and accessible."
    exit 1
fi

<<comment
    This script sets up autologin for multiple browser users and one menu user on different TTYs,
    including browser package installation and URL configuration.

    The script creates users if they do not exist, installs browser packages, sets up autologin 
    for browser users on specified TTYs with URLs, sets up menu autologin on a specified TTY, 
    and masks unused getty services.

    This script requires root privileges. Please run as root.

    Command line usage:
        - To set up multiple browser autologins with URLs:
            sudo ./autologin-setup.sh --browser-users="user1:tty1:https://site1.com,user2:tty3:https://site2.com" --menu-tty=tty2
        - To set up multiple browser autologins without URLs (configure URLs interactively):
            sudo ./autologin-setup.sh --browser-users="user1:tty1,user2:tty3" --menu-tty=tty2
        - Auto mode with URLs:
            sudo ./autologin-setup.sh -y --browser-users="user1:tty1:https://site1.com,user2:tty3:https://site2.com" --menu-tty=tty2

    Note: This script includes browser-setup functionality. URLs are configured during 
    the autologin setup process either via --browser-users parameter or interactive prompts.

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-22-2025 - Merged browser-setup functionality, added URL configuration, removed legacy support
comment

# Initialize common functionality
init_common "autologin-setup"

# System checks
check_debian
check_root

# Default configuration
BROWSER_USERS=""
MENU_TTY=""

# Parse common arguments first to set up GITHUB_BASE_URL and other common variables
if ! parse_common_args "$@"; then
    case $? in
        2) 
            echo "Additional options:"
            echo "  --browser-users=LIST   Browser users with TTYs and URLs"
            echo "                         Format: user1:tty1:url1,user2:tty2:url2"
            echo "                         URLs are optional: user1:tty1,user2:tty2"
            echo "  --menu-tty=TTY         TTY for menu autologin (e.g., tty2)"
            exit 0
            ;;
        *) 
            # Continue execution even if common args parsing had issues
            log_debug "parse_common_args returned non-zero, continuing anyway"
            ;;
    esac
fi

# Parse custom arguments after common args are processed
for arg in "$@"; do
    case $arg in
        --browser-users=*)
            BROWSER_USERS="$(strip_quotes "${arg#*=}")"
            ;;
        --menu-tty=*)
            MENU_TTY="$(strip_quotes "${arg#*=}")"
            ;;
        *)
            # Skip common arguments that were already processed
            ;;
    esac
done

# Validate TTY format
validate_tty() {
    local tty="$1"
    
    if [[ ! $tty =~ ^tty([1-9]|1[0-2])$ ]]; then
        log_error "Invalid TTY format: $tty. Use format: tty1, tty2, etc."
        return 1
    fi
    
    local tty_num="${tty#tty}"
    if [[ $tty_num -lt 1 || $tty_num -gt 12 ]]; then
        log_error "TTY number out of range: $tty_num. Use TTY 1-12."
        return 1
    fi
    
    return 0
}

# Validate URL format
validate_url() {
    local url="$1"
    
    # Basic URL format validation
    if [[ ! $url =~ ^https?://[a-zA-Z0-9.-]+([:/][^[:space:]]*)?$ ]]; then
        log_error "Invalid URL format. URL must start with http:// or https://"
        return 1
    fi
    
    # Test URL accessibility if we have internet
    if check_internet; then
        log_info "Testing URL accessibility..."
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL --max-time 10 --head "$url" >/dev/null 2>&1; then
                log_warn "URL may not be accessible: $url"
                if [[ "$AUTO_INSTALL" != "true" ]]; then
                    if ! prompt_yes_no "Continue anyway?"; then
                        return 1
                    fi
                fi
            fi
        fi
    else
        log_warn "Cannot test URL accessibility (no internet connection)"
    fi
    
    return 0
}

# Store TTY-URL mapping
store_tty_url_mapping() {
    local tty="$1"
    local url="$2"
    local config_dir="/etc/mediascreen"
    local config_file="$config_dir/tty-urls.conf"
    
    log_info "Storing TTY-URL mapping: $tty -> $url"
    
    # Create config directory if it doesn't exist
    mkdir -p "$config_dir" || {
        log_error "Failed to create config directory: $config_dir"
        return 1
    }
    
    # Create or update the configuration file
    # Remove existing entry for this TTY if it exists
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"
        grep -v "^$tty=" "$config_file" > "$config_file.tmp" 2>/dev/null || true
        mv "$config_file.tmp" "$config_file"
    fi
    
    # Add new entry
    echo "$tty=$url" >> "$config_file"
    chmod 644 "$config_file"
    
    log_info "TTY-URL mapping stored in $config_file"
}

# Get URL for browser configuration
get_url() {
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log_error "Auto mode requires URL to be specified in --browser-users parameter"
        exit 1
    fi
    
    local attempts=0
    local max_attempts=3
    
    while [[ $attempts -lt $max_attempts ]]; do
        attempts=$((attempts + 1))
        read -p "Enter the URL to launch in browser: " url
        
        if [[ -z "$url" ]]; then
            echo "URL cannot be empty. Please try again."
            continue
        fi
        
        if validate_url "$url"; then
            echo "$url"
            return 0
        fi
        
        if [[ $attempts -lt $max_attempts ]]; then
            echo "Please try again ($((max_attempts - attempts)) attempts remaining)."
        fi
    done
    
    log_error "Failed to get valid URL after $max_attempts attempts"
    return 1
}

# Install browser packages
install_browser_packages() {
    log_info "Installing required packages for browser launch..."
    
    # Update package cache first
    update_package_cache || {
        log_error "Failed to update package cache"
        return 1
    }
    
    # Install core X11 packages without recommended packages (lighter install)
    install_package "xserver-xorg-core xinit x11-xserver-utils" "core X11 packages" "true" || return 1
    
    # Install video and input drivers with recommendations (for hardware compatibility)
    install_package "xserver-xorg-video-all xserver-xorg-input-all" "X11 drivers" || return 1
    
    # Install browser and utilities
    install_package "chromium unclutter" "browser and utilities" || return 1
    
    log_info "All required packages installed successfully"
}

# Create dynamic xinitrc for user
create_xinitrc() {
    local username="$1"
    local xinitrc_file="/home/$username/.xinitrc"
    
    log_info "Creating dynamic .xinitrc file for user: $username"
    
    # Backup existing .xinitrc if it exists
    if [[ -f "$xinitrc_file" ]]; then
        backup_file "$xinitrc_file"
    fi
    
    # Create the .xinitrc file that reads from TTY configuration
    cat > "$xinitrc_file" << 'EOF'
#!/usr/bin/env sh

# MediaScreen Browser Kiosk Configuration
# Dynamic TTY-based URL loading
# Generated by autologin-setup.sh on $(date)

# Disable screensaver and power management
xset -dpms           # Disable DPMS (Display Power Management Signaling)
xset s off           # Disable screensaver
xset s noblank       # Disable screen blanking

# Get current TTY
current_tty=$(tty | sed 's#/dev/##')

# Read URL from configuration file
config_file="/etc/mediascreen/tty-urls.conf"
url=""

if [ -f "$config_file" ]; then
    url=$(grep "^${current_tty}=" "$config_file" | cut -d'=' -f2-)
fi

# Fallback to default URL if no configuration found
if [ -z "$url" ]; then
    url="https://www.google.com"
    echo "Warning: No URL configured for $current_tty, using default: $url"
fi

echo "Loading URL for $current_tty: $url"

# Get screen resolution dynamically
resolution=$(xrandr | grep '*' | head -1 | awk '{ print $1 }')
formatted_resolution=$(echo "$resolution" | sed 's/x/,/')

# Hide cursor when idle
unclutter -idle 1 &

# Launch Chromium in kiosk mode
exec chromium \
    --window-size=$formatted_resolution \
    --window-position=0,0 \
    --start-fullscreen \
    --kiosk \
    --noerrdialogs \
    --disable-translate \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-infobars \
    --disable-features=TranslateUI,VizDisplayCompositor \
    --overscroll-history-navigation=0 \
    --disable-pinch \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-backgrounding-occluded-windows \
    --disable-field-trial-config \
    --disable-ipc-flooding-protection \
    --enable-features=VaapiVideoDecoder \
    --use-gl=egl \
    --enable-zero-copy \
    "$url"
EOF
    
    # Set proper ownership and permissions
    chown "$username:$username" "$xinitrc_file"
    chmod 755 "$xinitrc_file"
    
    log_info ".xinitrc created successfully for $username"
}

# Check if TTY has URL configured
check_tty_url_configured() {
    local tty="$1"
    local config_file="/etc/mediascreen/tty-urls.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "No TTY-URL configuration file found at $config_file"
        return 1
    fi
    
    if grep -q "^$tty=" "$config_file"; then
        local url=$(grep "^$tty=" "$config_file" | cut -d'=' -f2-)
        log_info "TTY $tty is configured with URL: $url"
        return 0
    else
        log_warn "TTY $tty has no URL configured in $config_file"
        return 1
    fi
}

get_username() {
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log_error "Auto mode requires --browser-users parameter"
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

setup_browser_autologin() {
    local username="$1"
    local tty="$2"
    local url="${3:-}"  # Optional URL parameter
    
    log_info "Setting up browser autologin for $username on $tty..."
    
    # Validate inputs
    validate_username "$username" || return 1
    validate_tty "$tty" || return 1
    
    # Create user if needed
    create_user_if_not_exists "$username" || {
        log_error "Failed to create user: $username"
        return 1
    }
    
    # Install browser packages
    install_browser_packages || {
        log_error "Failed to install browser packages"
        return 1
    }
    
    # Store URL mapping if URL provided
    if [[ -n "$url" ]]; then
        if validate_url "$url"; then
            store_tty_url_mapping "$tty" "$url" || {
                log_error "Failed to store TTY-URL mapping"
                return 1
            }
        else
            log_error "Invalid URL provided: $url"
            return 1
        fi
    fi
    
    # Create xinitrc for the user
    create_xinitrc "$username" || {
        log_error "Failed to create .xinitrc for $username"
        return 1
    }
    
    # Create systemd override for the specified TTY
    create_systemd_override "$tty" "$username" || {
        log_error "Failed to create systemd override for $tty"
        return 1
    }
    
    # Download and setup browser autologin profile
    local profile_file="/home/$username/.bash_profile"
    local temp_file="$TEMP_DIR/browser_profile_$username"
    
    download_file "$GITHUB_BASE_URL/autologin/browser-dynamic" "$temp_file" "dynamic browser autologin profile" || {
        log_error "Failed to download dynamic browser autologin profile"
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
    
    # Check if TTY has URL configured
    if ! check_tty_url_configured "$tty"; then
        if [[ -z "$url" ]]; then
            log_warn "TTY $tty has no URL configured."
            log_warn "Consider using --browser-users format: user:tty:url"
        fi
    fi
    
    log_info "Browser autologin setup completed for $username on $tty"
}

setup_menu_autologin() {
    local tty="$1"
    
    log_info "Setting up menu autologin for root on $tty..."
    
    # Validate TTY
    validate_tty "$tty" || return 1
    
    # Create systemd override for the specified TTY
    create_systemd_override "$tty" "root" || {
        log_error "Failed to create systemd override for $tty"
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
    
    log_info "Menu autologin setup completed for root on $tty"
}

manage_getty_services() {
    local -a used_ttys
    
    log_info "Managing getty services..."
    
    # Collect all used TTYs
    for i in "${!BROWSER_USER_LIST[@]}"; do
        used_ttys+=("${BROWSER_TTY_LIST[$i]}")
    done
    
    if [[ -n "$MENU_TTY" ]]; then
        used_ttys+=("$MENU_TTY")
    fi
    
    log_info "Used TTYs: ${used_ttys[*]}"
    
    # Mask all getty services from tty1 to tty12, except the ones we're using
    for tty_num in {1..12}; do
        local tty="tty$tty_num"
        local service="getty@${tty}.service"
        
        # Check if this TTY is in use
        local in_use=false
        for used_tty in "${used_ttys[@]}"; do
            if [[ "$used_tty" == "$tty" ]]; then
                in_use=true
                break
            fi
        done
        
        if [[ "$in_use" == "true" ]]; then
            log_info "Enabling $service (in use)"
            systemctl unmask "$service" 2>/dev/null || true
            systemctl enable "$service" || log_warn "Failed to enable $service"
        else
            log_info "Masking $service (not in use)"
            systemctl mask "$service" || log_warn "Failed to mask $service"
        fi
    done
}

reload_systemd_and_restart_getty() {
    log_info "Reloading systemd and restarting getty services..."
    
    systemctl daemon-reload || {
        log_error "Failed to reload systemd daemon"
        return 1
    }
    
    # Restart getty services that are enabled
    for i in "${!BROWSER_USER_LIST[@]}"; do
        local tty="${BROWSER_TTY_LIST[$i]}"
        local service="getty@${tty}.service"
        
        systemctl restart "$service" || {
            log_warn "Failed to restart $service"
        }
    done
    
    if [[ -n "$MENU_TTY" ]]; then
        local service="getty@${MENU_TTY}.service"
        systemctl restart "$service" || {
            log_warn "Failed to restart $service"
        }
    fi
    
    log_info "Services restarted successfully"
}

# Interactive configuration
interactive_config() {
    echo
    echo "=== MediaScreen Autologin Configuration ==="
    echo
    
    # Get browser users
    declare -ga BROWSER_USER_LIST
    declare -ga BROWSER_TTY_LIST
    declare -ga BROWSER_URL_LIST
    
    # Ask how many browsers to configure
    local num_browsers=0
    while [[ $num_browsers -lt 1 || $num_browsers -gt 10 ]]; do
        read -p "How many browser instances would you like to configure? (1-10): " num_browsers
        
        if [[ ! "$num_browsers" =~ ^[0-9]+$ ]] || [[ $num_browsers -lt 1 || $num_browsers -gt 10 ]]; then
            echo "Please enter a number between 1 and 10."
            num_browsers=0
        fi
    done
    
    echo
    echo "Setting up $num_browsers browser instance(s)..."
    echo
    
    # Configure each browser
    for ((i=1; i<=num_browsers; i++)); do
        echo "=== Browser $i of $num_browsers ==="
        
        local username=""
        local tty=""
        local url=""
        
        # Get username
        while [[ -z "$username" ]]; do
            read -p "Enter username for browser $i: " username
            
            if ! validate_username "$username"; then
                username=""
                echo "Please try again with a valid username."
                continue
            fi
            
            # Check if username is already used
            for existing_user in "${BROWSER_USER_LIST[@]}"; do
                if [[ "$existing_user" == "$username" ]]; then
                    echo "Username '$username' is already used. Please choose another."
                    username=""
                    break
                fi
            done
        done
        
        # Get TTY
        while [[ -z "$tty" ]]; do
            read -p "Enter TTY for $username (e.g., tty1, tty3): " tty
            
            if ! validate_tty "$tty"; then
                tty=""
                echo "Please try again with a valid TTY (tty1-tty12)."
                continue
            fi
            
            # Check if TTY is already used
            for used_tty in "${BROWSER_TTY_LIST[@]}"; do
                if [[ "$used_tty" == "$tty" ]]; then
                    echo "TTY $tty is already assigned. Please choose another."
                    tty=""
                    break
                fi
            done
        done
        
        # Get URL
        while [[ -z "$url" ]]; do
            read -p "Enter URL for $username on $tty (e.g., https://example.com): " url
            
            if [[ -z "$url" ]]; then
                echo "URL cannot be empty. Please try again."
                continue
            fi
            
            if ! validate_url "$url"; then
                url=""
                echo "Please try again with a valid URL."
            fi
        done
        
        BROWSER_USER_LIST+=("$username")
        BROWSER_TTY_LIST+=("$tty")
        BROWSER_URL_LIST+=("$url")
        
        echo "Added: $username on $tty -> $url"
        
        read -p "Add another browser user? (y/n): " add_another
        if [[ ! "$add_another" =~ ^[Yy]$ ]]; then
            add_more=false
        fi
    done
    
    # Get menu TTY
    if [[ ${#BROWSER_USER_LIST[@]} -gt 0 ]]; then
        echo
        read -p "Configure menu autologin? (y/n): " setup_menu
        
        if [[ "$setup_menu" =~ ^[Yy]$ ]]; then
            while [[ -z "$MENU_TTY" ]]; do
                read -p "Enter TTY for menu (e.g., tty2): " MENU_TTY
                
                if ! validate_tty "$MENU_TTY"; then
                    MENU_TTY=""
                    echo "Please try again with a valid TTY (tty1-tty12)."
                    continue
                fi
                
                # Check if TTY is already used
                for used_tty in "${BROWSER_TTY_LIST[@]}"; do
                    if [[ "$used_tty" == "$MENU_TTY" ]]; then
                        echo "TTY $MENU_TTY is already assigned to a browser user. Please choose another."
                        MENU_TTY=""
                        break
                    fi
                done
            done
        fi
    fi
    
    # Show summary
    echo
    echo "Configuration Summary:"
    echo "Browser autologins:"
    for i in "${!BROWSER_USER_LIST[@]}"; do
        echo "  ${BROWSER_USER_LIST[$i]} -> ${BROWSER_TTY_LIST[$i]} -> ${BROWSER_URL_LIST[$i]}"
    done
    
    if [[ -n "$MENU_TTY" ]]; then
        echo "Menu autologin: root -> $MENU_TTY"
    fi
    
    echo
    if ! prompt_yes_no "Proceed with this configuration?" "y"; then
        log_info "Configuration cancelled"
        exit 0
    fi
}

# Main execution
main() {
    log_info "Starting autologin configuration..."
    
    # Parse browser users if provided
    if [[ -n "$BROWSER_USERS" ]]; then
        # Initialize arrays
        declare -ga BROWSER_USER_LIST=()
        declare -ga BROWSER_TTY_LIST=()
        declare -ga BROWSER_URL_LIST=()
        
        # Use common library function for parsing
        declare -A parsed_browsers
        declare -a unique_usernames
        
        if parse_browser_users "$BROWSER_USERS" parsed_browsers unique_usernames; then
            # Convert from common library format to local arrays
            for tty in "${!parsed_browsers[@]}"; do
                local user_url="${parsed_browsers[$tty]}"
                local user="${user_url%%:*}"
                local url="${user_url#*:}"
                
                BROWSER_USER_LIST+=("$user")
                BROWSER_TTY_LIST+=("$tty")
                BROWSER_URL_LIST+=("$url")
                
                if [[ -n "$url" ]]; then
                    log_debug "Added browser user: $user on $tty with URL: $url"
                else
                    log_debug "Added browser user: $user on $tty (no URL specified)"
                fi
            done
        else
            report_failure "Parsing browser users with common library"
        fi
    else
        # Initialize empty arrays if no browser users provided
        declare -ga BROWSER_USER_LIST=()
        declare -ga BROWSER_TTY_LIST=()
        declare -ga BROWSER_URL_LIST=()
    fi
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        # Auto mode validation
        if [[ ${#BROWSER_USER_LIST[@]} -eq 0 ]]; then
            log_error "Auto mode requires --browser-users parameter"
            exit 1
        fi
        
        log_info "Running in auto mode"
        
        # Show configuration
        log_info "Browser users: ${BROWSER_USER_LIST[*]}"
        log_info "Browser TTYs: ${BROWSER_TTY_LIST[*]}"
        
        # Show URLs if configured
        local has_urls=false
        for i in "${!BROWSER_URL_LIST[@]}"; do
            if [[ -n "${BROWSER_URL_LIST[$i]}" ]]; then
                has_urls=true
                break
            fi
        done
        
        if [[ "$has_urls" == "true" ]]; then
            log_info "Browser URLs configured:"
            for i in "${!BROWSER_USER_LIST[@]}"; do
                if [[ -n "${BROWSER_URL_LIST[$i]:-}" ]]; then
                    log_info "  ${BROWSER_USER_LIST[$i]} (${BROWSER_TTY_LIST[$i]}): ${BROWSER_URL_LIST[$i]}"
                else
                    log_info "  ${BROWSER_USER_LIST[$i]} (${BROWSER_TTY_LIST[$i]}): No URL specified"
                fi
            done
        fi
        
        if [[ -n "$MENU_TTY" ]]; then
            log_info "Menu TTY: $MENU_TTY"
        fi
        
    else
        # Interactive mode
        if [[ ${#BROWSER_USER_LIST[@]} -eq 0 ]]; then
            interactive_config
        else
            echo "Using provided configuration:"
            for i in "${!BROWSER_USER_LIST[@]}"; do
                if [[ -n "${BROWSER_URL_LIST[$i]:-}" ]]; then
                    echo "  Browser: ${BROWSER_USER_LIST[$i]} -> ${BROWSER_TTY_LIST[$i]} -> ${BROWSER_URL_LIST[$i]}"
                else
                    echo "  Browser: ${BROWSER_USER_LIST[$i]} -> ${BROWSER_TTY_LIST[$i]} -> No URL specified"
                fi
            done
            
            if [[ -n "$MENU_TTY" ]]; then
                echo "  Menu: root -> $MENU_TTY"
            fi
            
            echo
            if ! prompt_yes_no "Proceed with this configuration?" "y"; then
                log_info "Configuration cancelled"
                exit 0
            fi
        fi
    fi
    
    # Setup browser autologins
    for i in "${!BROWSER_USER_LIST[@]}"; do
        local username="${BROWSER_USER_LIST[$i]}"
        local tty="${BROWSER_TTY_LIST[$i]}"
        
        # Check for URL from parsed browser users
        local url=""
        if [[ -n "${BROWSER_URL_LIST[$i]:-}" ]]; then
            url="${BROWSER_URL_LIST[$i]}"
            log_debug "Using URL from browser users: $url"
        fi
        
        if [[ -n "$url" ]]; then
            setup_browser_autologin "$username" "$tty" "$url" || report_failure "Browser autologin setup for $username"
        else
            setup_browser_autologin "$username" "$tty" || report_failure "Browser autologin setup for $username"
        fi
    done
    
    # Setup menu autologin if specified
    if [[ -n "$MENU_TTY" ]]; then
        setup_menu_autologin "$MENU_TTY" || report_failure "Menu autologin setup"
    fi
    
    # Manage getty services (mask unused ones)
    manage_getty_services || log_warn "Issues managing getty services"
    
    report_success "Autologin configuration"
    
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        echo
        echo "Autologin has been configured. The changes will take effect after reboot."
        echo
        echo "Browser autologin configuration:"
        for i in "${!BROWSER_USER_LIST[@]}"; do
            local tty="${BROWSER_TTY_LIST[$i]}"
            local username="${BROWSER_USER_LIST[$i]}"
            if check_tty_url_configured "$tty" >/dev/null 2>&1; then
                local url=$(grep "^$tty=" "/etc/mediascreen/tty-urls.conf" 2>/dev/null | cut -d'=' -f2-)
                echo "  $tty: $username (browser autologin) -> $url"
            else
                echo "  $tty: $username (browser autologin) -> No URL configured"
            fi
        done
        
        if [[ -n "$MENU_TTY" ]]; then
            echo "  $MENU_TTY: root (menu autologin)"
        fi
        
        echo
        echo "Unused TTY services have been masked."
        echo
        
        if prompt_yes_no "Would you like to reboot now to activate autologin?" "n"; then
            log_info "Rebooting system..."
            reboot
        fi
        
    
        # Reload systemd and restart services
        reload_systemd_and_restart_getty || log_warn "Some services failed to restart"
    fi
}

# Run main function
main