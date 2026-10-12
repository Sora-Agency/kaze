# Publicar Kaze bajo Sora Agency

[English](PUBLISHING.md) · [Español](PUBLISHING.es.md)

El destino previsto es `Sora-Agency/kaze`. La compilación local no sube archivos.
GitHub Actions crea una release en borrador cuando subes un tag de versión.

## Repositorio

1. Crea un repositorio público llamado `kaze` en la organización `Sora-Agency`.
   Créalo vacío: este proyecto ya incluye README, licencia MIT y `.gitignore`.
2. Publica la rama `main` desde este proyecto con GitHub Desktop o Git.
3. En **About**, utiliza esta descripción:

   > A native macOS storage explorer and cleanup app by Sora Agency.

4. Añade los temas `macos`, `swift`, `swiftui`, `storage`, `disk-cleanup`,
   `sora-agency` y `open-source`.
5. Habilita Issues y GitHub Actions. El workflow `macos.yml` verifica los
   cambios en `macos-15` (Apple Silicon) y `macos-15-intel` (Intel), con permisos
   de lectura. Solo el job de release tiene `contents: write`, para crear el
   borrador y adjuntar archivos. No instala la app en el equipo ni ejecuta
   limpiezas reales; la prueba de instalación copia la app a una carpeta temporal.

Usa una cuenta o GitHub App de Sora para crear el repositorio y subir cambios.
La organización puede ser propietaria del repositorio, pero no es una cuenta
de acceso. Una cuenta personal puede aparecer en la actividad pública aunque
el autor de Git sea distinto. Configura el autor de este repositorio antes del
primer commit:

```sh
git config --local user.name "Sora Agency"
git config --local user.email "git@soraagency.invalid"
git config --local commit.gpgsign false
```

La dirección reservada `.invalid` es un dato de autoría, no un correo de
contacto, y no revela un correo personal. Puedes
reemplazarla por un correo verificado exclusivamente en la cuenta de Sora.
El correo `noreply` de una cuenta personal sigue atribuyéndole los commits.

