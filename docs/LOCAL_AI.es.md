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

El contexto contiene la pregunta acotada, totales medidos y hasta cuatro resúmenes
de reglas verificadas, sin contenidos de archivos ni rutas completas. Las respuestas
pueden equivocarse; las recomendaciones verificadas permanecen visibles junto a
ellas. La IA no tiene herramientas ni permisos para limpiar. Se conservan las
confirmaciones y verificaciones existentes para borrado.

Instalación: `~/Library/Application Support/Kaze/AI/<versión-fijada>/`.
Usa **Desinstalar IA** para recuperar su espacio; al abrir el asistente se
ofrecerá descargar nuevamente. Los archivos temporales de
consulta se eliminan al terminar y no se guarda historial de chat. Los archivos
AI persisten tras desinstalar Kaze hasta que los eliminas explícitamente.

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
