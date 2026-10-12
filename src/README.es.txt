KAZE · SORA
===========

English: README.txt · Español: README.es.txt

IDIOMA
La interfaz, los errores, las notificaciones, los términos y la privacidad están
en inglés y español. Usa el selector de idioma de la barra superior, junto al
botón de apariencia, para elegir Español o English. Cambia al instante y guarda
la preferencia para futuras aperturas y notificaciones programadas. Antes de
elegir, Kaze sigue el idioma de macOS, con inglés como alternativa. Las tareas y los nombres
de archivos se conservan; MIT y las licencias de terceros mantienen su texto.

Aplicación local para macOS. Funciona sin conexión a Internet.

INSTALAR EN OTRA MAC
Abre el DMG de tu arquitectura y arrastra Kaze a Aplicaciones.
Expulsa el volumen Kaze y abre /Applications/Kaze.app.
Para actualizar, cierra la app antes de reemplazarla.

ALTERNATIVA CON RESPALDO AUTOMÁTICO
1. Descomprime el ZIP completo.
2. Haz clic derecho sobre Instalar.command y elige Abrir.
3. La app quedará en ~/Applications. La limpieza programada empieza desactivada.
4. El paquete tiene firma ad hoc y no está notarizado por Apple. Si macOS
   bloquea la primera apertura, revisa su origen y autoriza Kaze desde Ajustes
   del Sistema > Privacidad y seguridad > Abrir igualmente.

EJECUTAR AHORA
Abre "Kaze" desde la carpeta Aplicaciones donde la instalaste.

INTERFAZ
- Términos y licencia está disponible en la barra lateral y en el menú Ayuda.
  Incluye los términos, la política de privacidad y la licencia MIT completos.
- Kaze (風, viento en japonés) es un producto de Sora Agency.
- Usa fondos grafito, acento cian y las tipografías DM Sans y Raleway.
  Incluye un toggle directo entre claro y oscuro.
- La app incluye barra lateral, logo original de Sora y una vista de almacenamiento.
- Explorador lee cualquier carpeta accesible del Mac y de discos externos.
- Inicio, Descargas, Documentos, Escritorio, Macintosh HD y Discos externos
  están disponibles en la barra lateral. También puedes elegir una carpeta
  o escribir su ruta desde el botón del lápiz.
- El tamaño total de cada carpeta incluye su contenido, aunque no la abras.
- Ordena por tamaño ascendente/descendente, nombre, tipo o fecha de modificación.
- Busca por nombre dentro de la carpeta actual y filtra archivos o carpetas.
- Los archivos ocultos están incluidos; puedes ocultarlos con el control Ocultos.
  Los filtros solo cambian la vista, no el total de la carpeta.
- Doble clic abre una carpeta; el menú contextual muestra elementos en Finder
  y permite copiar su ruta. Puedes volver, avanzar o usar las rutas superiores.
- Los tamaños se actualizan en segundo plano. Puedes detener el análisis y
  pulsar Actualizar para iniciarlo otra vez. Cambiar de carpeta cancela el anterior.
- Se mide espacio asignado en disco, no el tamaño lógico. Los enlaces simbólicos
  no se siguen y los enlaces duros se cuentan una vez por carpeta analizada.
  Un enlace duro compartido entre carpetas aparece en el tamaño de cada una,
  pero se cuenta una sola vez en el total de la carpeta que las contiene.
  APFS puede compartir bloques entre archivos; estos valores no predicen
  exactamente el espacio que se recuperaría al eliminarlos.
- macOS requiere Acceso total al disco para determinadas ubicaciones. Pulsa
  el icono del escudo y habilita Kaze en Ajustes del Sistema, luego vuelve
  a analizar. No se pueden eludir las protecciones del sistema.
- Un símbolo ≥ identifica tamaños parciales o en progreso; una carpeta todavía
  no medida muestra Calculando/Pendiente. Los errores se muestran explícitamente.
- El análisis usa metadatos, no abre contenidos ni solicita descargas de iCloud.
- Los iconos son vectores de Lucide incluidos en la app; no requieren conexión.
- La app anima el inicio, la navegación, las cargas y los controles. Respeta
  Reducir movimiento en Ajustes del Sistema > Accesibilidad > Pantalla.
- El paquete y las tareas nuevas usan el identificador com.soraagency.kaze.
  Los ajustes y tareas de versiones anteriores se migran al abrir Kaze.
- La sección Limpieza muestra el espacio libre, progreso y categorías.
- La sección Aplicaciones ordena las apps por el espacio total que ocupan.
- Cada app con datos locales tiene un desplegable con sus carpetas y tamaños.
- Puedes mover solo las carpetas seleccionadas a la Papelera, conservando la app.
- La sección Recursos detecta imágenes, contenedores y volúmenes Docker,
  además de simuladores y runtimes descargados de Xcode.
- Recursos también muestra, agrupados por aplicación, todos los datos locales
  detectados aunque Docker y Xcode estén cerrados.
- Las carpetas funcionan como un explorador jerárquico: cada nivel se carga al
  abrirlo y permite seleccionar carpetas o archivos concretos.
- Seleccionar una carpeta desmarca sus descendientes para evitar borrados
  duplicados; los enlaces simbólicos no se recorren.
- La sección Actividad muestra la actividad y los errores en tiempo real.
- Las aplicaciones solo se eliminan después de seleccionarlas y confirmar.
- Apps y datos relacionados se mueven a la Papelera; no se vacía sola.
- Los recursos Docker/Xcode se seleccionan individualmente y se eliminan
  permanentemente solo después de una segunda confirmación.
- Los contenedores en ejecución se pueden seleccionar; se detienen únicamente
  al confirmar su eliminación. Los simuladores encendidos quedan bloqueados.
