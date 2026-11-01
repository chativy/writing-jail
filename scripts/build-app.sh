#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app_dir="$repo_dir/dist/Writing Jail.app"
export CLANG_MODULE_CACHE_PATH="$repo_dir/.build/clang-module-cache"

swift_build() {
    swift "$@" \
        --disable-sandbox \
        --cache-path "$repo_dir/.build/swiftpm-cache" \
        --config-path "$repo_dir/.build/swiftpm-config" \
        --scratch-path "$repo_dir/.build/swiftpm" \
        --manifest-cache local
}

cd "$repo_dir"
if [[ ! -f "$repo_dir/assets/AppIcon.icns" ]]; then
    "$repo_dir/scripts/generate-icon.sh"
fi

swift_build build -c release -debug-info-format none
bin_dir=$(swift_build build -c release -debug-info-format none --show-bin-path)

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/WritingJail" "$app_dir/Contents/MacOS/WritingJail"
install -m 644 "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
rm -f "$app_dir/Contents/Resources/AppIcon.icns"
install -m 644 "$repo_dir/assets/AppIcon.icns" "$app_dir/Contents/Resources/WritingJailIcon.icns"
touch "$app_dir"
codesign \
    --force \
    --sign - \
    --requirements '=designated => identifier "local.writingjail.app"' \
    "$app_dir"

echo "Built $app_dir"
