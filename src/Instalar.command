#!/bin/zsh
set -euo pipefail
source "${0:A:h}/localization.zsh"
package_dir="${0:A:h}"
source_app="$package_dir/Kaze.app"
install_dir="$HOME/Applications"
installed_app="$install_dir/Kaze.app"
launch_agents="$HOME/Library/LaunchAgents"
legacy_agents=("$launch_agents"/*.liberar-espacio-mac.plist(N) "$launch_agents/com.soraagency.kaze.plist")
schedule_config="$HOME/Library/Application Support/Kaze/schedule.json"
if [[ ! -d "$source_app" || ! -x "$package_dir/disable-legacy-schedule.zsh" ]]; then
  print -u2 -- "$(kaze_text 'El paquete está incompleto.')"
  if [[ -t 0 ]]; then read -r "?$(kaze_text 'Pulsa Enter para cerrar.')"; fi
  exit 1
fi
/bin/mkdir -p "$install_dir" "$launch_agents"
staging_dir="$(/usr/bin/mktemp -d "$install_dir/.kaze-install.noindex-XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
/usr/bin/ditto "$source_app" "$staging_dir/Kaze.app"
/usr/bin/codesign --verify --strict "$staging_dir/Kaze.app"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$staging_dir/Kaze.app/Contents/Info.plist")" != com.soraagency.kaze ]]; then
  print -u2 -- "$(kaze_text 'El paquete no corresponde a Kaze.')"
  exit 1
fi
backup_root="$HOME/Library/Application Support/Kaze/Backups"
/bin/mkdir -p "$backup_root"
backup_dir="$(/usr/bin/mktemp -d "$backup_root/$(/bin/date +%Y%m%d-%H%M%S)-XXXXXX")"
legacy_apps=("$install_dir/Orbita.app" "$install_dir/Liberar espacio Mac Pro.app")
if [[ -d "$installed_app" ]]; then
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$installed_app" "$backup_dir/Kaze-previous.zip"
  /usr/bin/unzip -tq "$backup_dir/Kaze-previous.zip" >/dev/null
fi
for agent_plist in "${legacy_agents[@]}"; do
  if [[ -f "$agent_plist" ]]; then /bin/cp "$agent_plist" "$backup_dir/${agent_plist:t}"; fi
done
if [[ -f "$schedule_config" ]]; then /bin/cp "$schedule_config" "$backup_dir/schedule.json"; fi
if [[ -d "$installed_app" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$installed_app" || true
  /bin/mv "$installed_app" "$staging_dir/previous.app"
fi
if ! /bin/mv "$staging_dir/Kaze.app" "$installed_app"; then
  if [[ -d "$staging_dir/previous.app" ]]; then
    /bin/mv "$staging_dir/previous.app" "$installed_app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_app" || true
  fi
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_app" || true
for agent_plist in "${legacy_agents[@]}"; do
  "$package_dir/disable-legacy-schedule.zsh" "$agent_plist" "$schedule_config"
done
for legacy_app in "${legacy_apps[@]}"; do
  if [[ -d "$legacy_app" && ! -L "$legacy_app" ]]; then
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$legacy_app" "$backup_dir/${legacy_app:t}.zip"
    /usr/bin/unzip -tq "$backup_dir/${legacy_app:t}.zip" >/dev/null
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$legacy_app" || true
    /bin/rm -rf -- "$legacy_app"
  fi
done
print -r -- "$(kaze_text 'Kaze · Un producto de Sora Agency')"
print -r -- "$(kaze_text 'Instalado en: %s' "$installed_app")"
print -r -- "$(kaze_text 'Respaldo de la versión anterior: %s' "$backup_dir")"
print -r -- "$(kaze_text 'Preset: 09:30 cada día, por debajo de 70 GiB. La instalación nueva no activa la tarea.')"
print -r -- "$(kaze_text 'Software open source bajo licencia MIT. Consulta los términos y la privacidad en la app.')"
if [[ -t 0 ]]; then read -r "?$(kaze_text 'Pulsa Enter para cerrar.')"; fi
