#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
sparkle_dir="$(scripts/fetch-sparkle.sh)"
work_dir="$(mktemp -d -t kaze-updater-tests)"
trap 'rm -rf -- "$work_dir"' EXIT
app="$work_dir/Kaze.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp src/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.soraagency.kaze.updater-test.$RANDOM.$RANDOM" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$app/Contents/Info.plist"
ditto "$sparkle_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  src/Localization/L10n.swift src/Infrastructure/AppUpdater.swift tests/UpdaterTests.swift \
  -o "$app/Contents/MacOS/Kaze"
codesign --force --sign - "$app"
"$app/Contents/MacOS/Kaze"
