#!/usr/bin/env bash
# Baut die App fuer den Simulator und fotografiert jeden Bildschirm (Startargument -shot).
set -euxo pipefail
brew install xcodegen
cd ios
xcodegen generate
sed -i.bak 's/objectVersion = 77;/objectVersion = 56;/' KISS.xcodeproj/project.pbxproj
xcodebuild -project KISS.xcodeproj -scheme KISS -configuration Debug -sdk iphonesimulator \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP=build/Build/Products/Debug-iphonesimulator/KISS.app
UDID=$(xcrun simctl create kissshot com.apple.CoreSimulator.SimDeviceType.iPhone-15)
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 || true
cd ..
mkdir -p shots
for s in welcome code connect guide1 guide2 guide3 guide4 home waiting settings; do
  xcrun simctl terminate "$UDID" dev.drewers.kiss || true
  xcrun simctl launch "$UDID" dev.drewers.kiss -shot "$s"
  sleep 6
  xcrun simctl io "$UDID" screenshot "shots/$s.png"
done
ls -la shots
