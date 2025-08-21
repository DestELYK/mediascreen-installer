#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/../lib/common.sh"; then
    echo "ERROR: Failed to load common library"
    echo "Please ensure MediaScreen installer components are properly installed."
    exit 1
fi

<<comment
    This script sets up a splash screen for the Debian System.

    The script installs Plymouth and Plymouth themes, allows the user to add a boot logo,
    and configures the default Plymouth theme for a professional boot experience.

    This script requires root privileges. Please run as root.

    Command Line Usage:
        - Interactive setup:
            sudo ./splashscreen-setup.sh
        - Auto mode with URL:
            sudo ./splashscreen-setup.sh -y --url=<image_url>
        - Auto mode with default theme:
            sudo ./splashscreen-setup.sh -y

    Author: DestELYK
    Date: 07-09-2024
    Updated: 07-21-2025 - Added common library, improved image handling, and theme management
comment

# Initialize common functionality
init_common "splashscreen-setup"

# System checks
check_debian
check_root

# Exit prompt function (matching main branch style)
exit_prompt() {
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

trap exit_prompt SIGINT

# Parse arguments
SPLASH_MODE=""
for arg in "$@"; do
    case $arg in
        --splash-mode=*)
            SPLASH_MODE="$(strip_quotes "${arg#*=}")"
            ;;
        --logo-url=*)
            # This will be handled by parse_common_args
            ;;
    esac
done

if ! parse_common_args "$@"; then
    case $? in
        2) 
            echo "Additional splash screen options:"
            echo "  --splash-mode=MODE     Splash screen mode (url|upload|manual|default)"
            echo "  --logo-url=URL         Logo image URL (sets mode to 'url' automatically)"
            exit 0
            ;;
        *) 
            # Continue execution even if common args parsing had issues
            log_debug "parse_common_args returned non-zero, continuing anyway"
            ;;
    esac
fi

# Plymouth themes configuration
readonly PLYMOUTH_THEMES_DIR="/usr/share/plymouth/themes"
readonly CUSTOM_THEME_NAME="mediascreen"
readonly CUSTOM_THEME_DIR="$PLYMOUTH_THEMES_DIR/$CUSTOM_THEME_NAME"

# Install Plymouth packages
install_plymouth() {
    log_info "Installing Plymouth and themes..."
    
    update_package_cache || {
        log_error "Failed to update package cache"
        return 1
    }
    
    # Install packages using the simplified approach
    install_package "plymouth plymouth-themes python3 net-tools" "Plymouth packages and utilities" || {
        log_error "Failed to install Plymouth packages"
        return 1
    }
    
    log_info "Plymouth packages installed successfully"
}

