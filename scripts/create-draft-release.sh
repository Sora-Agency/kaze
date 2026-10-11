#!/bin/bash
set -euo pipefail
if [[ $# -ne 3 ]]; then
  echo "Uso: scripts/create-draft-release.sh tag directorio notas.md" >&2
  exit 1
fi
tag="$1"
asset_dir="$2"
notes="$3"
: "${GH_REPO:?Falta GH_REPO}"
: "${KAZE_RELEASE_COMMIT:?Falta KAZE_RELEASE_COMMIT}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
assets=(
  "$asset_dir/Kaze-Mac-arm64.dmg" "$asset_dir/Kaze-Mac-x86_64.dmg"
  "$asset_dir/Kaze-Mac-arm64.zip" "$asset_dir/Kaze-Mac-x86_64.zip"
  "$asset_dir/Kaze-Source.zip" "$asset_dir/Kaze-SHA256-arm64.txt"
  "$asset_dir/Kaze-SHA256-x86_64.txt" "$asset_dir/SHA256SUMS"
)
for asset in "${assets[@]}" "$notes"; do [[ -s "$asset" ]]; done
if draft="$(gh release view "$tag" --repo "$GH_REPO" --json isDraft --jq .isDraft 2>/dev/null)"; then
  if [[ "$draft" != true ]]; then
    echo "La release $tag ya está publicada. No se modificará." >&2
    exit 1
  fi
  gh release upload "$tag" "${assets[@]}" --repo "$GH_REPO" --clobber
else
  gh release create "$tag" "${assets[@]}" --repo "$GH_REPO" \
    --draft --verify-tag --target "$KAZE_RELEASE_COMMIT" \
    --title "Kaze ${tag#v}" --notes-file "$notes"
fi
