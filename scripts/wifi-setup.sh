#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

reconfigure_wifi() {
    echo "Checking internet connection..."
    attempts=0
    while true; do
        attempts=$((attempts+1))
        if [ $attempts -gt 3 ]; then
            echo "Failed to connect to the internet after 3 attempts. Exiting..."
            exit 1
        fi
        
        echo "Configuring WiFi..."
        read -p "Enter the SSID: " SSID
        read -p "Enter the password: " PASSWORD
        # Connect to WiFi using wpa_supplicant
        wpa_passphrase "$SSID" "$PASSWORD" | tee /etc/wpa_supplicant.conf > /dev/null
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf

        # Refresh network interfaces
        echo "Refreshing network interfaces..."
        systemctl restart networking

        if ping -q -c 1 -W 1 google.com >/dev/null; then
            break
        fi
    done
    echo "Connected to the internet."
}

# Check if connected to the internet
echo "Checking internet connection..."
if ping -q -c 1 -W 1 google.com >/dev/null; then
    read -p "You are already connected! Would you like to reconfigure the WiFi connection? (y/n): " choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        reconfigure_wifi
    fi
else
    reconfigure_wifi
fi

# Reconfigure Timezone
echo "Reconfiguring timezone..."
dpkg-reconfigure tzdata