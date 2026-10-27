# KeyboardKitHostPlugin 11.0.0

Official standalone host resolver from Kankoda Sweden AB, obtained through the vendor's public Swift Package binary distribution. Only its public `pluginHostApplicationResolver` entry point is used. No KeyboardKit core, LicenseKit, dictation engine or Pro HostApplication metadata is linked. No reverse engineering or license bypass.

Package URL and SHA256 are pinned in ios/HostSupport/Package.swift. Device static library is about75KB before linking. The binary is downloaded by SwiftPM, not committed here. The vendor license is bundled in the extension. This is a closed-source, free-to-start dependency, not an MIT/open-source component.

Vendor integration documentation states that plugins are completely standalone and use basic values. This plugin wraps optional system API usage for resolving the current keyboard host. Re-evaluate compatibility and license before distribution.

References: https://docs.keyboardkit.com/documentation/keyboardkit/plugins-article/ and https://github.com/KeyboardKit/KeyboardKit .
