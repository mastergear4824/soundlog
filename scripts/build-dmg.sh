#!/usr/bin/env bash
# Build a Release Soundlog.app and package it into a drag-to-install DMG under dist/.
# Ad-hoc signed (no Developer ID): runs locally; other Macs need a quarantine bypass.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Soundlog"
CONFIG="Release"
DERIVED="build"
DIST="dist"

echo "==> Regenerating project"
xcodegen generate >/dev/null

echo "==> Building $CONFIG"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "build product not found: $APP"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "==> Version $VERSION"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Staging DMG contents"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Short install note for machines that hit Gatekeeper.
cat > "$STAGE/처음 실행이 막히면 읽어주세요.txt" <<'EOF'
Soundlog 는 개인용/미서명 앱입니다.

설치:  Soundlog.app 을 Applications 폴더로 드래그하세요.

처음 실행 시 "확인되지 않은 개발자" 경고가 뜨면:
  • Applications 에서 Soundlog 를 우클릭 → "열기" → "열기"
  • 또는 터미널에서:  xattr -dr com.apple.quarantine /Applications/Soundlog.app

필요 도구(앱이 호출):  brew install yt-dlp ffmpeg
EOF

mkdir -p "$DIST"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"

echo "==> Creating $DMG"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE"
echo "==> Done: $DMG  ($(du -h "$DMG" | cut -f1))"
