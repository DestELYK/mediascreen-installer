#!/usr/bin/env python3
"""
MediaScreen Watermark Upload Server
Simple HTTP server for handling watermark image uploads
"""

import os
import sys
import json
import shutil
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
import cgi

class UploadHandler(BaseHTTPRequestHandler):
    """HTTP request handler for watermark uploads"""
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/' or self.path == '/index.html':
            self.serve_file('index.html', 'text/html')
        elif self.path == '/status':
            self.send_json_response({'status': 'ready'})
        else:
            self.send_error(404, "File not found")
    
    def do_POST(self):
        """Handle POST requests (file uploads)"""
        if self.path == '/upload':
            self.handle_upload()
        else:
            self.send_error(404, "Endpoint not found")
    
    def serve_file(self, filename, content_type):
        """Serve a static file"""
        try:
            with open(filename, 'rb') as f:
                content = f.read()
                self.send_response(200)
                self.send_header('Content-type', content_type)
                self.send_header('Content-length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
        except FileNotFoundError:
            self.send_error(404, f"File {filename} not found")
        except Exception as e:
            self.send_error(500, f"Error serving file: {e}")
    
    def send_json_response(self, data, status=200):
        """Send a JSON response"""
        response = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Content-length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)
    
    def handle_upload(self):
        """Handle file upload"""
        try:
            # Parse the multipart form data
            content_type = self.headers.get('content-type', '')
            if not content_type.startswith('multipart/form-data'):
                self.send_json_response({'error': 'Invalid content type'}, 400)
                return
            
            # Create a FieldStorage object to parse the upload
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={
                    'REQUEST_METHOD': 'POST',
                    'CONTENT_TYPE': self.headers.get('content-type'),
                }
            )
            
            # Look for the uploaded file
            if 'file' not in form:
                self.send_json_response({'error': 'No file uploaded'}, 400)
                return
            
            fileitem = form['file']
            if not fileitem.filename:
                self.send_json_response({'error': 'No file selected'}, 400)
                return
            
            # Validate file type
            filename = fileitem.filename.lower()
            allowed_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.bmp']
            if not any(filename.endswith(ext) for ext in allowed_extensions):
                self.send_json_response({
                    'error': f'Invalid file type. Allowed: {", ".join(allowed_extensions)}'
                }, 400)
                return
            
            # Read file data
            file_data = fileitem.file.read()
            
            # Validate file size (10MB limit)
            if len(file_data) > 10 * 1024 * 1024:
                self.send_json_response({'error': 'File too large (max 10MB)'}, 400)
                return
            
            # Save the uploaded file as watermark.png
            with open('watermark.png', 'wb') as f:
                f.write(file_data)
            
            # Create completion flag
            with open('upload_complete.flag', 'w') as f:
                f.write('success')
            
            # Send success response
            self.send_json_response({
                'status': 'success',
                'message': 'File uploaded successfully',
                'filename': 'watermark.png',
                'size': len(file_data)
            })
            
            print(f"Upload completed: {len(file_data)} bytes saved as watermark.png")
            
        except Exception as e:
            print(f"Upload error: {e}")
            self.send_json_response({'error': f'Server error: {e}'}, 500)
    
    def log_message(self, format, *args):
        """Suppress default HTTP logging (we'll handle our own)"""
        pass

def find_available_port(start_port=8080, max_attempts=100):
    """Find an available port starting from start_port"""
    import socket
    
    for port in range(start_port, start_port + max_attempts):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('', port))
                return port
        except OSError:
            continue
    
    raise RuntimeError(f"Could not find available port in range {start_port}-{start_port + max_attempts}")

def run_server(port=None):
    """Run the upload server"""
    if port is None:
        port = find_available_port()
    
    server_address = ('', port)
    
    try:
        httpd = HTTPServer(server_address, UploadHandler)
        print(f"MediaScreen upload server starting on port {port}")
        print(f"Access the upload interface at: http://localhost:{port}")
        print("Press Ctrl+C to stop the server")
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped by user")
        httpd.shutdown()
    except Exception as e:
        print(f"Server error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    # Parse command line arguments
    port = None
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port number: {sys.argv[1]}")
            sys.exit(1)
    
    run_server(port)
