#!/usr/bin/env bash
# 发布包构建脚本：把体积优化参数固化下来，避免每次手敲、也避免漏参数。
#
# 各参数的作用与实测收益（基线 49.8MB → 7.2MB）：
#   --target-platform android-arm64   只打 arm64。libflutter.so 每 ABI 一份且未压缩
#                                     时 8.6–13MB，三 ABI 全打 22.5MB vs 单 ABI 7.6MB。
#   --split-debug-info                Dart 符号表外置到 build/symbols，体积再降约 0.2MB。
#   压缩 .so（见 build.gradle.kts useLegacyPackaging） 16.7MB → 7.1MB。
#   去掉 WorkManager/Room/coroutines/AndroidX        dex 1.48MB → 1.02MB。
#   ProGuard 用 -keepnames 取代 -keep class io.flutter.** { *; }  dex 1.02MB → 0.73MB。
#
# 注意：--target-platform 必须由命令行给出。写在 gradle.properties 或
# defaultConfig.ndk.abiFilters 都无效——Flutter 引擎库由
# CopyFlutterJniLibsTask 按 target-platform 注入，绕过 ndk 过滤。
set -euo pipefail

cd "$(dirname "$0")/.."

PLATFORM="${1:-android-arm64}"

echo "==> 构建平台: $PLATFORM"
flutter build apk --release \
  --target-platform "$PLATFORM" \
  --split-debug-info=build/symbols

APK="build/app/outputs/flutter-apk/app-release.apk"
SIZE=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")
echo
echo "APK: $APK"
printf "体积: %s bytes (%.1f MB)\n" "$SIZE" "$(echo "$SIZE/1048576" | bc -l)"
echo "符号表: build/symbols（保留，用于 flutter symbolize 解读崩溃堆栈）"
