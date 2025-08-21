# MediaScreen Installer

A comprehensive installer and configuration toolkit for setting up Linux-based digital signage and kiosk systems. This installer automates the process of configuring Debian-based systems for unattended operation as media display screens.

## Features

- **Browser-based Kiosk Mode**: Automatic setup of Chromium in full-screen kiosk mode
- **Auto-login Configuration**: Seamless user login without manual intervention
- **Network Management**: Automated network configuration and connectivity setup
- **Security Hardening**: Firewall configuration and security best practices
- **Visual Customization**: Plymouth splash screen and boot customization
- **Auto-updates**: Automated system updates and maintenance
- **Web Upload Interface**: Modern web interface for uploading watermark images
- **Modular Architecture**: Organized script structure with shared common library

## Quick Start

### Basic Installation

```bash
# Download and run the installer
wget https://raw.githubusercontent.com/DestELYK/mediascreen-installer/main/install.sh
sudo chmod +x install.sh
sudo ./install.sh
```

### Advanced Usage

```bash
# Use development branch
sudo ./install.sh --dev

# Use custom repository
sudo ./install.sh --github-url=https://raw.githubusercontent.com/yourusername/mediascreen-installer/main

# Automated installation
sudo ./install.sh --auto --username=mediascreen --debug

# Show help
./install.sh --help
```

## Command Line Options

| Option             | Description                                    |
| ------------------ | ---------------------------------------------- |
| `-y, --auto`       | Run in automatic mode (non-interactive)        |
| `--username=USER`  | Specify username for operations                |
| `--url=URL`        | Specify URL for browser operations             |
| `--github-url=URL` | Use custom GitHub repository URL for downloads |
| `--debug`          | Enable debug logging                           |
| `--dev`            | Use development branch instead of main         |
| `-h, --help`       | Show help message                              |

## Repository Structure

```text
mediascreen-installer/
├── install.sh                 # Main installer script
├── menu_config.txt            # Menu configuration file
├── autologin/                 # Auto-login configuration files
│   ├── browser
│   └── menu
├── scripts/                   # Installation and configuration scripts
│   ├── lib/
│   │   └── common.sh          # Shared library functions
│   ├── autologin-setup.sh     # Auto-login configuration
│   ├── autoupdates-setup.sh   # Automatic updates setup
│   ├── browser-setup.sh       # Browser kiosk configuration
│   ├── configure-network.sh   # Network configuration
│   ├── firewall-setup.sh      # Firewall and security setup
│   ├── hide-grub.sh           # GRUB bootloader customization
│   ├── reboot-setup.sh        # Reboot scheduling configuration
│   └── splashscreen-setup.sh  # Plymouth splash screen setup
└── image-upload/              # Web interface for image uploads
    ├── index.html             # Upload interface
    └── server.py              # Python HTTP server
```

## Individual Scripts

Each script can be run independently with the same command-line options:

### Core System Scripts

- **`autologin-setup.sh`**: Configures automatic user login without password prompts
- **`browser-setup.sh`**: Sets up Chromium browser in full-screen kiosk mode
- **`configure-network.sh`**: Manages network interfaces and connectivity
- **`firewall-setup.sh`**: Configures UFW firewall with security rules

### System Customization Scripts

- **`splashscreen-setup.sh`**: Installs and configures Plymouth boot splash screen
- **`hide-grub.sh`**: Customizes GRUB bootloader for faster, cleaner boot
- **`autoupdates-setup.sh`**: Enables automatic system updates
- **`reboot-setup.sh`**: Configures scheduled system reboots

## Web Upload Interface

The installer includes a modern web interface for uploading watermark images:

```bash
# Start the upload server
cd image-upload
python3 server.py

# Access via browser
http://localhost:8000
```

Features:

- Drag-and-drop file upload
- Progress tracking
- File validation
- Modern responsive design

## Installation Location

When installed, scripts are organized in `/usr/local/bin/mediascreen-installer/`:

```text
/usr/local/bin/mediascreen-installer/
├── scripts/
│   ├── lib/common.sh
│   └── [all script files]
├── image-upload/
└── menu_config.txt
```

A convenient symlink `ms-util` is created in `/usr/local/bin/` for easy access.

## Error Handling

The installer includes comprehensive error handling:

- **404 Detection**: Automatically detects when GitHub files are not found
- **Custom Repository Support**: Prompts for alternative repository URLs
- **Network Connectivity**: Validates internet connection before downloads
- **Logging**: Comprehensive logging to `/var/log/mediascreen/`
- **Rollback Support**: Automatic backup of modified system files

## System Requirements

- **Operating System**: Debian-based Linux distribution (Ubuntu, Debian, etc.)
- **Privileges**: Root access (sudo) required
- **Internet**: Active internet connection for downloads
- **Display**: Graphics capability for GUI applications

## Development

### Branch Structure

- **`main`**: Stable release branch
- **`dev`**: Development branch with latest features

### Using Development Branch

```bash
# Test latest development features
sudo ./install.sh --dev

# Use development fork
sudo ./install.sh --github-url=https://raw.githubusercontent.com/yourusername/mediascreen-installer/dev
```

### Contributing

1. Fork the repository
2. Create a feature branch from `dev`
3. Make your changes
4. Test thoroughly
5. Submit a pull request to the `dev` branch

## Logging and Debugging

All operations are logged to `/var/log/mediascreen/`:

```bash
# View installation logs
sudo tail -f /var/log/mediascreen/install.log

# Enable debug mode
sudo ./install.sh --debug

# View all logs
sudo ls -la /var/log/mediascreen/
```

## Troubleshooting

### Common Issues

**Download Failures (404 errors)**:

```bash
# Use custom repository
sudo ./install.sh --github-url=https://raw.githubusercontent.com/yourusername/mediascreen-installer/main
```

**Network Connectivity**:

```bash
# Test internet connection
ping -c 3 8.8.8.8

# Check DNS resolution
nslookup github.com
```

**Permission Issues**:

```bash
# Ensure running with sudo
sudo ./install.sh

# Check script permissions
chmod +x install.sh
```

### Log Analysis

```bash
# Check system logs
sudo journalctl -f

# View MediaScreen logs
sudo find /var/log/mediascreen/ -name "*.log" -exec tail -20 {} \;
```

## Security Considerations

- Scripts require root privileges for system configuration
- Firewall rules are automatically configured
- System files are backed up before modification
- Automatic updates enhance security posture
- Network access is controlled and monitored

## License

This project is open source. See individual script headers for specific licensing information.

## Support

For issues, feature requests, or contributions:

- Open an issue on GitHub
- Check the logs in `/var/log/mediascreen/`
- Run with `--debug` flag for detailed output
- Review this README for troubleshooting steps

## Changelog

### Latest Updates

- Added web upload interface for watermark images
- Implemented comprehensive error handling with 404 detection
- Added support for custom GitHub repository URLs
- Enhanced logging and debugging capabilities
- Reorganized directory structure for better maintainability
- Added development branch support for testing new features

---

**Author**: DestELYK  
**Updated**: July 22, 2025
