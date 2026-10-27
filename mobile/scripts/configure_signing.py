#!/usr/bin/env python3
"""Generate local entitlements for the personal paid-team installation."""
import argparse
import pathlib
import plistlib

parser = argparse.ArgumentParser()
parser.add_argument('--app-group', default='group.network.utterleaf.mobile')
parser.add_argument('--cloud-container', default='iCloud.network.utterleaf.personal')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1] / 'ios'
shared = {'com.apple.security.application-groups': [args.app_group]}
app = dict(shared)
app.update({'com.apple.developer.icloud-services': ['CloudKit'],
            'com.apple.developer.icloud-container-identifiers': [args.cloud_container],
            'com.apple.developer.icloud-container-environment': 'Development'})
for name, entitlements in [('Runner/Runner.entitlements', app), ('UtterLeafKeyboard/Keyboard.entitlements', shared)]:
    with (root / name).open('wb') as output:
        plistlib.dump(entitlements, output)
print('Prepared app and keyboard entitlements; no credentials were read.')
