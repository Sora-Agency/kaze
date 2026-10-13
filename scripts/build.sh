#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
xcrun swift scripts/verify-rules.swift "$project_dir"
build_dir="$project_dir/build"
architecture="$(uname -m)"
sparkle_dir="$(scripts/fetch-sparkle.sh)"
binary_archive="Kaze-Mac-$architecture.zip"
disk_image="Kaze-Mac-$architecture.dmg"
package_dir="$build_dir/staging.noindex/package"
if [[ -e package && ! -L package ]]; then
  print -u2 -- "La ruta package debe ser un enlace a build/staging.noindex/package."
  exit 1
fi
mkdir -p "$build_dir/staging.noindex"
work_dir="$(mktemp -d "$build_dir/staging.noindex/run-XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
staged_package="$work_dir/package"
app="$staged_package/Kaze.app"
resources="$app/Contents/Resources"
assets="$work_dir/assets"
mkdir -p "$app/Contents/MacOS" "$resources/Icons/Lucide"
xcrun swift scripts/GenerateIcon.swift src/Brand/SoraLogo.svg "$assets"
iconutil -c icns "$assets/AppIcon.iconset" -o "$resources/AppIcon.icns"
xcrun clang -target "$(uname -m)-apple-macosx13.0" -O2 -Wall -Wextra -c src/Infrastructure/Recovery/AuthDisk.c -o "$work_dir/AuthDisk.o"
sources=(src/**/*.swift)
xcrun swiftc -swift-version 5 -I src/Infrastructure/Recovery -target "$architecture-apple-macosx13.0" -O \
  -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  "${sources[@]}" "$work_dir/AuthDisk.o" -o "$app/Contents/MacOS/Kaze"
cp src/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/Sora-Agency/kaze/releases/latest/download/appcast-$architecture.xml" "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Frameworks" "$resources/Sparkle"
ditto "$sparkle_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_dir/LICENSE" "$resources/Sparkle/LICENSE"
cp "$assets/SoraLogo.png" src/cleaner.zsh src/cleanup-lock.zsh src/localization.zsh "$resources/"
cp LICENSE TERMS.txt PRIVACY.txt THIRD_PARTY_NOTICES.txt "$resources/"
for language in en es; do
  ditto --norsrc --noextattr --noqtn "src/Localization/$language.lproj" "$resources/$language.lproj"
done
cp TERMS.txt PRIVACY.txt "$resources/es.lproj/"
cp src/Icons/Lucide/LICENSE "$resources/Icons/Lucide/"
ditto src/Fonts "$resources/Fonts"
ditto src/Rules "$resources/Rules"
ditto src/AI "$resources/AI"
ditto src/Recovery "$resources/Recovery"
chmod +x "$app/Contents/MacOS/Kaze" "$resources/cleaner.zsh"
cp src/localization.zsh src/disable-legacy-schedule.zsh src/Instalar.command src/Desinstalar.command src/README.txt src/README.es.txt "$staged_package/"
cp LICENSE TERMS.txt PRIVACY.txt THIRD_PARTY_NOTICES.txt "$staged_package/"
chmod +x "$staged_package/disable-legacy-schedule.zsh" "$staged_package/Instalar.command" "$staged_package/Desinstalar.command"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
codesign --verify --deep --strict "$app"
plutil -lint "$app/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$staged_package" "$work_dir/$binary_archive"
scripts/build-dmg.sh "$app" "$work_dir/$disk_image"
source_bundle="$work_dir/Kaze-Source"
mkdir -p "$source_bundle"
for directory in src scripts tests docs .github; do
  ditto --norsrc --noextattr --noqtn "$directory" "$source_bundle/$directory"
done
cp .gitignore .gitattributes README.md README.es.md CONTRIBUTING.md CONTRIBUTING.es.md LICENSE TERMS.txt PRIVACY.txt THIRD_PARTY_NOTICES.txt ARCHITECTURE.md "$source_bundle/"
cp src/README.txt "$source_bundle/README.txt"
cp src/README.es.txt "$source_bundle/README.es.txt"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$source_bundle" "$work_dir/Kaze-Source.zip"
rm -rf -- "$package_dir"
mv "$staged_package" "$package_dir"
mv "$work_dir/$binary_archive" "$work_dir/$disk_image" "$work_dir/Kaze-Source.zip" "$build_dir/"
if [[ -f "$build_dir/appcast-$architecture.xml" ]]; then
  rm -- "$build_dir/appcast-$architecture.xml"
fi
(cd "$build_dir" && shasum -a 256 "$disk_image" "$binary_archive" Kaze-Source.zip > "Kaze-SHA256-$architecture.txt")
if [[ ! -L package ]]; then ln -s build/staging.noindex/package package; fi
print -r -- "App: $package_dir/Kaze.app"
print -r -- "Paquete: $build_dir/$binary_archive"
print -r -- "Código fuente: $build_dir/Kaze-Source.zip"
