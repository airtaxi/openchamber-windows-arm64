# OpenChamber Windows ARM64

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

🌐 English | [한국어](README.ko.md)

OpenChamber Windows ARM64 is an unofficial automated build pipeline that produces Windows ARM64 NSIS installers for [OpenChamber](https://github.com/openchamber/openchamber), a desktop AI coding agent. It runs on GitHub Actions, polls the upstream repository for new releases every 6 hours, builds the ARM64 installer on a native Windows ARM runner, publishes a GitHub Release, and updates a Scoop bucket manifest for automatic updates.

This project is intended to be maintained until OpenChamber provides official Windows ARM64 builds.

## Disclaimer

This project is not affiliated with, endorsed by, sponsored by, or officially supported by the OpenChamber team. It is an independent community tool for Windows on ARM compatibility.

OpenChamber is a trademark of its respective owners. All other trademarks are the property of their respective owners.

## Quick Install From Release

With Scoop:

```powershell
scoop bucket add openchamber-arm64 https://github.com/airtaxi/openchamber-windows-arm64
scoop install openchamber-arm64
```

Update normally:

```powershell
scoop update
scoop update openchamber-arm64
```

Alternatively, download the installer from the [GitHub Releases](https://github.com/airtaxi/openchamber-windows-arm64/releases) page and run it directly.

## How It Works

1. **Scheduled check** — Every 6 hours, the workflow fetches the latest tag from the upstream OpenChamber repository and compares it against the latest release in this repository.
2. **Build** — If a newer tag is found (or a manual build is triggered), the workflow clones the tagged source, installs dependencies with Bun, applies ARM64 compatibility patches, and builds the NSIS installer using electron-builder on a native Windows ARM runner.
3. **Release** — The built installer is archived, a Scoop manifest is generated with the correct hash, and a GitHub Release is created.
4. **Scoop update** — The Scoop bucket manifest is committed to the repository so `scoop update` picks up the new version automatically.

## Applied Patches

The build applies the following patches to the cloned source after `bun install`:

- **prepare-opencode-cli.mjs** — Forces the x64-baseline OpenCode CLI binary instead of the non-functional ARM64 binary (runs via x64 emulation on Windows ARM).
- **node-pty binding.gyp** — Disables Spectre mitigation (`Spectre` → `false`) since ARM64 Spectre libraries are not available in the CI toolchain.


## Requirements (for local builds)

- Windows on ARM device (or a Windows ARM CI runner).
- PowerShell 7 (`pwsh`).
- [Bun](https://bun.sh) on `PATH`.
- Visual Studio 2022 with the "Desktop development with C++" workload (ARM64 toolset).
- NSIS on `PATH` (for electron-builder NSIS target).
- Node.js and Git on `PATH`.

## Outputs

A successful build produces:

- `dist/OpenChamber-<version>-win-arm64.exe` — NSIS installer.
- `dist.7z` — Archived installer for release upload.
- `bucket/openchamber-arm64.json` — Scoop manifest with hash.

## License

OpenChamber Windows ARM64 is licensed under the [MIT License](LICENSE).

## Author

Created by [Howon Lee (airtaxi)](https://github.com/airtaxi).