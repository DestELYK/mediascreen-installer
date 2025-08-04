#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/../lib/common.sh"; then
    echo "ERROR: Failed to load common library"
    echo "Please ensure MediaScreen installer components are properly installed."
    exit 1
fi

<<comment
    MSM Client Setup Script
    
    This script downloads, configures, and sets up the MSM (MediaScreen Manager) client
    as a systemd service. The MSM client connects to a central management server
    for remote configuration and monitoring of MediaScreen installations.
    
    Features:
    - Download latest MSM client from GitHub releases
    - Creates systemd service for automatic startup
    - Interactive configuration setup
    - Command-line configuration options
    - Supports automated configuration
    - Network connectivity validation
    - Service management and monitoring

    Command Line Usage:
        - Install MSM client:
            msm-client-setup install [options]
        - Show status:
            msm-client-setup status
        - Restart service:
            msm-client-setup restart
        - Update client:
            msm-client-setup update

    Author: DestELYK
    Date: 08-02-2025
    Description: MSM Client installation and configuration utility
comment

# Initialize common functionality
init_common "msm-client-setup"

# Configuration variables
MSM_CLIENT_URL="https://github.com/DestELYK/msm-client/releases/latest/download/msm-client.tar.gz"
INSTALL_DIR="/opt/msm-client"
CONFIG_FILE="/etc/msm-client/config.json"
SERVICE_FILE="/etc/systemd/system/msm-client.service"
BINARY_PATH="$INSTALL_DIR/msm-client"
TEMPLATES_DIR="$INSTALL_DIR/templates"

# Default configuration values
DEFAULT_AUTO_START="true"

# Command line argument variables
COMMAND=""
CONFIG_OPTIONS=()

# Configuration option variables
STATUS_UPDATE_INTERVAL=""
DISABLE_COMMANDS=""
VERIFICATION_CODE_LENGTH=""
VERIFICATION_CODE_ATTEMPTS=""
PAIRING_CODE_EXPIRATION=""
SCREEN_SWITCH_PATH=""
AUTO_INSTALL="false"

# Parse command line arguments
parse_arguments() {
    # First argument should be the command
    if [[ $# -gt 0 ]]; then
        case "$1" in
            install|restart|status|update|uninstall)
                COMMAND="$1"
                shift
                ;;
            -h|--help|help)
                show_usage
                exit 0
                ;;
            *)
                if [[ "$1" != "-h" && "$1" != "--help" && "$1" != "help" ]]; then
                    echo "Error: Unknown command '$1'"
                    echo "Use 'msm-client-setup help' for usage information."
                    exit 1
                fi
                ;;
        esac
    else
        # Default to install if no command provided
        COMMAND="install"
    fi
    
    # Parse configuration options (only for install command)
    if [[ "$COMMAND" == "install" ]]; then
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --status-update-interval=*)
                    STATUS_UPDATE_INTERVAL="${1#*=}"
                    ;;
                --disable-commands=*)
                    DISABLE_COMMANDS="${1#*=}"
                    ;;
                --verification-code-length=*)
                    VERIFICATION_CODE_LENGTH="${1#*=}"
                    ;;
                --verification-code-attempts=*)
                    VERIFICATION_CODE_ATTEMPTS="${1#*=}"
                    ;;
                --pairing-code-expiration=*)
                    PAIRING_CODE_EXPIRATION="${1#*=}"
                    ;;
                --screen-switch-path=*)
                    SCREEN_SWITCH_PATH="$(strip_quotes "${1#*=}")"
                    ;;
                -y|--yes|--auto)
                    AUTO_INSTALL="true"
                    ;;
                -h|--help)
                    show_usage
                    exit 0
                    ;;
                *)
                    log_warn "Unknown option: $1"
                    ;;
            esac
            shift
        done
    fi
}

