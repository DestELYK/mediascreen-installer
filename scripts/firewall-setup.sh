#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Firewall
echo "Installing ufw..."
apt install ufw -y

echo "Configuring firewall rules..."
ufw default deny incoming

# Ask for IP subnet
while true; do
    read -p "Enter the IP subnet to allow (in the format '_._._._/__'): " IP_SUBNET
    # Validate IP subnet format
    if [[ ! $IP_SUBNET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        echo "Invalid IP subnet format. Please enter in the format '_._._._/_'."
    else
        ufw allow from $IP_SUBNET to any

        read -p "Do you want to add more IP subnets? (y/n): " ADD_MORE
        if [[ $ADD_MORE =~ ^[Yy]$ ]]; then
            continue
        else
            break
        fi
    fi
done

if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
    echo "Enabling firewall, warning: you may lose SSH access if you haven't added your IP subnet..."
fi

ufw --force enable