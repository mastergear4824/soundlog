#!/usr/bin/env bash
# Download the bundled CLI binaries (yt-dlp + ffmpeg) into vendor/ so the app can ship
# self-contained (no `brew install` needed). vendor/ is gitignored; this reproduces it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor

if [ ! -x vendor/yt-dlp ]; then
  echo "==> yt-dlp (universal standalone)"
  curl -fsSL -o vendor/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
  chmod +x vendor/yt-dlp
fi

if [ ! -x vendor/ffmpeg ]; then
  echo "==> ffmpeg (arm64 static, portable)"
  curl -fsSL -o /tmp/ffmpeg-arm.zip "https://www.osxexperts.net/ffmpeg711arm.zip"
  unzip -oq /tmp/ffmpeg-arm.zip -d vendor
  chmod +x vendor/ffmpeg
  rm -f /tmp/ffmpeg-arm.zip
fi

echo "==> vendor ready ($(du -sh vendor | cut -f1)):"
ls -la vendor | grep -E "yt-dlp|ffmpeg"
