#!/usr/bin/env python3
# shim in front of podinfo, maps custom endpoins to podinfo paths
# emits structred JSON logs with APP_ENV, latency, etc.
import json
import os
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

APP_ENV = os.getenv("APP_ENV", "staging")
PORT = int(os.getenv("PORT", "8080"))
PODINFO_PORT = int(os.getenv("PODINFO_PORT", "9898"))
SLOW_SECONDS = max(0, int(float(os.getenv("SLOW_SECONDS", "2"))))
UPSTREAM_TIMEOUT_SECONDS = float(os.getenv("UPSTREAM_TIMEOUT_SECONDS", "15"))
UPSTREAM_BASE_URL = f"http://127.0.0.1:{PODINFO_PORT}"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class PodinfoShimHandler(BaseHTTPRequestHandler):
    server_version = "podinfo-shim/1.0"

    def log_message(self, _format: str, *_args) -> None:
        return

    def do_GET(self) -> None:
        self._handle_request("GET")

    def do_HEAD(self) -> None:
        self._handle_request("HEAD")

    def _map_path(self, raw_path: str) -> str:
        parts = urlsplit(raw_path)
        path = parts.path

        if path == "/health":
            path = "/healthz"
        elif path == "/ready":
            path = "/readyz"
        elif path == "/request":
            path = "/"
        elif path == "/error":
            path = "/status/500"
        elif path == "/slow":
            path = f"/delay/{SLOW_SECONDS}"

        return urlunsplit(("", "", path, parts.query, parts.fragment))

    def _proxy_request(self, method: str, upstream_path: str):
        forwarded_headers = {}
        for header_name, header_value in self.headers.items():
            name = header_name.lower()
            if name in (
                "host",
                "connection",
                "proxy-connection",
                "keep-alive",
                "transfer-encoding",
                "te",
                "trailer",
                "upgrade",
            ):
                continue
            forwarded_headers[header_name] = header_value
        forwarded_headers["Host"] = f"127.0.0.1:{PODINFO_PORT}"

        request = Request(f"{UPSTREAM_BASE_URL}{upstream_path}", headers=forwarded_headers, method=method)

        try:
            with urlopen(request, timeout=UPSTREAM_TIMEOUT_SECONDS) as response:
                return response.status, list(response.getheaders()), response.read()
        except HTTPError as error:
            body = error.read() if error.fp is not None else b""
            return error.code, list(error.headers.items()), body
        except URLError:
            payload = {"error": "podinfo upstream unavailable"}
            return 502, [("Content-Type", "application/json")], json.dumps(payload).encode("utf-8")

    def _send_response(self, status: int, headers, body: bytes, send_body: bool) -> None:
        self.send_response(status)

        has_content_type = False
        for header_name, header_value in headers:
            name = header_name.lower()
            if name in ("connection", "keep-alive", "proxy-connection", "transfer-encoding", "content-length"):
                continue
            if name == "content-type":
                has_content_type = True
            self.send_header(header_name, header_value)

        if not has_content_type:
            self.send_header("Content-Type", "application/json")

        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def _handle_request(self, method: str) -> None:
        request_path = urlsplit(self.path).path
        upstream_path = self._map_path(self.path)
        start = time.perf_counter()
        status, headers, body = self._proxy_request(method, upstream_path)

        self._send_response(status, headers, body, send_body=method != "HEAD")

        if request_path == "/metrics":
            return

        latency_ms = round((time.perf_counter() - start) * 1000.0, 3)
        level = "ERROR" if status >= 500 else "INFO"
        log_line = {
            "timestamp": _utc_now_iso(),
            "level": level,
            "endpoint": request_path,
            "latency": latency_ms,
            "APP_ENV": APP_ENV,
            "method": method,
            "status": status,
            "message": "request completed",
        }
        print(json.dumps(log_line, separators=(",", ":"), ensure_ascii=True), flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), PodinfoShimHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
