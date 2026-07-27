#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"

"$CLANG" -arch arm64 -dynamiclib \
  -isysroot "$SDK" \
  -miphoneos-version-min=12.0 \
  -fobjc-arc -fblocks \
  -framework UIKit -framework Foundation \
  -install_name "@executable_path/TransformDiagnostic.dylib" \
  -o TransformDiagnostic.dylib TransformDiagnostic.m

codesign -f -s - TransformDiagnostic.dylib || true
file TransformDiagnostic.dylib
test -s TransformDiagnostic.dylib
