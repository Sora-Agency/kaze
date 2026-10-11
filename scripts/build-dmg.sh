#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if (( $# != 2 )); then
  print -u2 -- "Uso: scripts/build-dmg.sh Kaze.app salida.dmg"
  exit 1
fi
app="${1:A}"
output="${2:A}"
codesign --verify --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.soraagency.kaze ]]
work_dir="$(mktemp -d -t kaze-dmg)"
mount_path=""
cleanup() {
  if [[ -n "$mount_path" ]] && ! python3 "$project_dir/scripts/detach-image.py" "$work_dir/writable.dmg"; then
    print -u2 -- "Se conservó el disco temporal en $work_dir."
    return
  fi
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/payload"
ditto "$app" "$work_dir/payload/Kaze.app"
ln -s /Applications "$work_dir/payload/Applications"
xcrun clang -Wno-deprecated-declarations -c "$project_dir/scripts/DMGAlias.c" -o "$work_dir/alias.o"
xcrun swiftc -swift-version 5 -import-objc-header "$project_dir/scripts/DMGAlias.h" \
  "$project_dir/scripts/GenerateDMG.swift" "$work_dir/alias.o" -framework CoreServices -o "$work_dir/layout"
payload_kib="$(du -sk "$work_dir/payload" | awk '{print $1}')"
image_kib=$((payload_kib + 16384))
hdiutil create -size "${image_kib}k" -srcfolder "$work_dir/payload" -volname Kaze -fs HFS+ -format UDRW -ov "$work_dir/writable.dmg" >/dev/null
mkdir -p "$work_dir/volume"
hdiutil attach -nobrowse -noautoopen -mountpoint "$work_dir/volume" -plist "$work_dir/writable.dmg" > "$work_dir/mount.plist"
mount_path="$("$work_dir/layout" mount-point "$work_dir/mount.plist")"
cp "$app/Contents/Resources/AppIcon.icns" "$mount_path/.VolumeIcon.icns"
xcrun SetFile -a C "$mount_path"
"$work_dir/layout" layout "$mount_path"
python3 "$project_dir/scripts/detach-image.py" "$work_dir/writable.dmg"
mount_path=""
hdiutil convert "$work_dir/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$work_dir/Kaze.dmg" >/dev/null
hdiutil verify "$work_dir/Kaze.dmg" >/dev/null
mkdir -p "${output:h}"
mv -f "$work_dir/Kaze.dmg" "$output"
print -r -- "DMG: $output"
