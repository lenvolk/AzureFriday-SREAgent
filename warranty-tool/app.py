"""Zava Warranty Lookup Service.

Serves warranty status data for the Azure Friday SRE Agent demo without
requiring third-party runtime packages in Azure App Service.
"""

import json
import os
from datetime import date
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

# Mock warranty database
WARRANTY_DB: dict[str, dict] = {
    "SN-2023-XPS-4471": {
        "device_model": "Dell XPS 15 9530",
        "purchase_date": "2023-03-15",
        "warranty_expiry": "2026-03-15",
        "warranty_years": 3,
        "recommended_replacement": "Dell XPS 15 9540 or equivalent",
    },
    "SN-2024-MBP-8832": {
        "device_model": 'MacBook Pro 16" M3',
        "purchase_date": "2024-06-20",
        "warranty_expiry": "2027-06-20",
        "warranty_years": 3,
        "recommended_replacement": 'MacBook Pro 16" M4 or equivalent',
    },
    "SN-2022-TPX-1199": {
        "device_model": "Lenovo ThinkPad X1 Carbon Gen 10",
        "purchase_date": "2022-01-10",
        "warranty_expiry": "2025-01-10",
        "warranty_years": 3,
        "recommended_replacement": "Lenovo ThinkPad X1 Carbon Gen 12 or equivalent",
    },
    "SN-2024-HPE-5567": {
        "device_model": "HP EliteBook 860 G10",
        "purchase_date": "2024-09-01",
        "warranty_expiry": "2027-09-01",
        "warranty_years": 3,
        "recommended_replacement": "HP EliteBook 860 G11 or equivalent",
    },
    "SN-2021-DEL-3344": {
        "device_model": "Dell Latitude 5520",
        "purchase_date": "2021-11-30",
        "warranty_expiry": "2024-11-30",
        "warranty_years": 3,
        "recommended_replacement": "Dell Latitude 5550 or equivalent",
    },
}


def _lookup(serial_number: str) -> dict:
    """Build a warranty result dict for a given serial number."""
    device = WARRANTY_DB.get(serial_number)
    if device is None:
        return None

    today = date.today()
    expiry = date.fromisoformat(device["warranty_expiry"])

    is_expired = today > expiry
    delta = (today - expiry).days if is_expired else 0
    warranty_years = device["warranty_years"]

    return {
        "found": True,
        "serial_number": serial_number,
        "device_model": device["device_model"],
        "purchase_date": device["purchase_date"],
        "warranty_expiry": device["warranty_expiry"],
        "warranty_status": "Expired" if is_expired else "Active",
        "days_since_expiry": delta if is_expired else None,
        "days_until_expiry": (expiry - today).days if not is_expired else None,
        "eligible_for_replacement": is_expired,
        "replacement_reason": (
            f"Standard warranty period ({warranty_years} years) has expired"
            if is_expired
            else f"Device is still under warranty until {device['warranty_expiry']}"
        ),
        "recommended_replacement": (
            device["recommended_replacement"] if is_expired else None
        ),
    }


def root():
    return {"service": "Zava Warranty Lookup Service", "version": "1.0.0"}


def health():
    return {"status": "healthy"}


def warranty_lookup(serial_number: str):
    result = _lookup(serial_number)
    if result is None:
        return HTTPStatus.NOT_FOUND, {
            "detail": {"found": False, "error": "Device not found in warranty database"}
        }
    return result


def list_devices():
    devices = []
    for serial, info in WARRANTY_DB.items():
        devices.append(
            {
                "serial_number": serial,
                "device_model": info["device_model"],
                "purchase_date": info["purchase_date"],
                "warranty_expiry": info["warranty_expiry"],
            }
        )
    return {"devices": devices, "count": len(devices)}


class WarrantyRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path.rstrip("/") or "/"

        if path == "/":
            self._send_json(root())
            return

        if path == "/health":
            self._send_json(health())
            return

        if path == "/devices":
            self._send_json(list_devices())
            return

        if path.startswith("/warranty/"):
            serial_number = unquote(path.removeprefix("/warranty/"))
            result = warranty_lookup(serial_number)
            if isinstance(result, tuple):
                status, payload = result
                self._send_json(payload, status)
            else:
                self._send_json(result)
            return

        self._send_json({"error": "Not found"}, HTTPStatus.NOT_FOUND)

    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}")

    def _send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), WarrantyRequestHandler)
    print(f"Starting Zava Warranty Lookup Service on port {port}")
    server.serve_forever()
