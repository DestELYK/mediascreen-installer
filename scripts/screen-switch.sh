#!/bin/bash

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

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

# Get available TTY terminals
get_terminals() {
    log_debug "Detecting available TTY terminals..."
    
    # Get current terminal
    local current_tty=$(fgconsole 2>/dev/null || echo "unknown")
    
    # Check for available TTY devices
    local tty_count=0
    for tty_num in {1..12}; do
        if [[ -c "/dev/tty${tty_num}" ]]; then
            local status=""
            if [[ "$tty_num" == "$current_tty" ]]; then
                status=" [CURRENT]"
            fi
            
            # Check if there's a getty process running on this TTY
            local getty_status=""
            if pgrep -f "getty.*tty${tty_num}" >/dev/null 2>&1; then
                getty_status=" (getty active)"
            fi
            
            echo "tty${tty_num}|TTY ${tty_num}|${status}${getty_status}"
            tty_count=$((tty_count + 1))
        fi
    done
    
    log_debug "Found $tty_count available TTY terminals"
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
    
    # Show running getty processes
    echo
    log_info "Active getty processes:"
    if pgrep -a getty 2>/dev/null | grep -E "tty[0-9]+" | head -10; then
        true
    else
        echo "  No getty processes found"
    fi
    
    # Show virtual terminal info
    echo
    log_info "Virtual terminal status:"
    if [[ -f "/sys/class/tty/console/active" ]]; then
        local active_consoles=$(cat /sys/class/tty/console/active 2>/dev/null || echo "unknown")
        echo "  Active consoles: $active_consoles"
    fi
    
    # Show systemd targets related to getty
    echo
    log_info "Getty systemd services:"
    systemctl list-units --type=service --state=active "getty@*" 2>/dev/null | head -10 || echo "  Unable to query systemd services"
}

# Switch to specific TTY terminal
switch_to_terminal() {
    local target_number="$1"
    
    log_info "Switching to TTY #$target_number..."
    
    # Get terminal list as array
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
        log_info "Available TTYs: 1-${#terminals[@]}"
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
        "")
            # Interactive mode
            if ! interactive_selection; then
                exit 1
            fi
            check_services_after_switch
            ;;
        [0-9]*)
            # Direct TTY number
            if ! switch_to_terminal "$1"; then
                exit 1
            fi
            check_services_after_switch
            ;;
        *)
            log_error "Unknown option: $1"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
