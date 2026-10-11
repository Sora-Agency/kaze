#!/bin/zsh
source "${${(%):-%x}:A:h}/localization.zsh"
kaze_acquire_cleanup_lock() {
  local target="$1"
  local mode="$2"
  local wait_limit="${3:-1800}"
  local waited=0
  while ! /bin/mkdir "$target" 2>/dev/null; do
    if [[ "$mode" != scheduled ]]; then
      log "$(kaze_text 'Otra limpieza ya está en ejecución; se omite esta pasada manual.')"
      return 1
    fi
    if (( waited == 0 )); then log "$(kaze_text 'Tarea programada en espera de otra limpieza.')"; fi
    if (( waited >= wait_limit )); then
      log "$(kaze_text 'No se pudo obtener el turno de limpieza en %s segundos; revisa el registro y el bloqueo.' "$wait_limit")"
      return 1
    fi
    /bin/sleep 1
    (( waited += 1 ))
  done
  return 0
}
