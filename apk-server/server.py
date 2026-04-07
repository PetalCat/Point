#!/usr/bin/env python3
"""HTTP server for APK distribution with proper ETag/Last-Modified for Obtainium."""
import http.server
import os
import hashlib
import json
import email.utils
import time

PORT = 9999
DIR = os.path.dirname(os.path.abspath(__file__))
APK_PATH = os.path.join(DIR, 'point.apk')

def get_apk_etag():
    """Generate ETag from first 8KB + file size (fast, changes when APK changes)."""
    try:
        size = os.path.getsize(APK_PATH)
        with open(APK_PATH, 'rb') as f:
            chunk = f.read(8192)
        h = hashlib.md5(chunk + str(size).encode()).hexdigest()
        return f'"{h}"'
    except Exception:
        return None

def get_apk_last_modified():
    """Get Last-Modified header value for the APK."""
    try:
        mtime = os.path.getmtime(APK_PATH)
        return email.utils.formatdate(mtime, usegmt=True)
    except Exception:
        return None

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        """Handle HEAD requests — Obtainium uses these to check for updates."""
        if self.path == '/point.apk' or self.path.startswith('/download/'):
            self._serve_apk_headers()
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self._serve_file('index.html', 'text/html')
        elif self.path == '/version.json':
            self._serve_file('version.json', 'application/json')
        elif self.path == '/point.apk' or self.path.startswith('/download/'):
            self._serve_apk()
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not found')

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def _cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Expose-Headers', 'ETag, Last-Modified, Content-Length')

    def _serve_apk_headers(self):
        """Send headers for the APK file (used by HEAD and GET)."""
        if not os.path.exists(APK_PATH):
            self.send_response(404)
            self.end_headers()
            return False

        etag = get_apk_etag()
        last_modified = get_apk_last_modified()
        size = os.path.getsize(APK_PATH)

        self.send_response(200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Length', str(size))
        self.send_header('Content-Disposition', 'attachment; filename="point.apk"')
        if etag:
            self.send_header('ETag', etag)
        if last_modified:
            self.send_header('Last-Modified', last_modified)
        self._cors_headers()
        self.end_headers()
        return True

    def _serve_apk(self):
        """Serve the APK file with proper headers."""
        if not self._serve_apk_headers():
            return
        with open(APK_PATH, 'rb') as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def _serve_file(self, filename, content_type):
        filepath = os.path.join(DIR, filename)
        if not os.path.exists(filepath):
            self.send_response(404)
            self.end_headers()
            return
        with open(filepath, 'rb') as f:
            data = f.read()
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self._cors_headers()
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
    print(f'APK server running on http://0.0.0.0:{PORT}')
    print(f'APK: {APK_PATH}')
    print(f'ETag: {get_apk_etag()}')
    print(f'Last-Modified: {get_apk_last_modified()}')
    server.serve_forever()
