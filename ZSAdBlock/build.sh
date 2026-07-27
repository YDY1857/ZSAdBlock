#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"

"$CLANG" -arch arm64 -dynamiclib \
  -isysroot "$SDK" \
  -miphoneos-version-min=12.0 \
  -fobjc-arc -fblocks \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  -install_name "@executable_path/ZSAdBlock.dylib" \
  -o ZSAdBlock.dylib ZSAdBlock.m welcome_popup.m

codesign -f -s - ZSAdBlock.dylib || true
file ZSAdBlock.dylib
test -s ZSAdBlock.dylib
