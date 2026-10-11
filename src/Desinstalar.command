#!/bin/zsh

set -u
source "${0:A:h}/localization.zsh"

installed_app="$HOME/Applications/Kaze.app"
launch_agents="$HOME/Library/LaunchAgents"

for task_agent in "$HOME/Library/LaunchAgents"/com.soraagency.kaze.task.*.plist(N) "$launch_agents"/*.liberar-espacio-mac.task.*.plist(N) "$HOME/Library/LaunchAgents/com.soraagency.kaze.plist" "$launch_agents"/*.liberar-espacio-mac.plist(N); do
  task_label="${task_agent:t:r}"
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$task_label" >/dev/null 2>&1 || true
  if [[ -f "$task_agent" ]]; then /bin/rm -f -- "$task_agent"; fi
done

if [[ -d "$installed_app" && ! -L "$installed_app" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$installed_app" >/dev/null 2>&1 || true
  /bin/rm -rf -- "$installed_app"
fi

print -r -- "$(kaze_text 'Kaze fue desinstalado. Los registros se conservaron.')"
if [[ -t 0 ]]; then read -r "?$(kaze_text 'Pulsa Enter para cerrar.')"; fi
