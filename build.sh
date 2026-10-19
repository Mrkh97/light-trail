#!/bin/zsh
# Builds build/LightTrail.app (release, ad-hoc signed).
#   --install   copy it to /Applications and launch it
#   --release   build for both Apple silicon and Intel, and zip it up as build/LightTrail.zip
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=()
[[ " $* " == *" --release "* ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/LightTrail"
APP=build/LightTrail.app
rm -rf "$APP" build/LightTrail.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/LightTrail.iconset
cp "$BIN" "$APP/Contents/MacOS/LightTrail"

"$BIN" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out build/LightTrail.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out build/LightTrail.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/LightTrail.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LightTrail</string>
  <key>CFBundleDisplayName</key><string>LightTrail</string>
  <key>CFBundleIdentifier</key><string>dev.lighttrail.app</string>
  <key>CFBundleExecutable</key><string>LightTrail</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>A lightning trail for your mouse.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ " $* " == *" --release "* ]]; then
  rm -f build/LightTrail.zip
  ditto -c -k --norsrc --noextattr --keepParent "$APP" build/LightTrail.zip
  echo "Zipped build/LightTrail.zip"
fi

if [[ " $* " == *" --install "* ]]; then
  pkill -x LightTrail 2>/dev/null || true
  sleep 1
  rm -rf /Applications/LightTrail.app
  cp -R "$APP" /Applications/LightTrail.app
  open /Applications/LightTrail.app || { sleep 2; open /Applications/LightTrail.app; }
  echo "Installed to /Applications/LightTrail.app"
fi
