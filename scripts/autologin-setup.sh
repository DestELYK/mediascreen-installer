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

# Check if the system is using Debian
if [[ ! -f /etc/debian_version ]]; then
    echo "System is not using Debian. Exiting..."
    exit 1
fi

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
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

# Create override.conf file for getty@tty1
echo "[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $username --noclear %I \$TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf

# Create systemd service file for getty@tty2
if [ ! -d "/etc/systemd/system/getty@tty2.service.d" ]; then
    mkdir -p /etc/systemd/system/getty@tty2.service.d
    echo "Created directory /etc/systemd/system/getty@tty2.service.d"
fi

# Create override.conf file for getty@tty2
echo "[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $SUDO_USER --noclear %I \$TERM" > /etc/systemd/system/getty@tty2.service.d/override.conf

# Update the number of virtual terminals in logind.conf
sed -i "s/#NAutoVTs=6/NAutoVTs=3/" /etc/systemd/logind.conf

touch /home/$username/.hushlogin
chown $username:$username /home/$username/.hushlogin

echo "Downloading autologin files..."
# Downloads the .bash_profile files for the browser
wget -q 'https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main/autologin/browser' || {
    echo "Failed to download autologin for browser. Exiting..."
    exit 1
}
chown $username:$username browser
mv browser /home/$username/.bash_profile

# Downloads the .bash_profile files for the menu
wget -q 'https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main/autologin/menu' || {
    echo "Failed to download autologin for menu. Exiting..."
    exit 1
}
chown $SUDO_USER:$SUDO_USER menu
mv menu /home/$SUDO_USER/.bash_profile