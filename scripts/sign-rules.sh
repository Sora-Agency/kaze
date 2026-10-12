#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
sparkle_dir="$(scripts/fetch-sparkle.sh)"
# The key stays in login Keychain. Temporary exports are removed on every exit.
work_dir="$(mktemp -d -t kaze-rules)"
chmod 700 "$work_dir"
trap 'rm -rf -- "$work_dir"' EXIT
"$sparkle_dir/bin/generate_keys" --account com.soraagency.kaze -x "$work_dir/key" >/dev/null
chmod 600 "$work_dir/key"
python3 - "$sparkle_dir/bin/sign_update" "$work_dir/key" <<'PY'
import pathlib, subprocess, sys
signature = subprocess.check_output([sys.argv[1], '--ed-key-file', '-', '-p', 'src/Rules/rules-v1.json'], input=pathlib.Path(sys.argv[2]).read_bytes()).decode().strip()
pathlib.Path('src/Rules/rules-v1.signature').write_text(signature + '\n')
PY
xcrun swift scripts/verify-rules.swift "$PWD"
