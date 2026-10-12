#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export KAZE_LANGUAGE=es
export KAZE_LOCALIZATION_RESOURCES="$PWD/src/Localization"
test_dir="$(mktemp -d -t kaze-tests)"
trap 'rm -rf -- "$test_dir"' EXIT
swift_flags=(-swift-version 5 -I src/Infrastructure/Recovery -target "$(uname -m)-apple-macosx13.0")
explorer_sources=(
  src/Domain/DeletionSafety.swift src/Domain/Formatting.swift src/Domain/FileModels.swift src/Domain/AnalysisModels.swift
  src/Domain/AnalysisCacheModels.swift src/Infrastructure/AnalysisCache.swift src/Infrastructure/FolderChangeMonitor.swift
  src/Infrastructure/ExplorerSnapshotBuilder.swift
  src/Infrastructure/DiskScanner.swift src/Infrastructure/DeletionClassifier.swift src/Features/Explorer/FileExplorerModel.swift
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
xcrun clang -target "$(uname -m)-apple-macosx13.0" -O2 -Wall -Wextra -c src/Infrastructure/Recovery/AuthDisk.c -o "$test_dir/AuthDisk.o"
command_sources=(src/Infrastructure/OperationCancellation.swift src/Infrastructure/ToolCommandRunner.swift)
recovery_sources=(src/Domain/RecoveryModels.swift src/Infrastructure/Recovery/*.swift "${command_sources[@]}")
run_swift_test RecoveryTests "${recovery_sources[@]}" "$test_dir/AuthDisk.o"
run_swift_test RecoveryImageTests "${recovery_sources[@]}" "$test_dir/AuthDisk.o"
run_swift_test StartupItemsTests "${command_sources[@]}" src/Domain/StartupItem.swift src/Domain/StartupItemsError.swift \
  src/Infrastructure/MutationLease.swift src/Infrastructure/LoginItemsAutomation.swift src/Infrastructure/StartupItemsService.swift
if [[ "${1:-}" == "--management-only" ]]; then exit 0; fi
for test_name in ScannerTests ExplorerModelTests DeletionSafetyTests; do
  run_swift_test "$test_name" "${explorer_sources[@]}"
done
analysis_sources=(
  src/App/AppIdentity.swift src/Domain/*.swift
  src/Infrastructure/DiskScanner.swift src/Infrastructure/DeletionClassifier.swift src/Infrastructure/StorageIndexer.swift
  src/Infrastructure/AnalysisCache.swift src/Infrastructure/FolderChangeMonitor.swift
  src/Infrastructure/DuplicateDetector.swift src/Infrastructure/RuleCatalog.swift
  src/Infrastructure/OperationJournal.swift src/Infrastructure/MutationLease.swift
  src/Infrastructure/CleanupAuthorization.swift src/Infrastructure/ApplicationAttribution.swift
  src/Infrastructure/CleanerOperations.swift src/Infrastructure/ManagedResourceDiscovery.swift
  src/Infrastructure/ManagedResourceRemoval.swift src/Infrastructure/AnalysisRemoval.swift
)
run_swift_test AnalysisEngineTests "${analysis_sources[@]}"
run_swift_test AnalysisRemovalTests "${analysis_sources[@]}"
run_swift_test AnalysisCacheTests "${analysis_sources[@]}" src/Infrastructure/ExplorerSnapshotBuilder.swift src/Features/Explorer/FileExplorerModel.swift
run_swift_test LocalAITests "${analysis_sources[@]}" src/Infrastructure/LocalAIService.swift \
  src/Infrastructure/SpotlightUsage.swift src/Features/SmartScan/SmartScanModel.swift src/Features/Assistant/LocalAssistantModel.swift
run_swift_test ScheduleTests "${schedule_sources[@]}"
run_swift_test IdentityTests src/App/AppIdentity.swift
run_swift_test DiskAccessTests src/Infrastructure/DiskAccessStore.swift
xcrun swiftc "${swift_flags[@]}" src/Localization/L10n.swift src/Domain/ScheduledCleanupTask.swift \
  tests/LocalizationTests.swift -o "$test_dir/LocalizationTests"
for language in en es; do
  KAZE_LANGUAGE="$language" "$test_dir/LocalizationTests"
done
python3 tests/LocalizationCatalogTests.py
tests/LocalizationRuntimeTests.zsh
sources=(src/**/*.swift)
xcrun swiftc "${swift_flags[@]}" -D KAZE_PREVIEW "${sources[@]}" "$test_dir/AuthDisk.o" \
  tests/PreviewFixtures.swift tests/PreviewPrivacyTests.swift -o "$test_dir/PreviewPrivacyTests"
"$test_dir/PreviewPrivacyTests"
xcrun swiftc "${swift_flags[@]}" -D KAZE_PREVIEW "${sources[@]}" "$test_dir/AuthDisk.o" \
  tests/PreviewFixtures.swift tests/LanguageSwitchTests.swift -o "$test_dir/LanguageSwitchTests"
"$test_dir/LanguageSwitchTests"
xcrun swiftc "${swift_flags[@]}" -D KAZE_PREVIEW "${sources[@]}" "$test_dir/AuthDisk.o" \
  tests/SmartScanModelTests.swift -o "$test_dir/SmartScanModelTests"
"$test_dir/SmartScanModelTests"
tests/LegacyScheduleTests.zsh
tests/CleanerLockTests.zsh
python3 tests/ReleaseTests.py
tests/UpdaterTests.zsh
python3 tests/DetachImageTests.py
for script in src/*.command src/*.zsh scripts/*.sh tests/*.zsh; do
  zsh -n "$script"
done
plutil -lint src/Info.plist
