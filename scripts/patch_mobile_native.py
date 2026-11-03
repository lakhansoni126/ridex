#!/usr/bin/env python3
"""Patch Android/iOS native projects for RideX location, branding, signing, HTTPS."""

from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
SIGNING = MOBILE / "signing"


def _inject_android_signing(app_gradle: Path) -> None:
    """Configure release signing with the committed RideX keystore (sideload-safe)."""
    if not app_gradle.exists():
        print("skip signing: app/build.gradle missing")
        return

    android_app = app_gradle.parent
    keystore_src = SIGNING / "ridex-release.p12"
    props_src = SIGNING / "key.properties"
    if not keystore_src.exists() or not props_src.exists():
        print("skip signing: mobile/signing keystore/properties missing")
        return

    shutil.copy2(keystore_src, android_app / "ridex-release.p12")
    (android_app / "key.properties").write_text(
        "storePassword=RideXRelease2026!\n"
        "keyPassword=RideXRelease2026!\n"
        "keyAlias=ridex\n"
        "storeFile=ridex-release.p12\n",
        encoding="utf-8",
    )

    text = app_gradle.read_text(encoding="utf-8")
    if "ridex-release.p12" in text and "signingConfigs" in text:
        print("signing already present in app/build.gradle")
        return

    signing_block = """
def ridexKeystoreProperties = new Properties()
def ridexKeystorePropertiesFile = rootProject.file('app/key.properties')
if (ridexKeystorePropertiesFile.exists()) {
    ridexKeystorePropertiesFile.withInputStream { stream ->
        ridexKeystoreProperties.load(stream)
    }
}
"""

    if "ridexKeystoreProperties" not in text:
        # Insert after first `plugins {` / `def localProperties` / beginning of plugins section
        if "def localProperties = new Properties()" in text:
            text = text.replace(
                "def localProperties = new Properties()",
                signing_block + "\ndef localProperties = new Properties()",
                1,
            )
        else:
            text = signing_block + "\n" + text

    android_signing = """
    signingConfigs {
        release {
            keyAlias ridexKeystoreProperties['keyAlias']
            keyPassword ridexKeystoreProperties['keyPassword']
            storeFile ridexKeystoreProperties['storeFile'] ? file(ridexKeystoreProperties['storeFile']) : null
            storePassword ridexKeystoreProperties['storePassword']
        }
    }
"""

    if "signingConfigs" not in text:
        text = re.sub(
            r"(android\s*\{)",
            r"\1\n" + android_signing,
            text,
            count=1,
        )

    # Force release buildType to use release signing
    if re.search(r"buildTypes\s*\{[\s\S]*?release\s*\{", text):
        if "signingConfig signingConfigs.release" not in text:
            text = re.sub(
                r"(release\s*\{)",
                r"\1\n            signingConfig signingConfigs.release",
                text,
                count=1,
            )
    else:
        text = re.sub(
            r"(android\s*\{)",
            r"\1\n    buildTypes {\n        release {\n            signingConfig signingConfigs.release\n        }\n    }\n",
            text,
            count=1,
        )

    app_gradle.write_text(text, encoding="utf-8")
    print(f"patched signing -> {app_gradle.relative_to(ROOT)}")


