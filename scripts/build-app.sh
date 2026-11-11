#!/bin/zsh
# Builds a universal "CW Notebook.app" into ./build. Pass --install to copy it to ~/Applications,
# or --zip to make build/CWNotebook-<version>.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary: build each architecture, then join them with lipo.
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx15.0"
done
BIN=".build/universal/CWNotebook"
mkdir -p .build/universal
lipo -create -output "$BIN" .build/arm64-apple-macosx/release/CWNotebook .build/x86_64-apple-macosx/release/CWNotebook
APP="build/CW Notebook.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CWNotebook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"   # ad-hoc signature, fine for running on your own Macs
echo "Built $APP"

if [[ "${1:-}" == "--zip" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  ZIP="build/CWNotebook-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Zipped $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"CW Notebook.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/CW Notebook.app"
fi
