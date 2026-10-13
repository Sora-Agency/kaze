#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d package/Kaze.app ]]; then scripts/build.sh; fi
preview_dir="$PWD/build/previews"
mkdir -p "$preview_dir"
work_dir="$(mktemp -d -t kaze-preview)"
trap 'rm -rf -- "$work_dir"' EXIT
xcrun clang -target "$(uname -m)-apple-macosx13.0" -O2 -Wall -Wextra -c src/Infrastructure/Recovery/AuthDisk.c -o "$work_dir/AuthDisk.o"
sources=(src/**/*.swift)
xcrun swiftc -swift-version 5 -I src/Infrastructure/Recovery -D KAZE_PREVIEW -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" "$work_dir/AuthDisk.o" tests/Preview.swift tests/PreviewFixtures.swift -o "$work_dir/preview"
export KAZE_LOCALIZATION_RESOURCES="$PWD/src/Localization"
export KAZE_LANGUAGE="${KAZE_LANGUAGE:-es}"
if [[ "${1:-}" == "--management-only" ]]; then
  for section in recovery startup; do
    "$work_dir/preview" "$preview_dir/Kaze-$section-dark.png" --dark "--$section" --compact
    "$work_dir/preview" "$preview_dir/Kaze-$section-light.png" "--$section" --compact
  done
  "$work_dir/preview" "$preview_dir/Kaze-recovery-browser.png" --dark --recovery --recovery-browser --compact
  exit 0
fi
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
"$work_dir/preview" "$preview_dir/Kaze-smart-dark.png" --dark --smart --access-granted
"$work_dir/preview" "$preview_dir/Kaze-smart-light.png" --smart --access-granted
"$work_dir/preview" "$preview_dir/Kaze-map-dark.png" --dark --map --access-granted
"$work_dir/preview" "$preview_dir/Kaze-map-light.png" --map --access-granted
for section in duplicates system-data development assistant rules history; do
  "$work_dir/preview" "$preview_dir/Kaze-$section-dark.png" --dark "--$section" --access-granted
done

"$work_dir/preview" "$preview_dir/Kaze-smart-busy.png" --dark --smart --compact --scanning
"$work_dir/preview" "$preview_dir/Kaze-assistant-light.png" --assistant --compact
"$work_dir/preview" "$preview_dir/Kaze-assistant-ready.png" --dark --assistant --assistant-ready --compact

"$work_dir/preview" "$preview_dir/Kaze-assistant-welcome.png" --dark --assistant --assistant-ready --assistant-empty --compact
"$work_dir/preview" "$preview_dir/Kaze-assistant-actions-dark.png" --dark --assistant --assistant-ready --assistant-actions
"$work_dir/preview" "$preview_dir/Kaze-assistant-actions-light.png" --assistant --assistant-ready --assistant-actions
"$work_dir/preview" "$preview_dir/Kaze-assistant-activity-dark.png" --dark --assistant --assistant-ready --assistant-actions --assistant-activity-expanded
"$work_dir/preview" "$preview_dir/Kaze-assistant-loading-dark.png" --dark --assistant --assistant-ready --assistant-running --assistant-activity-expanded

"$work_dir/preview" "$preview_dir/Kaze-assistant-disclosure-motion.png" --dark --assistant --assistant-ready --assistant-actions --assistant-disclosure-toggle --assistant-disclosure-mid
"$work_dir/preview" "$preview_dir/Kaze-assistant-conversation.png" --dark --assistant --assistant-ready --assistant-actions --assistant-memory

for section in recovery startup; do
  "$work_dir/preview" "$preview_dir/Kaze-$section-dark.png" --dark "--$section" --compact
  "$work_dir/preview" "$preview_dir/Kaze-$section-light.png" "--$section" --compact
done
"$work_dir/preview" "$preview_dir/Kaze-recovery-browser.png" --dark --recovery --recovery-browser --compact