[Atribución de commits en GitHub](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address)
· [Actividad pública del repositorio](https://docs.github.com/en/rest/activity/events)

```sh
git add .
git commit -m "Add Kaze for macOS"
git remote add origin git@github.com:Sora-Agency/kaze.git
git push -u origin main
```

Si ya tienes un remoto `origin`, verifica su destino antes de cambiarlo.
No se versionan binarios, preferencias, respaldos ni datos del equipo.
Las instalaciones anteriores se detectan localmente para migrarlas; los bundles
y tareas nuevas usan `com.soraagency.kaze`.

## Configurar las actualizaciones una vez

Kaze incorpora Sparkle 2.10.0. La clave pública `SUPublicEDKey` está en
`src/Info.plist`; la privada de esta distribución se conserva en el llavero de
inicio de sesión, cuenta `com.soraagency.kaze`. Mantén un respaldo seguro de la
clave: las apps ya instaladas confían en esa clave pública.

Configura el secret de Actions `KAZE_SPARKLE_PRIVATE_KEY` con la exportación de
Sparkle. No lo pongas en el repositorio, notas ni adjuntos. Para exportarlo a un
archivo temporal y subirlo sin mostrarlo en la terminal:

```sh
sparkle_dir="$(scripts/fetch-sparkle.sh)"
key_dir="$(mktemp -d -t kaze-key)"
"$sparkle_dir/bin/generate_keys" --account com.soraagency.kaze -x "$key_dir/key"
gh secret set KAZE_SPARKLE_PRIVATE_KEY --repo Sora-Agency/kaze < "$key_dir/key"
rm "$key_dir/key"
rmdir "$key_dir"
```

Un colaborador sin esa clave puede compilar y probar; para firmar releases debe
usar la clave original. Para una distribución independiente genera otra clave y
actualiza `SUPublicEDKey` antes de distribuir la primera versión.

Los tags generan y verifican firmas EdDSA del DMG y del feed para cada
arquitectura. Si falta el secret o las firmas no coinciden con la clave de la
app, el proceso falla antes de crear el borrador. Para probar localmente:

```sh
scripts/build.sh
scripts/generate-appcast.sh v1.1.0
```

Publica ambas feeds junto con los instaladores y marca la release estable como
**Latest**. Las URLs `releases/latest/download/appcast-arm64.xml` y
`appcast-x86_64.xml` apuntan a esa release; un borrador o prerelease no activa
actualizaciones. No edites las feeds después de firmarlas. Incrementa siempre
`CFBundleVersion`: Sparkle compara ese número, no solo la versión visible.

Quienes tienen 1.0.0 necesitan instalar 1.1.0 una vez. A partir de esa instalación,
la ventana de Sparkle permite descargar, instalar y reiniciar. Se conservan
las preferencias y tareas fuera del bundle; el respaldo del instalador ZIP
no se aplica a Sparkle. Las ventanas nativas de Sparkle siguen el idioma de
macOS; los controles de Kaze siguen el selector interno.

## Crear una release en borrador

1. Actualiza `CFBundleShortVersionString` y aumenta `CFBundleVersion` en
   `src/Info.plist`. La versión preparada es **1.2.6**, build **23**.
2. Actualiza [RELEASE_NOTES.md](RELEASE_NOTES.md). Su primera línea debe coincidir
   con la versión: por ejemplo, `# Kaze 1.2.6`. Estas notas serán el texto inicial
   del borrador.
3. Incorpora los cambios a `main` y espera a que las comprobaciones pasen.
4. Crea un tag anotado sobre ese commit y súbelo. Para la versión actual:

   ```sh
   git switch main
   git pull --ff-only
   git tag -a v1.2.6 -m "Kaze 1.2.6"
   git push origin v1.2.6
   ```

5. Sigue la ejecución de **macOS** en **Actions**. El tag vuelve a ejecutar
   pruebas, compilación y verificación del DMG en ambas arquitecturas.
6. Cuando termine, abre **Releases**, revisa el borrador **Kaze 1.2.6** y pulsa
   **Publish release** cuando esté listo. Puedes editar las notas antes de publicar.

Los tags admitidos tienen formato `vMAJOR.MINOR.PATCH` y deben coincidir con
la versión de la app. Los PRs, pushes de ramas y ejecuciones manuales solo
verifican y compilan; la creación del borrador requiere un push de tag.

El borrador contiene estos diez adjuntos:

| Archivo | Contenido |
| --- | --- |
| `Kaze-Mac-arm64.dmg` | Instalador por arrastre para Apple Silicon |
| `Kaze-Mac-x86_64.dmg` | Instalador por arrastre para Intel |
| `Kaze-Mac-arm64.zip` | App y scripts de instalación para Apple Silicon |
| `Kaze-Mac-x86_64.zip` | App y scripts de instalación para Intel |
| `Kaze-Source.zip` | Código, documentación y capturas |
| `Kaze-SHA256-arm64.txt` | Hashes del DMG, ZIP binario, fuentes compartidas y feed |
| `Kaze-SHA256-x86_64.txt` | Hashes del DMG, ZIP binario, fuentes compartidas y feed |
| `appcast-arm64.xml` | Feed firmado de actualizaciones para Apple Silicon |
| `appcast-x86_64.xml` | Feed firmado de actualizaciones para Intel |
| `SHA256SUMS` | Hashes de los nueve archivos anteriores |

Antes de crear el borrador se verifican los hashes y que ambas arquitecturas
incluyan el mismo código fuente. No se crea una release si falla un build.
El token automático de GitHub basta; no necesitas agregar un token personal.
La creación utiliza [`gh release create --draft`](https://cli.github.com/manual/gh_release_create).

Si falla la subida de adjuntos, usa **Re-run all jobs** en esa ejecución de
Actions. Si el borrador ya existe, se completan o reemplazan sus adjuntos y se
conservan las notas que hayas editado. Las releases publicadas no se modifican.

Revisa que las notas indiquen que los paquetes tienen firma ad hoc y no están
notarizados por Apple. Cada DMG y ZIP contiene una sola arquitectura.

La firma con Developer ID y la notarización requieren las credenciales y la
cuenta de Apple de quien distribuya la app; no forman parte de este proyecto.

## Actualizar la presentación

```sh
scripts/test.sh
scripts/build.sh
python3 tests/DistributionTests.py
scripts/screenshots.sh
```

Ambas arquitecturas incluyen inglés y español.

Revisa ambos README, los enlaces relativos y las imágenes. Las capturas públicas
solo usan fixtures ficticios; no las sustituyas por capturas del Finder,
registros reales o carpetas personales. Conserva los avisos de Lucide, Feather,
DM Sans y Raleway junto con los archivos legales de Kaze.
