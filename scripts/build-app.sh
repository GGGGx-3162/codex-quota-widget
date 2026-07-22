#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/build/CodexGauge.app"
scratch_dir="${TMPDIR:-/private/tmp}/CodexGaugeSwiftBuild"
module_cache="${TMPDIR:-/private/tmp}/CodexGaugeModuleCache"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -n "${CODEX_GAUGE_SDKROOT:-}" ]]; then
    sdk_path="$CODEX_GAUGE_SDKROOT"
elif [[ -d "$fallback_sdk" ]]; then
    # This fallback also handles beta Command Line Tools whose default SDK and
    # compiler versions do not match.
    sdk_path="$fallback_sdk"
else
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi

cd "$project_dir"
mkdir -p "$scratch_dir" "$module_cache"

SDKROOT="$sdk_path" \
CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
swift build -c release --disable-sandbox --scratch-path "$scratch_dir"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$scratch_dir/release/CodexGauge" "$app_dir/Contents/MacOS/CodexGauge"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
chmod +x "$app_dir/Contents/MacOS/CodexGauge"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
