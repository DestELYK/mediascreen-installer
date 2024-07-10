#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [[ "$@" == *"--resolution"* ]]; then
    exit 0
fi

if [ ! -f /boot/default/grub ]; then
    echo "grub configuration file does not exist"
    exit 1
fi

# Check if --username is in arguments
if [[ "$@" == *"--username"* ]]; then
    # Get the index of --username argument
    index=$(echo "$@" | grep -bo -- "--username" | awk -F: '{print $1}')
    # Get the value of --username argument
    username=$(echo "$@" | cut -d' ' -f$((index + 1)))
else
    # Ask user for username to launch browser
    read -p "Enter the username that autostarts: " username
fi

# Check if user exists
if ! id "$username" >/dev/null 2>&1; then
    echo "User $username does not exist. Exiting..."
    exit 1
fi

# Ask for resolution until a valid format is entered
TRIES=0
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
        TRIES=$((TRIES+1))
        if [ $TRIES -eq 3 ]; then
            echo "Exceeded maximum number of tries. Exiting..."
            exit 1
        fi
    fi
done

# Update GRUB configuration
# Check if GRUB_GFXMODE is set
if grep -q "^GRUB_GFXMODE=" /boot/default/grub; then
    # Replace GRUB_GFXMODE with new resolution
    sed -i "s/^GRUB_GFXMODE=.*/GRUB_GFXMODE=$RESOLUTION/" /boot/default/grub
else
    # Insert GRUB_GFXMODE into /boot/default/grub
    echo "GRUB_GFXMODE=$RESOLUTION" >> /boot/default/grub
fi

# Format resolution (chromium requires comma-separated resolution)
FORMATTED_RESOLUTION=$(echo "$RESOLUTION" | sed 's/x/,/')

if [ -f "/home/$username/.xinitrc" ]; then
    sed -i "s/--window-size=.*/--window-size=$FORMATTED_RESOLUTION/" "/home/$username/.xinitrc"
fi