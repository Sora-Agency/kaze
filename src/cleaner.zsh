#!/bin/zsh

set -u

source "${0:A:h}/localization.zsh"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly APP_NAME="Kaze"
threshold_gib=70
always_clean=0
notify_result=1
scheduled_task_id=""
readonly USER_HOME="${HOME:A}"
readonly DATA_VOLUME="/System/Volumes/Data"
readonly LOG_DIR="$USER_HOME/Library/Logs/LiberarEspacioMac"
readonly LOG_FILE="$LOG_DIR/limpieza.log"
readonly LOCK_DIR="/tmp/com.soraagency.kaze.lock"

journal_executable="${0:A:h}/../MacOS/Kaze"

run_mode="manual"
dry_run=0
show_dialog=1
clean_general=1
clean_development=1
clean_docker=1

for arg in "$@"; do
  case "$arg" in
    --scheduled) run_mode="scheduled" ;;
    --task-id=*)
      scheduled_task_id="${arg#--task-id=}"
      if [[ ! "$scheduled_task_id" =~ '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' ]]; then
        print -u2 -- "$(kaze_text 'Identificador de tarea no válido.')"
        exit 2
      fi ;;
    --always) always_clean=1 ;;
    --quiet) notify_result=0 ;;
    --threshold-gib=*)
      value="${arg#--threshold-gib=}"
      if [[ "$value" != <1-1024> ]]; then
        print -u2 -- "$(kaze_text 'El umbral debe ser un entero entre 1 y 1024 GiB.')"
        exit 2
      fi
      threshold_gib="$value" ;;
    --manual) run_mode="manual" ;;
    --dry-run) dry_run=1 ;;
    --no-dialog) show_dialog=0 ;;
    --skip-general) clean_general=0 ;;
    --skip-development) clean_development=0 ;;
    --skip-docker) clean_docker=0 ;;
  esac
done

