#!/bin/zsh
kaze_preferred_language() {
  local preference="$1"
  local languages="$2"
  case "$preference" in en|es) print -r -- "$preference"; return ;; esac
  languages="$(print -r -- "$languages" | /usr/bin/tr -d '()"[:space:]')"
  local language
  for language in ${(s:,:)languages}; do
    case "$language" in
      es|es-*) print -r -- es; return ;;
      en|en-*) print -r -- en; return ;;
    esac
  done
  print -r -- en
}
if [[ "${KAZE_LANGUAGE:-}" != en && "${KAZE_LANGUAGE:-}" != es ]]; then
  kaze_preference="$(/usr/bin/defaults read com.soraagency.kaze kaze.language 2>/dev/null || true)"
  kaze_languages="$(/usr/bin/defaults read com.soraagency.kaze AppleLanguages 2>/dev/null || /usr/bin/defaults read -g AppleLanguages 2>/dev/null || true)"
  KAZE_LANGUAGE="$(kaze_preferred_language "$kaze_preference" "$kaze_languages")"
  unset kaze_preference kaze_languages
fi
kaze_text() {
  local format="$1"
  shift
  if [[ "$KAZE_LANGUAGE" == en ]]; then
    case "$format" in
      'Identificador de tarea no válido.') format='Invalid task identifier.' ;;
      'El umbral debe ser un entero entre 1 y 1024 GiB.') format='The threshold must be an integer between 1 and 1024 GiB.' ;;
      Aceptar) format=OK ;;
      'BLOQUEADO: destino fuera de la lista permitida: %s') format='BLOCKED: target outside the allowlist: %s' ;;
      'SIMULACIÓN: %s ocupa %s GiB') format='DRY RUN: %s uses %s GiB' ;;
      'Limpieza: %s; tamaño previo %s GiB') format='Cleanup: %s; previous size %s GiB' ;;
      'Inicio (%s); tarea: %s; libres: %s GiB; simulación: %s') format='Starting (%s); task: %s; free: %s GiB; dry run: %s' ;;
      'Hay al menos %s GiB libres; no se limpia.') format='At least %s GiB are free; skipping cleanup.' ;;
      'Limpiando cachés generales') format='Cleaning general caches' ;;
      'Limpiando cachés de desarrollo') format='Cleaning development caches' ;;
      'Limpiando caché de Docker') format='Cleaning Docker cache' ;;
      'cachés generales del usuario') format='general user caches' ;;
      'cachés multiplataforma') format='cross-platform caches' ;;
      'caché de Discord') format='Discord cache' ;;
      'Code Cache de Discord') format='Discord code cache' ;;
      'GPUCache de Discord') format='Discord GPU cache' ;;
      'caché de compilación Nx') format='Nx build cache' ;;
      'cachés de Gradle') format='Gradle caches' ;;
      'daemons de Gradle') format='Gradle daemons' ;;
      'temporales nativos de Gradle') format='Gradle native temporary files' ;;
      'notificaciones de Gradle') format='Gradle notifications' ;;
      'temporales de Gradle') format='Gradle temporary files' ;;
      'caché de npm') format='npm cache' ;;
      'ejecuciones temporales de npx') format='temporary npx executions' ;;
      'logs de npm') format='npm logs' ;;
      'DerivedData de Xcode') format='Xcode DerivedData' ;;
      'caché de CoreSimulator') format='CoreSimulator cache' ;;
      'Docker: omitido por selección del usuario.') format='Docker: skipped by user selection.' ;;
      'SIMULACIÓN: Docker.raw ocupa físicamente %s GiB') format='DRY RUN: Docker.raw physically uses %s GiB' ;;
      'Docker: se limpiaron cachés de build antiguas y objetos dangling; volúmenes y contenedores preservados.') format='Docker: old build caches and dangling objects cleaned; volumes and containers preserved.' ;;
      'Docker: no fue posible iniciar la API; Docker.raw no se modificó.') format='Docker: could not start the API; Docker.raw was not modified.' ;;
      'Fin; libres: %s GiB; recuperados: %s GiB') format='Finished; free: %s GiB; reclaimed: %s GiB' ;;
      'Simulación completada. Revisa: %s') format='Dry run completed. Check: %s' ;;
      'Limpieza terminada. Recuperados: %s GB. Espacio libre: %s GB.') format='Cleanup completed. Reclaimed: %s GB. Free space: %s GB.' ;;
      'El disco sigue por debajo de 40 GB libres; revisa Docker, aplicaciones y archivos grandes.') format='The disk still has less than 40 GB free; review Docker, apps and large files.' ;;
      'Otra limpieza ya está en ejecución; se omite esta pasada manual.') format='Another cleanup is running; skipping this manual run.' ;;
      'Tarea programada en espera de otra limpieza.') format='Scheduled task waiting for another cleanup.' ;;
      'No se pudo obtener el turno de limpieza en %s segundos; revisa el registro y el bloqueo.') format='Could not acquire the cleanup lock within %s seconds; check the log and lock.' ;;
      'El paquete está incompleto.') format='The package is incomplete.' ;;
      'El paquete no corresponde a Kaze.') format='This package is not Kaze.' ;;
      'Pulsa Enter para cerrar.') format='Press Enter to close.' ;;
      'Kaze · Un producto de Sora Agency') format='Kaze · A Sora Agency product' ;;
      'Instalado en: %s') format='Installed at: %s' ;;
      'Respaldo de la versión anterior: %s') format='Previous version backup: %s' ;;
      'Preset: 09:30 cada día, por debajo de 70 GiB. La instalación nueva no activa la tarea.') format='Preset: daily at 09:30, below 70 GiB free. A new installation does not enable the task.' ;;
      'Software open source bajo licencia MIT. Consulta los términos y la privacidad en la app.') format='Open source software under the MIT license. See terms and privacy in the app.' ;;
      'Kaze fue desinstalado. Los registros se conservaron.') format='Kaze was uninstalled. Logs were retained.' ;;
      'Uso: disable-legacy-schedule.zsh agente configuración [launchctl]') format='Usage: disable-legacy-schedule.zsh agent configuration [launchctl]' ;;
      'Se conservan las tareas independientes configuradas en Kaze.') format='Independent tasks configured in Kaze are preserved.' ;;
      'Se conserva la programación configurada; Kaze la migrará a una tarea independiente.') format='The existing schedule is preserved; Kaze will migrate it to an independent task.' ;;
      'Limpieza programada desactivada. Configúrala y actívala desde Tareas programadas.') format='Scheduled cleanup disabled. Configure and enable it in Scheduled Tasks.' ;;
    esac
  fi
  /usr/bin/printf "$format" "$@"
}
