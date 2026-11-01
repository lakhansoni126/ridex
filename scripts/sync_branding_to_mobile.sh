#!/usr/bin/env bash
# Copy canonical branding exports into the Flutter package asset tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/mobile/assets/branding/exports/splash"
cp "$ROOT/assets/branding/"*.svg "$ROOT/mobile/assets/branding/" 2>/dev/null || true
cp "$ROOT/assets/branding/exports/ridex-icon-1024.png" "$ROOT/mobile/assets/branding/exports/"
cp "$ROOT/assets/branding/exports/ridex-wordmark.png" "$ROOT/mobile/assets/branding/exports/"
cp "$ROOT/assets/branding/exports/splash/splash-portrait.png" "$ROOT/mobile/assets/branding/exports/splash/"
echo "Synced branding → mobile/assets/branding"
