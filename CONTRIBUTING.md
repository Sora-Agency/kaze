# Contributing to Kaze

[English](CONTRIBUTING.md) · [Español](CONTRIBUTING.es.md)

You can propose improvements, fix bugs, improve accessibility or update the
documentation for this Sora Agency product.

## Set up

Requires macOS 13+, Xcode Command Line Tools and Git. Fork the repository,
clone it and create a branch for a focused change. Then run:

```sh
scripts/test.sh
scripts/build.sh
python3 tests/DistributionTests.py
python3 tests/NativeStartupTests.py
open package/Kaze.app
```

The first build downloads Sparkle 2.10.0 and verifies its pinned SHA-256;
subsequent builds use the local cache. Other resources are bundled. Docker, Homebrew
and full Xcode are optional and needed only to test their integrations.

## Project scripts

| Script | Purpose |
| --- | --- |
| `scripts/build.sh` | Builds the app, DMG, ZIPs and hashes |
| `scripts/build-dmg.sh` | Creates the drag-and-drop DMG |
| `scripts/test.sh` | Runs app and release workflow tests |
| `scripts/preview.sh` | Renders views for visual review |
| `scripts/screenshots.sh` | Generates public screenshots with fictional data |
| `scripts/vendor-lucide.py` | Updates the bundled vectors and compiled icons |
| `scripts/prepare-release.py` | Verifies versions and gathers release assets |
| `scripts/create-draft-release.sh` | Creates or completes a draft on GitHub |

Python files under `tests` verify the DMG and release automation. Runtime `.zsh`
files under `src` handle cleanup, localization and legacy scheduling compatibility.
Python is a development and CI dependency; the installed app does not require it.
The DMG includes the app and runtime resources; development scripts are included
in the source ZIP.

NativeStartupTests launches the built App/Scene with existing preferences and
both monitor states/themes, then checks that idle CPU and memory settle. Preview
renders alone do not exercise MenuBarExtra and AppStorage scene integration.

## Code organization

- Keep entities and rules in `Domain`, process and filesystem access in
  `Infrastructure`, and section views and models in `Features`.
- Use `DesignSystem` for buttons, inputs, selection, typography and icons.
  Check both themes and Reduce Motion.
- Preserve cleanup protections, link deduplication and migration of existing
  preferences and tasks.
- Test behavioral changes using temporary directories and launchd adapters.
  Tests must never clean the host computer or activate real tasks.

[ARCHITECTURE.md](ARCHITECTURE.md) describes the module boundaries.

## Localization

English and Spanish catalogs live in `src/Localization/en.lproj` and `es.lproj`.
Use `L10n.text("…")` for literals and interpolated messages, and `L10n.string`
for existing display keys. Add the same key to both `Localizable.strings` files
and preserve interpolation placeholders. Count messages use `Localizable.stringsdict`.
Keep persisted enum raw values, paths, identifiers and user-entered names stable.

Runtime cleanup messages are translated in `src/localization.zsh`. Update both
languages there too. Terms and privacy documents ship in both languages; MIT
and third-party license texts stay in their original language. Update both
READMEs and contribution guides when changing user-facing instructions.

`KAZE_LANGUAGE=en` or `es` selects a language for development previews.
Localization tests run in both languages and check fallback, interpolation,
catalog coverage, persisted schedules and live switching in a rendered view.
Use LocalizedText for stored presentation messages so they resolve when the
language changes. Observe AppLanguageStore in views that render translated text;
preserve view identity, user edits and in-flight operations.

## Visual changes and screenshots

```sh
scripts/preview.sh
scripts/screenshots.sh
```

Previews go to `build/previews`. Public screenshots go to `docs/images` (Spanish)
and `docs/images/en` (English). Always use the generator: never publish personal
usernames, folders, logs, resource identifiers or projects. Review the results
before including them in a pull request.

Fixtures live in `tests/PreviewFixtures.swift`. The renderer uses SwiftUI views
and a simulated runner; it never cleans files or registers tasks. The public
task editor uses a taller viewport to show all its options.

## Icons and fonts

Lucide vectors are pinned to a specific revision and compiled into
`LucidePaths.generated.swift`. To change the icon subset, edit and run
`scripts/vendor-lucide.py` using Python 3. This step may need Internet; a normal
build does not. Preserve third-party notices and original asset licenses.

## Submit a change

Describe the problem, resulting behavior and validation. Include example
screenshots for visual changes. Run `scripts/test.sh` and `scripts/build.sh`.
Do not commit `build`, `package`, logs or backups. Code contributions use the
project's MIT license.

GitHub Actions runs Apple Silicon and Intel builds and attaches their packages.
See the [publishing guide](docs/PUBLISHING.md) to prepare a version. Release
tests use temporary files and a simulated GitHub CLI; they never create or
publish real releases.

## Storage analysis rules

Read [the storage guide](docs/STORAGE_ANALYSIS.md) before changing scan or cleanup
scopes. Regenerable data still needs explicit selection and closed processes.
Keep payload reads cancellable, separate detail limits from measurement coverage,
and preserve APFS uncertainty. Rule changes need review, an Ed25519 signature
(`scripts/sign-rules.sh`) and tests using temporary data only. Never commit keys.
