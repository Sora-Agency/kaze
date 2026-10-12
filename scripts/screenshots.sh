#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d package/Kaze.app ]]; then scripts/build.sh; fi
output_dir="$PWD/docs/images"
mkdir -p "$output_dir"
work_dir="$(mktemp -d -t kaze-screenshots)"
trap 'rm -rf -- "$work_dir"' EXIT
sources=(src/**/*.swift)
xcrun swiftc -swift-version 5 -D KAZE_PREVIEW -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" tests/Preview.swift tests/PreviewFixtures.swift -o "$work_dir/preview"
export KAZE_LOCALIZATION_RESOURCES="$PWD/src/Localization"
for language in es en; do
  export KAZE_LANGUAGE="$language"
  language_dir="$output_dir"
  if [[ "$language" == en ]]; then language_dir="$output_dir/en"; fi
  mkdir -p "$language_dir"
  "$work_dir/preview" "$language_dir/smart-dark.png" --dark --smart --access-granted
  "$work_dir/preview" "$language_dir/assistant-dark.png" --dark --assistant
  "$work_dir/preview" "$language_dir/assistant-ready-dark.png" --dark --assistant --assistant-ready
  "$work_dir/preview" "$language_dir/map-light.png" --map --access-granted
  "$work_dir/preview" "$language_dir/explorer-dark.png" --dark
  "$work_dir/preview" "$language_dir/explorer-light.png"
  "$work_dir/preview" "$language_dir/cleanup-dark.png" --dark --cleanup
  "$work_dir/preview" "$language_dir/scheduled-tasks-light.png" --scheduled --weekly
  "$work_dir/preview" "$language_dir/task-editor-dark.png" --dark --scheduled --editor --weekly --full-editor
  "$work_dir/preview" "$language_dir/safety-light.png" --caches
done
print -r -- "Screenshots / Capturas: $output_dir"
