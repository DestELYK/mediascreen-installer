#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Check if connected to the internet
echo "Checking internet connection..."
attempts=0
while ! ping -q -c 1 -W 1 google.com >/dev/null; do
    attempts=$((attempts+1))
    if [ $attempts -gt 3 ]; then
        echo "Failed to connect to the internet after 3 attempts. Exiting..."
        exit 1
    fi

    echo "Not connected to the internet. Configuring WiFi..."
    read -p "Enter the SSID: " SSID
    read -p "Enter the password: " PASSWORD
    # Connect to WiFi using wpa_supplicant
    wpa_passphrase "$SSID" "$PASSWORD" | tee /etc/wpa_supplicant.conf > /dev/null
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf

    # Refresh network interfaces
    echo "Refreshing network interfaces..."
    systemctl restart networking
done
echo "Connected to the internet."

# Base URL for scripts and configuration file
base_url="https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main"
config_url="${base_url}/menu_config.txt"
base_url+="/scripts"

# Temporary directory for downloads
tmp_dir=$(mktemp -d)
cd "$tmp_dir"

# Download the configuration file
wget -q "${config_url}" -O menu_config.txt

# Read the configuration file and generate menu options
declare -a menu_names
declare -a menu_descriptions
declare -a script_filenames
while IFS=, read -r name description filename; do
    menu_names+=("$name")
    menu_descriptions+=("$description")
    script_filenames+=("$filename")
    echo "Downloading $name script..."
    # Download the script file
    wget -q "${base_url}/${filename}" -O "${filename}"
    # Move the script file to /usr/local/bin
    mv "${filename}" "/usr/local/bin/${filename}"

    chmod +x "/usr/local/bin/${filename}"
done < menu_config.txt

# Source the script file
source "/usr/local/bin/"

full_install() {
    echo "Running full install..."
    for script in "${script_filenames[@]}"; do
        bash "$script"
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
    echo "Select an installation option:"
    echo "0) Full Install"
    for i in "${!menu_names[@]}"; do
            echo "$((i+1))) ${menu_names[$i]} - ${menu_descriptions[$i]}"
    done
    echo "$((i+2))) Exit"
}

# Function to run a selected script
run_option() {
    if [ "$1" -eq 0 ]; then
            full_install
    elif [ "$1" -le "${#menu_names[@]}" ]; then
            local script="${script_filenames[$(($1-1))]}"
            bash $script
            if [ $? -ne 0 ]; then
                    echo "Script failed: $script. Exiting..."
                    exit 1
            fi
    elif [ "$1" -eq "$((${#menu_names[@]}+1))" ]; then
            echo "Exiting..."
            exit
    else
            echo "Invalid option. Please try again."
    fi
}

# Check for argument "--full-install"
if [ "$1" = "--full-install" ]; then
    full_install
    exit
fi

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    run_option "$choice"
done