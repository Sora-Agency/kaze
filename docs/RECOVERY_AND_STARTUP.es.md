# Recuperación y apps al inicio

Las dos herramientas están en **Gestionar**. Al abrir Kaze no se enumeran discos
ni se solicita permiso de Automatización.

## Recuperación

Kaze adapta el lector APFS de LibreRescateNativo, con licencia MIT. Lee una
partición física APFS de un disco externo o una imagen sin comprimir del
contenedor. Para una imagen del disco completo, indica el desplazamiento de la
partición en bytes en Opciones de imagen. No admite DMG comprimidos, volúmenes
cifrados o sellados, búsqueda de archivos borrados ni versiones históricas.
Los bloques ilegibles pueden impedir recuperar algunos archivos. La compresión
no soportada y los enlaces simbólicos quedan registrados como errores.
Se rescata el contenido de los archivos; no se reproducen todos sus atributos,
permisos, ACL ni resource forks independientes.

Pulsa Detectar discos, confirma la partición y abre el origen. El identificador
puede cambiar al reconectar. macOS autoriza la lectura mediante `authopen`;
Kaze no recibe la contraseña. Elige el volumen, explora las carpetas, marca
archivos o carpetas y pulsa Recuperar selección. Guarda en otro disco físico.
La comprobación contempla los discos físicos de contenedores APFS compartidos.
Kaze no repara, formatea, monta ni escribe en el origen. Otro programa puede
seguir modificando un volumen montado; una imagen o un disco desmontado antes
de iniciar la recuperación ofrece una fuente más estable.

El destino es una carpeta privada nueva con UUID. No se sobrescriben archivos.
Los errores de copia permiten continuar con otros archivos y se eliminan las
copias incompletas. Detener conserva los archivos completos y genera el informe.
En hardware dañado una lectura del sistema puede tardar en responder. El informe
contiene rutas y errores locales y no se envía. El índice admite hasta 500.000
registros/entradas de mapa, con caché de bloques de hasta 32 MiB. No hay un
proceso permanente de recuperación.

El proyecto LibreRescateNativo original permanece intacto. Se incluye su licencia
en `Recovery/LibreRescate-LICENSE.txt` dentro de la app.

## Apps al inicio

Pulsa Cargar apps para leer los elementos de inicio mediante Eventos del Sistema.
macOS puede pedir permiso en Privacidad y seguridad → Automatización. Cada
lectura o cambio requiere una acción del usuario. Desactivar una app elimina
su elemento de inicio; Kaze guarda antes su ruta y preferencia de apertura
oculta para poder volver a activarla. Confirma el resultado consultando macOS.
Añadir app permite seleccionar una aplicación instalada. Desactivarla al inicio
no cierra una app que ya está ejecutándose.

Las referencias desactivadas se conservan en
`~/Library/Application Support/Kaze/Startup/disabled-v1.json`. Si otra herramienta
elimina un elemento, Kaze solo conserva su referencia si la había guardado antes.
Esta lista no representa todos los servicios capaces de arrancar con macOS.

Los servicios en segundo plano y los helpers modernos tienen permisos distintos.
**Ajustes de macOS** abre su pantalla nativa para administrarlos. Kaze no modifica
la base privada de Background Task Management.

## Verificación

Las pruebas usan lectores simulados e imágenes APFS temporales. Comprueban copia
recursiva, errores, cancelación, rutas inválidas, colisiones, hash del origen,
selección de volumen y topología de discos. Las pruebas de inicio inyectan un
gestor simulado y ejecutan el script JXA contra Eventos del Sistema simulado.
No modifican apps de inicio reales ni leen un disco dañado del usuario.

Referencias: [APFS de Apple](https://developer.apple.com/support/downloads/Apple-File-System-Reference.pdf),
[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice),
[Mac Automation Scripting Guide](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/HowMacScriptingWorks.html).
