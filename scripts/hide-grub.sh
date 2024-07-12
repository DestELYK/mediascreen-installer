#!/bin/bash

<<comment
  This script hides the GRUB menu on boot.

  The script sets the GRUB_TIMEOUT to 0 and GRUB_GFXMODE to the specified resolution.

  This script requires root privileges. Please run as root.

  Command Line Usage:
      - To hide the GRUB menu with the default resolution (1920x1080):
          sudo ./hide-grub.sh
      - To hide the GRUB menu with a specific resolution:
          sudo ./hide-grub.sh --resolution=<resolution>

  Author: DestELYK
  Date: 07-09-2024
comment

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

for arg in "$@"; do
    case $arg in
        --resolution=*)
            resolution="${arg#*=}"
            # Validate resolution format
            if [[ ! $resolution =~ ^[0-9]+x[0-9]+$ ]]; then
                echo "Invalid resolution format. Please enter in the format '1920x1080'. Exiting..."
                exit 1
            fi
        ;;
    esac
done

# Check if --resolution is in arguments
if [[ -z "$resolution" ]]; then
    echo "No resolution provided. Defaulting to 1920x1080..."
    resolution="1920x1080"
fi

# GRUB Configuration
echo "Configuring GRUB..."
sh -c "echo 'GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0\"
GRUB_CMDLINE_LINUX=\"\"
GRUB_GFXMODE=$resolution' > /etc/default/grub"

sed -i 's/quiet_boot="0"/quiet_boot="1"/' /etc/grub.d/10_linux

update-grub