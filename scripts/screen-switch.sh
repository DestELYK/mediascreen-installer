#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/../lib/common.sh"; then
    echo "ERROR: Failed to load common library"
    echo "Please ensure MediaScreen installer components are properly installed."
    exit 1
fi

<<comment
    This script switches between TTY/getty terminals for MediaScreen systems.
    
    The script uses chvt (change virtual terminal) to switch between different
    virtual console terminals (TTY1, TTY2, etc.), allowing easy navigation
    between different terminal sessions.
    
    This script requires root privileges for terminal switching.

    Command Line Usage:
        - List available terminals:
            ms-switch list
        - Switch to specific terminal number:
            ms-switch <tty_number>
        - Interactive mode:
            ms-switch
        - Get current terminal info:
            ms-switch status

    Author: DestELYK
    Date: 07-22-2025
    Description: TTY/getty terminal switching utility for MediaScreen
comment

# Initialize common functionality (requires root for terminal switching)
init_common "screen-switch"

# Check if we have terminal switching capabilities
check_terminal_environment() {
    if ! command -v chvt >/dev/null 2>&1; then
        log_error "chvt command not found. Please install console-tools or kbd package:"
        log_info "sudo apt install kbd"
        return 1
    fi
    
    if ! command -v fgconsole >/dev/null 2>&1; then
        log_error "fgconsole command not found. Please install console-tools or kbd package:"
        log_info "sudo apt install kbd"
        return 1
    fi
    
    return 0
}

# Get available TTY terminals (only active/enabled ones)
get_terminals() {
    log_debug "Detecting active TTY terminals..."
    
    # Get current terminal
    local current_tty=$(fgconsole 2>/dev/null || echo "unknown")
    
    # Check for available and active TTY devices
    local tty_count=0
    for tty_num in {1..12}; do
        local tty_device="tty${tty_num}"
        local service="getty@${tty_device}.service"
        
        # Check if TTY device exists
        if [[ ! -c "/dev/${tty_device}" ]]; then
            continue
        fi
        
        # Check if getty service is enabled and not masked
        local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        local service_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        
        # Skip masked or disabled services
        if [[ "$service_state" == "masked" ]]; then
            log_debug "Skipping masked TTY: $tty_device"
            continue
        fi
        
        local status=""
        if [[ "$tty_num" == "$current_tty" ]]; then
            status=" [CURRENT]"
        fi
        
        # Check service status
        local service_info=""
        if [[ "$service_active" == "active" ]]; then
            service_info=" (active)"
        elif [[ "$service_state" == "enabled" ]]; then
            service_info=" (enabled)"
        else
            service_info=" (inactive)"
        fi
        
        # Get autologin user if configured
        local autologin_user=""
        local override_file="/etc/systemd/system/getty@${tty_device}.service.d/override.conf"
        if [[ -f "$override_file" ]]; then
            autologin_user=$(grep -o '\--autologin [^ ]*' "$override_file" 2>/dev/null | awk '{print $2}' || echo "")
            if [[ -n "$autologin_user" ]]; then
                service_info+=" - autologin: $autologin_user"
            fi
        fi
        
        echo "${tty_device}|TTY ${tty_num}|${status}${service_info}"
        tty_count=$((tty_count + 1))
    done
    
    log_debug "Found $tty_count active TTY terminals"
}

# List available TTY terminals
list_terminals() {
    log_info "Available TTY terminals:"
    echo
    
    local count=0
    while IFS='|' read -r tty_device tty_name status; do
        if [[ -n "$tty_device" ]]; then
            count=$((count + 1))
            printf "  %d. %s" "$count" "$tty_name"
            
            if [[ -n "$status" ]]; then
                printf " %s" "$status"
            fi
            
            echo
        fi
    done < <(get_terminals)
    
    if [[ $count -eq 0 ]]; then
        log_warn "No TTY terminals found"
        return 1
    fi
    
    echo
    log_info "Total TTY terminals found: $count"
    
    return 0
}

# Get terminal status
terminal_status() {
    log_info "Current TTY terminal configuration:"
    echo
    
    # Show current terminal
    local current_tty=$(fgconsole 2>/dev/null || echo "unknown")
    log_info "Current TTY: $current_tty"
    
    # Show enabled getty services
    echo
    log_info "Enabled getty services:"
    local found_enabled=false
    for tty_num in {1..12}; do
        local service="getty@tty${tty_num}.service"
        local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        local service_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        
        if [[ "$service_state" != "masked" && "$service_state" != "disabled" ]]; then
            found_enabled=true
            echo "  tty${tty_num}: $service_state ($service_active)"
            
            # Show autologin info if configured
            local override_file="/etc/systemd/system/getty@tty${tty_num}.service.d/override.conf"
            if [[ -f "$override_file" ]]; then
                local autologin_user=$(grep -o '\--autologin [^ ]*' "$override_file" 2>/dev/null | awk '{print $2}' || echo "")
                if [[ -n "$autologin_user" ]]; then
                    echo "    └─ Autologin: $autologin_user"
                fi
            fi
        fi
    done
    
    if [[ "$found_enabled" == "false" ]]; then
        echo "  No enabled getty services found"
    fi
    
    # Show masked services
    echo
    log_info "Masked getty services:"
    local found_masked=false
    for tty_num in {1..12}; do
        local service="getty@tty${tty_num}.service"
        local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        
        if [[ "$service_state" == "masked" ]]; then
            found_masked=true
            echo "  tty${tty_num}: masked"
        fi
    done
    
    if [[ "$found_masked" == "false" ]]; then
        echo "  No masked getty services"
    fi
    
    # Show virtual terminal info
    echo
    log_info "Virtual terminal status:"
    if [[ -f "/sys/class/tty/console/active" ]]; then
        local active_consoles=$(cat /sys/class/tty/console/active 2>/dev/null || echo "unknown")
        echo "  Active consoles: $active_consoles"
    fi
}

