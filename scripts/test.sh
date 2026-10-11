#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export KAZE_LANGUAGE=es
export KAZE_LOCALIZATION_RESOURCES="$PWD/src/Localization"
test_dir="$(mktemp -d -t kaze-tests)"
trap 'rm -rf -- "$test_dir"' EXIT
swift_flags=(-swift-version 5 -target "$(uname -m)-apple-macosx13.0")
explorer_sources=(
  src/Domain/DeletionSafety.swift src/Domain/Formatting.swift src/Domain/FileModels.swift
  src/Infrastructure/DiskScanner.swift src/Features/Explorer/FileExplorerModel.swift
)
schedule_sources=(
  src/App/AppIdentity.swift src/Domain/ScheduledCleanupTask.swift
  src/Infrastructure/LaunchCommandRunner.swift src/Infrastructure/ScheduleService.swift
  src/Features/ScheduledTasks/ScheduledTaskModel.swift
)
run_swift_test() {
  local test_name="$1"
  shift
  xcrun swiftc "${swift_flags[@]}" src/Localization/L10n.swift "$@" "tests/$test_name.swift" -o "$test_dir/$test_name"
  "$test_dir/$test_name"
}
for test_name in ScannerTests ExplorerModelTests DeletionSafetyTests; do
  run_swift_test "$test_name" "${explorer_sources[@]}"
done
run_swift_test ScheduleTests "${schedule_sources[@]}"
run_swift_test IdentityTests src/App/AppIdentity.swift
xcrun swiftc "${swift_flags[@]}" src/Localization/L10n.swift src/Domain/ScheduledCleanupTask.swift \
  tests/LocalizationTests.swift -o "$test_dir/LocalizationTests"
for language in en es; do
  KAZE_LANGUAGE="$language" "$test_dir/LocalizationTests"
done
python3 tests/LocalizationCatalogTests.py
tests/LocalizationRuntimeTests.zsh
sources=(src/**/*.swift)
xcrun swiftc "${swift_flags[@]}" -D KAZE_PREVIEW "${sources[@]}" \
  tests/PreviewFixtures.swift tests/PreviewPrivacyTests.swift -o "$test_dir/PreviewPrivacyTests"
"$test_dir/PreviewPrivacyTests"
xcrun swiftc "${swift_flags[@]}" -D KAZE_PREVIEW "${sources[@]}" \
  tests/PreviewFixtures.swift tests/LanguageSwitchTests.swift -o "$test_dir/LanguageSwitchTests"
"$test_dir/LanguageSwitchTests"
tests/LegacyScheduleTests.zsh
tests/CleanerLockTests.zsh
python3 tests/ReleaseTests.py
python3 tests/DetachImageTests.py
for script in src/*.command src/*.zsh scripts/*.sh tests/*.zsh; do
  zsh -n "$script"
done
plutil -lint src/Info.plist
