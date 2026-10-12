#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Pin both the version and its published SHA-256; never execute an unverified download.
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
dependency_dir="$PWD/build/dependencies"
destination="$dependency_dir/Sparkle-$version"
if [[ -f "$destination/.verified-$checksum" && -d "$destination/Sparkle.framework" ]]; then
  print -r -- "$destination"
  exit 0
fi
mkdir -p "$dependency_dir"
work_dir="$(mktemp -d "$dependency_dir/sparkle-XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
  -o "$work_dir/Sparkle.tar.xz"
actual="$(shasum -a 256 "$work_dir/Sparkle.tar.xz")"
[[ "${actual%% *}" == "$checksum" ]] || { print -u2 'Sparkle: SHA-256 incorrecto.'; exit 1; }
mkdir "$work_dir/distribution"
tar -xf "$work_dir/Sparkle.tar.xz" -C "$work_dir/distribution"
# Keep the signed framework, release tools and license. The demo app and
# upstream debugging symbols are not used by Kaze's build or release workflow.
rm -rf -- "$work_dir/distribution/Sparkle Test App.app" "$work_dir/distribution/Symbols"
touch "$work_dir/distribution/.verified-$checksum"
rm -rf -- "$destination"
mv "$work_dir/distribution" "$destination"
print -r -- "$destination"
