# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds customized ImmortalWrt/LEDE firmware images for x86_64 targets. It uses a **Python-based declarative build tool** — all customization is done by editing a single `wrt_core/build.yaml` file.

## Project Structure

```
├── build.sh                          # Compatibility layer → calls python builder/main.py
├── requirements.txt                  # pyyaml
├── wrt_core/
│   ├── build.yaml                    # ★ THE ONLY config file you need to edit
│   ├── builder/
│   │   ├── main.py                   # CLI entry + pipeline orchestration
│   │   ├── config.py                 # Config loading & validation (dataclasses)
│   │   ├── logger.py                 # Structured logging (color terminal + file)
│   │   ├── repo.py                   # Upstream repo clone/fetch/reset
│   │   ├── feeds.py                  # Feed management (sparse clone, external repos)
│   │   ├── packages.py               # Package removal & APK compatibility fixes
│   │   ├── patcher.py                # Patch manager (dry-run, apply, upgrade-check)
│   │   ├── system.py                 # System config (UCI defaults, PBR, ttyd, etc.)
│   │   ├── docker.py                 # Docker nftables backend compatibility
│   │   └── image.py                  # Build artifact handling (make, package)
│   ├── patches/                      # .patch files (OpenWrt standard format)
│   ├── deconfig/                     # Kernel .config fragments
│   └── compilecfg/                   # Build configuration (repo URL, branch)
└── .github/workflows/
    ├── release_wrt.yml               # Manual build → upload release
    └── schedule_daily.yml            # Scheduled daily build
```

## Build Commands

- **Build firmware**: `bash build.sh` from repo root
- **Debug mode (config only)**: `python wrt_core/builder/main.py --debug`
- **Run specific steps**: `python wrt_core/builder/main.py --step clone,feeds_update`
- **Check patch compatibility**: `python wrt_core/builder/main.py --upgrade-check`
- **Verbose logging**: `python wrt_core/builder/main.py --log-level debug`

## Architecture

The build pipeline runs 12 declarative steps (configurable in `build.yaml`):

1. **clone** — Clone/fetch upstream ImmortalWrt repo
2. **feeds_update** — Update feeds (`./scripts/feeds update -a`)
3. **feeds_install** — Install feeds
4. **remove_packages** — Remove unwanted packages from feeds
5. **install_custom_feed** — Sparse-clone custom feeds (kiddin9, kenzok8, etc.)
6. **apply_patches** — Apply all patches (dry-run first, skip existing)
7. **system_config** — UCI defaults, PBR, ttyd, build signature, etc.
8. **docker_config** — Docker nftables compatibility patches
9. **generate_config** — Generate .config from fragments
10. **make_download** — `make download`
11. **make_build** — `make V=s`
12. **package_output** — Copy artifacts to `firmware/`

## Key Details

- **Branch**: `x86_25` (active development), `main` is default
- **Target**: x86/64 (x86_64)
- **Upstream**: ImmortalWrt (URL and branch in `compilecfg/x64_immwrt.ini`)
- **Package manager**: APK (not opkg). Version compatibility fixes in `build.yaml`
- **AdGuardHome**: `luci-app-adguardhome` kept for UI, binary removed (installed via APK at runtime)
- **Build output**: Firmware images at `firmware/` directory after build
- **All configuration**: Edit `wrt_core/build.yaml` — no shell scripts to modify

## Adding/Modifying Features

All changes go in `wrt_core/build.yaml`:

| What | Where in build.yaml |
|------|-------------------|
| Change upstream repo/branch | `source:` |
| Add/remove packages | `packages.remove:` |
| Add custom feed source | `feeds.sources:` |
| Add new patch | `patches.<group>.files:` |
| Change LAN address | `uci_defaults.lan_addr:` |
| Change Docker config | `docker:` |
| Add PBR ISP | `pbr.isps:` |
| Change build steps | `steps:` |
