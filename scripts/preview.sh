#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d package/Kaze.app ]]; then scripts/build.sh; fi
preview_dir="$PWD/build/previews"
mkdir -p "$preview_dir"
work_dir="$(mktemp -d -t kaze-preview)"
trap 'rm -rf -- "$work_dir"' EXIT
sources=(src/**/*.swift)
xcrun swiftc -swift-version 5 -D KAZE_PREVIEW -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" tests/Preview.swift tests/PreviewFixtures.swift -o "$work_dir/preview"
export KAZE_LOCALIZATION_RESOURCES="$PWD/package/Kaze.app/Contents/Resources"
export KAZE_LANGUAGE="${KAZE_LANGUAGE:-es}"
"$work_dir/preview" "$preview_dir/Kaze-preview-dark.png" --dark
"$work_dir/preview" "$preview_dir/Kaze-preview-light.png" --compact
"$work_dir/preview" "$preview_dir/Kaze-legal-preview.png" --dark --legal
"$work_dir/preview" "$preview_dir/Kaze-cleanup-preview.png" --dark --cleanup --compact
"$work_dir/preview" "$preview_dir/Kaze-safety-preview.png" --dark --caches
"$work_dir/preview" "$preview_dir/Kaze-legal-light-preview.png" --legal --compact
"$work_dir/preview" "$preview_dir/Kaze-schedule-preview.png" --dark --scheduled --compact
"$work_dir/preview" "$preview_dir/Kaze-schedule-light-preview.png" --scheduled --weekly --compact
"$work_dir/preview" "$preview_dir/Kaze-task-editor-preview.png" --dark --scheduled --editor --weekly
"$work_dir/preview" "$preview_dir/Kaze-task-editor-light-preview.png" --scheduled --editor --weekly
"$work_dir/preview" "$preview_dir/Kaze-input-focused-light-preview.png" --scheduled --editor --focus-input
"$work_dir/preview" "$preview_dir/Kaze-input-focused-dark-preview.png" --dark --scheduled --editor --focus-input
"$work_dir/preview" "$preview_dir/Kaze-input-disabled-light-preview.png" --scheduled --editor --inactive-condition
"$work_dir/preview" "$preview_dir/Kaze-input-disabled-dark-preview.png" --dark --scheduled --editor --inactive-condition
