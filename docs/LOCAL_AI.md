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

The prompt includes a bounded question, measured category totals, up to four
verified rule summaries and six eligible file candidates from Smart Scan. Candidate
IDs, short locations and metadata are local context; file contents and absolute
paths are excluded. The engine uses a JSON schema constrained to candidate IDs,
and Kaze independently validates the response. Unknown IDs, commands, arbitrary
paths and incomplete responses never create actions. AssistantQueryIntent answers
simple greetings locally and only supplies file candidates for explicit management
or cleanup requests; informational questions and refusals receive no file actions.

When you request cleanup, the assistant can propose up to three items to move to
Trash. Each card shows the actual path, allocation and any signed rule's reason,
recovery and close-first requirements. **Review action** prepares a confirmation;
it does not move anything. Files require a separate confirmation; folders also
require acknowledging that you reviewed their contents. Typing approval in chat
never executes a proposal. There is no automatic or blanket approval, permanent
deletion, shell execution or empty-Trash tool.

Proposals are bound to the specific query, measured fingerprint, scan date and
analysis revision. Saved analyses remain available for conversation: Kaze shows
their date and notes that totals may have changed. Before proposing an action it
checks metadata for up to eighteen ranked items, skipping missing or modified
files and providing at most six valid candidates. There is no full scan or folder
walk at this stage. Another mutation revokes pending approvals; a new question
can revalidate unchanged files individually. Changes during inference preserve
the explanation but withhold its proposals.
New queries, cancellation, uninstalling AI or an analysis change revoke approvals.
Kaze rechecks location, file identity, active processes and protected descendants
before the move through the existing Trash service and mutation lease. Successful
moves appear in History and invalidate the remaining proposals. Existing backups,
Photos and synchronized-data protections remain. App uninstallation, Docker and
other native resource operations stay in their dedicated sections. The assistant
only offers eligible indexed findings; it does not enumerate the disk or read
documents again during inference.

Installation: `~/Library/Application Support/Kaze/AI/<pinned-version>/`.
Use **Uninstall AI** to remove the AI folder; reopening the assistant will offer
the download again. Query files use a private temporary
folder and are removed afterward. AI files persist after uninstalling the app,
until explicitly removed.

`LocalAITests` verifies no automatic installation, hash rejection, cancellation,
timeouts and native model phases using temporary fixtures. AssistantFileActionsTests
verifies grounded proposals, invalid-output rejection, explicit confirmation,
revoked approvals and History restoration without touching real user files. Its
optional `--real-model` mode checks structured inference with the already installed,
SHA-verified engine and model, read-only; it never downloads or installs AI.
Fixtures reject the unsupported `--json` option and require `--json-schema`. Its optional
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


## Saved conversations

**New chat** starts a separate conversation. **Chats** reopens saved conversations;
its context menu deletes a conversation after confirmation. Questions, answers,
activity summaries, timestamps and confirmed action paths stay locally in
`~/Library/Application Support/Kaze/Chats/conversations.json`. The archive has
owner-only permissions, a versioned format, at most 30 chats and 40 exchanges per
chat, and an 8 MiB storage ceiling. Read or write errors remain visible and a
corrupt archive is preserved. Completed answers are restored without inference.
Interrupted requests are marked stopped, rather than resumed automatically.

Each query supplies at most two recent completed exchanges from the selected
chat as bounded context. Past explanations are historical; only recorded
successful moves are described as confirmed actions. Chats never share memory
with one another, read documents for memory, or restore executable proposals.
New proposals require fresh checks and separate confirmation. Deleting a chat
does not remove the independent operation journal or affect restored files.
Uninstalling the AI preserves conversations. Chat I/O uses a serial utility queue
and saves at query boundaries and actual action events, without a polling timer.
