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

function exit_prompt()
{
    echo
    read -p "Do you want to exit? (y/n): " EXIT
    if [[ $EXIT =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

trap exit_prompt SIGINT

# Firewall
echo "Installing ufw..."
apt install --quiet ufw -y

echo "Configuring firewall rules..."
ufw default deny incoming

rules=$(ufw status numbered | grep -E '^\[ [0-9]\]+')
ips=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')

#
for ip in $ips; do
    subnet="$(echo $ip | cut -d. -f1-3).0"

    # Check rules to see if subnet is already allowed
    if echo "$rules" | grep -q "$subnet"; then
        echo "Subnet $subnet is already allowed. Skipping..."
        continue
    fi

    read -p "Do you want to allow subnet $subnet? (y/n): " ADD_SUBNET

    if [[ ! $ADD_SUBNET =~ ^[Yy]$ ]]; then
        continue
    fi

    while true; do
        read -p "What subnet mask do you want to use? (e.g. 24): " SUBNET_MASK

        # Verify subnet mask
        if [[ ! $SUBNET_MASK =~ ^[0-9]+$ ]] || [[ $SUBNET_MASK -gt 32 ]]; then
            echo "Invalid subnet mask. Please enter a valid subnet mask."
            continue
        fi

        subnet="$subnet/$SUBNET_MASK"
        break
    done

    # Verify subnet
    if [[ ! $subnet =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        echo "Invalid subnet. Continuing..."
        continue
    fi

    ufw allow from $subnet to any
done

# Ask for IP subnet
while true; do
    echo "Current rules: "
    echo "$rules"
    read -p "Do you want to add more IP subnets? (y/n): " ADD_MORE
    if [[ ! $ADD_MORE =~ ^[Yy]$ ]]; then
        break
    fi

    echo "Available IP addresses:"
    echo "$ips"
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