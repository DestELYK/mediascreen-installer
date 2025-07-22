# MediaScreen Image Upload Interface

This directory contains the web interface files for uploading watermark images to the MediaScreen splash screen setup.

## Files

- **index.html** - HTML upload interface with drag-and-drop support
- **server.py** - Python HTTP server for handling file uploads

## Usage

These files are automatically downloaded by the `splashscreen-setup.sh` script when the web upload option is selected. The script:

1. Downloads both files from GitHub to a temporary directory
2. Starts the Python server on an available port
3. Opens a web browser to the upload interface
4. Waits for the user to upload a watermark image
5. Processes the uploaded image for use as a Plymouth splash screen watermark

## Features

- Modern, responsive web interface
- Drag-and-drop file upload
- Real-time upload progress
- File type validation (PNG, JPG, JPEG, GIF, BMP)
- File size limits (10MB max)
- Automatic browser launching
- Cross-platform compatibility

## Technical Details

- The HTML interface uses vanilla JavaScript (no external dependencies)
- The Python server uses only standard library modules
- Files are validated both client-side and server-side
- Upload completion is signaled via a flag file
- The server automatically finds an available port if the default is busy

## Integration

The upload interface integrates seamlessly with the MediaScreen installer's splash screen configuration, providing a user-friendly way to customize the boot splash screen with custom watermark images.
