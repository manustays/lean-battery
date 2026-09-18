#!/bin/sh
# Regenerates docs/assets/menubar-*.png from the app's IconRenderer.
set -eu
out="$(mktemp -d)/sample-icons"
swiftc -O -o "$out" \
	Sources/LeanBatteryCore/BatteryState.swift \
	Sources/LeanBatteryCore/IconSpec.swift \
	Sources/LeanBatteryCore/IconRenderer.swift \
	scripts/sample-icons.swift
"$out"
