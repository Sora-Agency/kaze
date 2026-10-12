# Contribuir a Kaze

[English](CONTRIBUTING.md) · [Español](CONTRIBUTING.es.md)

Gracias por contribuir a Kaze, un producto de Sora Agency. Puedes proponer
mejoras, corregir errores, mejorar la accesibilidad o actualizar la documentación.

## Preparar el entorno

Necesitas macOS 13+, herramientas de línea de comandos de Xcode y Git.
Haz un fork, clónalo y crea una rama para un cambio concreto. Después ejecuta:

```sh
scripts/test.sh
scripts/build.sh
python3 tests/DistributionTests.py
python3 tests/NativeStartupTests.py
open package/Kaze.app
```

La primera compilación descarga Sparkle 2.10.0 y verifica su SHA-256 fijado;
las siguientes usan la caché local. Los demás recursos están incluidos. Docker, Homebrew y el Xcode completo son opcionales y solo hacen
falta para probar sus integraciones respectivas.

## Scripts del proyecto

| Script | Uso |
| --- | --- |
| `scripts/build.sh` | Compila la app y genera DMG, ZIPs y hashes |
| `scripts/build-dmg.sh` | Prepara el DMG con instalación por arrastre |
| `scripts/test.sh` | Ejecuta las pruebas de la app y del flujo de release |
| `scripts/preview.sh` | Genera vistas para revisar la interfaz |
| `scripts/screenshots.sh` | Genera las capturas públicas con datos ficticios |
| `scripts/vendor-lucide.py` | Actualiza los vectores e iconos compilados |
| `scripts/prepare-release.py` | Verifica versiones y reúne los adjuntos de release |
| `scripts/create-draft-release.sh` | Crea o completa el borrador en GitHub |

Los scripts Python de `tests` verifican el DMG y la automatización de releases.
Los archivos `.zsh` de `src` ejecutan la limpieza y mantienen compatibilidad con
programaciones antiguas. Python se usa en desarrollo y CI; no es una dependencia
para abrir la app instalada. El DMG contiene la app con su motor de limpieza,
fuentes, icono y avisos legales; los scripts de desarrollo quedan en el ZIP
de fuentes.

NativeStartupTests abre la app compilada con las preferencias existentes y
ambos estados del monitor/temas, y comprueba que CPU y memoria se estabilizan.
Las capturas no cubren la integración de MenuBarExtra y AppStorage entre escenas.

## Trabajar en el código

- Mantén las entidades y reglas en `Domain`, el acceso a procesos y archivos
  en `Infrastructure` y las vistas y modelos de cada sección en `Features`.
- Usa los componentes de `DesignSystem` para botones, inputs, selección,
  tipografía e iconos. Comprueba los modos claro y oscuro y Reducir movimiento.
- Conserva las protecciones de limpieza, la deduplicación de enlaces y la
  migración de preferencias y tareas de versiones anteriores.
- Verifica los cambios de comportamiento con pruebas en directorios temporales
  y adaptadores de launchd; las pruebas no deben limpiar el equipo ni activar
  tareas reales.

[ARCHITECTURE.md](ARCHITECTURE.md) describe los límites entre módulos.

## Localización

Los catálogos de inglés y español están en `src/Localization/en.lproj` y
`es.lproj`. Usa `L10n.text("…")` para literales y mensajes interpolados, y
`L10n.string` para claves existentes de presentación. Añade la misma clave a
ambos `Localizable.strings` y conserva los placeholders. Los contadores usan
`Localizable.stringsdict`. No traduzcas valores persistidos, rutas, identificadores
ni nombres introducidos por el usuario.

Los mensajes del motor están en `src/localization.zsh`. Mantén ambas versiones
de los README, guías, términos y privacidad. MIT y las licencias de terceros
conservan su texto original. `KAZE_LANGUAGE=en` o `es` permite elegir el idioma
de las previews. Las pruebas verifican ambos idiomas, las tareas y el cambio en
una vista renderizada. Usa LocalizedText para mensajes de presentación almacenados
y observa AppLanguageStore en vistas con traducciones. Conserva la identidad de
las vistas, las ediciones del usuario y las operaciones en curso.

## Cambios visuales y capturas

```sh
scripts/preview.sh
scripts/screenshots.sh
```

El primer comando deja previews de revisión en `build/previews`. El segundo
actualiza las imágenes públicas en español de `docs/images` y las de inglés
de `docs/images/en` con fixtures de ejemplo.
Para estas capturas usa siempre el generador: no publiques nombres de usuario,
carpetas, registros, identificadores de recursos o proyectos personales.
Revisa el resultado antes de incluirlo en una pull request.

Los fixtures viven en `tests/PreviewFixtures.swift`. El renderizador usa las
vistas de SwiftUI y un runner simulado; no ejecuta limpieza ni registra tareas.
El editor público se captura con un viewport más alto para mostrar sus opciones.

## Iconos y fuentes

Los vectores de Lucide están fijados a una revisión específica y compilados en
`LucidePaths.generated.swift`. Para actualizar el subconjunto de iconos, modifica
`scripts/vendor-lucide.py` y ejecútalo con Python 3. Ese paso puede necesitar
Internet; una compilación normal no lo necesita. Conserva los avisos de terceros
y las licencias de los recursos originales.

## Enviar un cambio

Describe el problema, el comportamiento resultante y cómo lo verificaste.
Incluye capturas de ejemplo para cambios visuales. Ejecuta `scripts/test.sh`
y `scripts/build.sh`; no añadas `build`, `package`, registros o respaldos a Git.
Las contribuciones al código se distribuyen bajo la licencia MIT del proyecto.

GitHub Actions tiene una matriz para Apple Silicon e Intel y adjunta los paquetes
de cada compilación. Los runners usados corresponden a los
[runners de macOS publicados por GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Para preparar una versión, sigue [la guía de publicación](docs/PUBLISHING.es.md).
Las pruebas de release usan archivos temporales y una CLI de GitHub simulada;
no crean ni publican releases reales.

## Reglas de análisis de almacenamiento

Lee [la guía de análisis](docs/STORAGE_ANALYSIS.es.md) antes de cambiar ámbitos.
Los datos regenerables requieren selección explícita y procesos cerrados.
Conserva cancelación en las lecturas, separa los límites de detalles de la
cobertura y mantén la incertidumbre de APFS. Las reglas requieren revisión,
firma Ed25519 (`scripts/sign-rules.sh`) y pruebas con datos temporales.
Nunca incluyas claves privadas en el repositorio.
