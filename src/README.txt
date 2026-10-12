KAZE · SORA
===========

English: README.txt · Español: README.es.txt
A local macOS app by Sora Agency. No accounts or Internet connection required.
Kaze (風) means wind in Japanese.

INSTALL ON ANOTHER MAC
Open the DMG for your architecture and drag Kaze onto Applications.
Eject the Kaze volume and open /Applications/Kaze.app.
Close the app before replacing it during an update.

ALTERNATIVE WITH AUTOMATIC BACKUP
1. Extract the complete ZIP.
2. Right-click Instalar.command and choose Open.
3. Kaze installs in ~/Applications; the scheduling preset starts disabled.
4. Packages are ad hoc signed and not notarized by Apple. If macOS blocks
   the first launch, verify the source and allow Kaze in System Settings >
   Privacy & Security > Open Anyway.

LANGUAGE
The interface, cleanup notifications, errors, terms and privacy notice support
English and Spanish. Choose Español or English in the top-bar language selector,
next to the appearance button. The interface changes immediately; the preference
is saved for future launches and scheduled notifications. Before you choose, Kaze
follows macOS language preferences, with English as fallback. Existing task names and
file paths are preserved. MIT and third-party license texts remain unchanged.

INTERFACE
- Light and dark themes, original Sora logo, Lucide icons, DM Sans and Raleway.
- Animated startup, navigation, loading and controls respect Reduce Motion.
- Terms, privacy and the MIT license are available in the sidebar and Help menu.
- Explore any accessible folder on your Mac or external drives. Home, Downloads,
  Documents, Desktop, Macintosh HD and external drives have sidebar shortcuts.
  You can also choose a folder or enter its path using the pencil button.
- Total folder sizes include their contents without opening the folder.
  Sort by size, name, type or modification date; search by name and filter
  files or folders. Hidden items are included and can be hidden from the view.
  Filters never change the folder total.
- Double-click to open folders. Context menus reveal items in Finder or copy
  their paths. Navigate back, forward or through parent folders.
- Sizes update in the background. Stop or refresh a scan; changing folders
  cancels the previous scan. A ≥ marks partial measurements; pending items
  never appear as zero. Errors are shown explicitly.
- Measurements use allocated disk space and metadata, without opening document
  contents, downloading iCloud files or following symbolic links. Hard links
  count once within a scan. APFS shared blocks mean sizes do not predict the
  exact space recovered after deletion.
- Protected locations may require Full Disk Access. Use the shield button to
  open permissions, then rescan. Kaze does not bypass macOS protections.
- Cleanup shows free space, progress and general, development and Docker caches.
- Applications lists installed apps and their total sizes, including related
  local data. Expand their folders and select individual files or folders.
- Resources groups app data and lists Docker images, containers and volumes,
  plus Xcode simulators and runtimes. App data is available even when Docker
  and Xcode are closed. Folder contents load as you expand them.
- Selecting a parent deselects descendants to avoid duplicate deletion.
- Apps and their selected data move to the Trash after confirmation; Kaze
  never empties it automatically. You can remove data while keeping the app.
- Docker/Xcode resources may be deleted permanently after an additional
  confirmation. Running containers stop only when their removal is confirmed.
- Activity shows local cleanup actions and errors in real time.

DELETION INDICATORS
Green: known regenerable caches and build files. Close apps using them first.
Red: system components, apps, settings or sensitive data.
Gray: review content and usage, including documents, downloads and symlinks.
Hover for the reason. Indicators do not delete files or change total sizes.

SCHEDULED TASKS
The 09:30 preset is disabled. Create, edit, enable or remove multiple independent
tasks with their own frequency, local time, categories, free-space threshold and
notifications. Active tasks run with your session logged in even with Kaze closed.
Saving a disabled task never schedules cleanup. Legacy preferences and explicitly
enabled tasks migrate to the com.soraagency.kaze namespace.

UNINSTALL
For a DMG installation, disable tasks in Kaze, close it and move the app from
Applications to the Trash. For a ZIP installation, run Desinstalar.command.
Logs and backups are preserved at:
~/Library/Logs/LiberarEspacioMac/limpieza.log
~/Library/Application Support/Kaze/Backups
The historical log path is retained for compatibility.

BUILD FROM SOURCE
Run scripts/test.sh and scripts/build.sh with Xcode Command Line Tools.
Outputs: package/Kaze.app, build/Kaze-Mac-<architecture>.dmg,
build/Kaze-Mac-<architecture>.zip and build/Kaze-Source.zip.
The package targets the architecture of the Mac running the build.
README.md / README.es.md include full instructions and fictional screenshots.

OPEN SOURCE
Kaze's code uses the MIT license (LICENSE). The software is provided as is,
without warranties. Sora Agency and contributor liability is excluded to the
extent permitted by law. See the Terms and Privacy section inside the app.
English texts: Kaze.app/Contents/Resources/en.lproj/TERMS.txt and PRIVACY.txt.
Spanish texts: TERMS.txt and PRIVACY.txt included with the package.
Fonts retain their SIL Open Font License; third-party notices are included.
The package does not itself create a public repository or promise ongoing support.

STORAGE INTELLIGENCE
Smart Scan shares one index with Space Map, Duplicates, System Data and the local
assistant. Choose a folder to limit scope. Nothing is removed during analysis.
SHA-256 checks exact copies; explicit Apple Vision comparison only suggests photos
for review. History restores intact Trash items without overwriting files;
permanent cache/Docker/simulator operations have no undo. Recovery is a potential
range because APFS may retain shared blocks. Menu bar notifications are optional.
Rules are bundled and Ed25519-signed. See the included source storage guide.
