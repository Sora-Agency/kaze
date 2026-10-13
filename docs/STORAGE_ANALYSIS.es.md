# Análisis de almacenamiento

[English](STORAGE_ANALYSIS.md) · [Español](STORAGE_ANALYSIS.es.md)

Smart Scan es el punto de entrada. **Analizar Mac** inventaría el home actual,
Applications, Library y private/var en sus respectivos volúmenes. **Elegir
carpeta** acota el análisis. No se elimina nada al analizar. Las rutas
inaccesibles, los proveedores de nube y los volúmenes excluidos se indican como
cobertura incompleta. Ubicaciones queda en el menú de navegación del Explorador.

- **Smart Scan:** agrupa cachés regenerables conocidas, elementos para revisar,
  aplicaciones, duplicados exactos y recursos de desarrollo. Nada se preselecciona.
- **Space Map:** zoom por carpetas, navegación superior/raíces, Quick Look,
  Finder y Explorador. El área representa bytes asignados. Más elementos
  conserva los totales cuando se omiten detalles.
- **Duplicados:** filtra por tamaño y compara SHA-256 por bloques. Conserva una
  copia y recalcula su hash y el de cada copia seleccionada antes de moverla a
  Papelera. Excluye enlaces duros, archivos con resource forks, paquetes Photos, respaldos y sincronizados.
  La búsqueda rápida lee hasta 8 GiB, 10.000 archivos candidatos o 60 segundos.
  Hashes exhaustivos retira esos límites sobre los candidatos conservados y
  permite cancelar. La comparación visual es explícita: Vision de Apple usa
  miniaturas locales, hasta 400 imágenes con un límite de entrada de 32 MiB.
  La similitud visual propone revisión; nunca decide eliminar automáticamente.
- **Aplicaciones:** identificadores exactos, grupos declarados en firmas y rutas
  de ejecutables de LaunchAgents aportan evidencia. Coincidencias por nombre,
  grupos compartidos y agentes pendientes de desactivar quedan para revisión.
  El cierre también comprueba helpers dentro del bundle. Solo se seleccionan
  datos con atribución verificable y sin dependencias compartidas.
- **Historial:** cada nueva operación registra fecha, ruta/recurso, resultado,
  asignación afectada y recuperación disponible. El destino de Papelera y los
  metadatos del inode/cambios permiten restaurar sin sobrescribir. Se rechazan
  contenidos cambiados o ausentes, rutas originales alteradas y restauraciones
  entre volúmenes. Vaciar cachés y eliminar mediante Docker/simctl no admite
  deshacer. Se cargan inicialmente 500 registros; Cargar operaciones anteriores recupera los más antiguos.
- **System Data:** explica cachés, simuladores, respaldos iOS, logs, datos de apps
  y nombres de snapshots locales de Time Machine. macOS no expone un desglose
  exacto de su etiqueta System Data ni bytes exclusivos fiables por snapshot.
- **Developer Mode:** dependencias y cachés Node/npm/pnpm, Gradle, CocoaPods,
  Swift y Python; recursos Docker y simuladores; modelos Ollama, Hugging Face y
  LM Studio. Cada regla explica reconstrucción y procesos que deben cerrarse.
  Las fechas indican modificación, no demuestran último uso. Consultar último uso
  busca metadatos opcionales de Spotlight (hasta 500 elementos o 30 segundos);
  la ausencia se indica como desconocida. Dependencias de
  proyectos, almacenes compartidos, entornos y modelos requieren revisión manual
  para conservar cambios locales y datos personalizados.
- **Monitor:** mismo proceso de la app, una consulta de capacidad por minuto con
  tolerancia del temporizador; espacio disponible, crecimiento reciente de hasta una hora
  y accesos rápidos. Las notificaciones opcionales por debajo de 20 GB empiezan
  desactivadas, requieren permiso de macOS y se limitan a una cada seis horas.
  Desactivarlo en Ajustes y seguridad o el menú detiene el temporizador.
- **Reglas:** JSON versionado incluido y firmado con Ed25519. Los ámbitos de
  cachés, comandos fijos de mantenimiento y políticas de acciones nativas
  documentan alcance, motivo, recuperación y apps que deben cerrarse. Si falla
  la firma, estas acciones se bloquean. Las reglas llegan con actualizaciones de
  la app; no se ejecutan reglas remotas arbitrarias.
- **Asistente local:** recomendaciones verificadas e [IA local opcional](LOCAL_AI.es.md).
  Descarga el motor y modelo una vez desde el asistente; no se instalan automáticamente.
  Si ya están verificados, se abre el asistente directamente. Las preguntas usan un
  resumen acotado del análisis y se quedan en tu Mac. La IA no ejecuta limpiezas.

## Tamaños y rendimiento

Los bytes lógicos difieren de los asignados en archivos dispersos/comprimidos.
Los enlaces duros se cuentan una vez por inode. Clones y snapshots APFS pueden
compartir o retener bloques: la asignación es un máximo potencial, no una promesa
de recuperación. Kaze muestra un **rango 0–máximo potencial**, excluye ámbitos
protegidos/inaccesibles y no suma snapshots a los archivos. Mover a Papelera
libera cero bytes. Historial distingue asignación afectada, liberación confirmada
(desconocida en acciones nativas irreversibles) y variación observada del espacio
libre, que puede incluir actividad concurrente de macOS.

