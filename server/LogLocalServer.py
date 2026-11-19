#!/usr/bin/env python3
"""
Log receiver for roku-remote-logger, protocol v1 (see docs/PROTOCOL.md).

Run:    python3 server/LogLocalServer.py [--host 0.0.0.0] [--port 8085] [--log-dir server/logs]
Device: POST JSON batches to http://<YOUR_PC_IP>:8085/v1/logs
Output: one JSON Lines file per session in the log directory, and one readable line per entry on the console

Uses only the Python standard library (3.9+).
"""

import argparse
import collections
import json
import os
import re
import socket
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 256 * 1024     # bytes, matches the protocol's body size limit
SEEN_PER_SESSION = 10000  # seqs remembered per session for duplicate removal


def safe_name(value):
    """Keep a filename part to letters, digits, '-' and '_' so it cannot leave the log directory."""
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value))[:64] or "unknown"


def from_ms(ms):
    """Device time (ms since the epoch) as a local datetime, or None when it is missing or out of range."""
    try:
        return datetime.fromtimestamp(ms / 1000)
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def validate(batch):
    """Return an error reason, or None when the batch is valid protocol v1."""
    if not isinstance(batch, dict):
        return "body is not a JSON object"
    if batch.get("v") != 1 or isinstance(batch.get("v"), bool):
        return "unsupported protocol version, expected v=1"
    session = batch.get("session")
    if not isinstance(session, dict) or not isinstance(session.get("id"), str):
        return "session.id must be a string"
    entries = batch.get("entries")
    if not isinstance(entries, list):
        return "entries must be a list"
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("seq"), int) or isinstance(entry.get("seq"), bool):
            return "every entry must be an object with an integer seq"
    return None


class Session:
    def __init__(self, path):
        self.path = path
        self.seen = set()
        self.order = collections.deque()
        self.last_seq = None

    def remember(self, seq):
        self.seen.add(seq)
        self.order.append(seq)
        if len(self.order) > SEEN_PER_SESSION:
            self.seen.discard(self.order.popleft())


class LogServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, log_dir):
        super().__init__(address, LogHandler)
        self.log_dir = log_dir
        self.sessions = {}
        self.lock = threading.Lock()  # one batch at a time: keeps files and console lines in order
        os.makedirs(log_dir, exist_ok=True)

    def open_session(self, session):
        sid = session["id"]
        if sid in self.sessions:
            return self.sessions[sid]
        start = from_ms(session.get("startedAt")) or datetime.now()
        device = session.get("device") if isinstance(session.get("device"), dict) else {}
        app = session.get("app") if isinstance(session.get("app"), dict) else {}
        name = "%s_%s_%s.jsonl" % (start.strftime("%Y%m%d-%H%M%S"), safe_name(device.get("model")), safe_name(sid))
        state = Session(os.path.join(self.log_dir, name))
        self.sessions[sid] = state
        print("== session %s | app %s %s (%s) | device %s OS %s | tags %s" % (
            sid, app.get("id"), app.get("version"), app.get("build"),
            device.get("model"), device.get("os"), json.dumps(session.get("tags") or {})))
        print("== writing %s" % state.path)
        return state

    def accept(self, batch):
        """Write the new entries of a batch to its session file and the console. Raises OSError on write failure."""
        state = self.open_session(batch["session"])
        sid = batch["session"]["id"]
        now = time.time()
        received = datetime.fromtimestamp(now).isoformat(timespec="milliseconds")
        records = []

        def notice(msg, data):
            return {"t": int(now * 1000), "lvl": "warn", "tag": "remote-logger", "msg": msg, "data": data}

        last_seq = state.last_seq
        new_seqs = []
        for entry in batch["entries"]:
            seq = entry["seq"]
            if seq in state.seen or seq in new_seqs:
                continue
            if last_seq is not None and seq > last_seq + 1:
                records.append(notice("seq jumped from %d to %d, %d missing" % (last_seq, seq, seq - last_seq - 1),
                                      {"from": last_seq, "to": seq, "missing": seq - last_seq - 1}))
            if last_seq is None or seq > last_seq:
                last_seq = seq
            new_seqs.append(seq)
            records.append(entry)

        # A batch whose entries were all seen before is a retry: its dropped count was already reported.
        dropped = batch.get("dropped")
        if isinstance(dropped, int) and dropped > 0 and (new_seqs or not batch["entries"]):
            records.insert(0, notice("device dropped %d entries" % dropped, {"dropped": dropped}))

        lines = [json.dumps(dict(r, session_id=sid, received=received), ensure_ascii=False) for r in records]
        if lines:
            with open(state.path, "a", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
        # Remember seqs only after the write, so a failed write can be retried by the device.
        for seq in new_seqs:
            state.remember(seq)
        state.last_seq = last_seq

        for r in records:
            t = from_ms(r.get("t"))
            data = r.get("data")
            print("%s %-5s %s: %s%s" % (
                t.strftime("%H:%M:%S.%f")[:-3] if t else "--:--:--.---",
                str(r.get("lvl", "")).upper(), r.get("tag", ""), r.get("msg", ""),
                " " + json.dumps(data, ensure_ascii=False) if data is not None else ""))


class LogHandler(BaseHTTPRequestHandler):
    timeout = 10  # seconds; a client that sends less than its Content-Length does not hold a thread forever

    def do_GET(self):
        if self.path.split("?")[0] != "/":
            return self.reply(404, "not found")
        self.reply(200, "Log server is running. POST protocol v1 batches to /v1/logs.")

    def do_POST(self):
        if self.path.split("?")[0] != "/v1/logs":
            return self.reply(404, "not found")
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            return self.reply(400, "Content-Length required")
        if length > MAX_BODY:
            self.close_connection = True  # the unread body stays on the socket
            return self.reply(413, "body larger than %d bytes" % MAX_BODY)
        try:
            batch = json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            return self.reply(400, "body is not valid JSON")
        error = validate(batch)
        if error:
            return self.reply(400, error)
        try:
            with self.server.lock:
                self.server.accept(batch)
        except OSError as e:
            print("!! could not write batch: %s" % e)
            return self.reply(500, "could not write log file")
        self.reply(204)

    def __getattr__(self, name):
        # Any other method (PUT, DELETE, ...) is answered with 404 instead of the default 501.
        if name.startswith("do_"):
            return lambda: self.reply(404, "not found")
        raise AttributeError(name)

    def reply(self, status, text=""):
        body = text.encode("utf-8")
        self.send_response(status)
        if status != 204:
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if status != 204 and self.command != "HEAD":
            self.wfile.write(body)

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


def main():
    parser = argparse.ArgumentParser(description="Receive roku-remote-logger batches (protocol v1).")
    parser.add_argument("--host", default="0.0.0.0", help="interface to listen on (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8085, help="port to listen on (default 8085)")
    parser.add_argument("--log-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs"),
                        help="directory for the per-session .jsonl files (default server/logs)")
    args = parser.parse_args()

    server = LogServer((args.host, args.port), args.log_dir)
    host = get_local_ip() if args.host in ("0.0.0.0", "") else args.host
    print("Log server listening. Device endpoint: http://%s:%d/v1/logs" % (host, server.server_address[1]))
    print("Saving logs to: %s" % os.path.abspath(args.log_dir))
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()


if __name__ == "__main__":
    main()
