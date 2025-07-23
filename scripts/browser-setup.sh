#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

<<comment
    This script configures the browser to launch on startup.

    The script installs the required packages for browser launch, configures the browser 
    to launch on startup, and sets the URL for the browser.

    This script requires root privileges. Please run as root.

    Command Line Usage:
        - To configure the browser launch:
            sudo ./browser-setup.sh
        - To configure the browser launch with a specific username:
            sudo ./browser-setup.sh --username=<username>
        - To configure the browser launch with a specific url:
            sudo ./browser-setup.sh --url=<url>
        - To configure the browser launch with a specific username and url:
            sudo ./browser-setup.sh --username=<username> --url=<url>
        - Auto mode:
            sudo ./browser-setup.sh -y --username=<username> --url=<url>

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added common library, improved error handling, and security enhancements
comment

# Initialize common functionality
init_common "browser-setup"

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

validate_url() {
    local url="$1"
    
    # Basic URL format validation
    if [[ ! $url =~ ^https?://[a-zA-Z0-9.-]+([:/][^[:space:]]*)?$ ]]; then
        log_error "Invalid URL format. URL must start with http:// or https://" >&2
        return 1
    fi
    
    # Test URL accessibility if we have internet
    if check_internet; then
        log_info "Testing URL accessibility..." >&2
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL --max-time 10 --head "$url" >/dev/null 2>&1; then
                log_warn "URL may not be accessible: $url" >&2
                if [[ "$AUTO_INSTALL" != "true" ]]; then
                    if ! prompt_yes_no "Continue anyway?"; then
                        return 1
                    fi
                fi
            fi
        fi
    else
        log_warn "Cannot test URL accessibility (no internet connection)" >&2
    fi
    
    return 0
}

get_username() {
    if [[ -n "$USERNAME" ]]; then
        if ! id "$USERNAME" >/dev/null 2>&1; then
            log_error "User '$USERNAME' does not exist"
            return 1
        fi
        echo "$USERNAME"
        return 0
    fi
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log_error "Auto mode requires --username parameter"
        exit 1
    fi
    
    while true; do
        read -p "Enter the username for browser autologin: " username
        
        if [[ -z "$username" ]]; then
            echo "Username cannot be empty. Please try again."
            continue
        fi
        
        if ! id "$username" >/dev/null 2>&1; then
            echo "User '$username' does not exist."
            if prompt_yes_no "Would you like to create this user?"; then
                if validate_username "$username" && create_user_if_not_exists "$username"; then
                    echo "$username"
                    return 0
                fi
            fi
            continue
        fi
        
        echo "$username"
        return 0
    done
}

get_url() {
    if [[ -n "$URL" ]]; then
        if validate_url "$URL"; then
            echo "$URL"
            return 0
        else
            log_error "Invalid URL provided: $URL"
            return 1
        fi
    fi
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        log_error "Auto mode requires --url parameter"
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

install_browser_packages() {
    log_info "Installing required packages for browser launch..."
    
    # Update package cache first
    update_package_cache || {
        log_error "Failed to update package cache"
        return 1
    }
    
    # List of required packages
    local packages=(
        "xserver-xorg-video-all"
        "xserver-xorg-input-all" 
        "xserver-xorg-core"
        "xinit"
        "x11-xserver-utils"
        "chromium"
        "unclutter"
    )
    
    # Install packages
    for package in "${packages[@]}"; do
        case $package in
            "chromium")
                install_package "$package" "Chromium browser" || return 1
                ;;
            "unclutter")
                install_package "$package" "cursor hiding utility" || return 1
                ;;
            "xinit")
                install_package "$package" "X11 initialization" || return 1
                ;;
            *)
                install_package "$package" || return 1
                ;;
        esac
    done
    
    log_info "All required packages installed successfully"
}

create_xinitrc() {
    local username="$1"
    local url="$2"
    local xinitrc_file="/home/$username/.xinitrc"
    
    log_info "Creating .xinitrc file for user: $username"
    
    # Backup existing .xinitrc if it exists
    if [[ -f "$xinitrc_file" ]]; then
        backup_file "$xinitrc_file"
    fi
    
    # Create the .xinitrc file
    cat > "$xinitrc_file" << EOF
#!/usr/bin/env sh

# MediaScreen Browser Kiosk Configuration
# Generated by browser-setup.sh on $(date)

# Disable screensaver and power management
xset -dpms           # Disable DPMS (Display Power Management Signaling)
xset s off           # Disable screensaver
xset s noblank       # Disable screen blanking

# Get screen resolution dynamically
resolution=\$(xrandr | grep '*' | head -1 | awk '{ print \$1 }')
formatted_resolution=\$(echo "\$resolution" | sed 's/x/,/')

# Hide cursor when idle
unclutter -idle 1 &

# Launch Chromium in kiosk mode
exec chromium \\
    --window-size=\$formatted_resolution \\
    --window-position=0,0 \\
    --start-fullscreen \\
    --kiosk \\
    --noerrdialogs \\
    --disable-translate \\
    --no-first-run \\
    --fast \\
    --fast-start \\
    --disable-infobars \\
    --disable-features=TranslateUI,VizDisplayCompositor \\
    --overscroll-history-navigation=0 \\
    --disable-pinch \\
    --disable-background-timer-throttling \\
    --disable-renderer-backgrounding \\
    --disable-backgrounding-occluded-windows \\
    --disable-field-trial-config \\
    --disable-ipc-flooding-protection \\
    --enable-features=VaapiVideoDecoder \\
    --use-gl=egl \\
    --enable-zero-copy \\
    "$url"
EOF
    
    # Set proper ownership and permissions
    chown "$username:$username" "$xinitrc_file"
    chmod 755 "$xinitrc_file"
    
    log_info ".xinitrc created successfully for $username"
}

# Main execution
main() {
    log_info "Starting browser setup configuration..."
    
    # Get username
    local username
    username=$(get_username) || report_failure "Getting username"
    
    # Get URL
    local url
    url=$(get_url) || report_failure "Getting URL"
    
    log_info "Configuring browser for user '$username' with URL: $url"
    
    # Install required packages
    install_browser_packages || report_failure "Package installation"
    
    # Create .xinitrc configuration
    create_xinitrc "$username" "$url" || report_failure "Creating .xinitrc configuration"
    
    report_success "Browser setup configuration"
    
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        echo
        echo "Browser configuration completed successfully!"
        echo "User: $username"
        echo "URL: $url"
        echo
        echo "The browser will automatically launch when the user logs in."
        echo "To test the configuration, you can:"
        echo "  1. Switch to TTY1 (Ctrl+Alt+F1)"
        echo "  2. Log in as $username"
        echo "  3. Run: startx"
        echo
    fi
}

# Run main function
main