Una cola serial de utilidad recorre metadatos sin seguir enlaces simbólicos ni
leer contenidos. Conserva hasta 250.000 detalles y termina los totales de
metadatos accesibles. Si faltan detalles candidatos, los duplicados indican
cobertura incompleta. Para carpetas mayores, acota el análisis o abre el
Explorador. El mapa dibuja hasta 120 tiles y un agregado; las listas cargan más
resultados por lotes. El análisis es explícito y los inventarios de apps/recursos
se cargan al abrir su sección. Smart Scan restaura los resultados de la última sesión sin recalcular hashes;
se indican como guardados y requieren un análisis nuevo antes de limpiar.
El Explorador guarda las carpetas visitadas, muestra cuándo se midieron y reutiliza
Smart Scan desde la primera entrada. Al abrir una carpeta valida eventos de macOS
para actualizar solo las ramas cambiadas en segundo plano. Si faltan eventos, el volumen cambió o la medición tiene más de un día, requiere
actualización. Las ramas inaccesibles que no cambiaron conservan su medición
parcial. Los árboles de 50.000 archivos medidos o más mantienen la base fechada
y piden actualizar al detectar cambios, evitando recorridos repetidos en segundo plano. Los enlaces duros compartidos conservan la deduplicación del
padre mediante un recorrido completo cuando hay cambios. Actualizar fuerza un
recorrido completo y Detener conserva los resultados anteriores. La caché local
contiene solo metadatos, ocupa hasta 128 MiB y conserva hasta 32 carpetas en
`~/Library/Application Support/Kaze/Analysis-v1`; eliminarla no elimina archivos del usuario.

Historial se guarda en `~/Library/Application Support/Kaze/Operations`.
Las rutas y mensajes de herramientas pueden ser sensibles; revísalos antes de
compartir logs/capturas. No se envían automáticamente. [Privacidad](../PRIVACY.txt)
describe los datos locales conservados.

## Cobertura de limpieza y oportunidades

El catálogo firmado v2 añade cachés HTTP, de código y GPU de VS Code y Slack,
y descargas globales de Yarn Classic. No incluye perfiles, User, Backups,
almacenamiento de sesiones, extensiones instaladas ni `.yarn/cache` de proyectos.
La limpieza manual/programada también incluye pip y CocoaPods. Cada ámbito
requiere cerrar sus procesos y volver a comprobar el árbol antes de modificarlo.

Smart Scan reserva detalles para las rutas firmadas y sus ancestros dentro del
mismo límite de 250.000 entradas. No añade otro recorrido ni amplía los límites
de hashes. Los totales y resúmenes se preparan en la cola de utilidad.

Recuperación potencial suma solo cachés aptas y copias exactas verificadas.
Espacio para revisar muestra asignación ocupada por apps, proyectos y archivos
que requieren decisión manual; excluye las copias redundantes ya verificadas.
No es espacio liberable garantizado ni se suma al rango de recuperación.
Las cards muestran bytes además del número de hallazgos; el tamaño lógico
sigue disponible en Detalles del análisis.

Fuentes de alcance: [caché de Electron](https://www.electronjs.org/docs/latest/api/session),
[cachés de VS Code](https://github.com/microsoft/vscode/blob/main/.github/skills/auto-perf-optimize/scripts/userDataProfile.mts)
y [caché de Yarn Classic](https://classic.yarnpkg.com/lang/en/docs/cli/cache/).

## Mantener las reglas

Edita `src/Rules/rules-v1.json`, revisa ámbitos/recuperación y firma mediante
`scripts/sign-rules.sh` con la clave existente de Kaze en el llavero de inicio.
Nunca incluyas claves privadas en el repositorio. `scripts/verify-rules.swift`
verifica firmas y la compilación rechaza reglas alteradas o sin firma. El runtime
comprueba también versión/esquema, IDs únicos y ámbitos relativos seguros.
Añade pruebas de comportamiento antes de ampliar un ámbito automáticamente
eliminable. Ejecuta `scripts/test.sh`, `scripts/build.sh` y
`python3 tests/DistributionTests.py` antes de publicar.

## Base persistente

Smart Scan se guarda de forma atómica antes de mostrar que terminó. Invalidar
conserva el último registro fechado y bloquea el borrado con datos antiguos.
Navegar por el Explorador no desplaza ese registro; siguen los límites de
128 MiB y 32 carpetas. Si un Smart Scan es demasiado grande, reduce detalles
guardados, conserva los totales completos de todas las raíces e indica límites
en mapa y duplicados. Los errores de guardado se muestran. Los registros
existentes se migran desde Library/Caches a Application Support en la cola de
utilidad. El Explorador guarda avances con frecuencia limitada; una medición
interrumpida queda pendiente, no se presenta como actualizada.
