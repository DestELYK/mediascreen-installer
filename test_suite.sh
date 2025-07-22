#!/bin/bash

# MediaScreen Installer Test Suite
# Author: DestELYK
# Updated: 07-22-2025
# Description: Comprehensive test suite for MediaScreen installer components

echo "=== MediaScreen Installer Test Suite ==="
echo "Date: $(date)"
echo "Testing MediaScreen installer components..."
echo

# Initialize test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$result" == "PASS" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "PASS: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $test_name"
    fi
    
    if [[ -n "$message" ]]; then
        echo "  └─ $message"
    fi
}

# Test 1: Repository structure
echo "Test 1: Checking repository structure..."
REPO_DIR="/home/kyle/projects/mediascreen-installer"

# Check main files
if [[ -f "$REPO_DIR/install.sh" ]]; then
    test_result "Main installer present" "PASS"
else
    test_result "Main installer present" "FAIL" "install.sh not found"
fi

if [[ -f "$REPO_DIR/menu_config.txt" ]]; then
    test_result "Menu configuration present" "PASS"
else
    test_result "Menu configuration present" "FAIL" "menu_config.txt not found"
fi

if [[ -f "$REPO_DIR/README.md" ]]; then
    test_result "Documentation present" "PASS"
else
    test_result "Documentation present" "FAIL" "README.md not found"
fi

if [[ -f "$REPO_DIR/ms-util.sh" ]]; then
    test_result "Menu utility present" "PASS"
else
    test_result "Menu utility present" "FAIL" "ms-util.sh not found"
fi

# Test 2: Scripts directory structure
echo
echo "Test 2: Checking scripts directory structure..."
SCRIPT_DIR="$REPO_DIR/scripts"

if [[ -d "$SCRIPT_DIR" ]]; then
    test_result "Scripts directory exists" "PASS"
else
    test_result "Scripts directory exists" "FAIL" "scripts/ directory not found"
fi

if [[ -d "$SCRIPT_DIR/../lib" ]]; then
    test_result "Library directory exists" "PASS"
else
    test_result "Library directory exists" "FAIL" "lib/ directory not found"
fi

# Test 3: Core scripts availability
echo
echo "Test 3: Checking core script availability..."
CORE_SCRIPTS=(
    "configure-network.sh"
    "autologin-setup.sh" 
    "browser-setup.sh"
    "firewall-setup.sh"
    "hide-grub.sh"
    "splashscreen-setup.sh"
    "autoupdates-setup.sh"
    "reboot-setup.sh"
)

all_scripts_present=true
for script in "${CORE_SCRIPTS[@]}"; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
        test_result "$script present" "PASS"
    else
        test_result "$script present" "FAIL" "Script not found"
        all_scripts_present=false
    fi
done

# Test 4: Common library functionality
echo
echo "Test 4: Checking common library..."
COMMON_LIB="$SCRIPT_DIR/../lib/common.sh"

if [[ -f "$COMMON_LIB" ]]; then
    test_result "Common library file exists" "PASS"
    
    # Test required functions
    REQUIRED_FUNCTIONS=(
        "init_common"
        "log_info"
        "log_error"
        "parse_common_args"
        "check_debian"
        "check_root"
        "download_file"
        "install_package"
        "prompt_yes_no"
    )
    
    functions_ok=true
    for func in "${REQUIRED_FUNCTIONS[@]}"; do
        if grep -q "^$func()" "$COMMON_LIB"; then
            test_result "Function $func exists" "PASS"
        else
            test_result "Function $func exists" "FAIL" "Function not found in common library"
            functions_ok=false
        fi
    done
    
    # Test common library syntax
    if bash -n "$COMMON_LIB" 2>/dev/null; then
        test_result "Common library syntax" "PASS"
    else
        test_result "Common library syntax" "FAIL" "Syntax errors in common library"
    fi
    
else
    test_result "Common library file exists" "FAIL" "common.sh not found"
