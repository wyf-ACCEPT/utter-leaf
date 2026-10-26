#!/usr/bin/env python3
"""Prepare an ignored personal bundle seed; never print credential values."""
import os
import pathlib
import plistlib
import shlex

allowed = {"DOUBAO_API_KEY", "DEEPSEEK_API_KEY"}
values = {key: os.environ[key] for key in allowed if os.environ.get(key)}
source = pathlib.Path.home() / ".llm.env"
if source.is_file():
    for line in source.read_text().splitlines():
        try:
            tokens = shlex.split(line, comments=True)
        except ValueError:
            continue
        if tokens and tokens[0] == "export":
            tokens = tokens[1:]
        if len(tokens) != 1 or "=" not in tokens[0]:
            continue
        key, value = tokens[0].split("=", 1)
        if key in allowed and key not in values and value:
            values[key] = value
if len(values) != 2:
    raise SystemExit("Both personal API keys are required. Configure them locally or enter them on the phone.")
destination = pathlib.Path(__file__).resolve().parents[1] / "ios/PersonalKeys.plist"
descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(descriptor, "wb") as output:
    plistlib.dump(values, output)
os.chmod(destination, 0o600)
print("Prepared personal iOS seed with two credentials. Values were not logged.")
