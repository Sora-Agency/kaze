#!/bin/zsh
set -euo pipefail
source "${0:A:h}/localization.zsh"
if [[ $# -lt 2 || $# -gt 3 ]]; then
  print -u2 -- "$(kaze_text 'Uso: disable-legacy-schedule.zsh agente configuración [launchctl]')"
  exit 2
fi
agent_file="$1"
configuration_file="$2"
launchctl_bin="${3:-/bin/launchctl}"
legacy_label="${agent_file:t:r}"
if [[ -f "$agent_file" ]]; then
  legacy_label="$(/usr/bin/plutil -extract Label raw -o - "$agent_file")"
fi
service="gui/$(/usr/bin/id -u)/$legacy_label"
if [[ -f "$configuration_file" ]]; then
  if /usr/bin/plutil -extract tasks json -o - "$configuration_file" >/dev/null 2>&1; then
    print -r -- "$(kaze_text 'Se conservan las tareas independientes configuradas en Kaze.')"
  else
    enabled="$(/usr/bin/plutil -extract enabled raw -o - "$configuration_file")"
    if [[ "$enabled" == true ]]; then
      print -r -- "$(kaze_text 'Se conserva la programación configurada; Kaze la migrará a una tarea independiente.')"
      exit 0
    fi
  fi
fi
if "$launchctl_bin" print "$service" >/dev/null 2>&1; then
  "$launchctl_bin" bootout "$service"
fi
if [[ -f "$agent_file" ]]; then /bin/rm -f -- "$agent_file"; fi
print -r -- "$(kaze_text 'Limpieza programada desactivada. Configúrala y actívala desde Tareas programadas.')"
