#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/module-cache .local/swift-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.local/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.local/module-cache"
swift test --disable-sandbox --cache-path "$PWD/.local/swift-cache"