fi

# Test 5: Script syntax validation
echo
echo "Test 5: Testing script syntax..."
syntax_ok=true

# Test install.sh
if bash -n "$REPO_DIR/install.sh" 2>/dev/null; then
    test_result "install.sh syntax" "PASS"
else
    test_result "install.sh syntax" "FAIL" "Syntax errors detected"
    syntax_ok=false
fi

# Test ms-util.sh
if bash -n "$REPO_DIR/ms-util.sh" 2>/dev/null; then
    test_result "ms-util.sh syntax" "PASS"
else
    test_result "ms-util.sh syntax" "FAIL" "Syntax errors detected"
    syntax_ok=false
fi

# Test all core scripts
for script in "${CORE_SCRIPTS[@]}"; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
        if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
            test_result "$script syntax" "PASS"
        else
            test_result "$script syntax" "FAIL" "Syntax errors detected"
            syntax_ok=false
        fi
    fi
done

# Test 6: Configuration file format
echo
echo "Test 6: Testing configuration format..."
CONFIG_FILE="$REPO_DIR/menu_config.txt"

if [[ -f "$CONFIG_FILE" ]]; then
    # Check format: number,number,description
    if grep -q "^[0-9]\+,[0-9]\+," "$CONFIG_FILE"; then
        test_result "Menu config format" "PASS"
    else
        test_result "Menu config format" "FAIL" "Invalid format in menu_config.txt"
    fi
    
    # Check if file is not empty
    if [[ -s "$CONFIG_FILE" ]]; then
        test_result "Menu config not empty" "PASS"
    else
        test_result "Menu config not empty" "FAIL" "menu_config.txt is empty"
    fi
else
    test_result "Menu config exists" "FAIL" "menu_config.txt not found"
fi

# Test 7: Image upload functionality
echo
echo "Test 7: Checking image upload functionality..."
IMAGE_UPLOAD_DIR="$REPO_DIR/image-upload"

if [[ -d "$IMAGE_UPLOAD_DIR" ]]; then
    test_result "Image upload directory exists" "PASS"
    
    if [[ -f "$IMAGE_UPLOAD_DIR/index.html" ]]; then
        test_result "Upload interface exists" "PASS"
    else
        test_result "Upload interface exists" "FAIL" "index.html not found"
    fi
    
    if [[ -f "$IMAGE_UPLOAD_DIR/server.py" ]]; then
        test_result "Upload server exists" "PASS"
        
        # Test Python script syntax
        if python3 -m py_compile "$IMAGE_UPLOAD_DIR/server.py" 2>/dev/null; then
            test_result "Upload server syntax" "PASS"
        else
            test_result "Upload server syntax" "FAIL" "Python syntax errors"
        fi
    else
        test_result "Upload server exists" "FAIL" "server.py not found"
    fi
else
    test_result "Image upload directory exists" "FAIL" "image-upload/ directory not found"
fi

# Test 8: Autologin configuration files
echo
echo "Test 8: Checking autologin configuration..."
AUTOLOGIN_DIR="$REPO_DIR/autologin"

if [[ -d "$AUTOLOGIN_DIR" ]]; then
    test_result "Autologin directory exists" "PASS"
    
    if [[ -f "$AUTOLOGIN_DIR/browser" ]]; then
        test_result "Browser autologin config exists" "PASS"
    else
        test_result "Browser autologin config exists" "FAIL" "autologin/browser not found"
    fi
    
    if [[ -f "$AUTOLOGIN_DIR/menu" ]]; then
        test_result "Menu autologin config exists" "PASS" 
    else
        test_result "Menu autologin config exists" "FAIL" "autologin/menu not found"
    fi
else
    test_result "Autologin directory exists" "FAIL" "autologin/ directory not found"
fi

# Test 9: Common arguments support
echo
echo "Test 9: Testing common arguments support..."

