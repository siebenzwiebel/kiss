#!/usr/bin/env bash
set -euxo pipefail

xcodebuild -version
# Branch ui-v2: erst Simulator-Screenshots (installiert xcodegen selbst)
bash ci-screenshots.sh
rm -rf ios/build

cd ios
xcodegen generate
# xcodegen 2.45 stempelt objectVersion=77 (Xcode 16) -> auf 56 senken, damit Xcode 15.4 es lesen kann
sed -i.bak 's/objectVersion = 77;/objectVersion = 56;/' KISS.xcodeproj/project.pbxproj
rm -f KISS.xcodeproj/project.pbxproj.bak
echo "--- xcodebuild -list ---"
xcodebuild -list -project KISS.xcodeproj || true

xcodebuild -project KISS.xcodeproj -scheme KISS -configuration Release -sdk iphoneos \
  -archivePath "$PWD/build/KISS.xcarchive" archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""

cd ..
mkdir -p Payload
cp -R ios/build/KISS.xcarchive/Products/Applications/KISS.app Payload/
zip -qry KISS-unsigned.ipa Payload
# Nur ui-v2: Screenshots ins hochgeladene Archiv, vor dem Installieren wieder entfernen
zip -qry KISS-unsigned.ipa shots
echo "fertig: $(ls -la KISS-unsigned.ipa)"
