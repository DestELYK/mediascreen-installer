#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Check if --resolution is in arguments
if [[ "$@" == *"--resolution"* ]]; then
    # Get the index of --resolution argument
    index=$(echo "$@" | grep -bo -- "--resolution" | awk -F: '{print $1}')
    # Get the value of --resolution argument
    resolution=$(echo "$@" | cut -d' ' -f$((index + 1)))
else
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