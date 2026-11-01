#!/usr/bin/env bash
# 发布包构建脚本：把体积优化参数固化下来，避免每次手敲、也避免漏参数。
#
# 默认产出 split-per-abi 三个分包（每架构一个），另可显式要 universal 单包：
#   bash scripts/build-release.sh            # 分包：arm64-v8a / armeabi-v7a / x86_64
#   bash scripts/build-release.sh universal  # 单包：三个架构打在一起，任意设备都能装
#
# 实测体积（基线 49.8MB → 现每包 6.9–7.7MB）：
#   分包 arm64-v8a    7.5MB   绝大多数真机
#   分包 armeabi-v7a  6.9MB   32 位老机型
#   分包 x86_64       7.7MB   模拟器
#   单包 universal    21.2MB  三个架构全带，分发最省事
#   只打 arm64        7.2MB  上一版做法，单架构最小
#
# 各参数的作用：
#   --split-per-abi    每架构独立出包。libflutter.so 每 ABI 一份且未压缩时
#                      8.6–13MB，所以分包比 universal 小得多。
#   --target-platform  universal 模式下可指定架构子集，否则三架构全打。
#                      注意：必须由命令行给出。写在 gradle.properties 或
#                      defaultConfig.ndk.abiFilters 都无效——Flutter 引擎库由
#                      CopyFlutterJniLibsTask 按 target-platform 注入，绕过 ndk 过滤。
#   --split-debug-info Dart 符号表外置到 build/symbols，体积再降约 0.2MB。
#   压缩 .so（见 build.gradle.kts useLegacyPackaging）16.7MB → 7.1MB/架构。
#   去掉 WorkManager/Room/coroutines/AndroidX       dex 1.48MB → 1.02MB。
#   ProGuard 用 -keepnames 取代 -keep class io.flutter.** { *; }  dex → 0.73MB。
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-split}"
OUT="build/app/outputs/flutter-apk"

human() {
  # macOS 与 Linux 的 stat 参数不同，两者都试。
  local size
  size=$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1")
  printf "%s bytes (%.1f MB)" "$size" "$(echo "$size/1048576" | bc -l)"
}

case "$MODE" in
  split|--split-per-abi)
    echo "==> 构建 split-per-abi 分包（arm64-v8a / armeabi-v7a / x86_64）"
    flutter build apk --release \
      --split-per-abi \
      --split-debug-info=build/symbols
    echo
    echo "产物："
    for abi in arm64-v8a armeabi-v7a x86_64; do
      apk="$OUT/app-$abi-release.apk"
      [ -f "$apk" ] && printf "  %-12s %s\n" "$abi" "$(human "$apk")"
    done
    echo
    echo "按设备架构选包安装："
    echo "  adb install -r $OUT/app-arm64-v8a-release.apk    # 绝大多数真机"
    echo "  adb install -r $OUT/app-armeabi-v7a-release.apk  # 32 位老机型"
    echo "  adb install -r $OUT/app-x86_64-release.apk       # 模拟器"
    ;;
  universal|--universal)
    # 可选第二参数指定架构子集，例如 universal android-arm64,android-arm
    PLATFORM="${2:-}"
    echo "==> 构建 universal 单包${PLATFORM:+（$PLATFORM）}"
    if [ -n "$PLATFORM" ]; then
      flutter build apk --release \
        --target-platform "$PLATFORM" \
        --split-debug-info=build/symbols
    else
      flutter build apk --release --split-debug-info=build/symbols
    fi
    echo
    printf "  universal    %s\n" "$(human "$OUT/app-release.apk")"
    echo "  任意架构设备都可直接安装：adb install -r $OUT/app-release.apk"
    ;;
  *)
    echo "未知模式：$MODE" >&2
    echo "用法：bash scripts/build-release.sh [split|universal [平台子集]]" >&2
    exit 2
    ;;
esac

echo
echo "符号表：build/symbols（保留，用于 flutter symbolize 解读崩溃堆栈）"
