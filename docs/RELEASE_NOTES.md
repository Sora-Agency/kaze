# Kaze 1.2.5

- Smoothly fade and collapse Smart Scan headings and category cards while keeping the three summary cards visible. Respect Reduce Motion and avoid viewport-driven collapse/expand loops.
- Use Kaze's turquoise accent throughout the optional AI assistant, including icons, focus borders and download progress.
- Replace the technical Rules and safety landing page with Settings and safety: menu bar preferences and cleanup protection first, signed rules and per-rule details collapsed by default.

# Kaze 1.2.4

- Restore the last Smart Scan, Space Map, duplicate results and measured recommendations across app sessions without rescanning or rehashing at launch.
- Persist Explorer folder measurements, show the measurement date and refresh changed branches in the background using macOS filesystem events.
- Reuse Smart Scan on the first Explorer entry; retain visible rows when updating or stopping a scan.
- Bound private metadata caches and fall back to full scans for missing history, changed volumes, incomplete results or cross-folder hard links.
- Restored analysis clears selections and requires a fresh scan before cleaning; existing live deletion checks remain in place.

# Kaze 1.2.3

- Redesigned local assistant with a focused question/answer view, a fixed composer and measured scan context alongside verified recommendations.
- Recommendations are grouped by rule, with counts and expandable recovery instructions instead of repeated cards for every matching project.
- Smart Scan keeps its three summary cards visible and compact when scrolling, hides category cards until returning to the top, and gives more room to readable result rows.
- Analysis status stays visible; full APFS, partial-scan and rule-verification details remain available in a popover.
- Optional AI installation and existing scan, selection and cleanup safeguards are preserved.

# Kaze 1.2.2

- Aligned Smart Scan category cards and scan progress controls, with subtle category colors.
- New brain icon and optional local AI assistant: one button downloads a pinned llama.cpp engine and Qwen3 0.6B model (about 650 MB).
- No automatic AI installation, model downloads on launch, or persistent AI service. Availability checks and integrity verification run off the main thread.
- Cancellable downloads and queries, verified SHA-256 assets, measured scan context and verified recommendations alongside AI answers.
- Local AI requires macOS 13.3+; all existing disk features remain available on macOS 13+ without AI.

# Kaze 1.2.1

Fix an unresponsive window at startup caused by the menu bar monitor writing its
existing insertion state back to preferences on every scene update. Ignore
unchanged insertion values so the native interface settles after launch.

Validated native startup with the monitor enabled/disabled and light/dark appearance.

# Kaze 1.2.0

Storage intelligence for Kaze, with a shared scan index and a reorganized sidebar.

- Smart Scan groups safe cleanup, review items, apps, exact duplicates and development resources.
- Interactive Space Map with folder zoom, Quick Look, Finder and Explorer navigation.
- Streaming SHA-256 duplicate checks and explicit local Apple Vision photo comparison.
- Verifiable app-data attribution, shared dependency review and helper-process checks.
- Operation history and restoration from Trash without overwriting existing files.
- System Data explanations, local snapshot inventory and logical/allocated/recoverable distinctions.
- Developer inventories for Node, pnpm/npm, Gradle, CocoaPods, Python, simulators, Docker and local AI models.
- Same-process menu bar monitor with optional low-space notifications.
- Bundled versioned Ed25519-signed rules and a deterministic local assistant.
- English/Spanish UI, explicit scans, cancellable comparisons and bounded map detail.

APFS clones and snapshots may retain blocks; recovery is a potential range.
Visual similarities, shared app data, project dependencies and model stores require review.
Trash operations can be restored while intact; cache clearing and Docker/simctl deletion have no undo.

# Kaze 1.1.0

Kaze now checks for new versions and lets you download, install and relaunch from its update window.

- Signed updates with Sparkle, separate Apple Silicon and Intel feeds.
- Check for Updates in the sidebar and Kaze menu; optional automatic checks.
- Terms and License is now a regular sidebar item, with a cleaner footer.
- Disk access shows a soft green shield with a check when access is available, and a neutral shield while permission is pending.
- Existing 1.0.0 users must install 1.1.0 once to enable future in-app updates.

A native Sora Agency app to explore Mac storage, clean caches and organize maintenance tasks.

