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


if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Configuring AutoLogin..."

# Check if --username is in arguments
for arg in "$@"; do
    case $arg in
        --username=*)
            username="${arg#*=}"
        ;;
    esac
done

# Check if --username is in arguments
if [[ -z "$username" ]]; then
    # Ask user for username to launch browser
    read -p "Enter the username that autostarts: " username
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

echo "Setting up autologin for $username..."

# Create systemd service file for getty@tty1
if [ ! -d "/etc/systemd/system/getty@tty1.service.d" ]; then
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    echo "Created directory /etc/systemd/system/getty@tty1.service.d"
fi

echo "[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $username --noclear %I \$TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf

# Ask user for the amount of terminals
while true; do
    read -p "Enter the amount of terminals (minimum 1): " num_terminals

    # Validate the input
    if [[ ! $num_terminals =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid input. Please enter a valid number greater than or equal to 1."
    else
        break
    fi
done

# Update the number of virtual terminals in logind.conf
sed -i "s/#NAutoVTs=6/NAutoVTs=$num_terminals/" /etc/systemd/logind.conf

su - $username -c "touch ~/.hushlogin"