def _write_network_security_config() -> None:
    xml_dir = MOBILE / "android" / "app" / "src" / "main" / "res" / "xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    cfg = xml_dir / "network_security_config.xml"
    cfg.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Production API is HTTPS. No cleartext to arbitrary hosts. -->
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
</network-security-config>
""",
        encoding="utf-8",
    )
    print(f"wrote {cfg.relative_to(ROOT)}")


def patch_android() -> None:
    manifest = MOBILE / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("skip android: manifest missing (run flutter create first)")
        return

    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]+"', 'android:label="RideX"', text, count=1)

    # Prefer HTTPS-only network security (Play Protect / sideload hygiene)
    text = re.sub(
        r'\s*android:usesCleartextTraffic="[^"]*"',
        "",
        text,
    )
    if "android:networkSecurityConfig" not in text:
        text = text.replace(
            "<application",
            '<application android:networkSecurityConfig="@xml/network_security_config"',
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

    # Ensure any existing service can declare location FGS type if present
    if "android:foregroundServiceType" not in text and "<service" in text:
        text = text.replace(
            "<service",
            '<service android:foregroundServiceType="location"',
            1,
        )

    manifest.write_text(text, encoding="utf-8")
    print(f"patched {manifest.relative_to(ROOT)}")

    _write_network_security_config()
    if os.environ.get("RIDEX_SKIP_SIGNING") == "1":
        print("skip signing injection (RIDEX_SKIP_SIGNING=1)")
    else:
        _inject_android_signing(MOBILE / "android" / "app" / "build.gradle")
        _inject_android_signing_kts(MOBILE / "android" / "app" / "build.gradle.kts")


def _inject_android_signing_kts(app_gradle_kts: Path) -> None:
    """Configure release signing for Kotlin DSL app/build.gradle.kts."""
    if not app_gradle_kts.exists():
        return

    android_app = app_gradle_kts.parent
    keystore_src = SIGNING / "ridex-release.p12"
    if not keystore_src.exists():
        print("skip kts signing: keystore missing")
        return

    shutil.copy2(keystore_src, android_app / "ridex-release.p12")
    (android_app / "key.properties").write_text(
        "storePassword=RideXRelease2026!\n"
        "keyPassword=RideXRelease2026!\n"
        "keyAlias=ridex\n"
        "storeFile=ridex-release.p12\n",
        encoding="utf-8",
    )

    text = app_gradle_kts.read_text(encoding="utf-8")

    # Gradle requires `plugins {}` before other script logic (imports are ok).
    # Strip any earlier broken preamble that was inserted above plugins {}.
    text = re.sub(
        r"(?s)^(?:\s*import java\.util\.Properties\s*"
        r"|\s*import java\.io\.FileInputStream\s*"
        r"|\s*val ridexKeystoreProperties[\s\S]*?\n\}\s*)+",
        "",
        text,
    )

    imports = (
        "import java.util.Properties\n"
        "import java.io.FileInputStream\n\n"
    )
    if "import java.util.Properties" not in text:
        text = imports + text

    # Load keystore props AFTER plugins {} block.
    props_loader = """
val ridexKeystoreProperties = Properties()
val ridexKeystorePropertiesFile = rootProject.file("app/key.properties")
if (ridexKeystorePropertiesFile.exists()) {
    ridexKeystoreProperties.load(FileInputStream(ridexKeystorePropertiesFile))
}

"""
    if "ridexKeystoreProperties" not in text:
        if re.search(r"plugins\s*\{[\s\S]*?\n\}", text):
            text = re.sub(
                r"(plugins\s*\{[\s\S]*?\n\})",
                r"\1\n" + props_loader,
                text,
                count=1,
            )
        else:
            text = props_loader + text

    signing_block = """
    signingConfigs {
        create("release") {
            keyAlias = ridexKeystoreProperties["keyAlias"] as String
            keyPassword = ridexKeystoreProperties["keyPassword"] as String
            storeFile = file(ridexKeystoreProperties["storeFile"] as String)
            storePassword = ridexKeystoreProperties["storePassword"] as String
            storeType = "PKCS12"
        }
    }
"""
    # Detect a real signingConfigs { ... } block, not just getByName("…")
    if "create(\"release\")" not in text and "create('release')" not in text:
        if re.search(r"android\s*\{", text):
            text = re.sub(
                r"(android\s*\{)",
                r"\1\n" + signing_block,
                text,
                count=1,
            )
        else:
            print("warn: no android { block in build.gradle.kts")

    # Normalize the release buildType to a single release signingConfig line.
    text = re.sub(
        r"[ \t]*// TODO: Add your own signing config for the release build\.\n"
        r"[ \t]*// Signing with the debug keys for now.*\n",
        "",
        text,
    )
    text = re.sub(
        r"[ \t]*signingConfig\s*=\s*signingConfigs\.getByName\(\"(?:debug|release)\"\)\s*\n?",
        "",
        text,
    )
    text = re.sub(
        r"[ \t]*signingConfig\s*=\s*signingConfigs\.getByName\('(?:debug|release)'\)\s*\n?",
        "",
        text,
    )
    text = re.sub(
        r"(buildTypes\s*\{[\s\S]*?release\s*\{)",
        r'\1\n            signingConfig = signingConfigs.getByName("release")',
        text,
        count=1,
    )

    app_gradle_kts.write_text(text, encoding="utf-8")
    print(f"patched signing -> {app_gradle_kts.relative_to(ROOT)}")


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

    # Production uses HTTPS — prefer tight ATS (remove arbitrary loads if we added them)
    if "NSAllowsArbitraryLoads" in text:
        text = text.replace(
            "\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n",
            "",
        )

    if "NSAppTransportSecurity" not in text:
        ats = (
            "\t<key>NSAppTransportSecurity</key>\n"
            "\t<dict>\n"
            "\t\t<key>NSAllowsLocalNetworking</key>\n"
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
