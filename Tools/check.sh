#!/bin/bash
# Headless checks that need no Xcode project or signing — only the command line
# tools. Runs the list-editing tests, then renders Tools/sample.md light and dark
# (plus with the caret on line 2) to /tmp/nota-preview-*.png for a visual check.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=(Nota/Design/*.swift Nota/Views/NoteTextView.swift)
FLAGS=(-parse-as-library -swift-version 6 -default-isolation MainActor -target arm64-apple-macos26.0)
out=$(mktemp -d)
swiftc "${FLAGS[@]}" Tools/EditTests.swift "${SRC[@]}" -o "$out/edit-tests"
"$out/edit-tests"
swiftc "${FLAGS[@]}" Tools/RenderPreview.swift "${SRC[@]}" -o "$out/render"
"$out/render" Tools/sample.md /tmp/nota-preview-light.png
"$out/render" Tools/sample.md /tmp/nota-preview-dark.png -1 dark
"$out/render" Tools/sample.md /tmp/nota-preview-caret.png 60
echo "previews: /tmp/nota-preview-{light,dark,caret}.png"
