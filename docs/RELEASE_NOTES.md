# Kaze 1.0.0

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
