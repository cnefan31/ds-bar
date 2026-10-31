#!/usr/bin/env bash
# 预下载 Flutter 引擎的 Maven 产物到 .flutter-m2，规避 storage.googleapis.com 直连限速。
#
# 背景：Gradle 从 storage.googleapis.com/download.flutter.io 拉 flutter_embedding_* 与
# <abi>_debug/release 的 jar，国内直连常被限到 100KB/s 以下，一次构建要等半小时以上。
# curl 走同一域名时速度正常，因此先用 curl 并发拉好，再当作本地 maven 仓库供 Gradle 使用。
#
# 用法：bash scripts/prefetch-flutter-engine.sh [debug|release|profile]
set -euo pipefail

MODE="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# /opt/homebrew/bin/flutter 是 symlink，必须解析到真实安装目录。
FLUTTER="${FLUTTER_ROOT:-$(cd "$(dirname "$(readlink -f "$(command -v flutter)")")/.." && pwd)}"
ENGINE="$(cat "$FLUTTER/bin/cache/engine.stamp" 2>/dev/null || cat "$FLUTTER/bin/internal/engine.version")"
BASE="https://storage.googleapis.com/download.flutter.io"
OUT="$ROOT/.flutter-m2"

if [[ -z "$ENGINE" ]]; then
  echo "无法确定 Flutter engine 版本，检查 $FLUTTER" >&2
  exit 1
fi

# 与 android/app/build.gradle.kts 的 abiFilters 对应；全量拉取代价小，直接覆盖三种 ABI。
ARTIFACTS=(
  "flutter_embedding_${MODE}"
  "arm64_v8a_${MODE}"
  "armeabi_v7a_${MODE}"
  "x86_64_${MODE}"
)

mkdir -p "$OUT"
for name in "${ARTIFACTS[@]}"; do
  ver="1.0.0-${ENGINE}"
  dir="$OUT/io/flutter/${name}/${ver}"
  mkdir -p "$dir"
  for ext in jar pom; do
    target="$dir/${name}-${ver}.${ext}"
    if [[ -s "$target" ]]; then
      echo "skip ${name}.${ext}"
      continue
    fi
    echo "fetch ${name}.${ext}"
    curl -fsSL --retry 3 -o "$target.part" "$BASE/io/flutter/${name}/${ver}/${name}-${ver}.${ext}"
    mv "$target.part" "$target"
  done
done

echo "完成：$OUT（$(du -sh "$OUT" | cut -f1)）"
echo "Gradle 会自动优先使用该目录（见 android/build.gradle.kts）。"
