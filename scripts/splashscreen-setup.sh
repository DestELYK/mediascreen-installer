#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Boot Screen Configuration
echo "Installing plymouth and plymouth-themes..."
apt install plymouth plymouth-themes -y

echo "Please choose an option:"
echo "1. Upload a file"
echo "2. Paste a URL"

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
        wget -q --spider $url
        if [ $? -eq 0 ]; then
            break
        else
            echo "Invalid URL. Please try again."
            tries=$((tries+1))
        fi
    done

    if [ $tries -eq 3 ]; then
        echo "Failed to download the watermark.png file. Exiting."
        exit 1
    fi

    echo "Downloading the watermark.png file..."
    wget -q $url -O /home/$SUDO_USER/watermark.png
else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Moving logo to plymouth themes..."
mv /home/$SUDO_USER/watermark.png /usr/share/plymouth/themes/spinner/watermark.png

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