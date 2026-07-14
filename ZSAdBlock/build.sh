#!/usr/bin/env bash
# 编译 ZSAdBlock.dylib（arm64，真机）—— 需在 macOS + Xcode 命令行工具环境执行
# Windows 用户请走 GitHub Actions（见 .github/workflows/build-dylib.yml）
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
OUT="ZSAdBlock.dylib"

echo ">> SDK: $SDK"
echo ">> 编译 $OUT ..."

"$CLANG" -arch arm64 -dynamiclib \
  -isysroot "$SDK" \
  -miphoneos-version-min=12.0 \
  -fobjc-arc \
  -fblocks \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -install_name "@executable_path/ZSAdBlock.dylib" \
  -o "$OUT" ZSAdBlock.m

echo ">> 伪签名（ldid，供后续重签名工具再替换）"
if command -v ldid >/dev/null 2>&1; then
  ldid -S "$OUT"
elif command -v codesign >/dev/null 2>&1; then
  codesign -f -s - "$OUT" || true
fi

echo ">> 完成：$(pwd)/$OUT"
file "$OUT" || true
