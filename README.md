# public-tools

Pinned, checksum-verified installers for the open-source tools used by our PCB layout
automation. This repository contains no designs, scripts or rules of our own; it only points
at official upstream releases and checks what it downloads.

| Tool | Version | Source |
|---|---|---|
| KiCad | 10.0.6 (10.0.x accepted) | github.com/KiCad/kicad-source-mirror releases |
| Freerouting | 1.9.0 | github.com/freerouting/freerouting releases |
| Java (Eclipse Temurin JRE) | 17.0.20.1+1 | github.com/adoptium/temurin17-binaries releases |

Exact URLs and SHA-256 sums are in [`toolchain.lock`](toolchain.lock). The installers refuse
any file whose hash does not match.

## Install

Windows (PowerShell):
```
powershell -ExecutionPolicy Bypass -File install.ps1               # Java + Freerouting
powershell -ExecutionPolicy Bypass -File install.ps1 -InstallKiCad # also KiCad (asks for admin)
```

Linux / macOS:
```
sh install.sh            # Java + Freerouting
sh install.sh --kicad    # macOS: also fetch + verify the KiCad .dmg; Linux: prints the PPA command
```

Tools go to `%LOCALAPPDATA%\cuzor-tools` (Windows) or `~/.cuzor-tools` (Linux/macOS), or to
`$CZL_TOOLS` / `-Dest`. The installer writes `tools.json` there with the paths it found;
exit code 0 means everything is present, 2 means KiCad is missing or the wrong version.

Freerouting is always run with analytics disabled by the layout kit.

## Updating the toolchain

Change `toolchain.lock` (URL + SHA-256 from the upstream release page), bump `id`, and let the
`check` workflow confirm both installers on a clean machine before anyone pulls it.

Third-party licences: see [THIRD_PARTY.md](THIRD_PARTY.md).
