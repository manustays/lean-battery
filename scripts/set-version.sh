#!/bin/sh
# Stamps a release version into Resources/Info.plist. Called by semantic-release's prepareCmd.
# Usage: scripts/set-version.sh 1.2.3
set -eu
version="${1:?usage: set-version.sh <version>}"
case "$version" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*) echo "not a three-part version: $version" >&2; exit 1 ;;
esac
plist="Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$plist"
echo "stamped $version into $plist"
