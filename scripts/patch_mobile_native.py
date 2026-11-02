#!/usr/bin/env python3
"""Patch Android/iOS native projects for RideX location, branding, cleartext LAN."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"


def patch_android() -> None:
    manifest = MOBILE / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("skip android: manifest missing (run flutter create first)")
        return

    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]+"', 'android:label="RideX"', text, count=1)

    # Allow http://LAN for local API testing
    if "android:usesCleartextTraffic" not in text:
        text = text.replace(
            "<application",
            '<application android:usesCleartextTraffic="true"',
            1,
        )

    perms = [
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_BACKGROUND_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.WAKE_LOCK",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.INTERNET",
    ]
    missing = [p for p in perms if p not in text]
    if missing:
        block = "\n".join(f'    <uses-permission android:name="{p}" />' for p in missing)
        text = text.replace("<application", f"{block}\n    <application", 1)

    manifest.write_text(text, encoding="utf-8")
    print(f"patched {manifest.relative_to(ROOT)}")


def patch_ios() -> None:
    plist = MOBILE / "ios" / "Runner" / "Info.plist"
    if not plist.exists():
        print("skip ios: Info.plist missing (run flutter create first)")
        return

    text = plist.read_text(encoding="utf-8")
    replacements = {
        "NSLocationWhenInUseUsageDescription": (
            "RideX needs your location for live group drives and optional friend sharing."
        ),
        "NSLocationAlwaysAndWhenInUseUsageDescription": (
            "RideX continues sharing your location in the background only while a drive "
            "is live or you choose to share with friends."
        ),
        "NSLocationAlwaysUsageDescription": (
            "RideX continues sharing your location in the background only while a drive "
            "is live or you choose to share with friends."
        ),
    }
    for key, value in replacements.items():
        if key in text:
            continue
        entry = f"\t<key>{key}</key>\n\t<string>{value}</string>\n"
        text = text.replace("</dict>\n</plist>", f"{entry}</dict>\n</plist>")

    if "UIBackgroundModes" not in text:
        bg = (
            "\t<key>UIBackgroundModes</key>\n"
            "\t<array>\n\t\t<string>location</string>\n\t</array>\n"
        )
        text = text.replace("</dict>\n</plist>", f"{bg}</dict>\n</plist>")
    elif "<string>location</string>" not in text:
        text = text.replace(
            "<key>UIBackgroundModes</key>\n\t<array>",
            "<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>",
        )

    # Allow local HTTP to LAN API during development
    if "NSAppTransportSecurity" not in text:
        ats = (
            "\t<key>NSAppTransportSecurity</key>\n"
            "\t<dict>\n"
            "\t\t<key>NSAllowsLocalNetworking</key>\n"
            "\t\t<true/>\n"
            "\t\t<key>NSAllowsArbitraryLoads</key>\n"
            "\t\t<true/>\n"
            "\t</dict>\n"
        )
        text = text.replace("</dict>\n</plist>", f"{ats}</dict>\n</plist>")

    plist.write_text(text, encoding="utf-8")
    print(f"patched {plist.relative_to(ROOT)}")


def main() -> int:
    patch_android()
    patch_ios()
    return 0


if __name__ == "__main__":
    sys.exit(main())
