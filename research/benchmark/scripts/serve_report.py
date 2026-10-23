"""Serve only the review document and manifest-selected audio over loopback."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
from urllib.parse import urlsplit

ROOT=Path(__file__).resolve().parents[1]
MANIFEST={x['case']:x for x in json.loads((ROOT/'data/manifest.json').read_text()) if x['split']=='test'}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('Host') not in ['127.0.0.1:'+str(self.server.server_port),'localhost:'+str(self.server.server_port)]:
            self.send_error(403);return
        path=urlsplit(self.path).path
        if path=='/':
            file=ROOT/'results/review.html';kind='text/html; charset=utf-8'
        elif path=='/prompt':
            file=ROOT/'prompts/v5-final.txt';kind='text/plain; charset=utf-8'
        elif path.startswith('/audio/') and path[len('/audio/'):] in MANIFEST:
            file=Path(MANIFEST[path[len('/audio/'):]]['ogg']);kind='audio/ogg'
        else:
            self.send_error(404);return
        data=file.read_bytes()
        self.send_response(200);self.send_header('Content-Type',kind)
        self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store')
        self.send_header('Referrer-Policy','no-referrer');self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('X-Frame-Options','DENY')
        self.end_headers();self.wfile.write(data)
    def log_message(self,*args):pass

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
print('Local review: http://127.0.0.1:'+str(server.server_port)+'/',flush=True)
server.serve_forever()
