#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
APP_DIR="$PROJECT_DIR/dist/UTHSEB.app"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
# This machine currently has a newer Swift compiler paired with an older 26.x
# SDK module interface. The installed 15.4 SDK is compatible with the compiler
# and still supports the deployment target used by this app.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
  SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE"
cp "$SCRIPT_DIR/UTHSEB/Info.plist" "$APP_DIR/Contents/Info.plist"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx12.0 \
  -O \
  -framework AppKit \
  -framework WebKit \
  -framework CryptoKit \
  -o "$APP_DIR/Contents/MacOS/UTHSEB" \
  "$SCRIPT_DIR/UTHSEB/AppDelegate.swift" \
  "$SCRIPT_DIR/UTHSEB/main.swift"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
