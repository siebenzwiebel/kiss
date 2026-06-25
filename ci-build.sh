#!/usr/bin/env bash
set -euxo pipefail

xcodebuild -version
brew install xcodegen

cd ios
xcodegen generate
ls -la
echo "--- project.pbxproj (head) ---"
head -25 KISS.xcodeproj/project.pbxproj || true
echo "--- xcodebuild -list ---"
xcodebuild -list -project KISS.xcodeproj || true

xcodebuild -project KISS.xcodeproj -scheme KISS -configuration Release -sdk iphoneos \
  -archivePath "$PWD/build/KISS.xcarchive" archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""

cd ..
mkdir -p Payload
cp -R ios/build/KISS.xcarchive/Products/Applications/KISS.app Payload/
zip -qry KISS-unsigned.ipa Payload
echo "fertig: $(ls -la KISS-unsigned.ipa)"
