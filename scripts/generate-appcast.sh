#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
architecture="$(uname -m)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' src/Info.plist)"
tag="${1:-v$version}"
python3 scripts/prepare-release.py --tag "$tag" --check-only
sparkle_dir="$(scripts/fetch-sparkle.sh)"
work_dir="$(mktemp -d -t kaze-appcast)"
trap 'rm -rf -- "$work_dir"' EXIT
archive="Kaze-Mac-$architecture.dmg"
feed="appcast-$architecture.xml"
cp "build/$archive" "$work_dir/"
python3 - "$work_dir/${archive%.dmg}.html" <<'PY'
import html, pathlib, sys
notes = pathlib.Path('docs/RELEASE_NOTES.md').read_text()
pathlib.Path(sys.argv[1]).write_text('<pre>' + html.escape(notes) + '</pre>')
PY
signing_options=(--account com.soraagency.kaze)
if [[ -n "${KAZE_SPARKLE_PRIVATE_KEY:-}" ]]; then signing_options=(--ed-key-file -); fi
signing_tool() {
  if [[ -n "${KAZE_SPARKLE_PRIVATE_KEY:-}" ]]; then
    print -rn -- "$KAZE_SPARKLE_PRIVATE_KEY" | "$@"
  else
    "$@"
  fi
}
signing_tool "$sparkle_dir/bin/generate_appcast" "${signing_options[@]}" \
  --download-url-prefix "https://github.com/Sora-Agency/kaze/releases/download/$tag/" \
  --link 'https://github.com/Sora-Agency/kaze' --maximum-deltas 0 --embed-release-notes \
  -o "$work_dir/$feed" "$work_dir"
signature="$(python3 scripts/validate-appcast.py --feed "$work_dir/$feed" \
  --archive "$work_dir/$archive" --info src/Info.plist --architecture "$architecture" --tag "$tag")"
signing_tool "$sparkle_dir/bin/sign_update" "${signing_options[@]}" --verify "$work_dir/$feed"
signing_tool "$sparkle_dir/bin/sign_update" "${signing_options[@]}" --verify "$work_dir/$archive" "$signature"
cp "$work_dir/$feed" "build/$feed"
(cd build && shasum -a 256 "$archive" "Kaze-Mac-$architecture.zip" Kaze-Source.zip "$feed" > "Kaze-SHA256-$architecture.txt")
print -r -- "Feed firmado y verificado: build/$feed"
