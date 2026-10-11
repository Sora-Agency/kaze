#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
for language in en es; do
  actual="$(KAZE_LANGUAGE="$language" zsh -c 'source src/localization.zsh; kaze_text "SIMULACIÓN: %s ocupa %s GiB" "file 100%" 2')"
  if [[ "$language" == en ]]; then expected='DRY RUN: file 100% uses 2 GiB'
  else expected='SIMULACIÓN: file 100% ocupa 2 GiB'; fi
  [[ "$actual" == "$expected" ]]
  actual="$(KAZE_LANGUAGE="$language" zsh src/cleaner.zsh --threshold-gib=0 2>&1 || true)"
  if [[ "$language" == en ]]; then expected='The threshold must be an integer between 1 and 1024 GiB.'
  else expected='El umbral debe ser un entero entre 1 y 1024 GiB.'; fi
  [[ "$actual" == "$expected" ]]
  print -r -- "PASS: Runtime interpolation and validation messages [$language]"
done
KAZE_LANGUAGE=en zsh -c '
  set -euo pipefail
  source src/localization.zsh
  [[ "$(kaze_preferred_language es en-US)" == es ]]
  [[ "$(kaze_preferred_language en es-UY)" == en ]]
  [[ "$(kaze_preferred_language unsupported "(fr-FR,es-UY,en-US)")" == es ]]
  [[ "$(kaze_preferred_language unsupported fr-FR)" == en ]]
' || exit 1
print -r -- "PASS: Scheduled cleanup follows the saved language preference"
