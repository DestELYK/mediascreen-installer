#!/bin/bash

<<comment
    This script configures automatic updates and reboots.
    
    The script installs unattended-upgrades and apt-listchanges, configures automatic updates and reboots, and schedules a weekly reboot.
    
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

# Automatic Updates and Reboots
echo "Installing unattended-upgrades and apt-listchanges..."
apt install unattended-upgrades apt-listchanges -y

echo "Configuring automatic updates and reboots..."
sh -c "echo 'Unattended-Upgrade::Allowed-Origins {
    \"\${distro_id}:\${distro_codename}-security\";
};
Unattended-Upgrade::Automatic-Reboot \"true\";
Unattended-Upgrade::Automatic-Reboot-Time \"02:00\";' >> /etc/apt/apt.conf.d/50unattended-upgrades"

sh -c "echo 'APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";' >> /etc/apt/apt.conf.d/20auto-upgrades"

sh -c "echo '0 0 * * 0 /sbin/shutdown -r now' > /etc/cron.d/reboot"