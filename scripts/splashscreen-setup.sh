#!/bin/bash

<<comment
    This script sets up a splash screen for the Debian System.

    The script installs plymouth and plymouth-themes, allows the user to add a boot logo, and sets the default plymouth theme.

    This script requires root privileges. Please run as root.

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

# Boot Screen Configuration
echo "Installing plymouth and plymouth-themes..."
apt install plymouth plymouth-themes -y

modify_watermark() {
echo "Please choose an option:"
    echo "1. Upload a file"
    echo "2. Using a URL"

    read -p "Enter your choice: " choice

    if [ "$choice" == "1" ]; then
        echo "Please upload the watermark.png file into /home/${SUDO_USER}."
        echo Available IP addresses:
        ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'
        echo -e $'\nOnce uploaded, press Enter to continue.'
        read
        echo "Checking for watermark..."
        if [ -f "/home/${SUDO_USER}/watermark.png" ]; then
            echo "Watermark found."
        else
            echo "Watermark not found. Exiting."
            exit 1
        fi
    elif [ "$choice" == "2" ]; then
        tries=0
        while [ $tries -lt 3 ]; do
            read -p "Enter the URL of the watermark.png file: " url
            wget -q --spider $url || {
                echo "Failed to download the watermark.png file. Please try again."
                tries=$((tries+1))
            }
            if [ $? -eq 0 ]; then
                break
            else
                echo "Invalid URL. Please try again."
                tries=$((tries+1))
            fi
        done

        if [ $tries -eq 3 ]; then
            echo "Failed to download the watermark.png file. Would you like to "
        fi

        echo "Downloading the watermark.png file..."
        wget -q $url -O /home/$SUDO_USER/watermark.png
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi

    echo "Moving logo to plymouth themes..."
    mv /home/$SUDO_USER/watermark.png /usr/share/plymouth/themes/spinner/watermark.png
}

if [ ! -f "/usr/share/plymouth/themes/spinner/watermark.png" ]; then
    echo "Watermark not found."
    read -p "Do you want to add a watermark? (y/n): " answer
    if [ "$answer" == "y" ]; then
        modify_watermark
    fi
else
    echo "Watermark found."
    read -p "Do you want to modify the watermark? (y/n): " answer
    if [ "$answer" == "y" ]; then
        modify_watermark
    fi
fi

echo "Updating VerticalAlignment and WatermarkVerticalAlignment..."
sed -i 's/VerticalAlignment=.*/VerticalAlignment=.8/' /usr/share/plymouth/themes/spinner/spinner.plymouth
sed -i 's/WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.5/' /usr/share/plymouth/themes/spinner/spinner.plymouth

echo "Setting default plymouth theme..."
plymouth-set-default-theme -R spinner

echo "Creating long_splash.conf file for making the splash screen longer at startup..."

if [ ! -d "/etc/systemd/system/plymouth-quit.service.d" ]; then
    mkdir /etc/systemd/system/plymouth-quit.service.d
fi

sh -c  "echo '[Unit]
Description=Make Plymouth Boot Screen last longer

[Service]
ExecStartPre=/usr/bin/sleep 5' > /etc/systemd/system/plymouth-quit.service.d/long_splash.conf"