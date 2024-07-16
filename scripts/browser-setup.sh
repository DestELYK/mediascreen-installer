#!/bin/bash

<<comment
    This script configures the browser to launch on startup.

    The script installs the required packages for browser launch, configures the browser to launch on startup, and sets the resolution for the browser.

    This script requires root privileges. Please run as root.

    Command Line Usage:
        - To configure the browser launch:
            sudo ./browser-setup.sh
        - To configure the browser launch with a specific username:
            sudo ./browser-setup.sh --username=<username>
        - To configure the browser launch with a specific resolution:
            sudo ./browser-setup.sh --resolution=<resolution>
        - To configure the browser launch with a specific username and resolution:
            sudo ./browser-setup.sh --username=<username> --resolution=<resolution>

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

echo "Configuring Browser Launch..."

# Check if --username or --resolution is in arguments
for arg in "$@"; do
    case $arg in
        --username=*)
            username="${arg#*=}"
        ;;
        --resolution=*)
            resolution="${arg#*=}"

            # Validate resolution format
            if [[ ! $resolution =~ ^[0-9]+x[0-9]+$ ]]; then
                echo "Invalid resolution format. Please enter in the format '1920x1080'. Exiting..."
                exit 1
            fi
        ;;
        --url=*)
            url="${arg#*=}"

            # Validate URL format
            if [[ ! $url =~ ^https?:// ]]; then
                echo "Invalid URL format. Please enter a valid URL starting with http:// or https://. Exiting..."
                exit 1
            fi
    esac
done

# Check if --username is in arguments
if [[ -z "$username" ]]; then
    # Ask user for username to launch browser
    read -p "Enter the username that autostarts: " username
fi

# Check if user exists
if ! id "$username" >/dev/null 2>&1; then
    echo "User $username does not exist. Exiting..."
    exit 1
fi

if [ -z "$url" ]; then
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
fi

# Check if resolution is set
if [[ -z "$resolution" ]]; then
    echo "No resolution provided. Defaulting to 1920x1080..."
    resolution="1920x1080"
else
    echo "Setting resolution to $resolution..."
fi

# Format resolution for later use
FORMATTED_RESOLUTION=$(echo $resolution | tr 'x' ',')

# Automatic Browser Launch
echo "Installing required packages for browser launch..."
apt-get install --no-install-recommends xserver-xorg-video-all xserver-xorg-input-all xserver-xorg-core xinit x11-xserver-utils chromium unclutter -y

# Configures the browser to launch on startup
echo "Creating .xinitrc file..."
su - $username -c "echo '#!/usr/bin/env sh
xset -dpms
xset s off
xset s noblank

unclutter &
chromium $url \\
    --window-size=$FORMATTED_RESOLUTION \\
    --window-position=0,0 \\
    --start-fullscreen \\
    --kiosk \\
    --noerrdialogs \\
    --disable-translate \\
    --no-first-run \\
    --fast \\
    --fast-start \\
    --disable-infobars \\
    --disable-features=TranslateUI \\
    --overscroll-history-navigation=0 \\
    --disable-pinch' > ~/.xinitrc"