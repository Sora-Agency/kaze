# Publishing Kaze under Sora Agency

[English](PUBLISHING.md) · [Español](PUBLISHING.es.md)

The intended repository is `Sora-Agency/kaze`. Local builds do not upload files.
GitHub Actions creates a draft release when you push a version tag.

## Repository

1. Create a public repository named `kaze` in the `Sora-Agency` organization.
   Leave it empty: this project already includes a README, MIT license and `.gitignore`.
2. Push `main` using GitHub Desktop or Git.
3. Use this **About** description:

   > A native macOS storage explorer and cleanup app by Sora Agency.

4. Add topics: `macos`, `swift`, `swiftui`, `storage`, `disk-cleanup`,
   `sora-agency`, `open-source`.
5. Enable Issues and GitHub Actions. `macos.yml` verifies Apple Silicon on
   `macos-15` and Intel on `macos-15-intel`, with read permissions. Only the
   release job has `contents: write` to create the draft and upload assets.
   Tests never install on the host or clean real data; installation checks
   copy the app to a temporary directory.

Use a Sora account or GitHub App to create the repository and push changes.
An organization owns repositories but is not a login account. A personal
account can appear in public repository activity even with a different Git
author. Configure this repository's author before the first commit:

```sh
git config --local user.name "Sora Agency"
git config --local user.email "git@soraagency.invalid"
git config --local commit.gpgsign false
```

The reserved `.invalid` address is attribution metadata, not a contact address,
and does not disclose a personal email. You can replace it with an
address verified exclusively by the Sora account. A personal account's `noreply`
address still attributes commits to that account.

[GitHub commit attribution](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address)
· [Public repository activity](https://docs.github.com/en/rest/activity/events)

```sh
git add .
git commit -m "Add Kaze for macOS"
git remote add origin git@github.com:Sora-Agency/kaze.git
git push -u origin main
```

If `origin` already exists, check its destination before changing it. Binaries,
preferences, backups and host data are not tracked. Previous installations are detected locally for migration; new bundles and
jobs use `com.soraagency.kaze`.

## Configure updates once

Kaze embeds Sparkle 2.10.0. The public `SUPublicEDKey` is in `src/Info.plist`;
this distribution's private key is stored in the login Keychain under account
`com.soraagency.kaze`. Keep a secure backup: installed apps trust that public key.

Set the Actions secret `KAZE_SPARKLE_PRIVATE_KEY` to Sparkle's private key export.
Never include it in source, notes or release assets. Export to a temporary file
and upload without printing the key:

```sh
sparkle_dir="$(scripts/fetch-sparkle.sh)"
key_dir="$(mktemp -d -t kaze-key)"
"$sparkle_dir/bin/generate_keys" --account com.soraagency.kaze -x "$key_dir/key"
gh secret set KAZE_SPARKLE_PRIVATE_KEY --repo Sora-Agency/kaze < "$key_dir/key"
rm "$key_dir/key"
rmdir "$key_dir"
```

Contributors without the key can build and test; releases must be signed with
the original key. For an independent distribution, generate your own key and
replace `SUPublicEDKey` before shipping the first version.

Tags generate and verify EdDSA signatures for each architecture's DMG and feed.
Missing secrets or a key mismatch fail before draft creation. To test locally:

```sh
scripts/build.sh
scripts/generate-appcast.sh v1.1.0
```

Publish both feeds with the installers and mark the stable release **Latest**.
The `releases/latest/download/appcast-arm64.xml` and `appcast-x86_64.xml` URLs
resolve to that release; drafts and prereleases do not enable updates. Do not
edit signed feeds. Always increment `CFBundleVersion`: Sparkle compares this
build number rather than just the displayed version.

Users of 1.0.0 must install 1.1.0 once. Subsequent updates use Sparkle's download,
install and relaunch window. Preferences and tasks outside the bundle are
preserved; the ZIP installer's backup behavior does not apply to Sparkle.
Sparkle's native windows follow the macOS language; Kaze controls follow the
in-app language selector.

## Create a draft release

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `src/Info.plist`. The prepared version is **1.3.0**, build **24**.
2. Update [RELEASE_NOTES.md](RELEASE_NOTES.md). Its first line must match the
   version, for example `# Kaze 1.3.0`. These notes initialize the draft.
3. Merge the changes into `main` and wait for checks to pass.
4. Create and push an annotated tag on that commit. For the current version:

   ```sh
   git switch main
   git pull --ff-only
   git tag -a v1.3.0 -m "Kaze 1.3.0"
   git push origin v1.3.0
   ```

5. Follow **macOS** in **Actions**. The tag runs tests, builds and DMG
   verification for both architectures again.
6. Open **Releases**, review the **Kaze 1.3.0** draft and choose **Publish release**
   when ready. You can edit the notes before publishing.

Tags must use `vMAJOR.MINOR.PATCH` and match the app version. Pull requests,
branch pushes and manual workflow runs only verify and build; creating a draft
requires a tag push.

The draft contains ten attachments:

| File | Contents |
| --- | --- |
| `Kaze-Mac-arm64.dmg` | Drag-and-drop installer for Apple Silicon |
| `Kaze-Mac-x86_64.dmg` | Drag-and-drop installer for Intel |
| `Kaze-Mac-arm64.zip` | Apple Silicon app and installation scripts |
| `Kaze-Mac-x86_64.zip` | Intel app and installation scripts |
| `Kaze-Source.zip` | Source, bilingual documentation and screenshots |
| `Kaze-SHA256-arm64.txt` | Hashes for the DMG, binary ZIP, shared source and update feed |
| `Kaze-SHA256-x86_64.txt` | Hashes for the DMG, binary ZIP, shared source and update feed |
| `appcast-arm64.xml` | Signed Apple Silicon update feed |
| `appcast-x86_64.xml` | Signed Intel update feed |
| `SHA256SUMS` | Hashes for the nine files above |

Both architectures include both languages. Before creating the draft, the job
checks hashes and verifies that both builds contain equivalent source. A failed
build prevents release creation. GitHub's automatic token is sufficient; you
do not need a personal access token. The script uses
[`gh release create --draft`](https://cli.github.com/manual/gh_release_create).

If uploading assets fails, choose **Re-run all jobs** for that workflow run.
An existing draft receives missing or replacement assets while retaining edited
notes. Published releases are never modified.

Ensure the notes disclose that packages are ad hoc signed and not notarized by
Apple. Each DMG and ZIP contains a single architecture. Developer ID signing
and notarization require the distributor's Apple credentials and account and
are not configured by this project.

## Update the presentation

```sh
scripts/test.sh
scripts/build.sh
python3 tests/DistributionTests.py
scripts/screenshots.sh
```

Review both READMEs, relative links and images. Public screenshots use fictional
fixtures only; never substitute real Finder views, logs or personal folders.
Keep Lucide, Feather, DM Sans and Raleway notices alongside Kaze's legal files.
