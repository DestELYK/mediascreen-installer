#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# GRUB Configuration
echo "Configuring GRUB..."
sh -c "echo 'GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0\"
GRUB_CMDLINE_LINUX=\"\"' > /etc/default/grub"

sed -i 's/quiet_boot="0"/quiet_boot="1"/' /etc/grub.d/10_linux

update-grub