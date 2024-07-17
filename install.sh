#!/bin/bash

<<comment
    This script installs the required scripts for the MediaScreen system.

    The script downloads the configuration file and required scripts from the GitHub repository.
    The user can choose to run a specific script or run the full installation.

    This script requires root privileges. Please run as root.

    Command Usage:
        - To run the full installation:
            sudo bash install.sh --full-install
        - To run the full installation and autolaunch with specific username:
            sudo bash install.sh --full-install --username=<username>
        - To run a specific script:
            sudo bash install.sh

    Author: DestELYK
    Date: 07-09-2024
comment

# Check if the system is using Debian
if [[ ! -f /etc/debian_version ]]; then
    echo "System is not using Debian. Exiting..."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

function exit_prompt()
{
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

trap exit_prompt SIGINT

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

    for script in "${script_filenames[@]}"; do
        arguments="--username='$username'"
        if [ -n "$2" ]; then
            arguments+=" --url='$2'"
        fi

        command="$script $arguments"

        echo "Running script: $command"

        bash -c "$command" || {
            echo "Failed to run script: $script. Exiting in 10 seconds..."
            sleep 10
            exit 1
        }
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

FULL_INSTALL=false

for arg in "$@"; do
    case $arg in
        --full-install)
            FULL_INSTALL=true
        ;;
        --username=*)
            USERNAME="${arg#*=}"
        ;;
        --url=*)
            URL="${arg#*=}"
        ;;
    esac
done

# Check for argument "--full-install"
if [[ "$@" == *"--full-install"* ]]; then
    full_install "$USERNAME" "$URL"
    exit
fi

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    run_option "$choice"
done