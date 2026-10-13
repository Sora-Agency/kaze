# Optional local AI

[Español](LOCAL_AI.es.md)

Kaze ships the integration and licenses, without an AI engine or model. Open
**Local assistant → Download local AI** to download about 650 MB once. The
button shows progress, cancellation and integrity errors with retry. A verified
installation opens the assistant directly; a damaged one requires downloading
again. Smart Scan and cleanup rules work without AI. AI requires macOS 13.3+.

The pinned components are [llama.cpp b10566](https://github.com/ggml-org/llama.cpp/releases/tag/b10566)
(MIT, native arm64 or x64) and [Qwen3-0.6B Q8_0](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/tree/23749fefcc72300e3a2ad315e1317431b06b590a)
(Apache 2.0). LocalAIPackage records exact sizes, SHA-256 and model revision.
Downloads come from GitHub/Hugging Face and their CDNs. No scan context is sent.
Failed/canceled transfers never activate a partial installation. Temporary staging
is removed; subsequent attempts restart the transfer. Allow at least 1.5 GB free.

Only a question starts inference. A short-lived child process uses 2 CPU threads,
no GPU, a 4096-token context and at most 384 output tokens. Cancellation or a
90-second deadline stops it. Checks, SHA verification and inference stay off the
main thread. There is no AI service running while idle. Model RAM is released
when the child exits; inference still needs additional memory and CPU temporarily.

The prompt includes a bounded question, measured category totals and up to four
verified rule summaries. It excludes file contents and full paths. Responses are
advisory and can be wrong; verified recommendations remain visible alongside them.
AI has no tools or cleanup capability. Existing cleanup confirmations and safety
checks are unchanged, including protected backups, Photos and synchronized data.

Installation: `~/Library/Application Support/Kaze/AI/<pinned-version>/`.
Use **Uninstall AI** to remove the AI folder; reopening the assistant will offer
the download again. Query files use a private temporary
folder and are removed afterward. The integration does not retain chat history;
AI files persist after uninstalling the app, until explicitly removed.

`LocalAITests` verifies no automatic installation, hash rejection, cancellation,
timeouts and native model phases using temporary fixtures. Its optional
`--real-model` check uses verified assets under `build/verification/ai-engine` in
a temporary home, never the user's AI directory. Those QA assets are excluded
from Git and all release packages. DistributionTests checks that the app contains
licenses but no GGUF, engine archive or llama executable.

## Uninstall AI

The assistant's **Uninstall AI** button only removes downloaded engines, models
and previous versions within `~/Library/Application Support/Kaze/AI`. It asks
for confirmation, stops pending queries and removes files in the background.
Scans, history, settings and other tools' models are preserved. A damaged
installation can also be removed and downloaded again. External directory
symlinks are not followed.
