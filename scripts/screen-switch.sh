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

# Handle potential display conflicts when switching TTYs
handle_display_cleanup() {
    local from_tty="$1"
    local to_tty="$2"
    
    log_debug "Checking for display conflicts between TTY$from_tty and TTY$to_tty"
    
    # Check if there are any X11 processes that might conflict
    local x_processes=$(pgrep -f "X.*:.*tty$to_tty" 2>/dev/null || true)
    if [[ -n "$x_processes" ]]; then
        log_debug "Found X11 processes on target TTY$to_tty"
    fi
    
    # Check for hanging display processes
    local display_processes=$(pgrep -f "startx\|X\|Xorg" 2>/dev/null || true)
    if [[ -n "$display_processes" ]]; then
        log_debug "Active display processes found: $display_processes"
        
        # Give them a moment to settle
        sleep 1
    fi
    
    return 0
}

# Check if TTY is responsive and ready for use
verify_tty_responsive() {
    local tty_num="$1"
    local tty_device="/dev/tty${tty_num}"
    
    # Check if the TTY device is accessible
    if [[ ! -c "$tty_device" ]]; then
        log_debug "TTY device $tty_device is not accessible"
        return 1
    fi
    
    # Try to write a simple test to the TTY (non-destructive)
    if echo -n "" > "$tty_device" 2>/dev/null; then
        log_debug "TTY $tty_num is responsive"
        return 0
    else
        log_debug "TTY $tty_num is not responsive"
        return 1
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
        
        # Wait for the service to fully start and be ready
        log_info "Waiting for getty service to initialize..."
        local wait_count=0
        while [[ $wait_count -lt 10 ]]; do
            sleep 1
            local current_status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            if [[ "$current_status" == "active" ]]; then
                # Give it an extra moment to be fully ready for connections
                sleep 2
                break
            fi
            wait_count=$((wait_count + 1))
        done
        
        # Verify service is actually active
        local final_status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        if [[ "$final_status" != "active" ]]; then
            log_error "Getty service failed to start properly after 10 seconds"
            return 1
        fi
    fi
    
    # Store current TTY for verification
    local current_before=$(fgconsole 2>/dev/null || echo "unknown")
    
    # Handle potential display conflicts
    handle_display_cleanup "$current_before" "$target_tty_num"
    
    # Switch to target TTY
    log_debug "Switching to TTY $target_tty_num (from TTY $current_before)..."
    if chvt "$target_tty_num"; then
        # Verify the switch was successful
        sleep 1
        local current_after=$(fgconsole 2>/dev/null || echo "unknown")
        
        if [[ "$current_after" == "$target_tty_num" ]]; then
            log_info "Successfully switched to $target_tty_name"
            
            # Additional verification: check if the TTY is responsive
            if ! verify_tty_responsive "$target_tty_num"; then
                log_warn "TTY $target_tty_num may not be fully responsive"
                log_info "You may need to reload the getty service if you encounter issues"
            fi
            
            return 0
        else
            log_error "Switch appeared to succeed but current TTY is $current_after, expected $target_tty_num"
            return 1
        fi
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

# Reload/restart specific TTY getty service
reload_terminal() {
    local target_number="$1"
    
    if [[ -z "$target_number" ]]; then
        log_error "TTY number is required for reload command"
        log_info "Usage: ms-switch reload <tty_number>"
        return 1
    fi
    
    # Validate that it's a number
    if [[ ! "$target_number" =~ ^[0-9]+$ ]]; then
        log_error "Invalid TTY number: $target_number (must be a number)"
        return 1
    fi
    
    log_info "Reloading TTY #$target_number..."
    
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
    
    # Validate terminal number against available terminals
    if [[ $target_number -lt 1 || $target_number -gt ${#terminals[@]} ]]; then
        log_error "Invalid TTY number: $target_number"
        log_info "Available active TTYs: 1-${#terminals[@]}"
        return 1
    fi
    
    local target_tty_num="${tty_numbers[$((target_number - 1))]}"
    local target_tty_name="${terminals[$((target_number - 1))]}"
    local service="getty@tty${target_tty_num}.service"
    
    log_info "Target TTY: $target_tty_name (tty$target_tty_num)"
    
    # Check if target TTY exists
    if [[ ! -c "/dev/tty${target_tty_num}" ]]; then
        log_error "TTY device /dev/tty${target_tty_num} does not exist"
        return 1
    fi
    
    # Check if target TTY service exists and is not masked
    local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
    
    if [[ "$service_state" == "masked" ]]; then
        log_error "TTY $target_tty_num is masked and cannot be reloaded"
        log_info "Use autologin-setup.sh to configure this TTY"
        return 1
    fi
    
    # Restart the getty service
    log_info "Restarting $service..."
    if systemctl restart "$service"; then
        log_info "Getty service restart command completed"
        
        # Wait for the service to fully restart and be ready
        log_info "Waiting for getty service to initialize after restart..."
        local wait_count=0
        while [[ $wait_count -lt 15 ]]; do
            sleep 1
            local current_status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            if [[ "$current_status" == "active" ]]; then
                # Give it an extra moment to be fully ready for connections
                sleep 2
                break
            fi
            wait_count=$((wait_count + 1))
        done
        
        # Check service status after restart
        local service_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        if [[ "$service_active" == "active" ]]; then
            log_info "$target_tty_name is now active"
            
            # Verify TTY responsiveness
            if verify_tty_responsive "$target_tty_num"; then
                log_info "$target_tty_name is responsive and ready for use"
            else
                log_warn "$target_tty_name may not be fully responsive yet"
                log_info "Give it a few more moments before switching to this TTY"
            fi
        else
            log_warn "$target_tty_name restart completed but service is $service_active"
        fi
        
        return 0
    else
        log_error "Failed to restart $service"
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
    
    # Additional diagnostics for troubleshooting
    log_debug "Post-switch diagnostics:"
    log_debug "- Current TTY: $current_tty"
    log_debug "- Active consoles: $(cat /sys/class/tty/console/active 2>/dev/null || echo 'unknown')"
    
    # Check for any display-related processes that might be causing issues
    local x_procs=$(pgrep -f "X\|startx\|Xorg" 2>/dev/null || true)
    if [[ -n "$x_procs" ]]; then
        log_debug "- Active X11 processes: $x_procs"
    fi
}

# Run comprehensive diagnostics to help troubleshoot switching issues
run_diagnostics() {
    log_info "Running comprehensive TTY diagnostics..."
    echo
    
    # Basic TTY info
    echo "=== Basic TTY Information ==="
    local current_tty=$(fgconsole 2>/dev/null || echo "unknown")
    echo "Current TTY: $current_tty"
    
    if [[ -f "/sys/class/tty/console/active" ]]; then
        local active_consoles=$(cat /sys/class/tty/console/active 2>/dev/null || echo "unknown")
        echo "Active consoles: $active_consoles"
    fi
    echo
    
    # Display processes
    echo "=== Display-Related Processes ==="
    local x_procs=$(pgrep -af "X\|startx\|Xorg" 2>/dev/null || echo "None found")
    echo "X11 processes:"
    if [[ "$x_procs" != "None found" ]]; then
        echo "$x_procs" | while read -r line; do
            echo "  $line"
        done
    else
        echo "  $x_procs"
    fi
    echo
    
    # Getty services status
    echo "=== Getty Services Status ==="
    for tty_num in {1..12}; do
        local service="getty@tty${tty_num}.service"
        local service_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        local service_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        
        if [[ "$service_state" != "disabled" ]] || [[ "$service_active" != "inactive" ]]; then
            echo "  tty${tty_num}: $service_state ($service_active)"
            
            # Check autologin configuration
            local override_file="/etc/systemd/system/getty@tty${tty_num}.service.d/override.conf"
            if [[ -f "$override_file" ]]; then
                local autologin_user=$(grep -o '\--autologin [^ ]*' "$override_file" 2>/dev/null | awk '{print $2}' || echo "")
                if [[ -n "$autologin_user" ]]; then
                    echo "    └─ Autologin: $autologin_user"
                fi
            fi
            
            # Check TTY responsiveness
            if verify_tty_responsive "$tty_num"; then
                echo "    └─ Status: Responsive"
            else
                echo "    └─ Status: Not responsive"
            fi
        fi
    done
    echo
    
    # TTY device status
    echo "=== TTY Device Status ==="
    for tty_num in {1..12}; do
        local tty_device="/dev/tty${tty_num}"
        if [[ -c "$tty_device" ]]; then
            local perms=$(ls -l "$tty_device" 2>/dev/null | awk '{print $1,$3,$4}')
            echo "  $tty_device: exists ($perms)"
        fi
    done
    echo
    
    # Kernel messages related to TTY
    echo "=== Recent TTY-related Kernel Messages ==="
    local tty_messages=$(dmesg | grep -i "tty\|console\|vt" | tail -10 2>/dev/null || echo "No recent messages")
    if [[ "$tty_messages" != "No recent messages" ]]; then
        echo "$tty_messages" | while read -r line; do
            echo "  $line"
        done
    else
        echo "  $tty_messages"
    fi
    echo
    
    # Environment checks
    echo "=== Environment Checks ==="
    echo "User: $(whoami)"
    echo "Groups: $(groups 2>/dev/null || echo "unknown")"
    echo "TERM: ${TERM:-unset}"
    echo "DISPLAY: ${DISPLAY:-unset}"
    echo
    
    log_info "Diagnostics complete. If you're experiencing black screens, check:"
    log_info "1. Getty services are active for the target TTY"
    log_info "2. TTY devices are responsive"
    log_info "3. No conflicting X11 processes"
    log_info "4. Proper autologin configuration if needed"
}

# Show usage information
show_usage() {
    echo "MediaScreen TTY Terminal Switcher"
    echo
    echo "Usage: ms-switch [OPTION|TTY_NUMBER]"
    echo
    echo "Options:"
    echo "  list              List available TTY terminals"
    echo "  status            Show current TTY terminal status"
    echo "  reload TTY_NUMBER Restart getty service for specified TTY"
    echo "  diagnose          Show detailed diagnostic information"
    echo "  -h, --help        Show this help message"
    echo
    echo "Arguments:"
    echo "  TTY_NUMBER        Switch to specified TTY number (1, 2, 3, etc.)"
    echo
    echo "Examples:"
    echo "  ms-switch             # Interactive mode"
    echo "  ms-switch list        # List available TTY terminals"
    echo "  ms-switch 2           # Switch to TTY #2"
    echo "  ms-switch reload 1    # Restart getty service for TTY #1"
    echo "  ms-switch status      # Show current TTY terminal info"
    echo "  ms-switch diagnose    # Show detailed diagnostic information"
    echo
    echo "Note: This command requires root privileges to switch terminals and restart services."
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
        "diagnose"|"d")
            run_diagnostics
            ;;
        "reload"|"r")
            # Reload/restart specific TTY
            if ! reload_terminal "$2"; then
                exit 1
            fi
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
