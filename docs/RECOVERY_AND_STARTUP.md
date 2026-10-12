# Recovery and startup apps

Both tools live under **Manage**. Neither inventories devices nor asks for
Automation authorization when Kaze launches.

## Recovery

Kaze adapts the MIT-licensed LibreRescateNativo APFS reader. It reads an external
APFS physical partition or an uncompressed raw container image. For a whole-disk
image, enter the partition's byte offset under Image options. Compressed DMGs,
FileVault/encrypted volumes, sealed volumes, deleted-file carving and checkpoint
history are not supported. A complete recovery cannot be guaranteed when metadata
or data blocks are unreadable. Unsupported compression and symbolic links appear
in the report rather than being silently copied incorrectly. Recovery copies file
contents; it does not reproduce all original metadata, permissions, ACLs or
independent resource forks.

Choose Detect disks, confirm the external partition, then Open source. Device
identifiers can change after reconnecting. macOS authorizes read-only access via
`authopen`; Kaze never handles the password. Select a volume and browse folders,
select files/folders, then Recover selection. Choose a destination on a different
physical disk. Kaze checks APFS physical stores, including shared containers.
It never repairs, formats, mounts or writes to the source. Recovery from a mounted
volume is a best-effort view; other apps can still change that volume while read.
For a stable source, use an image or an externally prepared unmounted disk.

The destination is a new private UUID directory. Existing files are never
replaced. Copy errors continue with other files; incomplete files are removed.
Stop keeps completed files and writes a report. Device I/O can still take time
to return on failing hardware. The report contains paths and errors locally and
is never uploaded. A full APFS index is bounded to 500,000 records/map entries;
block caches are bounded to 32 MiB. No data-recovery daemon runs.

The standalone LibreRescateNativo project is unchanged. Its MIT notice is bundled
in `Recovery/LibreRescate-LICENSE.txt`.

## Startup apps

Choose Load apps to read login items through macOS System Events. The OS may ask
for permission under Privacy & Security → Automation. Kaze only reads or changes
these items after a user action. Toggle an app off to remove its login item;
Kaze saves its path and hidden preference first so you can enable it again.
Changes are re-read from macOS before Kaze reports success. Add app supports
installed application bundles. Turning startup off does not quit a running app.

Disabled references live in the private
`~/Library/Application Support/Kaze/Startup/disabled-v1.json`. Apps removed in
other tools are only shown if Kaze previously retained their references. This
is not a complete inventory of all services that can start on macOS.
Background services and modern app-managed helpers use a separate OS permission
system. **macOS settings** opens Apple's native Login Items settings to manage
those; Kaze does not edit the private Background Task Management database.

## Verification

Recovery tests use fake readers and disposable APFS images. They cover recursive
copy, failures, cancellation, path traversal, collision refusal, source hashes,
volume choice and source/destination disk topology. Startup tests inject a fake
login-item manager and evaluate the JXA script against mock System Events.
No test toggles a real app's startup setting or reads a real damaged disk.

References: [Apple APFS reference](https://developer.apple.com/support/downloads/Apple-File-System-Reference.pdf),
[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice),
[Mac Automation Scripting Guide](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/HowMacScriptingWorks.html).
