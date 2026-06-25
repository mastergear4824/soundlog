#!/usr/bin/env bash
# Build a Release SoundLog.app and package it into a drag-to-install DMG under dist/,
# with the app icon applied to both the .dmg file and the mounted volume.
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
ICNS="$APP/Contents/Resources/AppIcon.icns"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "==> Version $VERSION"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Staging DMG contents"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Volume icon (shown when the DMG is mounted).
[ -f "$ICNS" ] && cp "$ICNS" "$STAGE/.VolumeIcon.icns"
# Short install note for machines that hit Gatekeeper.
cat > "$STAGE/처음 실행이 막히면 읽어주세요.txt" <<'EOF'
SoundLog 는 개인용/미서명 앱입니다.

설치:  SoundLog.app 을 Applications 폴더로 드래그하세요.

처음 실행 시 "확인되지 않은 개발자" 경고가 뜨면:
  • Applications 에서 SoundLog 를 우클릭 → "열기" → "열기"
  • 또는 터미널에서:  xattr -dr com.apple.quarantine /Applications/Soundlog.app

필요 도구(앱이 호출):  brew install yt-dlp ffmpeg
EOF

mkdir -p "$DIST"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
TMPDMG="$DIST/.tmp-build.dmg"
VOL="SoundLog ${VERSION}"
rm -f "$DMG" "$TMPDMG"

echo "==> Creating writable image"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMPDMG" >/dev/null

# Flag the mounted volume to use its .VolumeIcon.icns. Best-effort.
echo "==> Applying volume icon"
DEV="$(hdiutil attach "$TMPDMG" -nobrowse -noverify -readwrite | awk '/^\/dev\// {print $1; exit}')"
VOLPATH="/Volumes/$VOL"
if [ -f "$VOLPATH/.VolumeIcon.icns" ]; then
  (SetFile -a C "$VOLPATH" 2>/dev/null || /usr/bin/SetFile -a C "$VOLPATH" 2>/dev/null) || true
fi
sync; sleep 1
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

echo "==> Compressing -> $DMG"
hdiutil convert "$TMPDMG" -format UDZO -o "$DMG" >/dev/null
rm -f "$TMPDMG"

# Apply the icon to the .dmg FILE itself (how it appears in Finder).
echo "==> Applying .dmg file icon"
if [ -f "$ICNS" ]; then
  ICONSWIFT="$(mktemp).swift"
  cat > "$ICONSWIFT" <<'SWIFTEOF'
import Cocoa
let a = CommandLine.arguments
if a.count >= 3, let img = NSImage(contentsOfFile: a[1]) {
    NSWorkspace.shared.setIcon(img, forFile: a[2], options: [])
}
SWIFTEOF
  swift "$ICONSWIFT" "$ICNS" "$DMG" 2>/dev/null || true
  rm -f "$ICONSWIFT"
fi

rm -rf "$STAGE"
echo "==> Done: $DMG  ($(du -h "$DMG" | cut -f1))"
