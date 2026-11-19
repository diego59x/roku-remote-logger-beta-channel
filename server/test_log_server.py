"""Tests for LogLocalServer.py. Run: python3 -m unittest discover -s server -v"""

import contextlib
import glob
import http.client
import io
import json
import os
import shutil
import socket
import tempfile
import threading
import unittest

from LogLocalServer import MAX_BODY, LogServer


def batch(sid, seqs, dropped=0, model="4802X"):
    return {
        "v": 1,
        "session": {
            "id": sid,
            "startedAt": 1794480000000,
            "app": {"id": "dev", "version": "4.12.0", "build": "381"},
            "device": {"model": model, "os": "15.0.4", "locale": "en_US"},
            "tags": {"tester": "qa-01"},
        },
        "dropped": dropped,
        "entries": [
            {"seq": s, "t": 1794480012345 + s, "lvl": "info", "tag": "PlayerScreen", "msg": "entry %d" % s,
             "data": {"state": "playing"}}
            for s in seqs
        ],
    }


class LogServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log_dir = tempfile.mkdtemp()
        cls.server = LogServer(("127.0.0.1", 0), cls.log_dir)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        shutil.rmtree(cls.log_dir)

    def request(self, method, path, body=None):
        """Send a request; return (status, response text, console output)."""
        if isinstance(body, dict):
            body = json.dumps(body)
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            conn.request(method, path, body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            text = resp.read().decode()
        conn.close()
        return resp.status, text, out.getvalue()

    def session_lines(self, sid):
        files = glob.glob(os.path.join(self.log_dir, "*_%s.jsonl" % sid))
        self.assertEqual(len(files), 1, files)
        with open(files[0], encoding="utf-8") as f:
            return [json.loads(line) for line in f]

    def test_health_check(self):
        status, text, _ = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn("running", text)

    def test_valid_batch(self):
        status, _, console = self.request("POST", "/v1/logs", batch("valid1", [1, 2]))
        self.assertEqual(status, 204)
        lines = self.session_lines("valid1")
        self.assertEqual([l["seq"] for l in lines], [1, 2])
        self.assertEqual(lines[0]["session_id"], "valid1")
        self.assertIn("received", lines[0])
        self.assertEqual(lines[0]["data"], {"state": "playing"})
        self.assertIn("== session valid1 | app dev 4.12.0 (381) | device 4802X OS 15.0.4", console)
        self.assertRegex(console, r'\d\d:\d\d:\d\d\.\d{3} INFO  PlayerScreen: entry 1 \{"state": "playing"\}')
        self.assertTrue(os.path.basename(glob.glob(os.path.join(self.log_dir, "*_valid1.jsonl"))[0])
                        .endswith("_4802X_valid1.jsonl"))

    def test_invalid_json(self):
        status, _, _ = self.request("POST", "/v1/logs", "{not json")
        self.assertEqual(status, 400)

    def test_wrong_version(self):
        b = batch("v2", [1])
        b["v"] = 2
        status, text, _ = self.request("POST", "/v1/logs", b)
        self.assertEqual(status, 400)
        self.assertIn("v=1", text)

    def test_missing_fields(self):
        for b in ({"v": 1, "session": {"id": 5}, "entries": []},
                  {"v": 1, "session": {"id": "x"}, "entries": {}},
                  {"v": 1, "session": {"id": "x"}, "entries": [{"msg": "no seq"}]},
                  [1, 2]):
            status, _, _ = self.request("POST", "/v1/logs", json.dumps(b))
            self.assertEqual(status, 400, b)

    def test_oversized_refused_before_body(self):
        # Announce a large body but send none: the server must answer without waiting for it.
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as s:
            s.sendall(b"POST /v1/logs HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
                      b"Content-Length: %d\r\n\r\n" % (MAX_BODY + 1))
            self.assertTrue(s.recv(1024).startswith(b"HTTP/1.0 413"))

    def test_duplicate_batch_written_once(self):
        self.request("POST", "/v1/logs", batch("dup1", [1, 2, 3]))
        status, _, console = self.request("POST", "/v1/logs", batch("dup1", [2, 3, 4]))
        self.assertEqual(status, 204)
        self.assertEqual([l["seq"] for l in self.session_lines("dup1")], [1, 2, 3, 4])
        self.assertNotIn("entry 2", console)

    def test_dropped_reported(self):
        self.request("POST", "/v1/logs", batch("drop1", [1, 2]))
        status, _, console = self.request("POST", "/v1/logs", batch("drop1", [8, 9], dropped=5))
        self.assertEqual(status, 204)
        self.assertIn("device dropped 5 entries", console)
        self.assertIn("seq jumped from 2 to 8, 5 missing", console)
        notices = [l for l in self.session_lines("drop1") if l["tag"] == "remote-logger"]
        self.assertEqual([n["data"] for n in notices],
                         [{"dropped": 5}, {"from": 2, "to": 8, "missing": 5}])
        # A retry of the same batch is not reported again.
        _, _, console = self.request("POST", "/v1/logs", batch("drop1", [8, 9], dropped=5))
        self.assertNotIn("dropped", console)

    def test_unknown_path_and_method(self):
        self.assertEqual(self.request("POST", "/log", "hello")[0], 404)
        self.assertEqual(self.request("GET", "/v1/logs")[0], 404)
        self.assertEqual(self.request("PUT", "/v1/logs", "{}")[0], 404)

    def test_filename_sanitised(self):
        status, _, _ = self.request("POST", "/v1/logs", batch("../../evil", [1], model="../../x"))
        self.assertEqual(status, 204)
        names = os.listdir(self.log_dir)
        hostile = [n for n in names if "evil" in n]
        self.assertEqual(len(hostile), 1, names)
        self.assertNotIn("/", hostile[0])
        self.assertNotIn("..", hostile[0])
        self.assertTrue(hostile[0].endswith("_______x_______evil.jsonl"), hostile[0])


if __name__ == "__main__":
    unittest.main()
