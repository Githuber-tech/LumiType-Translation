#!/usr/bin/env bash
# 编译包装：把 .build 放到本地缓存目录。
# 本工程在 OneDrive 同步盘上，SwiftPM 的 .build 有数万文件、数百 MB，
# 直接生成在同步目录会拖垮同步并产生冲突副本。
set -euo pipefail
SCRATCH="${LUMITYPE_SCRATCH:-$HOME/Library/Caches/LumiTypeBuild}"
exec swift build --scratch-path "$SCRATCH" "$@"