# Show usage information
show_usage() {
    echo "MSM Client Setup and Configuration"
    echo
    echo "Usage: msm-client-setup <command> [options]"
    echo
    echo "Commands:"
    echo "  install                  Install and configure MSM client (interactive if no options provided)"
    echo "  restart                  Restart MSM client service"
    echo "  status                   Show MSM client status"
    echo "  update                   Update MSM client to latest version"
    echo "  uninstall                Uninstall MSM client completely"
    echo "  help                     Show this help message"
    echo
    echo "Install Options:"
    echo "  Note: If no options are provided, interactive configuration mode will be used."
    echo "  -y, --auto               Non-interactive mode with defaults"
    echo "  --status-update-interval=TIME   Status Update interval (e.g., 30s, 1m, 5m)"
    echo "  --disable-commands=BOOL  Disable command execution"
    echo "  --verification-code-length=NUM    Verification code length"
    echo "  --verification-code-attempts=NUM  Max verification attempts"
    echo "  --pairing-code-expiration=TIME    Pairing code expiration"
    echo "  --screen-switch-path=PATH         Path to screen switch script"
    echo
    echo "Examples:"
    echo "  # Interactive installation (prompts for configuration)"
    echo "  msm-client-setup install"
    echo
    echo "  # Non-interactive installation with defaults"
    echo "  msm-client-setup install -y"
    echo
    echo "  # Non-interactive installation with custom update interval"
    echo "  msm-client-setup install -y --status-update-interval=1m"
    echo
    echo "  # Non-interactive installation with custom configuration"
    echo "  msm-client-setup install -y --status-update-interval=30s --disable-commands=true --verification-code-length=8"
    echo
    echo "  # Check service status"
    echo "  msm-client-setup status"
    echo
    echo "  # Restart service"
    echo "  msm-client-setup restart"
    echo
    echo "  # Update to latest version"
    echo "  msm-client-setup update"
    echo
    echo "  # Uninstall MSM client"
    echo "  msm-client-setup uninstall"
    echo
    echo "Configuration file: $CONFIG_FILE"
    echo
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity..."
    
    # Check if we can resolve DNS
    if ! nslookup github.com >/dev/null 2>&1; then
        log_error "DNS resolution failed. Please check network configuration."
        return 1
    fi
    
    # Check if we can reach GitHub
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s --connect-timeout 10 https://github.com >/dev/null; then
            log_error "Cannot reach GitHub. Please check internet connectivity."
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget --timeout=10 --tries=1 -q --spider https://github.com; then
            log_error "Cannot reach GitHub. Please check internet connectivity."
            return 1
        fi
    else
        log_error "Neither curl nor wget is available for connectivity check"
        return 1
    fi
    
    log_info "Network connectivity verified"
    return 0
}

# Download MSM client binary
download_msm_client() {
    log_info "Downloading MSM client from GitHub..."
    
    # Create install directory
    if ! mkdir -p "$INSTALL_DIR"; then
        log_error "Failed to create install directory: $INSTALL_DIR"
        return 1
    fi
    
    # Download the tar.gz file
    local tar_file="$INSTALL_DIR/msm-client.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$tar_file" "$MSM_CLIENT_URL"; then
            log_error "Failed to download MSM client from $MSM_CLIENT_URL using curl"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$tar_file" "$MSM_CLIENT_URL"; then
            log_error "Failed to download MSM client from $MSM_CLIENT_URL using wget"
            return 1
        fi
    else
        log_error "Neither curl nor wget is available for downloading"
        return 1
    fi
    
    log_info "MSM client tar.gz file downloaded successfully"
    
    # Extract the tar.gz file
    log_info "Extracting MSM client..."
    if ! tar -xzf "$tar_file" -C "$INSTALL_DIR"; then
        log_error "Failed to extract MSM client tar.gz file"
        rm -f "$tar_file"
        return 1
    fi
    
    # Remove the tar.gz file after extraction
    rm -f "$tar_file"
    
    # Make the binary executable
    if [[ -f "$BINARY_PATH" ]]; then
        if ! chmod +x "$BINARY_PATH"; then
            log_error "Failed to make MSM client executable"
            return 1
        fi
    else
        log_error "MSM client binary not found after extraction: $BINARY_PATH"
        return 1
    fi
    
    log_info "MSM client extracted successfully to $INSTALL_DIR"
    
    # Verify the binary is executable
    if [[ -x "$BINARY_PATH" ]]; then
        log_info "MSM client binary is ready"
    else
        log_error "Downloaded binary is not executable"
        return 1
    fi
    
    # Check if templates directory exists
    if [[ -d "$TEMPLATES_DIR" ]]; then
        log_info "Templates directory found: $TEMPLATES_DIR"
        local template_count=$(find "$TEMPLATES_DIR" -type f 2>/dev/null | wc -l)
        log_info "Found $template_count template files"
    else
        log_warn "Templates directory not found: $TEMPLATES_DIR"
    fi
    
    return 0
}

