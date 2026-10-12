# Storage intelligence

[English](STORAGE_ANALYSIS.md) · [Español](STORAGE_ANALYSIS.es.md)

Smart Scan is the entry point. **Scan Mac** inventories the current home,
Applications, Library and private/var on their respective volumes. **Choose
folder** limits the scope. No files are removed during a scan. Unreadable paths,
cloud providers and excluded volumes are disclosed as incomplete coverage.
Locations now live in Explorer's navigation menu.

- **Smart Scan:** groups known regenerable caches, review items, applications,
  exact duplicates and development resources. Nothing starts selected.
- **Space Map:** folder zoom, parent/root navigation, Quick Look, Finder and
  Explorer actions. Tile area represents allocated bytes. A More items tile
  preserves totals when details are omitted.
- **Duplicates:** size filtering followed by streaming SHA-256. One copy stays
  unselected; both it and each selected copy are hashed again before moving to
  Trash. Hard links, files with resource forks, Photos packages, backup and synced directories are excluded.
  Quick search reads at most 8 GiB, 10,000 candidate files or 60 seconds.
  Exhaustive hashes removes those limits for retained candidates and remains
  cancellable. Photo comparison is explicit: Apple Vision operates locally on
  thumbnails, at most 400 images with a 32 MiB input limit. Visual similarity is
  a review suggestion, never an automatic deletion decision.
- **Apps:** exact bundle IDs, signed app-group entitlements and LaunchAgent
  executable paths provide evidence. Name matches, shared groups and agents
  awaiting unloading remain for review. Closing the app also checks for helpers
  inside its bundle. Only verifiably owned, unshared data can be selected.
- **History:** each new mutation records date, path/resource, outcome, affected
  allocation and available recovery. Trash destinations and inode/change
  metadata enable restoration without overwriting existing files. Changed or
  missing contents, changed parent paths and cross-volume restores are rejected.
  Cache clearing and native Docker/simctl deletions have no undo. The latest 500
  records load initially; Load earlier operations retrieves earlier records.
- **System Data:** explains known caches, simulators, iOS backups, logs, app data
  and local Time Machine snapshot names. macOS does not expose an exact mapping
  to its System Data label or reliable exclusive bytes for each snapshot.
- **Developer Mode:** project dependencies and caches for Node/npm/pnpm, Gradle,
  CocoaPods, Swift and Python; Docker resources and simulators; Ollama,
  Hugging Face and LM Studio model stores. Each rule explains rebuilding cost
  and required closed processes. Dates are modification dates, not proof of last
  use. Look up last use queries optional Spotlight metadata on request (up to
  500 items or 30 seconds); missing metadata remains unknown. Project dependencies, shared stores, virtual environments and models
  require manual review to preserve local edits and custom data.
- **Monitor:** same app process, one filesystem capacity query per minute with
  timer tolerance; available space, recent growth over up to one hour and shortcuts. Optional
  macOS notifications below 20 GB are off initially, require notification
  permission and are limited to one per six hours. Disable the monitor in Rules
  and safety or the app menu to stop its timer.
- **Rules:** the bundled versioned JSON is signed with Ed25519. Cache scopes,
  fixed maintenance commands and native action policies explain scope, reason,
  recovery and required closed apps. Signature failure blocks these actions.
  Rules ship with app updates; there is no arbitrary remote rule execution.
- **Local assistant:** verified recommendations plus [optional local AI](LOCAL_AI.md).
  Download the engine and model once from the assistant; no automatic AI installation.
  Existing verified installations open the assistant directly. Questions use a bounded
  measured scan summary and stay on your Mac. AI cannot execute cleanup operations.

## Sizes and performance

Logical bytes differ from allocated bytes for sparse/compressed files. Hard
links are counted once per inode. APFS clones and snapshots can share or retain
blocks, so file allocation is an upper bound on capacity recovery, not a promise
of freed bytes. Kaze displays a **0–upper-bound recovery range**, excludes
protected/unreadable scopes and does not add snapshot sizes to file totals.
Moving to Trash frees zero bytes. History distinguishes affected allocation,
confirmed freed bytes (unknown for irreversible native actions) and an observed
filesystem free-space delta, which may include concurrent macOS activity.

A serial utility queue streams metadata without following symbolic links or
reading file payloads. It retains at most 250,000 detail nodes while finishing
accessible metadata totals. Duplicate coverage is marked incomplete if candidate
details were omitted. For larger folders, analyze a narrower scope or open them
in Explorer. Map rendering limits tiles to 120 plus an aggregate; result lists
load additional batches on request. Analysis is explicit and app/resource
inventory loads only when its section is opened. Smart Scan restores the previous session without recomputing hashes;
restored results are labeled and require a fresh scan before cleaning. Explorer
persists visited folder measurements, shows their date and reuses Smart Scan on
its first entry. macOS filesystem events identify changed branches for background
refresh. Missing history, changed volumes, incomplete results or measurements
older than a day trigger a complete walk. Shared hard links use a full walk when
content changes so parent totals remain deduplicated. Refresh always forces a
complete walk; stopping preserves previous visible results. The private metadata
cache in `~/Library/Caches/Kaze/Analysis-v1` holds up to 128 MiB and 32 folders.
Removing this cache does not remove user files.

Operation history is local at
`~/Library/Application Support/Kaze/Operations`. Paths and tool results can be
sensitive; review exported logs/screenshots before sharing them. No records are
sent automatically. [Privacy](../PRIVACY.txt) describes retained local data.

## Maintaining rules

Edit `src/Rules/rules-v1.json`, review scopes/recovery and sign with
`scripts/sign-rules.sh` using the existing Kaze signing key in login Keychain.
Private keys must not enter the repository. `scripts/verify-rules.swift` verifies
signatures; builds reject unsigned or tampered rules. Runtime validation also
checks schema/version, unique IDs and safe relative scopes. Add behavior tests
before expanding an automatically removable scope. Run `scripts/test.sh`,
`scripts/build.sh` and `python3 tests/DistributionTests.py` before shipping.
