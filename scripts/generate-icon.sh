#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
source_png="$repo_dir/assets/AppIcon-1024.png"
iconset_dir="$repo_dir/.build/AppIcon.iconset"
output_icns="$repo_dir/assets/AppIcon.icns"

mkdir -p "$repo_dir/assets" "$iconset_dir"
find "$iconset_dir" -type f -name '*.png' -delete
rm -f "$output_icns"

swift "$repo_dir/scripts/generate-icon.swift" "$source_png"

function render_icon {
    local pixels=$1
    local filename=$2
    sips -z "$pixels" "$pixels" "$source_png" \
        --out "$iconset_dir/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1_024 icon_512x512@2x.png

iconutil -c icns "$iconset_dir" -o "$output_icns"
print "Generated $output_icns"
