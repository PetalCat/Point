#!/usr/bin/env python3
"""
App Registry — Self-hosted APK distribution server.
Serves multiple apps with proper ETag/Last-Modified headers for Obtainium.

Usage:
  Upload:   curl -X POST http://host:8484/api/apps/myapp/upload -F "apk=@app.apk" -F "version=1.0.0" -F "name=My App"
  Download: http://host:8484/apps/myapp/download/myapp.apk
  List:     http://host:8484/api/apps
  Info:     http://host:8484/api/apps/myapp

Obtainium setup:
  URL: http://host:8484/apps/myapp/download/myapp.apk
  Source: Direct APK link
  Versioning: ETag
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import html as html_mod
import json
import os
import hashlib
import email.utils
import cgi
import time
import re

PORT = int(os.environ.get('PORT', '8484'))
DATA_DIR = os.environ.get('DATA_DIR', '/data')
UPLOAD_TOKEN = os.environ.get('UPLOAD_TOKEN', '')  # REQUIRED for upload auth
MAX_UPLOAD_SIZE = int(os.environ.get('MAX_UPLOAD_SIZE', str(500 * 1024 * 1024)))  # 500MB default
ALLOWED_HOST = os.environ.get('ALLOWED_HOST', 'app.petalcat.dev')

def ensure_dirs():
    os.makedirs(os.path.join(DATA_DIR, 'apps'), exist_ok=True)

def app_dir(app_id):
    return os.path.join(DATA_DIR, 'apps', app_id)

def app_apk_path(app_id):
    return os.path.join(app_dir(app_id), f'{app_id}.apk')

def app_meta_path(app_id):
    return os.path.join(app_dir(app_id), 'meta.json')

def load_meta(app_id):
    path = app_meta_path(app_id)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return None

def save_meta(app_id, meta):
    os.makedirs(app_dir(app_id), exist_ok=True)
    with open(app_meta_path(app_id), 'w') as f:
        json.dump(meta, f, indent=2)

def list_apps():
    apps_dir = os.path.join(DATA_DIR, 'apps')
    if not os.path.exists(apps_dir):
        return []
    result = []
    for d in sorted(os.listdir(apps_dir)):
        meta = load_meta(d)
        if meta:
            result.append(meta)
    return result

def compute_etag(filepath):
    try:
        size = os.path.getsize(filepath)
        with open(filepath, 'rb') as f:
            chunk = f.read(8192)
        h = hashlib.md5(chunk + str(size).encode()).hexdigest()
        return f'"{h}"'
    except Exception:
        return None

def get_last_modified(filepath):
    try:
        mtime = os.path.getmtime(filepath)
        return email.utils.formatdate(mtime, usegmt=True)
    except Exception:
        return None


class Handler(BaseHTTPRequestHandler):

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_HEAD(self):
        # Obtainium sends HEAD to check for updates
        m = re.match(r'^/apps/([a-zA-Z0-9_-]+)/download/', self.path)
        if m:
            self._serve_apk_head(m.group(1))
        else:
            self.send_response(200)
            self.end_headers()

    def do_GET(self):
        path = self.path.split('?')[0]

        if path == '/' or path == '/index.html':
            self._serve_index()
        elif path == '/api/apps':
            self._api_list_apps()
        elif re.match(r'^/api/apps/([a-zA-Z0-9_-]+)$', path):
            app_id = re.match(r'^/api/apps/([a-zA-Z0-9_-]+)$', path).group(1)
            self._api_app_info(app_id)
        elif re.match(r'^/apps/([a-zA-Z0-9_-]+)/download/', path):
            app_id = re.match(r'^/apps/([a-zA-Z0-9_-]+)/download/', path).group(1)
            self._serve_apk(app_id)
        elif re.match(r'^/apps/([a-zA-Z0-9_-]+)/icon\.png$', path):
            app_id = re.match(r'^/apps/([a-zA-Z0-9_-]+)/icon\.png$', path).group(1)
            self._serve_icon(app_id)
        else:
            self._404()

    def do_POST(self):
        path = self.path.split('?')[0]
        m = re.match(r'^/api/apps/([a-zA-Z0-9_-]+)/upload$', path)
        if m:
            self._api_upload(m.group(1))
        else:
            self._404()

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Expose-Headers', 'ETag, Last-Modified, Content-Length')
        # Prevent Cloudflare from caching APKs
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('CDN-Cache-Control', 'no-store')

    def _404(self):
        self.send_response(404)
        self.send_header('Content-Type', 'application/json')
        self._cors()
        self.end_headers()
        self.wfile.write(json.dumps({"error": "not found"}).encode())

    def _json_response(self, data, status=200):
        body = json.dumps(data, indent=2).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _api_list_apps(self):
        self._json_response(list_apps())

    def _api_app_info(self, app_id):
        meta = load_meta(app_id)
        if not meta:
            self._404()
            return
        self._json_response(meta)

    def _api_upload(self, app_id):
        # Require upload token — prevents supply chain attacks
        auth = self.headers.get('Authorization', '')
        if not UPLOAD_TOKEN or auth != f'Bearer {UPLOAD_TOKEN}':
            self._json_response({"error": "unauthorized — set UPLOAD_TOKEN and pass as Bearer token"}, 401)
            return

        content_type = self.headers.get('Content-Type', '')
        if 'multipart/form-data' not in content_type:
            self._json_response({"error": "multipart/form-data required"}, 400)
            return

        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={'REQUEST_METHOD': 'POST', 'CONTENT_TYPE': content_type}
        )

        apk_field = form['apk'] if 'apk' in form else None
        if not apk_field or not apk_field.file:
            self._json_response({"error": "apk file required"}, 400)
            return

        version = form.getvalue('version', '0.0.1')
        name = form.getvalue('name', app_id)

        os.makedirs(app_dir(app_id), exist_ok=True)
        apk_path = app_apk_path(app_id)
        total_written = 0
        with open(apk_path, 'wb') as f:
            while True:
                chunk = apk_field.file.read(65536)
                if not chunk:
                    break
                total_written += len(chunk)
                if total_written > MAX_UPLOAD_SIZE:
                    f.close()
                    os.remove(apk_path)
                    self._json_response({"error": f"file too large (max {MAX_UPLOAD_SIZE // 1048576}MB)"}, 413)
                    return
                f.write(chunk)

        size = os.path.getsize(apk_path)
        etag = compute_etag(apk_path)

        meta = {
            "id": app_id,
            "name": name,
            "version": version,
            "size": size,
            "etag": etag,
            "updated": time.strftime('%Y-%m-%d %H:%M:%S'),
            "download_url": f"/apps/{app_id}/download/{app_id}.apk",
        }
        save_meta(app_id, meta)

        self._json_response(meta)

    def _serve_apk_head(self, app_id):
        apk_path = app_apk_path(app_id)
        if not os.path.exists(apk_path):
            self.send_response(404)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Length', str(os.path.getsize(apk_path)))
        self.send_header('Content-Disposition', f'attachment; filename="{app_id}.apk"')
        etag = compute_etag(apk_path)
        if etag:
            self.send_header('ETag', etag)
        lm = get_last_modified(apk_path)
        if lm:
            self.send_header('Last-Modified', lm)
        self._cors()
        self.end_headers()

    def _serve_apk(self, app_id):
        apk_path = app_apk_path(app_id)
        if not os.path.exists(apk_path):
            self._404()
            return

        size = os.path.getsize(apk_path)
        self.send_response(200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Length', str(size))
        self.send_header('Content-Disposition', f'attachment; filename="{app_id}.apk"')
        etag = compute_etag(apk_path)
        if etag:
            self.send_header('ETag', etag)
        lm = get_last_modified(apk_path)
        if lm:
            self.send_header('Last-Modified', lm)
        self._cors()
        self.end_headers()

        with open(apk_path, 'rb') as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def _serve_icon(self, app_id):
        """Serve app icon PNG if it exists."""
        icon_path = os.path.join(app_dir(app_id), 'icon.png')
        if not os.path.exists(icon_path):
            self.send_response(404)
            self.end_headers()
            return
        with open(icon_path, 'rb') as f:
            data = f.read()
        self.send_response(200)
        self.send_header('Content-Type', 'image/png')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'public, max-age=3600')
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _serve_index(self):
        apps = list_apps()
        # Hardcode host to prevent Host header injection
        base_url = f'https://{ALLOWED_HOST}'

        html = """<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PetalCat Apps</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',system-ui,sans-serif;background:#000000;color:#fff;min-height:100vh}
