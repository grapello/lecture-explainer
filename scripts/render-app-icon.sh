#!/bin/sh
# Renders the app icon from LexiaLogo, the same SwiftUI view as the loading
# screen's logo, into Assets.xcassets/AppIcon.appiconset. Run it again after
# changing LexiaLogo.swift:
#
#     scripts/render-app-icon.sh
set -e
cd "$(dirname "$0")/.."
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
swiftc -parse-as-library -O \
    scripts/RenderAppIcon.swift Lecture-Explainer/Views/LexiaLogo.swift \
    -o "$build/render-app-icon"
"$build/render-app-icon" Lecture-Explainer/Assets.xcassets/AppIcon.appiconset
