#!/bin/bash

"""
This script installs the required scripts for the MediaScreen system.

The script downloads the configuration file and required scripts from the GitHub repository.
The user can choose to run a specific script or run the full installation.

This script requires root privileges. Please run as root.

Command Usage:
    - To run the full installation:
        sudo bash install.sh --full-install
    - To run the full installation and autolaunch with specific username:
        sudo bash install.sh --full-install --username <username>
    - To run a specific script:
        sudo bash install.sh

Author: DestELYK
Date: 07-09-2024
"""

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Check internet connection
if ping -q -c 1 -W 1 google.com >/dev/null; then
    echo "Internet connected"
else
    echo "Internet not connected. Exiting..."
    exit 1
fi

# Base URL for scripts and configuration file
base_url="https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main"
config_url="${base_url}/menu_config.txt"

# Temporary directory for downloads
tmp_dir=$(mktemp -d)
cd "$tmp_dir"

# Download the configuration file
wget -q "${config_url}" -O menu_config.txt || {
    echo "Failed to download configuration file. Exiting..."
    exit 1
}

# Read the configuration file and generate menu options
declare -a menu_names
declare -a menu_descriptions
declare -a script_filenames
echo "Downloading required scripts..."
while IFS=, read -r name description filename; do
    filename=$(echo $filename | tr -d '\r') # Remove carriage return

    menu_names+=("$name")
    menu_descriptions+=("$description")
    script_filenames+=("$filename")
    # Download the script file
    wget -q "${base_url}/scripts/${filename}" -O "${filename}" || {
        echo "Failed to download script: ${filename}. Exiting..."
        exit 1
    }
    chmod +x "$filename"
    chown ${SUDO_USER}:${SUDO_USER} "$filename"
    
    # Move the script file to /usr/local/bin
    mv "${filename}" "/usr/local/bin/${filename}"

done < menu_config.txt
echo "Finished downloading required scripts"

sleep 1

full_install() {
    echo "Running full install..."
    # Check if username is provided as argument
    if [ -n "$1" ]; then
        username="$1"
    else
        read -p "Enter the username: " username
    fi

    # Check if user exists
    if ! id "$username" >/dev/null 2>&1; then
        # Create user with no password
        useradd -m -s /bin/bash -p '*' "$username"
        echo "User $username created with no password."
    fi

    while true; do
        read -p "Enter the resolution (in the format '1920x1080', press Enter for default): " RESOLUTION

        # Validate resolution format
        if [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
            break
        elif [[ -z $RESOLUTION ]]; then
            RESOLUTION="1920x1080"
            break
        else
            echo "Invalid resolution format. Please enter in the format '1920x1080'."
        fi
    done

    for script in "${script_filenames[@]}"; do
        bash -c "'$script' --username '$username' --resolution '$RESOLUTION'"
        if [ $? -ne 0 ]; then
            echo "Script failed: ${script}. Exiting..."
            exit 1
        fi
    done
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
}

# Function to display the menu
show_menu() {
    clear

    echo "+-----------------------------------------------------------------------------------------+"
    echo "|                                 MediaScreen Installer                               |"
    echo "+-----------------------------------------------------------------------------------------+"
    echo "0) Full Install"
    for i in "${!menu_names[@]}"; do
            echo "$((i+1))) ${menu_names[$i]} - ${menu_descriptions[$i]}"
    done
    echo "==========================================================================================="
    echo "                            u - Update | r - Reboot | q - Exit"
    echo "==========================================================================================="
}

# Function to run a selected script
run_option() {
    case $1 in
        0)
            full_install
            ;;
        [1-9]*)
            local script="${script_filenames[$(($1-1))]}"
            bash $script || {
                echo "Failed to run script: $script. Exiting..."
                exit 1
            }
            ;;
        u|update)
            echo "Updating..."
            wget -q "${base_url}/install.sh" -O install.sh || {
                echo "Download failed. Please enter the URL:"
                read -r new_url
                wget -q "$new_url" -O install.sh || {
                    echo "Download failed again. Please check the URL and try again later."
                    return 1
                }
            }
            chmod +x install.sh
            mv install.sh /usr/local/bin/mediascreen-util.sh
            echo "Updated successfully. This script will now exit."
            exit
            ;;
        r|reboot)
            echo "Rebooting in 10 seconds..."
            sleep 10
            reboot
            ;;
        q|quit|exit)
            echo "Exiting..."
            exit
            ;;
        *)
            echo "Invalid option. Please try again."
            return
            ;;
    esac
}

# Check for argument "--full-install"
if [[ "$@" == *"--full-install"* ]]; then
    # Check if --username is in arguments
    if [[ "$@" == *"--username"* ]]; then
        # Get index of --username argument
        index=$(echo "$@" | grep -o -n -- "--username" | cut -d ":" -f 1)

        # Get the value of --username argument
        username=$(echo "$@" | cut -d' ' -f$((index + 2)))

        full_install "$username"
    else
        full_install
    fi

    exit
fi

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    run_option "$choice"
done