# Interactive configuration setup
interactive_config() {
    echo
    echo "=== MSM Client Interactive Configuration ==="
    echo
    echo "Press Enter to skip optional configuration values."
    echo
    
    # Update interval
    read -p "Status Update interval (e.g., 30s, 1m, 5m, optional): " input_interval
    if [[ -n "$input_interval" ]]; then
        # Validate time duration format (e.g., 30s, 1m, 5m)
        if [[ "$input_interval" =~ ^[0-9]+[smh]$ ]]; then
            STATUS_UPDATE_INTERVAL="$input_interval"
        else
            echo "Invalid format (use format like 30s, 1m, 5m). Leaving unset."
            STATUS_UPDATE_INTERVAL=""
        fi
    else
        STATUS_UPDATE_INTERVAL=""
    fi
    
    # Disable commands
    read -p "Disable remote command execution? (true/false, optional): " input_disable
    case "$input_disable" in
        [Tt]rue|[Yy]es|[Yy]|1)
            DISABLE_COMMANDS="true"
            ;;
        [Ff]alse|[Nn]o|[Nn]|0)
            DISABLE_COMMANDS="false"
            ;;
        "")
            DISABLE_COMMANDS=""
            ;;
        *)
            echo "Invalid input. Leaving unset."
            DISABLE_COMMANDS=""
            ;;
    esac
    
    # Verification code length
    read -p "Verification code length (4-12, optional): " input_code_length
    if [[ -n "$input_code_length" ]]; then
        if [[ "$input_code_length" =~ ^[0-9]+$ ]] && [[ "$input_code_length" -ge 4 ]] && [[ "$input_code_length" -le 12 ]]; then
            VERIFICATION_CODE_LENGTH="$input_code_length"
        else
            echo "Invalid input (must be 4-12). Leaving unset."
            VERIFICATION_CODE_LENGTH=""
        fi
    else
        VERIFICATION_CODE_LENGTH=""
    fi
    
    # Verification code attempts
    read -p "Maximum verification code attempts (optional): " input_attempts
    if [[ -n "$input_attempts" ]]; then
        if [[ "$input_attempts" =~ ^[0-9]+$ ]] && [[ "$input_attempts" -gt 0 ]]; then
            VERIFICATION_CODE_ATTEMPTS="$input_attempts"
        else
            echo "Invalid input. Leaving unset."
            VERIFICATION_CODE_ATTEMPTS=""
        fi
    else
        VERIFICATION_CODE_ATTEMPTS=""
    fi
    
    # Pairing code expiration
    read -p "Pairing code expiration time (e.g., 1m, 30s, 2h, optional): " input_expiration
    if [[ -n "$input_expiration" ]]; then
        # Basic validation for time format (e.g., 1m, 30s, 2h)
        if [[ "$input_expiration" =~ ^[0-9]+[smh]$ ]]; then
            PAIRING_CODE_EXPIRATION="$input_expiration"
        else
            echo "Invalid format (use format like 1m, 30s, 2h). Leaving unset."
            PAIRING_CODE_EXPIRATION=""
        fi
    else
        PAIRING_CODE_EXPIRATION=""
    fi
    
    # Screen switch path
    echo
    echo "Screen switch script path (optional):"
    echo "Default: Client will use its own default path"
    read -p "Enter custom path or press Enter to leave unset: " input_path
    if [[ -n "$input_path" ]]; then
        SCREEN_SWITCH_PATH="$(strip_quotes "$input_path")"
    else
        SCREEN_SWITCH_PATH=""
    fi
    
    # Show configuration summary
    echo
    echo "=== Configuration Summary ==="
    if [[ -n "$STATUS_UPDATE_INTERVAL" ]]; then
        echo "Update Interval: $STATUS_UPDATE_INTERVAL"
    else
        echo "Update Interval: (using client default)"
    fi
    
    if [[ -n "$DISABLE_COMMANDS" ]]; then
        echo "Disable Commands: $DISABLE_COMMANDS"
    else
        echo "Disable Commands: (using client default)"
    fi
    
    if [[ -n "$VERIFICATION_CODE_LENGTH" ]]; then
        echo "Verification Code Length: $VERIFICATION_CODE_LENGTH"
    else
        echo "Verification Code Length: (using client default)"
    fi
    
    if [[ -n "$VERIFICATION_CODE_ATTEMPTS" ]]; then
        echo "Verification Code Attempts: $VERIFICATION_CODE_ATTEMPTS"
    else
        echo "Verification Code Attempts: (using client default)"
    fi
    
    if [[ -n "$PAIRING_CODE_EXPIRATION" ]]; then
        echo "Pairing Code Expiration: $PAIRING_CODE_EXPIRATION"
    else
        echo "Pairing Code Expiration: (using client default)"
    fi
    
    if [[ -n "$SCREEN_SWITCH_PATH" ]]; then
        echo "Screen Switch Path: $SCREEN_SWITCH_PATH"
    else
        echo "Screen Switch Path: (using client default)"
    fi
    echo
    
    read -p "Proceed with this configuration? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Configuration cancelled by user"
        return 1
    fi
    
    return 0
}

