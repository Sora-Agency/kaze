#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
test_dir="$(mktemp -d -t kaze-schedule-migration)"
trap 'rm -rf "$test_dir"' EXIT
agent="$test_dir/legacy-agent.plist"
template="$test_dir/legacy-template.plist"
config="$test_dir/schedule.json"
runner="$test_dir/launchctl-test"
cat > "$runner" <<'SCRIPT'
#!/bin/zsh
print -r -- "$1" >> "${0:h}/commands"
if [[ "$1" == print ]]; then exit 0; fi
if [[ "$1" == bootout ]]; then exit 0; fi
exit 99
SCRIPT
chmod +x "$runner"
cat > "$template" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>org.example.liberar-espacio-mac</string>
  <key>ProgramArguments</key><array><string>/legacy/cleaner.zsh</string><string>--scheduled</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>30</integer></dict>
</dict>
</plist>
PLIST
cp "$template" "$agent"
src/disable-legacy-schedule.zsh "$agent" "$config" "$runner"
[[ ! -f "$agent" ]]
[[ "$(<"$test_dir/commands")" == $'print\nbootout' ]]
print -r -- "PASS: Migration unloads the legacy job without registering a replacement"
print -r -- '{"enabled":true}' > "$config"
cp "$template" "$agent"
: > "$test_dir/commands"
src/disable-legacy-schedule.zsh "$agent" "$config" "$runner"
[[ -f "$agent" && ! -s "$test_dir/commands" ]]
print -r -- "PASS: Installer preserves an explicitly enabled schedule"
print -r -- '{"enabled":false}' > "$config"
src/disable-legacy-schedule.zsh "$agent" "$config" "$runner"
[[ ! -f "$agent" ]]
print -r -- "PASS: Installer keeps a saved inactive schedule inactive"
print -r -- '{"version":2,"tasks":[]}' > "$config"
cp "$template" "$agent"
src/disable-legacy-schedule.zsh "$agent" "$config" "$runner"
[[ -f "$config" && ! -f "$agent" ]]
print -r -- "PASS: Updates preserve task collections while removing obsolete legacy agents"
for threshold in 0 1025 abc -1 '70;touch invalid'; do
  if src/cleaner.zsh "--threshold-gib=$threshold" 2>/dev/null; then
    print -u2 -- "Invalid threshold was accepted: $threshold"
    exit 1
  fi
done
print -r -- "PASS: Invalid cleaner thresholds fail before any cleanup"