- Total folder sizes without opening them; sorting by size, name, type and date.
- Indicators for regenerable caches and sensitive locations.
- Management of apps, related data and Docker/Xcode resources.
- Multiple independent scheduled tasks; disabled 09:30 preset.
- Light and dark modes, Sora logo, Lucide icons and consistent controls.
- Animated interface with Reduce Motion support.
- English and Spanish interface, notifications and documentation; instant in-app language switching.
- Compact Sora installer with bilingual instructions and Retina graphics.
- Modular code, local builds and MIT license.

## Install

Choose `Kaze-Mac-arm64.dmg` for Apple Silicon or `Kaze-Mac-x86_64.dmg` for Intel.
Open the DMG, drag Kaze to Applications and eject the volume. Requires macOS 13+.
The architecture ZIP also includes `Instalar.command` for installation in
`~/Applications` with automatic backup, and `Desinstalar.command` to remove that
installation and its scheduled agents.

Packages are ad hoc signed and not notarized by Apple. If macOS blocks the first
launch, verify the source and use **Privacy & Security → Open Anyway**.
`Kaze-Source.zip` includes source and build instructions; SHA-256 hashes verify
file integrity. Kaze works locally and does not send your files to Sora Agency.
Review selections before deletion: Docker/Xcode resources may be permanently
removed. MIT code is provided without warranties, under the included license
and terms.

---

## Español

Kaze ahora busca versiones nuevas y permite descargar, instalar y reiniciar desde su ventana de actualización.

- Actualizaciones firmadas con Sparkle, para Apple Silicon e Intel.
- Buscar actualizaciones en el menú lateral y el menú Kaze; búsqueda automática opcional.
- Términos y licencia pasa a ser un ítem del menú lateral; se elimina «Sora Agency» del pie.
- El acceso al disco muestra un escudo verde suave con un check cuando está disponible, y un escudo neutro mientras el permiso está pendiente.
- Quienes usan 1.0.0 deben instalar 1.1.0 una vez para habilitar las siguientes actualizaciones dentro de la app.

Una app nativa de Sora Agency para explorar el almacenamiento de tu Mac,
limpiar cachés y organizar tareas de mantenimiento.

- Tamaño total de las carpetas sin abrirlas; orden por peso, nombre, tipo y fecha.
- Indicadores de cachés regenerables y ubicaciones sensibles.
- Gestión de apps, datos asociados y recursos de Docker y Xcode.
- Varias tareas programadas, con horarios y categorías independientes.
- Preset de las 09:30 desactivado y activación siempre explícita.
- Modos claro y oscuro, logo original de Sora, iconos Lucide y controles uniformes.
- Interfaz animada con soporte de Reducir movimiento.
- Interfaz, notificaciones y documentación en inglés y español, con selector dentro de la app.
- Instalador con estética Sora, instrucciones bilingües y gráficos Retina.
- Código modular, compilación local y licencia MIT.

## Instalar

Elige `Kaze-Mac-arm64.dmg` para Apple Silicon o `Kaze-Mac-x86_64.dmg` para Intel.
Abre el DMG, arrastra Kaze a Aplicaciones y expulsa el volumen. Abre la app desde
`/Applications/Kaze.app`. Requiere macOS 13 o posterior.

El ZIP de cada arquitectura incluye también `Instalar.command` para instalar
en `~/Applications` con respaldo automático de la versión anterior, además de
`Desinstalar.command` para retirar esa instalación y sus agentes programados.

Los paquetes tienen firma ad hoc y no están notarizados por Apple. Si macOS
bloquea la primera apertura, revisa su origen y utiliza **Privacidad y seguridad
→ Abrir igualmente**. No necesitas desactivar Gatekeeper.

`Kaze-Source.zip` contiene las fuentes y las instrucciones para compilar.
Los hashes SHA-256 permiten verificar la integridad de los archivos descargados.

Kaze trabaja localmente y no envía tus archivos a Sora Agency. Revisa las
selecciones antes de eliminar datos: los recursos Docker/Xcode pueden borrarse
permanentemente. El código se ofrece bajo MIT, sin garantías, según la licencia
y los términos incluidos en cada paquete.