# Switch to specific TTY terminal
switch_to_terminal() {
    local target_number="$1"
    
    log_info "Switching to TTY #$target_number..."
    
    # Get terminal list as array (only active/enabled ones)
    local terminals=()
    local tty_numbers=()
    while IFS='|' read -r tty_device tty_name status; do
        if [[ -n "$tty_device" ]]; then
            terminals+=("$tty_name")
            # Extract number from tty device (e.g., tty1 -> 1)
            local tty_num=$(echo "$tty_device" | sed 's/tty//')
            tty_numbers+=("$tty_num")
        fi
    done < <(get_terminals)
    
    # Validate terminal number
    if [[ $target_number -lt 1 || $target_number -gt ${#terminals[@]} ]]; then
        log_error "Invalid TTY number: $target_number"
        log_info "Available active TTYs: 1-${#terminals[@]}"
        return 1
    fi
    
    local target_tty_num="${tty_numbers[$((target_number - 1))]}"
    local target_tty_name="${terminals[$((target_number - 1))]}"
    
    log_info "Target TTY: $target_tty_name (tty$target_tty_num)"
    
    # Check if target TTY exists
    if [[ ! -c "/dev/tty${target_tty_num}" ]]; then
        log_error "TTY device /dev/tty${target_tty_num} does not exist"
        return 1
    fi
    
    # Check if target TTY service is active
    local service="getty@tty${target_tty_num}.service"
    local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
    local service_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    
    if [[ "$service_state" == "masked" ]]; then
        log_error "TTY $target_tty_num is masked and not available"
        log_info "Use autologin-setup.sh to configure this TTY"
        return 1
    fi
    
    if [[ "$service_active" != "active" ]]; then
        log_warn "TTY $target_tty_num service is not active ($service_active)"
        log_info "Attempting to start the service..."
        
        if ! systemctl start "$service"; then
            log_error "Failed to start $service"
            return 1
        fi
        
        # Wait a moment for the service to start
        sleep 1
    fi
    
    # Switch to target TTY
    log_debug "Switching to TTY $target_tty_num..."
    if chvt "$target_tty_num"; then
        log_info "Successfully switched to $target_tty_name"
        return 0
    else
        log_error "Failed to switch to $target_tty_name"
        log_info "Make sure you have permission to switch virtual terminals"
        return 1
    fi
}

# Interactive terminal selection
interactive_selection() {
    echo
    echo "=== MediaScreen TTY Terminal Switcher ==="
    echo
    
    if ! list_terminals; then
        return 1
    fi
    
    echo
    read -p "Enter TTY number to switch to (or 'q' to quit): " choice
    
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        log_info "TTY switching cancelled"
        return 0
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        switch_to_terminal "$choice"
    else
        log_error "Invalid input. Please enter a number or 'q' to quit."
        return 1
    fi
}

# Handle services that might need attention after TTY switch
check_services_after_switch() {
    log_debug "Checking MediaScreen services after TTY switch..."
    
    # Check if MediaScreen browser service is running
    if systemctl is-active --quiet mediascreen-browser 2>/dev/null; then
        log_info "MediaScreen browser service is running"
    fi
    
    # Check autologin service
    if systemctl is-active --quiet getty@tty1 2>/dev/null; then
        log_debug "Getty service on TTY1 is active"
    fi
    
    # Show current TTY status after switch
    local current_tty=$(fgconsole 2>/dev/null || echo "unknown")
    log_info "Now on TTY: $current_tty"
}

# Show usage information
show_usage() {
    echo "MediaScreen TTY Terminal Switcher"
    echo
    echo "Usage: ms-switch [OPTION|TTY_NUMBER]"
    echo
    echo "Options:"
    echo "  list          List available TTY terminals"
    echo "  status        Show current TTY terminal status"
    echo "  -h, --help    Show this help message"
    echo
    echo "Arguments:"
    echo "  TTY_NUMBER    Switch to specified TTY number (1, 2, 3, etc.)"
    echo
    echo "Examples:"
    echo "  ms-switch           # Interactive mode"
    echo "  ms-switch list      # List available TTY terminals"
    echo "  ms-switch 2         # Switch to TTY #2"
    echo "  ms-switch status    # Show current TTY terminal info"
    echo
    echo "Note: This command requires root privileges to switch terminals."
    echo
}

# Main execution
main() {
    log_info "Starting MediaScreen TTY terminal switcher..."
    
    # Check terminal environment
    if ! check_terminal_environment; then
        exit 1
    fi
    
    # Parse arguments
    case "${1:-}" in
        "list"|"l")
            list_terminals
            ;;
        "status"|"s")
            terminal_status
            ;;
        "-h"|"--help"|"help")
            show_usage
            ;;
        [0-9]*)
            # Direct TTY number
            if ! switch_to_terminal "$1"; then
                exit 1
            fi
            check_services_after_switch
            ;;
        *)
            # Interactive mode
            if ! interactive_selection; then
                exit 1
            fi
            check_services_after_switch
            ;;
    esac
}

# Run main function
main "$@"