.page{max-width:480px;margin:0 auto;padding:24px 16px 60px}
.header{text-align:center;margin-bottom:32px;padding-top:20px}
.logo{font-size:32px;font-weight:900;background:linear-gradient(135deg,#3F51FF,#7C5CFF,#00D4FF);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.sub{color:rgba(255,255,255,0.3);font-size:13px;margin-top:4px}
.app{background:#0a0a0f;border:1px solid rgba(255,255,255,0.06);border-radius:20px;padding:20px;margin-bottom:16px;border:1px solid rgba(255,255,255,0.04)}
.app-top{display:flex;align-items:center;gap:14px;margin-bottom:16px}
.app-icon{width:52px;height:52px;border-radius:14px;background:linear-gradient(135deg,#3F51FF,#5C3FD4);display:flex;align-items:center;justify-content:center;color:white;font-weight:900;font-size:22px;box-shadow:0 4px 16px rgba(63,81,255,0.25);overflow:hidden}
.app-icon img{width:100%;height:100%;object-fit:cover}
.btn-row{display:flex;gap:8px;margin-top:10px}
.btn-obt{flex:1;display:block;background:rgba(255,255,255,0.06);color:rgba(255,255,255,0.6);text-decoration:none;padding:12px;border-radius:12px;text-align:center;font-weight:700;font-size:13px;border:1px solid rgba(255,255,255,0.06);transition:all 0.15s}
.btn-obt:hover{background:rgba(255,255,255,0.1);color:rgba(255,255,255,0.8)}
.btn-obt:active{transform:scale(0.98)}
.app-name{font-size:20px;font-weight:900}
.app-meta{font-size:11px;color:rgba(255,255,255,0.3);margin-top:2px}
.app-dl{display:block;background:linear-gradient(135deg,#3F51FF,#5C3FD4);color:white;text-decoration:none;padding:14px;border-radius:14px;text-align:center;font-weight:800;font-size:15px;box-shadow:0 4px 20px rgba(63,81,255,0.3);transition:transform 0.1s}
.app-dl:active{transform:scale(0.98)}
.app-info{display:flex;gap:8px;margin-top:12px}
.app-stat{flex:1;background:rgba(255,255,255,0.03);border-radius:10px;padding:10px;text-align:center}
.app-stat-val{font-size:14px;font-weight:800}
.app-stat-label{font-size:9px;color:rgba(255,255,255,0.2);text-transform:uppercase;letter-spacing:0.5px;margin-top:2px}
.obtainium{margin-top:14px;background:rgba(255,255,255,0.03);border-radius:12px;padding:12px}
.obt-label{font-size:10px;color:rgba(255,255,255,0.2);font-weight:700;letter-spacing:0.5px;text-transform:uppercase;margin-bottom:6px}
.obt-url{font-size:11px;color:rgba(255,255,255,0.5);word-break:break-all;font-family:'SF Mono',monospace;cursor:pointer;padding:8px;background:rgba(255,255,255,0.03);border-radius:8px;transition:background 0.15s}
.obt-url:hover{background:rgba(63,81,255,0.1)}
.obt-url:active{background:rgba(63,81,255,0.2)}
.copied{position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#3F51FF;color:white;padding:10px 20px;border-radius:12px;font-size:13px;font-weight:700;opacity:0;transition:opacity 0.3s;pointer-events:none}
.copied.show{opacity:1}
.empty{text-align:center;color:rgba(255,255,255,0.15);padding:60px 20px;font-size:15px;font-weight:600}
.footer{text-align:center;margin-top:32px;font-size:10px;color:rgba(255,255,255,0.1)}
</style></head><body>
<div class="page">
<div class="header"><div class="logo">PetalCat Apps</div><div class="sub">Self-hosted app distribution</div></div>"""

        if not apps:
            html += '<div class="empty">No apps registered yet</div>'
        else:
            esc = html_mod.escape  # prevent XSS via app metadata
            for app in apps:
                name = esc(app.get('name', ''))
                initial = esc(name[0].upper() if name else '?')
                dl_url = esc(app.get('download_url', ''))
                full_dl_url = f'{base_url}{dl_url}'
                version = esc(app.get('version', '?'))
                updated = esc(app.get('updated', '?'))
                size_mb = app.get('size', 0) / 1048576
                app_id = esc(app.get('id', ''))
                icon_url = f'/apps/{app_id}/icon.png'
                obt_url = f'obtainium://add/{full_dl_url}'
                html += f"""<div class="app">
<div class="app-top">
<div class="app-icon"><img src="{icon_url}" alt="{initial}" onerror="this.style.display='none';this.parentElement.textContent='{initial}'"></div>
<div><div class="app-name">{name}</div>
<div class="app-meta">v{version} &middot; {updated}</div></div></div>
<a class="app-dl" href="{dl_url}">Download APK</a>
<div class="btn-row">
<a class="btn-obt" href="{obt_url}"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/obtainium.svg" style="width:16px;height:16px;vertical-align:middle;margin-right:6px;filter:brightness(2)">Add to Obtainium</a>
</div>
<div class="app-info">
<div class="app-stat"><div class="app-stat-val">v{version}</div><div class="app-stat-label">Version</div></div>
<div class="app-stat"><div class="app-stat-val">{size_mb:.0f} MB</div><div class="app-stat-label">Size</div></div>
<div class="app-stat"><div class="app-stat-val">{updated.split(' ')[0] if ' ' in updated else updated}</div><div class="app-stat-label">Updated</div></div>
</div>
<div class="obtainium">
<div class="obt-label">Obtainium &middot; Direct APK Link</div>
<div class="obt-url" onclick="copyUrl(this,'{full_dl_url}')">{full_dl_url}</div>
</div>
</div>"""

        html += """</div>
<div class="footer">petalcat.dev</div>
<div class="copied" id="toast">Copied to clipboard</div>
<script>
function copyUrl(el,url){navigator.clipboard.writeText(url);var t=document.getElementById('toast');t.classList.add('show');setTimeout(function(){t.classList.remove('show')},1500)}
</script>
</body></html>"""
        body = html.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(f"[{time.strftime('%H:%M:%S')}] {args[0]}")


if __name__ == '__main__':
    ensure_dirs()
    server = HTTPServer(('0.0.0.0', PORT), Handler)
    print(f'App Registry running on http://0.0.0.0:{PORT}')
    print(f'Data dir: {DATA_DIR}')
    server.serve_forever()
