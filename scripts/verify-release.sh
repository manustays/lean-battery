#!/bin/sh
# Refuses to let a wrong bundle or zip be published. Usage: scripts/verify-release.sh <version>
set -eu
version="${1:?usage: verify-release.sh <version>}"
app="LeanBattery.app"
zip="dist/LeanBattery-$version.zip"
fail() { echo "release check failed: $*" >&2; exit 1; }

[ -d "$app" ] || fail "$app is missing"
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ "$plist_version" = "$version" ] || fail "bundle says $plist_version, release is $version"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "am.abhi.leanbattery" ] \
	|| fail "wrong bundle identifier"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" = "26.0" ] \
	|| fail "LSMinimumSystemVersion is not 26.0"
[ "$(lipo -archs "$app/Contents/MacOS/LeanBattery")" = "arm64" ] || fail "executable is not arm64-only"
codesign --verify --deep --strict "$app" || fail "codesign verification failed"

[ -s "$zip" ] || fail "$zip is missing or empty"
unzip -l "$zip" >/dev/null 2>&1 || fail "$zip is not a valid zip"
root="$(unzip -Z1 "$zip" | sed -e 's|/.*||' | sort -u)"
[ "$root" = "LeanBattery.app" ] || fail "zip root is '$root', expected LeanBattery.app"
sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
echo "$sha" | grep -Eq '^[0-9a-f]{64}$' || fail "sha256 is not 64 hex chars: $sha"
echo "ok $zip sha256=$sha"
