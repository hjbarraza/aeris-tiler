#!/bin/bash
# Build Aeris Tiler into ~/Applications/Aeris Tiler.app, sign it, and link the command line
# tool to ~/.local/bin/aeris-tiler.
#   ./build.sh          build and install
#   ./build.sh run      build, install and (re)start the app
#   ./build.sh cert     create a local signing certificate, once (see below)
#
# Signing: macOS ties the Accessibility permission to the app's signature. An ad-hoc signature
# changes with every build, so each build would need the permission again. `./build.sh cert`
# makes a self-signed certificate in its own keychain (~/Library/Keychains/aeris-signing);
# builds signed with it keep the permission. Set SIGN_ID to use a Developer ID instead.

set -euo pipefail
cd "$(dirname "$0")"

name="Aeris Tiler Local Signing"
keychain="$HOME/Library/Keychains/aeris-signing.keychain-db"
pass=aeris   # guards a key that can only sign local builds of this app

if [[ ${1:-} == cert ]]; then
  tmp=$(mktemp -d)
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$name" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass"
  security create-keychain -p "$pass" "$keychain"
  security set-keychain-settings "$keychain"   # no auto-lock
  security unlock-keychain -p "$pass" "$keychain"
  security import "$tmp/id.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$pass" "$keychain" >/dev/null
  # Add it to the keychains macOS searches, keeping the ones already there.
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
  rm -rf "$tmp"
  echo "created signing identity \"$name\" in $keychain"
  exit 0
fi

swift build -c release
bin=.build/release/AerisTiler
app="$HOME/Applications/Aeris Tiler.app"
pkill -x AerisTiler 2>/dev/null || true
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/AerisTiler"

iconset=$(mktemp -d)/AppIcon.iconset
"$bin" make-icon "$iconset" && iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AerisTiler</string>
<key>CFBundleIdentifier</key><string>com.aeris.tiler</string>
<key>CFBundleName</key><string>Aeris Tiler</string>
<key>CFBundleDisplayName</key><string>Aeris Tiler</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [[ -n ${SIGN_ID:-} ]]; then
  codesign --force --sign "$SIGN_ID" "$app"
elif [[ -f $keychain ]]; then
  security unlock-keychain -p "$pass" "$keychain"
  codesign --force --sign "$name" --keychain "$keychain" "$app"
else
  echo "no signing identity: ad-hoc signature (run ./build.sh cert once to keep the Accessibility permission across builds)"
  codesign --force --sign - "$app"
fi

mkdir -p "$HOME/.local/bin"
ln -sf "$app/Contents/MacOS/AerisTiler" "$HOME/.local/bin/aeris-tiler"
echo "installed $app"
if [[ ${1:-} == run ]]; then open "$app"; fi
