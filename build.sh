#!/bin/zsh
# Builds build/LightTrail.app (release build configuration).
#   --install   copy it to /Applications and launch it
#   --release   build for both Apple silicon and Intel, notarize it, and zip it up as build/LightTrail.zip
#
# Signing: uses the "Developer ID Application" certificate in your keychain, or $LIGHTTRAIL_SIGN_IDENTITY.
# Without one (or with LIGHTTRAIL_SIGN_IDENTITY=-) the app is ad-hoc signed, which is fine for running it yourself.
# Notarizing (--release with a Developer ID) needs notarytool credentials, saved once:
#   xcrun notarytool store-credentials lighttrail --apple-id <your Apple ID> --team-id <your team ID>
# Set $LIGHTTRAIL_NOTARY_PROFILE to use a profile name other than "lighttrail".
set -euo pipefail
cd "$(dirname "$0")"

RELEASE=0
[[ " $* " == *" --release "* ]] && RELEASE=1
ARCHS=()
(( RELEASE )) && ARCHS=(--arch arm64 --arch x86_64)
IDENTITY=${LIGHTTRAIL_SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Developer ID Application: /{print $2; exit}' || true)}
[[ -z $IDENTITY ]] && IDENTITY=-

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
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>A lightning trail for your mouse.</string>
</dict>
</plist>
PLIST

if [[ $IDENTITY == - ]]; then
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc signed)"
else
  # Hardened runtime and a secure timestamp are what notarization asks for. The timestamp needs the
  # network, so everyday builds skip it.
  TIMESTAMP=--timestamp=none
  (( RELEASE )) && TIMESTAMP=--timestamp
  codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
  echo "Built $APP (signed by $IDENTITY)"
fi

if (( RELEASE )); then
  rm -f build/LightTrail.zip
  if [[ $IDENTITY == - ]]; then
    echo "Note: no Developer ID certificate, so build/LightTrail.zip won't be notarized." >&2
  else
    PROFILE=${LIGHTTRAIL_NOTARY_PROFILE:-lighttrail}
    echo "Sending it to Apple to notarize (usually a minute or two)…"
    ditto -c -k --keepParent "$APP" build/notarize.zip
    if ! RESULT=$(xcrun notarytool submit build/notarize.zip --keychain-profile "$PROFILE" --wait --output-format json); then
      echo "Couldn't reach the notary service. Saved credentials as \"$PROFILE\"? See the top of build.sh." >&2
      exit 1
    fi
    rm build/notarize.zip
    if [[ $(plutil -extract status raw -o - - <<< "$RESULT") != Accepted ]]; then
      echo "$RESULT" >&2
      xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$RESULT")" --keychain-profile "$PROFILE" >&2
      exit 1
    fi
    xcrun stapler staple -q "$APP"
    spctl --assess --type execute "$APP"
    echo "Notarized"
  fi
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
