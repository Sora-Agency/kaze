# IA local opcional

[English](LOCAL_AI.md)

Kaze incluye la integración y licencias, sin motor ni modelo de IA. Abre
**Asistente local → Descargar IA local** para descargar aproximadamente 650 MB
una sola vez. El botón muestra progreso, cancelación y errores con reintento.
Si existe una instalación verificada, se abre el asistente directamente; si está
dañada, se solicita descargar otra vez. Smart Scan y sus reglas funcionan sin IA.
La IA requiere macOS 13.3 o posterior y al menos 1,5 GB libres para prepararse.

Los componentes fijados son [llama.cpp b10566](https://github.com/ggml-org/llama.cpp/releases/tag/b10566)
(MIT, arm64 o x64 nativo) y [Qwen3-0.6B Q8_0](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/tree/23749fefcc72300e3a2ad315e1317431b06b590a)
(Apache 2.0). LocalAIPackage registra tamaños, SHA-256 y revisión del modelo.
Las descargas conectan con GitHub/Hugging Face y sus CDN; no envían el análisis.
Una descarga cancelada o inválida no activa una instalación parcial. Se eliminan
los archivos temporales; el siguiente intento reinicia la transferencia.

Solo una consulta inicia el motor: un proceso temporal con 2 hilos de CPU, sin
GPU, contexto de 4096 tokens y hasta 384 tokens de respuesta. Se detiene al
cancelar o tras 90 segundos. Las comprobaciones, hashes e inferencia se ejecutan
fuera del hilo principal. No hay un servicio de IA activo cuando no consultas.
La memoria del modelo se libera al terminar; consultar requiere RAM y CPU extra.

El contexto contiene la pregunta acotada, totales medidos, hasta cuatro resúmenes
de reglas verificadas y seis candidatos de Smart Scan. Sus identificadores,
ubicaciones abreviadas y metadatos se procesan localmente; se excluyen contenidos
y rutas absolutas. El motor genera JSON restringido a esos identificadores y Kaze
valida la respuesta por separado. Los identificadores desconocidos, comandos,
rutas inventadas y respuestas incompletas no crean acciones. AssistantQueryIntent
responde a saludos simples sin ejecutar el motor y solo entrega candidatos para
peticiones de gestión o limpieza; las preguntas informativas y negativas no
ofrecen acciones sobre archivos.

Cuando pides limpiar, el asistente puede proponer hasta tres elementos para mover
a la Papelera. Cada tarjeta muestra la ruta real, asignación y, si existe una regla
firmada, motivo, recuperación y procesos que cerrar. **Revisar acción** abre una
confirmación sin mover nada. Cada archivo requiere su confirmación; las carpetas
requieren además marcar que revisaste su contenido. Escribir una autorización en
el chat nunca ejecuta una propuesta. No hay autorización general ni automática,
borrado permanente, ejecución de comandos ni herramienta para vaciar la Papelera.

Las propuestas se vinculan a la consulta, identidad medida, fecha y revisión del
análisis. Los análisis guardados permiten seguir conversando: Kaze indica su
fecha y que los totales pueden haber cambiado. Antes de proponer acciones verifica
metadatos de hasta dieciocho candidatos, descarta los modificados o inexistentes
y entrega como máximo seis a la IA. No recorre el disco ni las carpetas en esta
etapa. Otra operación revoca las aprobaciones pendientes; una nueva consulta
puede comprobar de nuevo los archivos sin cambios. Un cambio durante la inferencia
conserva la explicación y descarta sus propuestas.
Otra consulta, cancelar, desinstalar la IA o un cambio de análisis revocan las
aprobaciones. Antes de mover, Kaze vuelve a verificar ubicación, identidad,
procesos activos y contenido protegido mediante el servicio de Papelera y la
exclusión de operaciones existentes. Cada traslado aparece en Historial e invalida
las propuestas restantes. Se mantienen las protecciones de respaldos, Photos y
datos sincronizados. Las apps y los recursos nativos de Docker siguen en sus
secciones. Solo se ofrecen hallazgos elegibles del índice; la consulta no vuelve
a recorrer el disco ni lee documentos.

Instalación: `~/Library/Application Support/Kaze/AI/<versión-fijada>/`.
Usa **Desinstalar IA** para recuperar su espacio; al abrir el asistente se
ofrecerá descargar nuevamente. Los archivos temporales de
consulta se eliminan al terminar. Los archivos AI persisten tras desinstalar Kaze hasta que los eliminas explícitamente.

Las pruebas usan instalaciones temporales, nunca la carpeta de IA del usuario.
Los archivos del modelo utilizados para QA quedan en build y no se incluyen en
Git ni en los instaladores. DistributionTests verifica que solo se empaquetan las
licencias, sin modelo GGUF, archivo del motor ni ejecutable llama.

## Desinstalar la IA

El botón **Desinstalar IA** en el asistente elimina solo el motor, los modelos y
versiones anteriores dentro de `~/Library/Application Support/Kaze/AI`. Pide
confirmación, detiene las consultas pendientes y ejecuta el borrado en segundo
plano. Conserva análisis, historial, ajustes y modelos de otras herramientas.
También permite retirar una instalación dañada y descargarla nuevamente.
No sigue enlaces simbólicos a directorios externos.

La comprobación opcional `AssistantFileActionsTests --real-model` usa el motor
y modelo ya instalados y verificados por SHA, en modo de lectura. No descarga
ni instala IA; sus consultas contienen solo datos de prueba. El motor recibe
`--json-schema`, y las pruebas rechazan la opción incompatible `--json`.


## Conversaciones guardadas

**Nuevo chat** inicia una conversación independiente. **Chats** permite reabrir
las conversaciones guardadas; su menú contextual elimina una conversación tras
confirmarlo. Preguntas, respuestas, actividad, fechas y rutas de acciones
confirmadas se guardan localmente en
`~/Library/Application Support/Kaze/Chats/conversations.json`. El archivo tiene
permisos exclusivos del usuario y un formato versionado, conserva hasta 30 chats
y 40 consultas por chat y tiene un límite de 8 MiB. Los errores de lectura o
escritura se muestran; un archivo dañado se conserva. Las respuestas terminadas
se restauran sin inferencia. Las consultas interrumpidas quedan detenidas y no
se reanudan automáticamente.

Cada consulta usa como contexto hasta dos intercambios recientes y terminados
del chat seleccionado, con longitud acotada. Las explicaciones anteriores son
históricas; solo los traslados registrados correctamente se consideran acciones
confirmadas. Los chats no comparten memoria entre sí ni leen documentos para
recordar el contexto. No se restauran propuestas ejecutables: cada propuesta
nueva exige comprobaciones actuales y confirmación separada. Eliminar un chat
conserva el registro de operaciones y no afecta a los archivos restaurados.
Desinstalar la IA conserva las conversaciones. La lectura y escritura usan una
cola serial en segundo plano y ocurren al iniciar o terminar consultas y al
registrar acciones reales, sin temporizadores de sondeo.
