#!/bin/sh
# Builds Resources/AppIcon.icns from a 1024x1024 Resources/AppIcon.png.
# ponytail: sips + iconutil are already on every Mac; no asset catalog, no tooling.
set -eu
src="Resources/AppIcon.png"
[ -f "$src" ] || { echo "no $src — skipping icon" >&2; exit 0; }
set="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set"
for size in 16 32 128 256 512; do
	sips -z $size $size "$src" --out "$set/icon_${size}x${size}.png" >/dev/null
	sips -z $((size * 2)) $((size * 2)) "$src" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "built Resources/AppIcon.icns"