- El análisis de Docker y Xcode tiene límites de tiempo: si una herramienta no
  responde, Recursos termina el análisis sin bloquear el resto de la app.
- Si Docker Desktop está abierto pero su motor no responde, la app ofrece un
  reinicio confirmado y vuelve a analizar al finalizar.
- Las apps instaladas para todos los usuarios pueden pedir contraseña de
  administrador; algunos contenedores requieren Acceso total al disco.

QUÉ LIMPIA
- Cachés generales del usuario.
- Cachés regenerables de Nx, Gradle, npm y pnpm.
- Versiones antiguas y caché de Homebrew.
- DerivedData de Xcode y dispositivos de simulador no disponibles.
- Cachés de Discord.
- Caché de compilación de Docker con más de siete días y objetos dangling.

QUÉ CONSERVA
- Documentos, Descargas, Escritorio, fotos y archivos de iCloud.
- Proyectos, repositorios, .git y node_modules.
- Credenciales, historiales y datos de aplicaciones.
- En la limpieza automática: contenedores, imágenes etiquetadas y todos los
  volúmenes de Docker. Solo se borran si los seleccionas en Recursos.
- En la limpieza automática: simuladores disponibles, runtimes y archivos
  Archive de Xcode. Simuladores y runtimes solo se borran desde Recursos.

PROGRAMACIÓN
La pestaña Tareas programadas incluye una limpieza preconfigurada para las
09:30 cada día, solo cuando queden menos de 70 GiB, pero desactivada.
Puedes crear, nombrar, editar, activar o eliminar varias tareas independientes.
Cada tarea tiene su propio horario y categorías, además de frecuencia diaria,
de lunes a viernes o semanal; hora, día,
umbral de espacio, categorías y notificaciones. Guardar cambios no activa
una tarea desactivada: usa el interruptor Activar tarea para programarla.
La programación funciona con tu sesión iniciada aunque Kaze esté cerrada.
Las actualizaciones conservan una tarea que hayas activado desde esta UI.
Al migrar una versión antigua se desactiva la programación automática de
las 09:30 y se guarda un respaldo. La limpieza manual sigue siendo inmediata.
La configuración está en ~/Library/Application Support/Kaze/schedule.json;
se instala un agente por tarea en ~/Library/LaunchAgents solo al activarla.
La configuración anterior se migra conservando sus opciones y estado.
Las tareas coincidentes esperan su turno de limpieza hasta 30 minutos; si
no logran el turno, lo registran y finalizan sin limpiar. Los respaldos de
versiones anteriores se guardan en ZIP para evitar apps duplicadas en macOS.

REGISTRO
~/Library/Logs/LiberarEspacioMac/limpieza.log

DESINSTALAR
Ejecuta Desinstalar.command desde el paquete.

ACTUALIZACIÓN
Instalar.command guarda una copia de la app anterior y de su programación en
~/Library/Application Support/Kaze/Backups antes de instalar Kaze.
El identificador y la ruta del registro se conservan para mantener compatibilidad.

COMPILAR DESDE EL CÓDIGO
Ejecuta scripts/build.sh con las herramientas de línea de comandos de Xcode.
El resultado queda en package/Kaze.app, build/Kaze-Mac-<arquitectura>.dmg
y build/Kaze-Mac-<arquitectura>.zip.
El código fuente distribuible queda en build/Kaze-Source.zip.
README.es.md incluye las instrucciones completas y capturas con datos ficticios.
Ejecuta scripts/test.sh para verificar el escáner y la navegación.
El paquete generado corresponde a la arquitectura del Mac que lo compila.

OPEN SOURCE
El código de Kaze se distribuye bajo licencia MIT (archivo LICENSE).
El software se ofrece tal cual, sin garantías, y la responsabilidad de Sora
Agency y los colaboradores se excluye en la medida permitida por la ley.
Consulta TERMS.txt para los riesgos, límites y derechos que siguen vigentes,
y PRIVACY.txt para el tratamiento local de datos y registros.
Las tipografías incluidas conservan su licencia SIL Open Font License en Fonts.
El código está preparado para publicarse; este paquete no crea por sí solo
un repositorio público ni promete soporte o mantenimiento continuos.

INDICADORES DE BORRADO

El explorador permite filtrar la lista por seguridad de borrado:
- Verde: cachés del usuario y archivos de compilación conocidos y regenerables.
  Cierra las aplicaciones que los utilizan antes de borrarlos.
- Rojo: componentes del sistema, aplicaciones, configuración y datos sensibles.
- Gris: archivos que requieren revisar su contenido, incluidos documentos,
  descargas y enlaces simbólicos. No se consideran seguros por su extensión.
Pasa el cursor sobre cada elemento para leer el motivo. Estos indicadores
no borran archivos ni cambian el tamaño total mostrado de la carpeta.

El botón de sol/luna alterna entre modo claro y oscuro con un clic.
La ubicación activa sigue marcada al navegar por sus subcarpetas.
Kaze utiliza el logo original de Sora en la interfaz y en el icono de la app.

ANÁLISIS DE ALMACENAMIENTO
Smart Scan comparte un índice con Space Map, Duplicados, System Data y el asistente
local. Elegir carpeta acota el análisis. No se elimina nada al analizar.
SHA-256 comprueba copias exactas; Vision explícito solo propone fotos para revisar.
Historial restaura elementos intactos de Papelera sin sobrescribir; las operaciones
permanentes de cachés/Docker/simuladores no admiten deshacer. La recuperación es un
rango potencial porque APFS puede retener bloques compartidos. Las alertas son
opcionales. Las reglas se incluyen firmadas con Ed25519. Consulta la guía incluida
con el código fuente.
