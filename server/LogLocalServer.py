#!/usr/bin/env python3
"""
Simple log receiver for Roku debugging.

Run:    python3 log_server.py
Roku:   POST text to http://<YOUR_PC_IP>:8085/log
Output: appended to roku_logs.txt (and printed to the console)

Uses only the Python standard library.
"""

import os
import socket
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"          # listen on all network interfaces
PORT = 8085               # change if the port is busy
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roku_logs.txt")

file_lock = threading.Lock()


class LogHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        line = f"[{timestamp}] {body}"

        with file_lock:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")

        print(line)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):
        # Handy to check from a browser that the server is reachable
        msg = b"Log server is running. POST your logs here."
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)

    def log_message(self, format, *args):
        pass  # silence default per-request logging


def get_local_ip():
    """Best-effort detection of this machine's LAN IP."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # no traffic is actually sent
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    # Start with a clean log file on every run
    open(LOG_FILE, "w", encoding="utf-8").close()

    server = ThreadingHTTPServer((HOST, PORT), LogHandler)
    print(f"Log server listening on http://{get_local_ip()}:{PORT}")
    print(f"Saving logs to: {LOG_FILE}")
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()
