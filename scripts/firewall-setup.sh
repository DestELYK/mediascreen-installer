#!/bin/bash

<<comment
    This script configures the firewall to allow only specified IP subnets.
    
    The script installs ufw and configures the firewall to allow only specified IP subnets.
    
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

# Firewall
echo "Installing ufw..."
apt install ufw -y

echo "Configuring firewall rules..."
ufw default deny incoming

echo "Current rules: "
ufw status numbered

echo Available IP addresses:
ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'

# Ask for IP subnet
while true; do
    read -p "Do you want to add more IP subnets? (y/n): " ADD_MORE
    if [[ $ADD_MORE =~ ^[Yy]$ ]]; then
        continue
    else
        break
    fi

    read -p "Enter the IP subnet to allow (in the format '_._._._/__'): " IP_SUBNET
    # Validate IP subnet format
    if [[ ! $IP_SUBNET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        echo "Invalid IP subnet format. Please enter in the format '_._._._/_'."
    else
        ufw allow from $IP_SUBNET to any
    fi
done

if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
    echo "Enabling firewall, warning: you may lose SSH access if you haven't added your IP subnet..."
fi

ufw --force enable