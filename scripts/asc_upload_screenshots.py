#!/usr/bin/env python3
"""Upload Writing Jail macOS screenshots through the App Store Connect API."""

import hashlib
import json
import os
import pathlib
import subprocess
import urllib.error
import urllib.request

APP_ID = "6829436529"
VERSION_ID = "bba677c3-ff68-4059-871a-b6e7a4710bd9"
VERSION_LOCALIZATION_ID = "87dee5f7-4989-4aa8-a3f7-f3b6be72d629"
KEY_ID = "R9J2865VAJ"
DISPLAY_TYPE = "APP_DESKTOP"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"
SCREENSHOT_DIR = pathlib.Path("AppStore/Screenshots/macOS")


def setting(name: str) -> str:
    value = os.environ.get(name)
    if value:
        return value
    env_path = pathlib.Path("~/.appstoreconnect/asc.env").expanduser()
    for line in env_path.read_text().splitlines():
        key, separator, value = line.removeprefix("export ").partition("=")
        if separator and key == name:
            return value
    raise SystemExit(f"{name} is not configured")


def token() -> str:
    key = pathlib.Path(
        f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    ).expanduser()
    helper = pathlib.Path("~/.appstoreconnect/bin/ascjwt").expanduser()
    return subprocess.run(
        [helper, key, KEY_ID, setting("ASC_ISSUER")],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def request(method: str, path: str, payload=None) -> dict:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"{method} {path} failed: {error.code}\n{detail}")


def ensure_set() -> str:
    response = request(
        "GET",
        f"/appStoreVersionLocalizations/{VERSION_LOCALIZATION_ID}/appScreenshotSets",
    )
    for item in response.get("data", []):
        if item["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return item["id"]

    response = request(
        "POST",
        "/appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": VERSION_LOCALIZATION_ID,
                        }
                    }
                },
            }
        },
    )
    return response["data"]["id"]


def upload(set_id: str, path: pathlib.Path) -> None:
    data = path.read_bytes()
    checksum = hashlib.md5(data).hexdigest()
    response = request(
        "POST",
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileSize": len(data),
                    "fileName": path.name,
                },
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        },
    )

    screenshot = response["data"]
    for operation in screenshot["attributes"].get("uploadOperations", []):
        headers = {
            header["name"]: header["value"]
            for header in operation.get("headers", [])
        }
        offset = operation["offset"]
        length = operation["length"]
        upload_request = urllib.request.Request(
            operation["url"],
            data=data[offset:offset + length],
            method=operation["method"],
            headers=headers,
        )
        with urllib.request.urlopen(upload_request, timeout=120):
            pass

    request(
        "PATCH",
        f"/appScreenshots/{screenshot['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": screenshot["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum,
                },
            }
        },
    )
    print(f"uploaded {path.name}")


def main() -> None:
    set_id = ensure_set()
    files = sorted(SCREENSHOT_DIR.glob("0*.png"))
    if not files:
        raise SystemExit(f"No screenshots found in {SCREENSHOT_DIR}")
    for path in files:
        upload(set_id, path)
    print(f"uploaded {len(files)} screenshots to {DISPLAY_TYPE}")


if __name__ == "__main__":
    main()
