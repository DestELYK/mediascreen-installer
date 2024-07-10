#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Configuring Browser Launch..."

# Ask user for username to launch browser
read -p "Enter the username that autostarts: " username

# Check if user exists
if ! id "$username" >/dev/null 2>&1; then
    echo "User $username does not exist. Exiting..."
    exit 1
fi

# Ask for URL to launch
tries=0
while [[ $tries -lt 3 ]]; do
    read -p "Enter the URL to launch: " url

    # Loop to validate URL
    if [[ $url =~ ^https?:// ]]; then
        break
    else
        echo "Invalid URL. Please enter a valid URL starting with http:// or https://"
        tries=$((tries + 1))
    fi
done

# Exit if URL is not provided after 3 tries
if [[ $tries -eq 3 && ! $url =~ ^https?:// ]]; then
    echo "URL not provided. Exiting..."
    exit 1
fi

# Ask for resolution until a valid format is entered
TRIES=0
while true; do
    read -p "Enter the resolution (in the format '1920x1080'): " RESOLUTION

    # Validate resolution format
    if [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
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

# Format resolution (chromium requires comma-separated resolution)
FORMATTED_RESOLUTION=$(echo "$RESOLUTION" | sed 's/x/,/')

# Automatic Browser Launch
echo "Installing required packages for browser launch..."
apt-get install --no-install-recommends xserver-xorg-video-all xserver-xorg-input-all xserver-xorg-core xinit x11-xserver-utils chromium unclutter -y

# Checks if the logged in user is using the display and using tty1
echo "Configuring browser launch..."
su - $username -c "echo 'if [ -z \$DISPLAY ] && [ \$(tty) = /dev/tty1 ]
then
    exec startx &>/dev/null
fi' > ~/.bash_profile"

# Configures the browser to launch on startup
echo "Creating .xinitrc file..."
su - $username -c "echo '#!/usr/bin/env sh
xset -dpms
xset s off
xset s noblank

unclutter &
chromium $url \
    --window-size=$FORMATTED_RESOLUTION \
    --window-position=0,0 \
    --start-fullscreen \
    --kiosk \
    --noerrdialogs \
    --disable-translate \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-infobars \
    --disable-features=TranslateUI \
    --overscroll-history-navigation=0 \
    --disable-pinch' > ~/.xinitrc"