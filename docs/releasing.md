# Releasing Meraline

How a tag becomes a signed, notarized download, what each script does, and how to change the
installer's look.

## What a release contains

| File | Purpose |
| --- | --- |
| `Meraline-<version>.dmg` | The installer: a styled disk image with the app and a link to Applications. Signed and notarized in its own right. |
| `Meraline-<version>.zip` | The archive [Sparkle](https://sparkle-project.org) downloads when an installed copy updates. |
| `appcast.xml` | The Sparkle feed entry for this version, EdDSA-signed, with the release notes embedded. Installed copies check `releases/latest/download/appcast.xml` once a day. |
| `Meraline-<version>-dSYMs.zip` | Debug symbols, for reading crash reports. |
| `SHA256SUMS.txt` | Checksums of the files above. |

The app inside the zip and inside the disk image is the same notarized, stapled bundle.

## Shipping a version

```sh
git tag v1.2.0
git push origin v1.2.0
```

That is all. The Release workflow builds the tagged commit, and the tag decides the version: `v1.2.0` ships as 1.2.0. A tag with a suffix, such as `v1.2.0-beta.1`, is published as a GitHub pre-release and goes out on the beta channel (see below); `releases/latest` never points at a pre-release, so copies on the stable channel are not offered it.

Two optional things before tagging:

- **Release notes.** Add a `## v1.2.0 - 2026-10-01` section to `CHANGELOG.md` and it becomes the release description on GitHub and the notes in the in-app update window. Without an entry, the notes list the commits since the previous tag.
- **Screenshots in the notes.** Show what's new with pictures: retake the README screenshots (`scripts/screenshots.sh --wait-idle`), then put the ones that show the new features in the section, each on a line of its own after the entry it illustrates, as `![What it shows](https://raw.githubusercontent.com/Meldiron/meraline/v1.2.0/docs/screenshots/panel-light.png)`. The link names the tag, so the picture never changes once released. The notes under the input in the app skip picture lines and show the words.
- **Nothing to bump.** The version comes from the tag and the build number is the number of commits reachable from the tagged commit, so every release is newer than the one before it and a local build of the same commit gets the same number.

## The beta channel

Installed copies follow one of two Sparkle feeds, chosen in Settings › Software Update › Update channel:

| Channel | Feed | Sees |
| --- | --- | --- |
| Stable (default) | `releases/latest/download/appcast.xml` | The newest stable release |
| Beta | `releases/download/beta/appcast.xml` | The newest build of either kind |

A pre-release tag produces an appcast item tagged `<sparkle:channel>beta</sparkle:channel>`, which only clients on the beta channel accept. After every release, stable or beta, the workflow copies the new `appcast.xml` onto a rolling `beta` pre-release, so the beta feed always advertises the newest build and testers get stable releases too. The downloadable files stay in their own versioned release; the beta release holds only the feed.

Version numbers must keep increasing for this to work, and they do: the build number is the commit count, and a beta tagged on a branch is superseded by the next stable tagged on `main`.

## What the workflow does

`.github/workflows/release.yml` runs on `macos-26` when a `v*` tag is pushed. Both workflows select Xcode 26.6 explicitly (`XCODE_VERSION` at the top of each file), so a runner image update cannot change what a tag builds with; bump it on purpose, together with the deployment target in `project.yml`. Dependencies are pinned to exact versions in `project.yml` for the same reason.

1. Checks the tag looks like a version and that all six secrets are present. A Meraline release is always signed and notarized, so a missing secret fails the run immediately instead of at the notarization step.
2. Imports the Developer ID certificate into a temporary keychain with plain `security` commands. The keychain is deleted by a final step that runs even when the job fails.
3. Runs `scripts/release.sh <version>`, which does everything listed in the next section.
4. Attaches a [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) to the `.dmg` and the `.zip`.
5. Writes the release description: a download link, the release notes, and a collapsed table of every file with its checksum.
6. Creates the release as a draft, uploads the files, then publishes it, so `releases/latest` never points at a half-uploaded release.
7. Copies `appcast.xml` onto the rolling `beta` release, creating that release the first time.

`.github/workflows/ci.yml` runs on every push to `main` and every pull request. Alongside the tests, it runs `scripts/release.sh --adhoc`, which is the same pipeline without a certificate or notarization, and uploads the resulting disk image as an artifact. A broken build script or a mislaid installer layout is caught there, before a tag is pushed.

## The scripts

Everything lives in `scripts/` and runs the same on a Mac and on the runner.

| Script | What it does |
| --- | --- |
| `release.sh <version>` | The whole pipeline: build, verify, notarize, zip, notes, appcast, disk image, checksums. |
| `build.sh --version <v>` | `xcodebuild archive` plus `-exportArchive` with `ExportOptions.plist`. The export step is what signs Sparkle's nested helpers with the Developer ID certificate. `--adhoc` does a plain build with no certificate. |
| `verify_app.sh <app or dmg>` | Reads the finished artifact the way Gatekeeper does: valid signature, hardened runtime on every nested binary, one consistent Team ID, universal binaries, and with `--require notarized` a stapled ticket and a Gatekeeper verdict on a quarantined copy. |
| `notarize.sh <app or dmg>` | Submits to the notary service, waits, prints Apple's log if the verdict is not Accepted, and staples the ticket. |
| `make_dmg.sh <app> <dmg>` | Builds the styled disk image. |
| `verify_dmg.sh <dmg>` | Mounts the image, reads the saved Finder layout out of `.DS_Store`, and verifies the app inside. |
| `release_notes.sh <version>` | The changelog entry for the version, or the commits since the previous tag. |
| `render_html_png.swift` | Renders an HTML file to a PNG with WebKit. Used for the disk image background. |
| `dev_run.sh`, `test.sh`, `install.sh`, `clean.sh` | Day-to-day developer wrappers; see [CONTRIBUTING.md](../CONTRIBUTING.md). They sign ad-hoc when no certificate is present. |

`release.sh` runs in three modes:

```sh
scripts/release.sh 1.2.0 --adhoc         # no credentials; the app opens only on this Mac
scripts/release.sh 1.2.0 --no-notarize   # Developer ID signed, not notarized
scripts/release.sh 1.2.0                 # signed, notarized, stapled: what the workflow runs
```

The full mode needs three things on the Mac running it:

- The **Developer ID Application** certificate in the keychain. Xcode's export uses it directly.
- **Notary credentials**, either a profile saved with `xcrun notarytool store-credentials meraline` and passed as `NOTARY_PROFILE=meraline`, or the App Store Connect key as `NOTARY_KEY` (a path to the `.p8`, or its contents), `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`.
- The **Sparkle private key**, either in the keychain where Sparkle's `generate_keys` put it, or in `SPARKLE_PRIVATE_KEY`.

Output goes to `build/release/`. Nothing is uploaded; publishing is the workflow's job.

To rehearse the appcast step without the real Sparkle key, or to point a fork at its own feed, set `MERALINE_SPARKLE_PUBLIC_KEY` and `MERALINE_FEED_URL` when running the script. They override the values in `project.yml` at build time, so the app being packaged carries the public half of whatever key signs its appcast. Sparkle refuses to sign an update for an app whose public key does not match.

## The disk image

Opening `Meraline-<version>.dmg` shows a window with a heading, the app on the left, the Applications folder on the right, and a pink-to-lavender arrow between them. The volume carries the app icon. There is no toolbar, sidebar, or status bar, so the window reads as one instruction rather than a folder.

### Editing the background

The background is not a checked-in image. Its source is `assets/dmg/background.html`, plain HTML and CSS with inline SVG for the sparkle and the arrow. `make_dmg.sh` renders it at 1x and 2x with `render_html_png.swift` and merges both into one TIFF, so Finder picks the sharp rendition on Retina displays. Edit the HTML, rebuild the image, and the diff stays readable.

To look at the artwork on its own:

```sh
swift scripts/render_html_png.swift assets/dmg/background.html /tmp/background.png 660 380 2
open /tmp/background.png
```

Design rules the file follows:

- The base is white and neutral; pink and lavender appear only in the arrow, the sparkle, and two faint glows behind the icon slots. That matches the app, which uses pink as an accent and never as a background.
- The outer edges are pure white. Finder draws the image at its natural size anchored top-left and fills the rest of the window with white, so any tint at the edge shows as a seam.
- The app icon and the Applications folder are never drawn into the artwork. Both are real Finder items placed on top of it; painting them in produces doubled icons.
- There is no dark variant, because Finder has no way to pick one. A custom background pins the window to light rendering, so the artwork has to work in a light window even when the title bar is dark.

### Layout contract

These numbers live in two places that must change together: the CSS custom properties at the top of `assets/dmg/background.html`, and `scripts/lib/dmg.sh`, which `make_dmg.sh` and `verify_dmg.sh` both read.

| Value | Setting |
| --- | --- |
| Canvas | 660 × 380 pt |
| Finder chrome allowance | 68 pt |
| Window | 660 × 448 pt |
| Icon size | 128 pt |
| Label size | 13 pt |
| Icon row centre | y = 210 |
| `Meraline.app` centre | x = 170 |
| `Applications` centre | x = 490 |

The window is taller than the canvas on purpose. Finder chrome eats into the window frame: a 28 pt title bar always, and a 36 pt tab bar for anyone who keeps View › Show Tab Bar on. An image taller than the remaining area makes the window scroll, which is the most common way a styled disk image ends up looking broken. Sizing for the worst case and letting the white canvas edge blend into Finder's white margin avoids it.

Positions are the centre of each icon. With 128 pt icons the artwork must leave roughly y = 146 to 296 clear across both icon columns.

### Why dmgbuild

`make_dmg.sh` uses [dmgbuild](https://dmgbuild.readthedocs.io), installed into `build/.dmg-venv` on first run. It writes the `.DS_Store` directly instead of driving Finder over AppleScript, so it needs no GUI session and behaves the same on a runner as on a Mac. It also only stores positions for the items it is told about. Tools that position every item, hidden ones included, make Finder count the hidden files towards the scrollable area, and anyone browsing with hidden files shown gets a scroll bar.

The app's `.app` extension is not hidden, even though dmgbuild can do that. The setting works by writing a Finder attribute onto the bundle inside the image, and `codesign --strict` treats that attribute as detritus, so the copy a user drags out would fail to verify. Finder hides the extension by default anyway.

### Checking a change

`scripts/verify_dmg.sh` runs on every build and fails if the saved positions, the window size, or the icon and label sizes differ from `scripts/lib/dmg.sh`, or if anything other than the app and the Applications link has a saved position. For a look at the real thing, open the image with the Finder tab bar on and off and with hidden files shown and not, and confirm none of the four shows a scroll bar.

## Secrets

The workflow needs these repository secrets.

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64 of the exported Developer ID Application certificate and private key: `base64 -i Certificates.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the `.p12` |
| `NOTARY_KEY` | The contents of the App Store Connect API key, `AuthKey_XXXXXXXXXX.p8`, including the BEGIN and END lines |
| `NOTARY_KEY_ID` | The `XXXXXXXXXX` from that filename |
| `NOTARY_ISSUER_ID` | The issuer UUID from App Store Connect, under Users and Access › Integrations › Team Keys |
| `SPARKLE_PRIVATE_KEY` | The EdDSA private key from Sparkle's `generate_keys -x` |

There is no secret for the Team ID or the certificate name. The workflow imports the `.p12` into a keychain that holds exactly one Developer ID identity and fails if it finds none or several, and Xcode picks that identity up through `ExportOptions.plist`.

## Verifying a download

Any file from the Releases page can be checked three ways:

```sh
# Built by GitHub Actions from the tag, in this repository
gh attestation verify Meraline-1.2.0.dmg --repo Meldiron/meraline

# Matches the checksum published with the release
shasum -a 256 -c SHA256SUMS.txt

# Accepted by Gatekeeper as a notarized Developer ID artifact
spctl -a -vv -t open --context context:primary-signature Meraline-1.2.0.dmg
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Missing repository secrets` | Add the secrets listed above. Releases are never built ad-hoc. |
| `Expected exactly one Developer ID Application identity` | The `.p12` decoded to something other than one Developer ID certificate. Re-export it from Keychain Access with only that identity selected. |
| `is still ad-hoc signed while the app is not` | A nested helper was not signed by the export step. Check that `ExportOptions.plist` still uses the `developer-id` method. |
| `entitlements include com.apple.security.get-task-allow` | The artifact came from `xcodebuild build` rather than an export. |
| Notary status `Invalid` | `notarize.sh` prints Apple's log; it names the binary and the reason. |
| `rejected once quarantined` | Signed and notarized, but the ticket did not staple. Re-run; stapling needs Apple's servers to have the ticket. |
| `Finder layout differs from scripts/lib/dmg.sh` | The two copies of the layout constants disagree, or dmgbuild changed how it writes `.DS_Store`. |
| `appcast.xml has no EdDSA signature` | The Sparkle private key was not found. Set `SPARKLE_PRIVATE_KEY` or run `generate_keys` on this Mac. |
