#!/bin/bash

<<comment
    This script sets up autologin for a user on tty1.

    The script creates a user if it does not exist, sets up autologin for the user on tty1, and updates the number of virtual terminals in logind.conf.

    This script requires root privileges. Please run as root.

    Command line usage:
        - To set up autologin for a specific user:
            sudo ./autologin-setup.sh --username=<username>

    Author: DestELYK
    Date: 07-09-2024
comment

function get_username() {
    while true; do
        # Ask user for username to launch browser
        read -p "Enter the username that autostarts: " username

        # Validate username
        if [[ ! $username =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo "Invalid username. Please use only alphanumeric characters and underscores."
            continue
        fi

        break
    done

    echo $username
}

function setup_tty1() {
    if [[ -z "$1" ]]; then
        username=$(get_username)
    else
        username=$1
    fi

    echo "Setting up autologin for $username..."

    if ! id "$username" >/dev/null 2>&1; then
        # Create user with no password
        useradd -m -s /bin/bash -p '*' "$username"
        echo "User $username created with no password."
    fi

    # Create systemd service file for getty@tty1
    if [ ! -d "/etc/systemd/system/getty@tty1.service.d" ]; then
        mkdir -p /etc/systemd/system/getty@tty1.service.d
        echo "Created directory /etc/systemd/system/getty@tty1.service.d"
    fi

    # Create override.conf file for getty@tty1
    echo "[Service]
    ExecStart=
    ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $username --noclear %I \$TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf

    echo "Downloading autologin file..."
    # Downloads the .bash_profile files for the browser
    wget -q 'https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main/autologin/browser' || {
        echo "Failed to download autologin for browser. Exiting..."
        exit 1
    }
    chown $username:$username browser
    mv browser /home/$username/.bash_profile

    touch /home/$username/.hushlogin
    chown $username:$username /home/$username/.hushlogin
}

function setup_tty2() {
    # Create systemd service file for getty@tty2
    if [ ! -d "/etc/systemd/system/getty@tty2.service.d" ]; then
        mkdir -p /etc/systemd/system/getty@tty2.service.d
        echo "Created directory /etc/systemd/system/getty@tty2.service.d"
    fi

    # Create override.conf file for getty@tty2
    echo "[Service]
    ExecStart=
    ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin root --noclear %I \$TERM" > /etc/systemd/system/getty@tty2.service.d/override.conf

    # Downloads the .bash_profile files for the menu
    echo "Downloading autologin file..."
    wget -q 'https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main/autologin/menu' || {
        echo "Failed to download autologin for menu. Exiting..."
        exit 1
    }
    mv menu /root/.bash_profile
}

function exit_prompt()
{
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# Check if the system is using Debian
if [[ ! -f /etc/debian_version ]]; then
    echo "System is not using Debian. Exiting..."
    exit 1
fi

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

trap exit_prompt SIGINT

echo "Configuring AutoLogin..."

# Check if --username is in arguments
for arg in "$@"; do
    case $arg in
        --username=*)
            username="${arg#*=}"
        ;;
        -y)
            auto_install=true
        ;;
    esac
done

if [[ ! -z "$auto_install" ]]; then
    # Check if --username is in arguments
    if [[ -z "$username" ]]; then
        echo "No username provided. Exiting..."
        exit 1
    fi

    # Check if user exists
    if ! id "$username" >/dev/null 2>&1; then
        #Validate username
        if [[ ! $username =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo "Invalid username. Please use only alphanumeric characters and underscores. Exiting..."
            exit 1
        fi

        # Create user with no password
        useradd -m -s /bin/bash -p '*' "$username"
        echo "User $username created with no password."
    fi

    setup_tty1 $username

    setup_tty2

    # Update the number of virtual terminals in logind.conf
    sed -i "s/.*NAutoVTs=.*/NAutoVTs=3/" /etc/systemd/logind.conf
else
    # Check if autologin for tty1 is already set up
    if [ -d "/etc/systemd/system/getty@tty1.service.d" ]; then
        read -p "Autologin for tty1 is already set up. Do you want to reconfigure or remove? (y/r/n): " reconfigure

        # Check if user wants to reconfigure or remove autologin for tty1
        if [[ $reconfigure =~ ^[Yy]$ ]]; then
            username=$(get_username)

            setup_tty1 $username
        elif [[ $reconfigure =~ ^[Rr]$ ]]; then
            echo "Removing autologin for tty1..."
            rm -rf "/etc/systemd/system/getty@tty1.service.d"

            username=$(get_username)
            
            # Remove .bash_profile and .hushlogin files
            if [ -f "/home/$username/.bash_profile" ]; then
                rm -f "/home/$username/.bash_profile"
            fi

            if [ -f "/home/$username/.hushlogin" ]; then
                rm -f "/home/$username/.hushlogin"
            fi

            # Remove user
            read -p "Do you want to remove the user $username? (y/n): " remove_user
            if [[ $remove_user =~ ^[Yy]$ ]]; then
                userdel -r $username
                echo "User $username removed."
            fi
        fi
    else
        read -p "Do you want to setup tty1 to autologin? (y/n): " autologin_tty1

        if [[ $autologin_tty1 =~ ^[Yy]$ ]]; then
            setup_tty1 $username

            tty1_autologin=true
        fi
    fi

    # Check if tty2 is already set up
    if [ -d "/etc/systemd/system/getty@tty2.service.d" ]; then
        read -p "Autologin for tty2 is already set up. Do you want to reconfigure or remove? (y/r/n): " reconfigure

        # Check if user wants to reconfigure or remove autologin for tty2
        if [[ $reconfigure =~ ^[Yy]$ ]]; then
            setup_tty2
        elif [[ $reconfigure =~ ^[Rr]$ ]]; then
            echo "Removing autologin for tty2..."
            rm -rf "/etc/systemd/system/getty@tty2.service.d"

            # Remove .bash_profile file
            if [ -f "/root/.bash_profile" ]; then
                rm -f "/root/.bash_profile"
            fi
        fi
    else
        read -p "Do you want to set up a menu for tty2? (y/n): " autologin_tty2

        if [[ $autologin_tty2 =~ ^[Yy]$ ]]; then
            setup_tty2

            tty2_autologin=true
        fi
    fi

    sed -i "s/.*NAutoVTs=.*/NAutoVTs=3/" /etc/systemd/logind.conf
fi