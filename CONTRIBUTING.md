# Contributing to Meraline

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. The engineering reference, including the rules that shape the code, is [AGENTS.md](AGENTS.md); read it before changing anything.

## Getting started

You need macOS 26, Xcode 26.6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). [xcbeautify](https://github.com/cpisciotta/xcbeautify) is optional and makes build output readable.

```sh
git clone https://github.com/Meldiron/meraline.git
cd meraline
scripts/dev_run.sh
```

`dev_run.sh` generates the Xcode project, builds Debug, and relaunches the app from DerivedData with its output in `/tmp/meraline.log`. No Apple Developer account or certificate is needed; without one, the build is signed ad-hoc, which runs fine on your own Mac.

To work in Xcode instead, run `xcodegen generate` and open `Meraline.xcodeproj`. The project file is generated and gitignored, so edit `project.yml`, not the project.

## Day to day

| Task | Command |
| --- | --- |
| Build and run | `scripts/dev_run.sh` |
| Run the tests | `scripts/test.sh` |
| Run one suite | `scripts/test.sh HistoryTests` |
| Also run the real command-line tools | `scripts/test.sh --e2e` |
| Install a Release build into /Applications | `scripts/install.sh` |
| Rehearse the release pipeline | `scripts/release.sh 0.0.1 --adhoc` |
| Start over | `scripts/clean.sh` |

Every push and pull request runs the tests and the credential-free release pipeline in GitHub Actions, and attaches the resulting disk image as an artifact.

## Reporting bugs

Use the bug report template. Settings › About › **Copy Diagnostics** puts a report on your clipboard with versions, provider setup (no keys), and recent log events (no questions or answers); paste it into the issue. [docs/diagnostics.md](docs/diagnostics.md) lists exactly what it contains.

## Pull requests

- Keep the change focused and describe what it does and why in the pull request template.
- Run `scripts/test.sh` before pushing. Add a test when you fix a bug that a test could have caught; the suites in `MeralineTests/` show the style (Swift Testing, injected `UserDefaults` and `SecretStore`).
- Follow the rules in [AGENTS.md](AGENTS.md): nothing on disk, secrets only in the Keychain, logging through `Log`, pink only as an accent.
- Screenshots or a short recording help for anything visible.
- Dependencies are pinned to exact versions in `project.yml`; bump them in their own pull request.

## Releases

Maintainers ship by pushing a tag. [docs/releasing.md](docs/releasing.md) covers the pipeline, the beta channel, and how to rehearse a release locally.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
