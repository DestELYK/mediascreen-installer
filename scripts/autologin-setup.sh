#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Configuring AutoLogin..."

# Check if --username is in arguments
if [[ "$@" == *"--username"* ]]; then
    # Get index of --username argument
    index=$(echo "$@" | grep -o -n -- "--username" | cut -d ":" -f 1)

    # Get the value of --username argument
    username=$(echo "$@" | cut -d' ' -f$((index + 1)))
else
    # Ask user for username to launch browser
    read -p "Enter the username that autostarts: " username
fi

# Check if user exists
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