# Create MSM client configuration
create_config() {
    log_info "Creating MSM client configuration..."
    
    # Create config directory
    local config_dir=$(dirname "$CONFIG_FILE")
    if ! mkdir -p "$config_dir"; then
        log_error "Failed to create config directory: $config_dir"
        return 1
    fi
    
    # Build JSON configuration with only set values
    local json_content="{"
    local field_count=0
    
    if [[ -n "$STATUS_UPDATE_INTERVAL" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"update_interval\": \"$STATUS_UPDATE_INTERVAL\""
        ((field_count++))
    fi
    
    if [[ -n "$DISABLE_COMMANDS" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"disable_commands\": $DISABLE_COMMANDS"
        ((field_count++))
    fi
    
    if [[ -n "$VERIFICATION_CODE_LENGTH" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"verification_code_length\": $VERIFICATION_CODE_LENGTH"
        ((field_count++))
    fi
    
    if [[ -n "$VERIFICATION_CODE_ATTEMPTS" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"verification_code_attempts\": $VERIFICATION_CODE_ATTEMPTS"
        ((field_count++))
    fi
    
    if [[ -n "$PAIRING_CODE_EXPIRATION" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"pairing_code_expiration\": \"$PAIRING_CODE_EXPIRATION\""
        ((field_count++))
    fi
    
    if [[ -n "$SCREEN_SWITCH_PATH" ]]; then
        if [[ $field_count -gt 0 ]]; then json_content="$json_content,"; fi
        json_content="$json_content\n    \"screen_switch_path\": \"$SCREEN_SWITCH_PATH\""
        ((field_count++))
    fi
    
    json_content="$json_content\n}"
    
    # Write configuration file
    printf "$json_content" > "$CONFIG_FILE"
    
    if [[ $? -eq 0 ]]; then
        log_info "Configuration created: $CONFIG_FILE"
        log_debug "Config contents:"
        log_debug "$(cat "$CONFIG_FILE")"
        return 0
    else
        log_error "Failed to create configuration file"
        return 1
    fi
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=MSM Client - MediaScreen Manager Client
Documentation=https://github.com/DestELYK/msm-client
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
Group=root
ExecStart=$BINARY_PATH start --enable-display
StandardOutput=journal
StandardError=journal
SyslogIdentifier=msm-client

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR /etc/msm-client /var/lib/msm-client
PrivateTmp=yes

# Environment
Environment=HOME=/root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Systemd service created: $SERVICE_FILE"
        
        # Reload systemd
        if systemctl daemon-reload; then
            log_info "Systemd daemon reloaded"
        else
            log_error "Failed to reload systemd daemon"
            return 1
        fi
        
        # Always enable service for automatic startup
        if systemctl enable msm-client; then
            log_info "MSM client service enabled for automatic startup"
        else
            log_error "Failed to enable MSM client service"
            return 1
        fi
        
        return 0
    else
        log_error "Failed to create systemd service file"
        return 1
    fi
}

# Start MSM client service
start_service() {
    log_info "Starting MSM client service..."
    
    if systemctl start msm-client; then
        log_info "MSM client service started successfully"
        
        # Wait a moment and check status
        sleep 2
        if systemctl is-active --quiet msm-client; then
            log_info "MSM client service is running"
            return 0
        else
            log_warn "MSM client service started but may not be running properly"
            return 1
        fi
    else
        log_error "Failed to start MSM client service"
        return 1
    fi
}

# Show service status
show_service_status() {
    echo
    echo "=== MSM Client Status ==="
    echo
    
    # Check if binary exists
    if [[ -f "$BINARY_PATH" ]]; then
        echo "Binary: $BINARY_PATH (installed)"
    else
        echo "Binary: Not installed"
    fi
    
    # Check templates directory
    if [[ -d "$TEMPLATES_DIR" ]]; then
        echo "Templates: $TEMPLATES_DIR (exists)"
        local template_count=$(find "$TEMPLATES_DIR" -type f 2>/dev/null | wc -l)
        echo "  Template files: $template_count"
    else
        echo "Templates: Not installed"
    fi
    
    # Check configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config: $CONFIG_FILE (exists)"
    else
        echo "Config: Not configured"
    fi
    
    # Check systemd service
    if [[ -f "$SERVICE_FILE" ]]; then
        echo "Service: $SERVICE_FILE (installed)"
        local service_enabled=$(systemctl is-enabled msm-client 2>/dev/null || echo "disabled")
        local service_active=$(systemctl is-active msm-client 2>/dev/null || echo "inactive")
        echo "  Enabled: $service_enabled"
        echo "  Status: $service_active"
        
        if [[ "$service_active" == "active" ]]; then
            echo "  Process:"
            systemctl show msm-client --property=MainPID,ExecMainStartTimestamp --no-pager 2>/dev/null | sed 's/^/    /'
        fi
    else
        echo "Service: Not installed"
    fi
    
    # Show recent logs if service exists
    if systemctl list-unit-files msm-client.service >/dev/null 2>&1; then
        echo
        echo "Recent logs (last 10 lines):"
        journalctl -u msm-client --no-pager -n 10 2>/dev/null | sed 's/^/  /' || echo "  No recent logs available"
    fi
    
    echo
}

# Restart service
restart_service() {
    log_info "Restarting MSM client service..."
    
    if systemctl restart msm-client; then
        log_info "MSM client service restarted successfully"
        
        # Wait and check status
        sleep 2
        if systemctl is-active --quiet msm-client; then
            log_info "MSM client service is running after restart"
            return 0
        else
            log_warn "MSM client service restarted but may not be running properly"
            return 1
        fi
    else
        log_error "Failed to restart MSM client service"
        return 1
    fi
}

# Update MSM client to latest version
update_client() {
    log_info "Updating MSM client to latest version..."
    
    # Check if MSM client is installed
    if [[ ! -f "$BINARY_PATH" ]]; then
        log_error "MSM client is not installed. Run setup first."
        return 1
    fi
    
    # Check if service exists
    if [[ ! -f "$SERVICE_FILE" ]]; then
        log_error "MSM client service is not installed. Run setup first."
        return 1
    fi
    
    # Check network connectivity
    if ! check_network; then
        return 1
    fi
    
    # Stop service before update
    local was_running=false
    if systemctl is-active --quiet msm-client; then
        was_running=true
        log_info "Stopping MSM client service for update..."
        if ! systemctl stop msm-client; then
            log_error "Failed to stop MSM client service"
            return 1
        fi
    fi
    
    # Backup current binary
    local backup_path="${BINARY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$BINARY_PATH" "$backup_path"; then
        log_info "Current binary backed up to: $backup_path"
    else
        log_warn "Failed to backup current binary"
    fi
    
    # Download new version
    log_info "Downloading latest MSM client..."
    local tar_file="$INSTALL_DIR/msm-client-update.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$tar_file" "$MSM_CLIENT_URL"; then
            log_error "Failed to download updated MSM client using curl"
            
            # Restore backup if download failed
            if [[ -f "$backup_path" ]]; then
                log_info "Restoring backup binary..."
                mv "$backup_path" "$BINARY_PATH"
            fi
            
            # Restart service if it was running
            if [[ "$was_running" == "true" ]]; then
                systemctl start msm-client
            fi
            
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$tar_file" "$MSM_CLIENT_URL"; then
            log_error "Failed to download updated MSM client using wget"
            
            # Restore backup if download failed
            if [[ -f "$backup_path" ]]; then
                log_info "Restoring backup binary..."
                mv "$backup_path" "$BINARY_PATH"
            fi
            
            # Restart service if it was running
            if [[ "$was_running" == "true" ]]; then
                systemctl start msm-client
            fi
            
            return 1
        fi
    else
        log_error "Neither curl nor wget is available for downloading"
        
        # Restore backup if download failed
        if [[ -f "$backup_path" ]]; then
            log_info "Restoring backup binary..."
            mv "$backup_path" "$BINARY_PATH"
        fi
        
        # Restart service if it was running
        if [[ "$was_running" == "true" ]]; then
            systemctl start msm-client
        fi
        
        return 1
    fi
    
    # Extract the new version
    log_info "Extracting updated MSM client..."
    if ! tar -xzf "$tar_file" -C "$INSTALL_DIR"; then
        log_error "Failed to extract updated MSM client"
        rm -f "$tar_file"
        
        # Restore backup if extraction failed
        if [[ -f "$backup_path" ]]; then
            log_info "Restoring backup binary..."
            mv "$backup_path" "$BINARY_PATH"
        fi
        
        # Restart service if it was running
        if [[ "$was_running" == "true" ]]; then
            systemctl start msm-client
        fi
        
        return 1
    fi
    
    # Remove the tar.gz file after extraction
    rm -f "$tar_file"
    
    # Make it executable
    if ! chmod +x "$BINARY_PATH"; then
        log_error "Failed to make updated MSM client executable"
        return 1
    fi
    
    log_info "MSM client updated successfully"
    
    # Start service if it was running before
    if [[ "$was_running" == "true" ]]; then
        log_info "Starting MSM client service with updated binary..."
        if systemctl start msm-client; then
            log_info "MSM client service started successfully"
            
            # Wait and verify
            sleep 2
            if systemctl is-active --quiet msm-client; then
                log_info "MSM client service is running with updated binary"
            else
                log_warn "MSM client service started but may not be running properly"
                return 1
            fi
        else
            log_error "Failed to start MSM client service after update"
            return 1
        fi
    fi
    
    # Clean up backup if update was successful
    if [[ -f "$backup_path" ]]; then
        rm -f "$backup_path"
        log_debug "Backup binary removed"
    fi
    
    echo
    echo "=========================================="
    echo "     MSM Client Update Complete!"
    echo "=========================================="
    echo
    echo "Binary: $BINARY_PATH"
    echo "Service: $(systemctl is-active msm-client 2>/dev/null || echo "inactive")"
    echo
    echo "The MSM client has been updated successfully."
    echo
    
    return 0
}

# Uninstall MSM client completely
uninstall_client() {
    log_info "Starting MSM client uninstallation..."
    
    # Check if MSM client is installed
    if [[ ! -f "$BINARY_PATH" && ! -f "$CONFIG_FILE" && ! -f "$SERVICE_FILE" ]]; then
        log_info "MSM client is not installed"
        echo "MSM client is not installed on this system."
        return 0
    fi
    
    # Show what will be removed
    echo
    echo "=== MSM Client Uninstallation ==="
    echo
    echo "The following will be removed:"
    
    if [[ -f "$BINARY_PATH" ]]; then
        echo "  Binary: $BINARY_PATH"
    fi
    
    if [[ -d "$TEMPLATES_DIR" ]]; then
        local template_count=$(find "$TEMPLATES_DIR" -type f 2>/dev/null | wc -l)
        echo "  Templates: $TEMPLATES_DIR ($template_count files)"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "  Configuration: $CONFIG_FILE"
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        echo "  Systemd service: $SERVICE_FILE"
    fi
    
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "  Installation directory: $INSTALL_DIR"
    fi
    
    if [[ -L "/bin/msm-client" ]]; then
        echo "  Symbolic link: /bin/msm-client"
    fi
    
    local config_dir=$(dirname "$CONFIG_FILE")
    if [[ -d "$config_dir" ]]; then
        echo "  Configuration directory: $config_dir"
    fi
    
    echo
    read -p "Are you sure you want to uninstall MSM client? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled by user"
        echo "Uninstallation cancelled."
        return 0
    fi
    
    # Stop and disable service if it exists
    if [[ -f "$SERVICE_FILE" ]]; then
        if systemctl is-active --quiet msm-client; then
            log_info "Stopping MSM client service..."
            if systemctl stop msm-client; then
                log_info "MSM client service stopped"
            else
                log_warn "Failed to stop MSM client service"
            fi
        fi
        
        if systemctl is-enabled --quiet msm-client 2>/dev/null; then
            log_info "Disabling MSM client service..."
            if systemctl disable msm-client; then
                log_info "MSM client service disabled"
            else
                log_warn "Failed to disable MSM client service"
            fi
        fi
        
        # Remove service file
        log_info "Removing systemd service file..."
        if rm -f "$SERVICE_FILE"; then
            log_info "Systemd service file removed: $SERVICE_FILE"
        else
            log_error "Failed to remove systemd service file: $SERVICE_FILE"
        fi
        
        # Reload systemd
        if systemctl daemon-reload; then
            log_info "Systemd daemon reloaded"
        else
            log_warn "Failed to reload systemd daemon"
        fi
    fi
    
    # Remove configuration file and directory
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Removing configuration file..."
        if rm -f "$CONFIG_FILE"; then
            log_info "Configuration file removed: $CONFIG_FILE"
        else
            log_error "Failed to remove configuration file: $CONFIG_FILE"
        fi
    fi
    
    local config_dir=$(dirname "$CONFIG_FILE")
    if [[ -d "$config_dir" ]]; then
        # Only remove config directory if it's empty
        if rmdir "$config_dir" 2>/dev/null; then
            log_info "Configuration directory removed: $config_dir"
        else
            log_info "Configuration directory not empty, leaving: $config_dir"
        fi
    fi
    
    # Remove installation directory and all contents
    if [[ -d "$INSTALL_DIR" ]]; then
        log_info "Removing installation directory..."
        if rm -rf "$INSTALL_DIR"; then
            log_info "Installation directory removed: $INSTALL_DIR"
        else
            log_error "Failed to remove installation directory: $INSTALL_DIR"
        fi
    fi
    
    # Remove symbolic link from /bin
    if [[ -L "/bin/msm-client" ]]; then
        log_info "Removing symbolic link from /bin..."
        if rm -f "/bin/msm-client"; then
            log_info "Symbolic link removed: /bin/msm-client"
        else
            log_error "Failed to remove symbolic link: /bin/msm-client"
        fi
    fi
    
    echo
    echo "=========================================="
    echo "     MSM Client Uninstallation Complete!"
    echo "=========================================="
    echo
    echo "MSM client has been successfully removed from this system."
    echo "All files, configuration, and services have been cleaned up."
    echo
    
    return 0
}

# Main setup function
setup_msm_client() {
    log_info "Starting MSM client setup..."
    
    # Use interactive mode unless -y flag was provided
    if [[ "$AUTO_INSTALL" != "true" ]]; then
        log_info "No -y flag provided, starting interactive configuration..."
        if ! interactive_config; then
            return 1
        fi
    fi
    
    # Check network connectivity
    if ! check_network; then
        return 1
    fi
    
    # Download MSM client
    if ! download_msm_client; then
        return 1
    fi
    
    # Create configuration
    if ! create_config; then
        return 1
    fi
    
    # Create systemd service
    if ! create_systemd_service; then
        return 1
    fi
    
    # Create symbolic link to /bin for system-wide access
    log_info "Creating symbolic link to /bin..."
    if ln -sf "$BINARY_PATH" "/bin/msm-client"; then
        log_info "Symbolic link created: /bin/msm-client -> $BINARY_PATH"
    else
        log_warn "Failed to create symbolic link to /bin/msm-client"
    fi
    
    # Start service
    if ! start_service; then
        return 1
    fi
    
    echo
    echo "=========================================="
    echo "     MSM Client Setup Complete!"
    echo "=========================================="
    echo
    echo "Configuration:"
    if [[ -n "$STATUS_UPDATE_INTERVAL" ]]; then
        echo "  Status Update Interval: $STATUS_UPDATE_INTERVAL"
    else
        echo "  Status Update Interval: (using client default)"
    fi
    
    if [[ -n "$DISABLE_COMMANDS" ]]; then
        echo "  Disable Commands: $DISABLE_COMMANDS"
    else
        echo "  Disable Commands: (using client default)"
    fi
    
    if [[ -n "$VERIFICATION_CODE_LENGTH" ]]; then
        echo "  Verification Code Length: $VERIFICATION_CODE_LENGTH"
    else
        echo "  Verification Code Length: (using client default)"
    fi
    
    if [[ -n "$PAIRING_CODE_EXPIRATION" ]]; then
        echo "  Pairing Code Expiration: $PAIRING_CODE_EXPIRATION"
    else
        echo "  Pairing Code Expiration: (using client default)"
    fi
    
    echo "  Auto-start: enabled"
    echo
    echo "Files created:"
    echo "  Binary: $BINARY_PATH"
    echo "  Config: $CONFIG_FILE"
    echo "  Service: $SERVICE_FILE"
    echo "  System link: /bin/msm-client"
    if [[ -d "$TEMPLATES_DIR" ]]; then
        local template_count=$(find "$TEMPLATES_DIR" -type f 2>/dev/null | wc -l)
        echo "  Templates: $TEMPLATES_DIR ($template_count files)"
    fi
    echo
    echo "Service commands:"
    echo "  Status: systemctl status msm-client"
    echo "  Start:  systemctl start msm-client"
    echo "  Stop:   systemctl stop msm-client"
    echo "  Logs:   journalctl -u msm-client -f"
    echo
    echo "MSM Client commands:"
    echo "  Run client: msm-client start --enable-display"
    echo "  Show help: msm-client --help"
    echo
    echo "The MSM client is now running and will start automatically on boot."
    echo "The 'msm-client' command is available system-wide."
    echo
    
    return 0
}

# Main execution
main() {
    log_info "Starting MSM Client setup script..."
    
    # Parse arguments
    parse_arguments "$@"
    
    # Execute based on command
    case "$COMMAND" in
        "status")
            show_service_status
            return 0
            ;;
        "restart")
            restart_service
            return $?
            ;;
        "update")
            update_client
            return $?
            ;;
        "uninstall")
            uninstall_client
            return $?
            ;;
        "install")
            # Check if already installed and running for status display
            if [[ -f "$BINARY_PATH" && -f "$CONFIG_FILE" && -f "$SERVICE_FILE" ]]; then
                log_info "MSM client appears to be already installed"
                show_service_status
                
                echo
                read -p "MSM client is already installed. Reinstall/reconfigure? (y/n): " reinstall
                if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
                    log_info "Setup cancelled by user"
                    return 0
                fi
            fi
            
            # Run setup
            setup_msm_client
            ;;
        *)
            echo "Error: Unknown command '$COMMAND'"
            echo "Use 'msm-client-setup help' for usage information."
            return 1
            ;;
    esac
}

# Run main function
main "$@"