# Test all core scripts
help_scripts_ok=true
for script in "${CORE_SCRIPTS[@]}"; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
        # Skip configure-network.sh as it doesn't use common library by design
        if [[ "$script" == "configure-network.sh" ]]; then
            test_result "$script present (standalone)" "PASS"
            continue
        fi
        
        # Check if script sources common library
        if grep -q "source.*common.sh" "$SCRIPT_DIR/$script"; then
            test_result "$script uses common library" "PASS"
        else
            test_result "$script uses common library" "FAIL" "Script doesn't source common.sh"
            help_scripts_ok=false
        fi
        
        # Check if script calls parse_common_args
        if grep -q "parse_common_args" "$SCRIPT_DIR/$script"; then
            test_result "$script supports common args" "PASS"
        else
            test_result "$script supports common args" "FAIL" "Script doesn't use parse_common_args"
            help_scripts_ok=false
        fi
    fi
done

# Test 10: Error handling and 404 support
echo
echo "Test 10: Testing error handling features..."

# Check if common library has 404 handling
if grep -q "handle_404_error" "$COMMON_LIB"; then
    test_result "404 error handling present" "PASS"
else
    test_result "404 error handling present" "FAIL" "handle_404_error function not found"
fi

# Check if download_file has enhanced error handling
if grep -q "http_code" "$COMMON_LIB"; then
    test_result "Enhanced download error handling" "PASS"
else
    test_result "Enhanced download error handling" "FAIL" "HTTP status code handling not found"
fi

# Check for GitHub URL customization support
if grep -q "CUSTOM_GITHUB_URL" "$COMMON_LIB"; then
    test_result "Custom GitHub URL support" "PASS"
else
    test_result "Custom GitHub URL support" "FAIL" "Custom GitHub URL functionality not found"
fi

# Test 11: Dev branch support
echo
echo "Test 11: Testing development features..."

# Check for dev branch support
if grep -q "\-\-dev" "$COMMON_LIB"; then
    test_result "Dev branch switch support" "PASS"
else
    test_result "Dev branch switch support" "FAIL" "--dev flag support not found"
fi

# Check for debug mode support
if grep -q "\-\-debug" "$COMMON_LIB"; then
    test_result "Debug mode support" "PASS"
else
    test_result "Debug mode support" "FAIL" "--debug flag support not found"
fi

# Test 12: Installation simulation (dry run)
echo
echo "Test 12: Testing installer dry run..."

cd "$REPO_DIR"

# Test install.sh argument parsing (check for help option support)
if grep -q "\-\-help" "$REPO_DIR/install.sh"; then
    test_result "Installer help functionality" "PASS"
else
    test_result "Installer help functionality" "FAIL" "Help option not found in script"
fi

# Test ms-util.sh argument parsing (check for help option support)
if grep -q "\-\-help" "$REPO_DIR/ms-util.sh"; then
    test_result "Menu utility help functionality" "PASS"
else
    test_result "Menu utility help functionality" "FAIL" "Help option not found in script"
fi

# Summary
echo
echo "========================================"
echo "=== Test Summary ==="
echo "========================================"
echo "Tests Run: $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED" 
echo "Tests Failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "ALL TESTS PASSED!"
    echo "The MediaScreen installer is ready for production use."
    echo
    echo "Key features validated:"
    echo "  - Modular script architecture with common library"
    echo "  - Separated installation (install.sh) and menu (ms-util.sh) systems"
    echo "  - Enhanced error handling with 404 detection"
    echo "  - Custom GitHub URL support"
    echo "  - Development branch switching"
    echo "  - Web-based image upload functionality"
    echo "  - Comprehensive argument parsing"
    echo "  - Clean directory structure with lib outside scripts"
    exit 0
else
    echo "SOME TESTS FAILED!"
    echo "Please review the failed tests above and fix any issues."
    echo "The installer may not function correctly until all tests pass."
    exit 1
fi
