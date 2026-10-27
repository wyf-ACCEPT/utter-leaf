#!/usr/bin/env python3
"""Fetch the official standalone binary with its published checksum."""
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

URL = "https://github.com/KeyboardKit/KeyboardKit-Binaries/releases/download/11.0.0/KeyboardKitHostPlugin.zip"
SHA256 = "a9c804c9bb5811318d812b3a63ebd91a9709e864f15b85b976be34016c078ac8"
destination = Path(__file__).resolve().parents[1] / "ios/HostSupport/Artifacts"
with urllib.request.urlopen(URL, timeout=60) as response:
    data = response.read(8 * 1024 * 1024)
if hashlib.sha256(data).hexdigest() != SHA256:
    raise SystemExit("Host plugin checksum mismatch; artifact was not installed.")
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for entry in archive.infolist():
        path = Path(entry.filename)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit("Unsafe SDK archive path; artifact was not installed.")
    destination.mkdir(parents=True, exist_ok=True)
    archive.extractall(destination)
print("Prepared official KeyboardKitHostPlugin 11.0.0; published SHA256 verified.")
