#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Configuring Browser Launch..."

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

# Check if --resolution is in arguments
if [[ "$@" == *"--resolution"* ]]; then
    # Get the index of --resolution argument
    index=$(echo "$@" | grep -bo -- "--resolution" | awk -F: '{print $1}')
    # Get the value of --resolution argument
    resolution=$(echo "$@" | cut -d' ' -f$((index + 1)))
else
    echo "No resolution provided. Defaulting to 1920x1080..."
    resolution="1920x1080"
fi

# Format resolution for later use
FORMATTED_RESOLUTION=$(echo $resolution | tr 'x' ',')

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