# List available Plymouth themes
list_available_themes() {
    log_info "Available Plymouth themes:"
    
    if [[ -d "$PLYMOUTH_THEMES_DIR" ]]; then
        for theme_dir in "$PLYMOUTH_THEMES_DIR"/*; do
            if [[ -d "$theme_dir" ]]; then
                local theme_name=$(basename "$theme_dir")
                if [[ -f "$theme_dir/$theme_name.plymouth" ]]; then
                    echo "  - $theme_name"
                fi
            fi
        done
    else
        log_warn "Plymouth themes directory not found"
    fi
}

# Validate image URL
validate_image_url() {
    local url="$1"
    
    # Basic URL validation
    if [[ ! $url =~ ^https?://.*\.(png|jpg|jpeg|gif|bmp)$ ]]; then
        log_error "URL must be a valid HTTP/HTTPS link to an image file (png, jpg, jpeg, gif, bmp)"
        return 1
    fi
    
    # Test URL accessibility
    if check_internet; then
        log_info "Testing image URL accessibility..."
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL --max-time 10 --head "$url" >/dev/null 2>&1; then
                log_info "Image URL is accessible"
                return 0
            else
                log_error "Image URL is not accessible or does not exist"
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q --spider --timeout=10 "$url" 2>/dev/null; then
                log_info "Image URL is accessible"
                return 0
            else
                log_error "Image URL is not accessible or does not exist"
                return 1
            fi
        fi
    else
        log_warn "Cannot test URL accessibility (no internet connection)"
    fi
    
    return 0
}

# Download watermark image
download_watermark() {
    local url="$1"
    local output_file="$2"
    
    log_info "Downloading watermark image from URL..."
    
    if ! validate_image_url "$url"; then
        return 1
    fi
    
    download_file "$url" "$output_file" "watermark image" || {
        log_error "Failed to download watermark image"
        return 1
    }
    
    # Verify it's actually an image file
    if command -v file >/dev/null 2>&1; then
        local file_type
        file_type=$(file -b --mime-type "$output_file")
        
        if [[ ! $file_type =~ ^image/ ]]; then
            log_error "Downloaded file is not a valid image (detected: $file_type)"
            rm -f "$output_file"
            return 1
        fi
        
        log_info "Downloaded image verified (type: $file_type)"
    fi
    
    return 0
}

# Create upload server
create_upload_server() {
    local upload_dir="$1"
    local port="${2:-8080}"
    
    # Create upload directory
    mkdir -p "$upload_dir"
    
    echo "Downloading upload interface from GitHub..."
    echo -n "Progress: "
    
    # Download HTML upload page from GitHub
    local html_url="$GITHUB_BASE_URL/image-upload/index.html"
    if download_file "$html_url" "$upload_dir/index.html" "upload interface" 2>/dev/null; then
        echo " COMPLETE!"
        echo "Upload interface downloaded successfully"
    else
        echo " FAILED"
        log_error "Failed to download upload interface from GitHub"
        return 1
    fi
    
    # Download Python upload server script from GitHub
    echo -n "Downloading server script: "
    local server_url="$GITHUB_BASE_URL/image-upload/server.py"
    if download_file "$server_url" "$upload_dir/server.py" "server script" 2>/dev/null; then
        echo " COMPLETE!"
        chmod +x "$upload_dir/server.py"
        echo "Server script downloaded successfully"
    else
        echo " FAILED"
        log_error "Failed to download server script from GitHub"
        return 1
    fi
    
    log_info "Upload server files ready"
    return 0
}

# Start upload server
start_upload_server() {
    local upload_dir="$1"
    local port="${2:-8080}"
    
    log_info "Starting upload server on port $port..."
    
    # Check if Python3 is available
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 is required for the upload server but not installed"
        return 1
    fi
    
    # Find an available port
    local test_port=$port
    local max_attempts=100
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Check if port is in use (try multiple methods)
        local port_in_use=false
        
        if command -v netstat >/dev/null 2>&1; then
            if netstat -ln 2>/dev/null | grep -q ":$test_port "; then
                port_in_use=true
            fi
        elif command -v ss >/dev/null 2>&1; then
            if ss -ln 2>/dev/null | grep -q ":$test_port "; then
                port_in_use=true
            fi
        else
            # Fallback: try to bind to the port briefly
            if python3 -c "
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('', $test_port))
    s.close()
except:
    exit(1)
" 2>/dev/null; then
                port_in_use=false
            else
                port_in_use=true
            fi
        fi
        
        if [[ "$port_in_use" == "false" ]]; then
            break
        fi
        
        test_port=$((test_port + 1))
        attempts=$((attempts + 1))
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        log_error "Could not find an available port after $max_attempts attempts"
        return 1
    fi
    
    if [[ $test_port -ne $port ]]; then
        log_info "Port $port is busy, using port $test_port instead"
        port=$test_port
    fi
    
    # Start server in background
    cd "$upload_dir"
    python3 server.py $port &
    local server_pid=$!
    
    # Wait a moment for server to start
    sleep 2
    
    # Check if server is running
    if ! kill -0 $server_pid 2>/dev/null; then
        log_error "Failed to start upload server"
        return 1
    fi
    
    echo "$server_pid:$port"
    return 0
}

# Handle web upload
handle_web_upload() {
    local target_file="$1"
    local upload_dir="$TEMP_DIR/upload"
    
    echo
    echo "=========================================="
    echo "   MediaScreen Web Upload Setup"
    echo "=========================================="
    echo
    
    # Step 1: Prepare upload server
    echo "[1/4] Preparing upload server..."
    create_upload_server "$upload_dir" || {
        log_error "Failed to create upload server"
        return 1
    }
    echo "      Server files ready"
    
    # Step 2: Start server
    echo "[2/4] Starting upload server..."
    local server_info
    server_info=$(start_upload_server "$upload_dir") || {
        log_error "Failed to start upload server"
        return 1
    }
    
    local server_pid="${server_info%:*}"
    local port="${server_info#*:}"
    echo "      Server started on port $port"
    
    # Step 3: Display access information
    echo "[3/4] Server ready for uploads"
    echo
    echo "Upload your watermark image using any of these URLs:"
    echo
    
    # Show all available IP addresses
    local ips
    ips=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1)
    local primary_url=""
    
    if [[ -n "$ips" ]]; then
        while read -r ip; do
            local url="http://$ip:$port"
            echo "  $url"
            if [[ -z "$primary_url" ]]; then
                primary_url="$url"
            fi
        done <<< "$ips"
    else
        primary_url="http://localhost:$port"
        echo "  $primary_url"
    fi
    
    echo "Access the upload interface at:"
    echo "  http://localhost:$port"
    echo
    echo "Instructions:"
    echo "1. Use the web interface to upload your watermark image"
    echo "2. Supported formats: PNG, JPG, JPEG, GIF, BMP"
    echo "3. Recommended size: 800x600 or smaller"
    echo "4. After uploading, return here and press Enter"
    echo
    echo "Progress will be shown below..."
    echo "----------------------------------------"
    
    # Wait for upload completion with progress
    local upload_complete=false
    local upload_file="$upload_dir/watermark.png"
    local flag_file="$upload_dir/upload_complete.flag"
    local dots=0
    local check_count=0
    
    # Set up cleanup trap
    trap "kill $server_pid 2>/dev/null; rm -rf '$upload_dir'" EXIT
    
    echo -n "Waiting for upload"
    
    while true; do
        if [[ -f "$flag_file" ]]; then
            upload_complete=true
            echo " COMPLETE!"
            break
        fi
        
        # Show progress dots
        echo -n "."
        dots=$((dots + 1))
        check_count=$((check_count + 1))
        
        # Every 10 seconds, show a status update
        if [[ $check_count -eq 10 ]]; then
            echo
            echo "Still waiting... (Press Enter if upload is complete)"
            echo -n "Waiting for upload"
            check_count=0
            dots=0
        fi
        
        # Reset dots after 60
        if [[ $dots -gt 60 ]]; then
            echo
            echo -n "Waiting for upload"
            dots=0
        fi
        
        # Check if user wants to continue
        if read -t 1 -n 1; then
            echo
            if [[ -f "$upload_file" ]]; then
                upload_complete=true
                echo "Upload file detected!"
                break
            else
                echo "No file uploaded yet."
                echo -n "Continue waiting? (y/n): "
                read -r continue_wait
                if [[ ! $continue_wait =~ ^[Yy] ]]; then
                    echo "Upload cancelled by user."
                    break
                fi
                echo -n "Waiting for upload"
                dots=0
            fi
        fi
        
        sleep 1
    done
    
    # Stop server
    kill $server_pid 2>/dev/null
    
    echo
    echo "=========================================="
    
    if [[ "$upload_complete" == "true" && -f "$upload_file" ]]; then
        cp "$upload_file" "$target_file"
        
        # Show file info
        if command -v file >/dev/null 2>&1; then
            local file_info
            file_info=$(file "$target_file")
            echo "Uploaded file: $file_info"
        fi
        
        if command -v stat >/dev/null 2>&1; then
            local file_size
            file_size=$(stat -c%s "$target_file" 2>/dev/null || stat -f%z "$target_file" 2>/dev/null)
            if [[ -n "$file_size" ]]; then
                echo "File size: $((file_size / 1024)) KB"
            fi
        fi
        
        echo "Upload completed successfully!"
        echo "=========================================="
        echo "$target_file"
        return 0
    else
        echo "Upload was not completed."
        echo "=========================================="
        return 1
    fi
}

# Handle watermark setup
setup_watermark() {
    # Check if watermark already exists
    if [[ -f "/usr/share/plymouth/themes/spinner/watermark.png" ]]; then
        log_info "Watermark found."
        if [[ "$AUTO_INSTALL" != "true" ]]; then
            read -p "Do you want to modify the watermark? (y/n): " modify_answer
            if [[ ! $modify_answer =~ ^[Yy]$ ]]; then
                return 0
            fi
        else
            # In auto mode, check if we should replace existing watermark
            if [[ -n "$LOGO_URL" || "$SPLASH_MODE" == "url" || "$SPLASH_MODE" == "upload" ]]; then
                log_info "Auto mode: Replacing existing watermark"
            else
                log_info "Auto mode: Keeping existing watermark"
                return 0
            fi
        fi
    fi
    
    # Handle auto mode
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        # Determine mode - logo-url takes precedence, then splash-mode, then smart default
        local mode="$SPLASH_MODE"
        
        if [[ -n "$LOGO_URL" ]]; then
            mode="url"
            log_info "Auto mode: Using URL mode (logo-url provided)"
        elif [[ -z "$mode" ]]; then
            # Smart default: if no mode specified, check what's available
            if [[ -f "/usr/share/plymouth/themes/spinner/watermark.png" ]]; then
                log_info "Auto mode: Existing watermark found, keeping it"
                return 0
            else
                log_info "Auto mode: No existing watermark, using upload server"
                mode="upload"
            fi
        fi
        
        case "$mode" in
            "url")
                if [[ -n "$LOGO_URL" ]]; then
                    log_info "Auto mode: Downloading watermark from URL"
                    if download_watermark "$LOGO_URL" "/usr/share/plymouth/themes/spinner/watermark.png"; then
                        log_info "Watermark downloaded and installed successfully"
                        return 0
                    else
                        log_error "Failed to download watermark from URL in auto mode"
                        return 1
                    fi
                else
                    log_error "Auto mode: URL mode specified but no logo-url provided"
                    return 1
                fi
                ;;
            "upload")
                log_info "Auto mode: Starting web upload server for watermark"
                local watermark_file
                if watermark_file=$(handle_web_upload "/usr/share/plymouth/themes/spinner/watermark.png"); then
                    log_info "Watermark uploaded via web interface successfully"
                    return 0
                else
                    log_warn "Auto mode: Web upload failed, proceeding without custom watermark"
                    return 1
                fi
                ;;
            "manual")
                log_info "Auto mode: Manual mode not supported in auto install, skipping watermark"
                return 1
                ;;
            "default"|"")
                log_info "Auto mode: Using default theme without custom watermark"
                return 1
                ;;
            *)
                log_error "Auto mode: Invalid splash mode '$mode'. Valid modes: url, upload, manual, default"
                return 1
                ;;
        esac
    fi
    
    # Interactive mode
    echo
    echo "Please choose an option:"
    echo "1. Upload a file manually"
    echo "2. Download from URL"
    echo "3. Upload via web interface (recommended)"
    echo "4. Skip watermark"
    echo
    
    while true; do
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                echo "Please upload the watermark.png file to /home/${SUDO_USER:-root}/"
                echo "Available IP addresses:"
                ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'
                echo
                read -p "Press Enter after uploading the file..."
                
                local upload_file="/home/${SUDO_USER:-root}/watermark.png"
                if [[ -f "$upload_file" ]]; then
                    cp "$upload_file" "/usr/share/plymouth/themes/spinner/watermark.png"
                    log_info "Watermark uploaded successfully"
                    return 0
                else
                    echo "Watermark file not found at $upload_file"
                    echo "Please try again."
                fi
                ;;
            2)
                local tries=0
                while [[ $tries -lt 3 ]]; do
                    read -p "Enter the URL of the watermark image: " url
                    
                    if validate_image_url "$url"; then
                        if download_watermark "$url" "/usr/share/plymouth/themes/spinner/watermark.png"; then
                            log_info "Watermark downloaded successfully"
                            return 0
                        else
                            echo "Failed to download the watermark image. Please try again."
                        fi
                    else
                        echo "Invalid URL. Please try again."
                    fi
                    tries=$((tries + 1))
                done
                
                if [[ $tries -eq 3 ]]; then
                    echo "Failed to download watermark after 3 attempts."
                    echo "Please choose another option."
                fi
                ;;
            3)
                log_info "Starting web upload interface..."
                local watermark_file
                if watermark_file=$(handle_web_upload "/usr/share/plymouth/themes/spinner/watermark.png"); then
                    log_info "Watermark uploaded via web interface successfully"
                    return 0
                else
                    echo "Web upload failed. Please try another option."
                fi
                ;;
            4)
                log_info "Skipping watermark setup"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1-4."
                ;;
        esac
    done
}

# Create custom Plymouth theme
create_custom_theme() {
    local watermark_file="$1"
    
    log_info "Creating custom Plymouth theme: $CUSTOM_THEME_NAME"
    
    # Create theme directory
    mkdir -p "$CUSTOM_THEME_DIR" || {
        log_error "Failed to create theme directory"
        return 1
    }
    
    # Copy watermark image
    cp "$watermark_file" "$CUSTOM_THEME_DIR/watermark.png" || {
        log_error "Failed to copy watermark image"
        return 1
    }
    
    # Create theme configuration file
    cat > "$CUSTOM_THEME_DIR/$CUSTOM_THEME_NAME.plymouth" << EOF
[Plymouth Theme]
Name=$CUSTOM_THEME_NAME
Description=MediaScreen Custom Splash Theme
ModuleName=script

[script]
ImageDir=$CUSTOM_THEME_DIR
ScriptFile=$CUSTOM_THEME_DIR/$CUSTOM_THEME_NAME.script
EOF
    
    # Create Plymouth script with watermark
    cat > "$CUSTOM_THEME_DIR/$CUSTOM_THEME_NAME.script" << 'EOF'
# MediaScreen Plymouth Theme Script

# Load the watermark image
watermark_image = Image("watermark.png");
watermark_sprite = Sprite(watermark_image);

# Get screen dimensions
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

# Position watermark in center
watermark_sprite.SetX((screen_width - watermark_image.GetWidth()) / 2);
watermark_sprite.SetY((screen_height - watermark_image.GetHeight()) / 2);

# Simple progress indication
progress_sprite = Sprite();
progress_sprite.SetPosition(screen_width / 2, screen_height * 0.8, 1);

fun progress_callback(duration, progress) {
    # Simple text progress indicator
    progress_text = Math.Int(progress * 100) + "%";
    progress_image = Image.Text(progress_text, 1, 1, 1);
    progress_sprite.SetImage(progress_image);
    progress_sprite.SetX(screen_width / 2 - progress_image.GetWidth() / 2);
}

Plymouth.SetBootProgressFunction(progress_callback);

# Message handling
message_sprite = Sprite();
message_sprite.SetPosition(screen_width / 2, screen_height * 0.9, 1);

fun display_message_callback(text) {
    message_image = Image.Text(text, 1, 1, 1);
    message_sprite.SetImage(message_image);
    message_sprite.SetX(screen_width / 2 - message_image.GetWidth() / 2);
}

Plymouth.SetMessageFunction(display_message_callback);
EOF
    
    log_info "Custom Plymouth theme created successfully"
}

# Set Plymouth theme
set_plymouth_theme() {
    local theme_name="$1"
    
    log_info "Setting Plymouth theme to: $theme_name"
    
    # Check if theme exists
    if [[ ! -d "$PLYMOUTH_THEMES_DIR/$theme_name" ]]; then
        log_error "Theme '$theme_name' not found in $PLYMOUTH_THEMES_DIR"
        return 1
    fi
    
    # Set the theme
    if plymouth-set-default-theme "$theme_name"; then
        log_info "Plymouth theme set successfully"
    else
        log_error "Failed to set Plymouth theme"
        return 1
    fi
    
    # Update initramfs
    log_info "Updating initramfs..."
    if update-initramfs -u; then
        log_info "Initramfs updated successfully"
    else
        log_error "Failed to update initramfs"
        return 1
    fi
    
    return 0
}

# Choose default theme
choose_default_theme() {
    log_info "Selecting default Plymouth theme..."
    
    # Try to use a good default theme
    local preferred_themes=("spinner" "fade-in" "glow" "solar" "spinfinity")
    
    for theme in "${preferred_themes[@]}"; do
        if [[ -d "$PLYMOUTH_THEMES_DIR/$theme" ]]; then
            log_info "Using default theme: $theme"
            set_plymouth_theme "$theme"
            return 0
        fi
    done
    
    # Fallback to text theme
    log_warn "No preferred themes found, using text theme"
    set_plymouth_theme "text"
}

# Main execution
main() {
    log_info "Starting splash screen setup..."
    
    # Install Plymouth
    install_plymouth || report_failure "Plymouth installation"
    
    # Handle watermark setup
    setup_watermark
    local watermark_result=$?
    
    # Configure Plymouth theme based on watermark setup
    if [[ $watermark_result -eq 0 ]]; then
        # Watermark was set up successfully, configure spinner theme
        log_info "Configuring spinner theme with watermark..."
        
        # Update VerticalAlignment and WatermarkVerticalAlignment
        sed -i 's/VerticalAlignment=.*/VerticalAlignment=.8/' /usr/share/plymouth/themes/spinner/spinner.plymouth
        sed -i 's/WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.5/' /usr/share/plymouth/themes/spinner/spinner.plymouth
        
        # Set spinner theme as default
        plymouth-set-default-theme -R spinner || {
            log_error "Failed to set spinner theme"
            return 1
        }
        
        log_info "Spinner theme with watermark configured successfully"
    else
        # No watermark, use default theme
        log_info "Setting up default Plymouth theme..."
        choose_default_theme || report_failure "Default theme setup"
    fi
    
    # Create long splash configuration
    log_info "Creating long splash configuration..."
    if [[ ! -d "/etc/systemd/system/plymouth-quit.service.d" ]]; then
        mkdir -p /etc/systemd/system/plymouth-quit.service.d
    fi
    
    cat > /etc/systemd/system/plymouth-quit.service.d/long_splash.conf << 'EOF'
[Unit]
Description=Make Plymouth Boot Screen last longer

[Service]
ExecStartPre=/usr/bin/sleep 5
EOF
    
    log_info "Plymouth configuration completed successfully"
    
    report_success "Splash screen setup"
    
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        echo
        echo "Splash screen setup completed successfully!"
        echo "- Plymouth boot splash is now configured"
        
        local current_theme
        current_theme=$(plymouth-set-default-theme)
        echo "- Active theme: $current_theme"
        
        if [[ "$current_theme" == "spinner" && -f "/usr/share/plymouth/themes/spinner/watermark.png" ]]; then
            echo "- Custom watermark image configured"
        fi
        
        echo
        echo "The splash screen will be displayed on next boot."
        echo "Changes will take effect after reboot."
        echo
    fi
}

# Run main function
main