if [[ ! -d "$USER_HOME" || "$USER_HOME" != /Users/* ]]; then
  exit 2
fi

/bin/mkdir -p "$LOG_DIR"

log() {
  /usr/bin/printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

notify() {
  local message="$1"
  (( notify_result )) || return 0
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
    -e 'end run' \
    -- "$message" "$APP_NAME" >/dev/null 2>&1 || true
}

show_result() {
  local message="$1"
  if [[ "$run_mode" == "manual" && "$show_dialog" -eq 1 ]]; then
    /usr/bin/osascript \
      -e 'on run argv' \
      -e 'display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 3 of argv} default button (item 3 of argv)' \
      -e 'end run' \
      -- "$message" "$APP_NAME" "$(kaze_text Aceptar)" >/dev/null 2>&1 || true
  else
    notify "$message"
  fi
}

free_kib() {
  /bin/df -k "$DATA_VOLUME" | /usr/bin/awk 'NR == 2 { print $4 }'
}

format_gib() {
  /usr/bin/awk -v kib="$1" 'BEGIN { printf "%.1f", kib / 1048576 }'
}

path_kib() {
  local target="$1"
  if [[ -e "$target" ]]; then
    /usr/bin/du -sk "$target" 2>/dev/null | /usr/bin/awk '{ print $1 }'
  else
    /usr/bin/printf '0\n'
  fi
}

is_allowed_clean_target() {
  local target="$1"
  if [[ "$target" == "$USER_HOME/.nx/"*"/cache" ]]; then
    local workspace_id="${target:h:h:t}"
    [[ "$workspace_id" =~ '^[0-9a-f]{16}$' ]] && return 0
  fi
  case "$target" in
    "$USER_HOME/Library/Caches"|\
    "$USER_HOME/Library/Caches/Google/Chrome"|\
    "$USER_HOME/Library/Caches/com.google.Chrome"|\
    "$USER_HOME/Library/Caches/com.apple.Safari"|\
    "$USER_HOME/Library/Caches/Yarn"|\
    "$USER_HOME/Library/Caches/pip"|\
    "$USER_HOME/.cache/pip"|\
    "$USER_HOME/Library/Caches/CocoaPods"|\
    "$USER_HOME/Library/Application Support/Code/Cache"|\
    "$USER_HOME/Library/Application Support/Code/Code Cache"|\
    "$USER_HOME/Library/Application Support/Code/GPUCache"|\
    "$USER_HOME/Library/Application Support/Code/CachedData"|\
    "$USER_HOME/Library/Application Support/Slack/Cache"|\
    "$USER_HOME/Library/Application Support/Slack/Code Cache"|\
    "$USER_HOME/Library/Application Support/Slack/GPUCache"|\
    "$USER_HOME/.cache"|\
    "$USER_HOME/.gradle/caches"|\
    "$USER_HOME/.gradle/daemon"|\
    "$USER_HOME/.gradle/native"|\
    "$USER_HOME/.gradle/notifications"|\
    "$USER_HOME/.gradle/.tmp"|\
    "$USER_HOME/.npm/_cacache"|\
    "$USER_HOME/.npm/_npx"|\
    "$USER_HOME/.npm/_logs"|\
    "$USER_HOME/Library/Developer/Xcode/DerivedData"|\
    "$USER_HOME/Library/Developer/CoreSimulator/Caches"|\
    "$USER_HOME/Library/Application Support/discord/Cache"|\
    "$USER_HOME/Library/Application Support/discord/Code Cache"|\
    "$USER_HOME/Library/Application Support/discord/GPUCache") return 0 ;;
    *) return 1 ;;
  esac
}

clean_contents() {
  local label="$1"
  local target="$2"

  if ! is_allowed_clean_target "$target"; then
    log "$(kaze_text 'BLOQUEADO: destino fuera de la lista permitida: %s' "$target")"
    return 1
  fi

  if [[ ! -d "$target" || -L "$target" ]]; then
    return 0
  fi

  local before
  if (( dry_run )); then
    before="$(path_kib "$target")"
    log "$(kaze_text 'SIMULACIÓN: %s ocupa %s GiB' "$label" "$(format_gib "$before")")"
    return 0
  fi

  local before_bytes
  if [[ ! -x "$journal_executable" ]] || ! before_bytes="$("$journal_executable" --kaze-authorize-cleanup "$target")"; then
    log "$(kaze_text 'BLOQUEADO: regla no verificada o aplicación en uso: %s' "$target")"
    return 1
  fi
  before=$(( before_bytes / 1024 ))
  local operation_id cleanup_result=0 free_before="$(free_kib)"
  operation_id="$("$journal_executable" --kaze-journal-begin "$target" "$label" "$(( before * 1024 ))")" || return 1
  /usr/bin/find "$target" -mindepth 1 -maxdepth 1 -exec /bin/rm -rf -- {} + 2>>"$LOG_FILE" || cleanup_result=$?
  "$journal_executable" --kaze-journal-finish "$operation_id" "$cleanup_result" 'Limpieza irreversible de caché regenerable; los bloques retenidos por APFS no se consideran liberados.' "$(( ($(free_kib) - free_before) * 1024 ))" || return 1
  log "$(kaze_text 'Limpieza: %s; tamaño previo %s GiB' "$label" "$(format_gib "$before")")"
}

source "${0:A:h}/cleanup-lock.zsh"
if ! kaze_acquire_cleanup_lock "$LOCK_DIR" "$run_mode"; then
  [[ "$run_mode" == scheduled ]] && exit 1
  exit 0
fi
trap '/bin/rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

initial_free="$(free_kib)"
threshold_kib=$(( threshold_gib * 1048576 ))
log "$(kaze_text 'Inicio (%s); tarea: %s; libres: %s GiB; simulación: %s' "$run_mode" "${scheduled_task_id:-manual}" "$(format_gib "$initial_free")" "$dry_run")"

if [[ "$run_mode" == "scheduled" && "$dry_run" -eq 0 && "$always_clean" -eq 0 && "$initial_free" -ge "$threshold_kib" ]]; then
  log "$(kaze_text 'Hay al menos %s GiB libres; no se limpia.' "$threshold_gib")"
  exit 0
fi

run_audited_command() {
  local label="$1" target="$2"
  shift 2
  [[ -x "$journal_executable" ]] || return 1
  "$journal_executable" --kaze-authorize-command "$@" || { log "$(kaze_text 'BLOQUEADO: regla no verificada o aplicación en uso: %s' "$label")"; return 1; }
  local operation_id command_result=0 free_before="$(free_kib)"
  operation_id="$("$journal_executable" --kaze-journal-begin "$target" "$label" unknown)" || return 1
  "$@" >>"$LOG_FILE" 2>&1 || command_result=$?
  "$journal_executable" --kaze-journal-finish "$operation_id" "$command_result" 'Recurso administrado: sin deshacer; tamaño liberado no verificable por archivo.' "$(( ($(free_kib) - free_before) * 1024 ))" || return 1
  return "$command_result"
}

if (( clean_general )); then
  log "[PROGRESS] $(kaze_text 'Limpiando cachés generales')"
  clean_contents "Chrome" "$USER_HOME/Library/Caches/Google/Chrome"
  clean_contents "Chrome" "$USER_HOME/Library/Caches/com.google.Chrome"
  clean_contents "Safari" "$USER_HOME/Library/Caches/com.apple.Safari"
  clean_contents "$(kaze_text 'caché de Discord')" "$USER_HOME/Library/Application Support/discord/Cache"
  clean_contents "$(kaze_text 'Code Cache de Discord')" "$USER_HOME/Library/Application Support/discord/Code Cache"
  clean_contents "$(kaze_text 'GPUCache de Discord')" "$USER_HOME/Library/Application Support/discord/GPUCache"
  for cache_name in Cache 'Code Cache' GPUCache; do
    clean_contents "Slack · $cache_name" "$USER_HOME/Library/Application Support/Slack/$cache_name"
  done
fi

if (( clean_development )); then
  log "[PROGRESS] $(kaze_text 'Limpiando cachés de desarrollo')"
  clean_contents "$(kaze_text 'cachés de Gradle')" "$USER_HOME/.gradle/caches"
  clean_contents "$(kaze_text 'caché de npm')" "$USER_HOME/.npm/_cacache"
  clean_contents "$(kaze_text 'ejecuciones temporales de npx')" "$USER_HOME/.npm/_npx"
  clean_contents "$(kaze_text 'DerivedData de Xcode')" "$USER_HOME/Library/Developer/Xcode/DerivedData"
  clean_contents "$(kaze_text 'caché de CoreSimulator')" "$USER_HOME/Library/Developer/CoreSimulator/Caches"
  clean_contents "Yarn Classic" "$USER_HOME/Library/Caches/Yarn"
  clean_contents "pip" "$USER_HOME/Library/Caches/pip"
  clean_contents "pip" "$USER_HOME/.cache/pip"
  clean_contents "CocoaPods" "$USER_HOME/Library/Caches/CocoaPods"
  for cache_name in Cache 'Code Cache' GPUCache CachedData; do
    clean_contents "VS Code · $cache_name" "$USER_HOME/Library/Application Support/Code/$cache_name"
  done
fi

if (( ! dry_run && clean_development )); then
  if command -v pnpm >/dev/null 2>&1; then
    run_audited_command "pnpm" "$USER_HOME/Library/pnpm/store" pnpm store prune || true
  fi

  if command -v xcrun >/dev/null 2>&1; then
    run_audited_command "CoreSimulator" "$USER_HOME/Library/Developer/CoreSimulator/Devices" xcrun simctl delete unavailable || true
  fi
fi

if (( ! dry_run && clean_general )) && command -v brew >/dev/null 2>&1; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  run_audited_command "Homebrew" "$USER_HOME/Library/Caches/Homebrew" brew cleanup --prune=all || true
fi

docker_raw="$USER_HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
docker_raw_kib="$(path_kib "$docker_raw")"
docker_started_here=0

if (( ! clean_docker )); then
  log "$(kaze_text 'Docker: omitido por selección del usuario.')"
elif (( dry_run )); then
  log "$(kaze_text 'SIMULACIÓN: Docker.raw ocupa físicamente %s GiB' "$(format_gib "$docker_raw_kib")")"
elif (( docker_raw_kib > 10485760 )); then
  log "[PROGRESS] $(kaze_text 'Limpiando caché de Docker')"
  docker_ready=0
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker_ready=1
  elif [[ -d "/Applications/Docker.app" || -d "$USER_HOME/Applications/Docker.app" ]]; then
    docker_started_here=1
    /usr/bin/open -gj -a Docker >/dev/null 2>&1 || true
    for _ in {1..24}; do
      /bin/sleep 3
      if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker_ready=1
        break
      fi
    done
  fi

  if (( docker_ready )); then
    if run_audited_command "Docker build cache" "$docker_raw" docker builder prune -af --filter until=168h; then docker_build_result=0; else docker_build_result=1; fi
    if run_audited_command "Docker dangling images" "$docker_raw" docker image prune -f; then docker_image_result=0; else docker_image_result=1; fi
    if (( docker_build_result == 0 && docker_image_result == 0 )); then
      log "$(kaze_text 'Docker: se limpiaron cachés de build antiguas y objetos dangling; volúmenes y contenedores preservados.')"
    else
      log "$(kaze_text 'Docker: hubo operaciones omitidas o fallidas; revisa Historial y Actividad.')"
    fi
  else
    log "$(kaze_text 'Docker: no fue posible iniciar la API; Docker.raw no se modificó.')"
  fi

  if (( docker_started_here )); then
    /usr/bin/osascript -e 'tell application "Docker" to quit' >/dev/null 2>&1 || true
  fi
fi

final_free="$(free_kib)"
reclaimed_kib=$(( final_free - initial_free ))
if (( reclaimed_kib < 0 )); then
  reclaimed_kib=0
fi

log "$(kaze_text 'Fin; libres: %s GiB; cambio observado: %s GiB' "$(format_gib "$final_free")" "$(format_gib "$reclaimed_kib")")"

if (( dry_run )); then
  print -r -- "$(kaze_text 'Simulación completada. Revisa: %s' "$LOG_FILE")"
  exit 0
fi

summary="$(kaze_text 'Limpieza terminada. Cambio observado en espacio libre: %s GB. Espacio libre: %s GB.' "$(format_gib "$reclaimed_kib")" "$(format_gib "$final_free")")"
if (( final_free < 41943040 )); then
  summary="$summary $(kaze_text 'El disco sigue por debajo de 40 GB libres; revisa Docker, aplicaciones y archivos grandes.')"
fi

show_result "$summary"
