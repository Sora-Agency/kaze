#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
test_dir="$(mktemp -d -t kaze-cleanup-lock)"
trap 'rm -rf "$test_dir"' EXIT
source src/cleanup-lock.zsh
log() { print -r -- "$*" >> "$test_dir/log"; }
lock="$test_dir/lock"
kaze_acquire_cleanup_lock "$lock" scheduled 3
if kaze_acquire_cleanup_lock "$lock" manual 0; then
  print -u2 -- "A manual cleanup ignored the active lock"; exit 1
fi
(
  kaze_acquire_cleanup_lock "$lock" scheduled 5
  print -r -- acquired > "$test_dir/second"
  rmdir "$lock"
) &
waiting_pid=$!
/bin/sleep 1
[[ ! -f "$test_dir/second" ]]
rmdir "$lock"
wait "$waiting_pid"
[[ -f "$test_dir/second" && ! -d "$lock" ]]
print -r -- "PASS: Coincident scheduled cleanups wait and acquire the lock in turn"
mkdir "$lock"
if kaze_acquire_cleanup_lock "$lock" scheduled 0; then
  print -u2 -- "A waiting cleanup ignored its timeout"; exit 1
fi
[[ -d "$lock" ]]
print -r -- "PASS: A timed-out cleanup preserves the existing lock"
