#!/bin/bash

<<comment
  This script hides the GRUB menu on boot.

  The script sets the GRUB_TIMEOUT to 0.

  This script requires root privileges. Please run as root.

  Command Line Usage:
      - To hide the GRUB menu:
          sudo ./hide-grub.sh

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

# GRUB Configuration
echo "Configuring GRUB..."
sh -c "echo 'GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0\"
GRUB_CMDLINE_LINUX=\"\"' > /etc/default/grub"

sed -i 's/quiet_boot="0"/quiet_boot="1"/' /etc/grub.d/10_linux

update-grub