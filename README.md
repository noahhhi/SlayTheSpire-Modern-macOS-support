# Slay the Spire modern macOS support

[简体中文](README.zh-CN.md)

A community compatibility patch for the Steam macOS release of *Slay the
Spire*. Version 1.1.0 is one Universal distribution for Intel and Apple
Silicon Macs running macOS 11 or later.

## Features

- Native `x86_64` and `arm64` Azul Zulu OpenJDK 8 runtimes.
- Retina-aware windowed, borderless, and native macOS Space fullscreen modes.
- Freely resizable windows with logical-point input and physical-pixel OpenGL
  viewports/font rasterization. Ratios remain continuously adjustable from 4:3
  through 21:9; only layout-breaking extremes are clamped (minimum 800×450),
  and resizing never reconstructs UI or restarts menu audio.
- One fullscreen behavior for the in-game Fullscreen toggle, Borderless
  Fullscreen toggle, and the green window button.
- Automatic Steam library discovery, including additional libraries listed in
  `libraryfolders.vdf`.
- Strict original-jar SHA-256 validation, payload checksum verification,
  exact-file backup, and automatic rollback on installation failure.

The release contains patch files and redistributable runtimes only. It does
not contain `desktop-1.0.jar`, the game app, saves, art, audio, or other game
content. You must own and install the Steam version first.

## Install

### PKG (recommended)

1. Download `SlayTheSpire-Modern-macOS-v1.1.0-universal.pkg` and its `.sha256`
   file from [Releases](../../releases).
2. Optional integrity check:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c SlayTheSpire-Modern-macOS-v1.1.0-universal.pkg.sha256
   ```

3. Open the package. It finds the logged-in user's Steam library and runs the
   patch as that user, not as root against the game directory.

The package is currently ad-hoc/unsigned. If macOS blocks it, open System
Settings > Privacy & Security and choose **Open Anyway**. Do not disable
Gatekeeper globally.

### ZIP fallback

1. Download and verify `SlayTheSpire-Modern-macOS-v1.1.0-universal.zip`.
2. Extract it and double-click `Install SlayTheSpire Modern macOS.command`, or
   run:

   ```bash
   ./install.sh
   ```

For a non-standard location, pass the app explicitly:

```bash
./install.sh "/Volumes/Games/SteamLibrary/steamapps/common/SlayTheSpire/SlayTheSpire.app"
```

Run a complete read-only preflight with `./install.sh --dry-run`. It validates
the Release payload, locates the game, checks the original jar, builds a
candidate patched jar, verifies the selected Zulu JRE, and verifies Universal
natives without changing the app.

## Universal implementation

The archive bundles matching Azul Zulu 8.96.0.205 JREs for `arm64` and
`x86_64`; the installer selects the native runtime using `uname -m`.

The payload includes a from-source Universal `liblwjgl.dylib`, because the new
fullscreen Java code requires matching new JNI implementations on both
architectures. To avoid redistributing other binaries from the game, the
remaining patch-native payload carries arm64 slices only. After the original
Steam jar passes an exact SHA-256 allowlist check, the installer extracts its
x86_64 libGDX/OpenAL/Steamworks slices and uses the system `/usr/bin/lipo` to
assemble Universal dylibs in a temporary directory. It never substitutes the
original unpatched LWJGL slice. Missing tools, patched JNI, or slices fail
during preflight, before any game file is moved.

## Backup, rollback, and uninstall

Installation preserves the original JRE, jar, launcher, and `Info.plist` in
`SlayTheSpire-Modern-backup` next to the app. The candidate jar and runtime are
fully prepared first. Once replacement starts, an `EXIT`/signal handler
restores the originals if any later step fails.

To revert:

```bash
./uninstall.sh
```

The uninstaller restores the exact files and verifies the original jar hash
before deleting the backup. Steam's **Verify integrity of game files** is an
additional recovery route.

## Troubleshooting

Save a ZIP-installer log:

```bash
./install.sh 2>&1 | tee ~/Desktop/SlayTheSpire-install.log
```

Save relevant PKG output:

```bash
grep 'sts-modern' /var/log/install.log > ~/Desktop/SlayTheSpire-pkg-install.log
```

- **Unsupported or modified jar:** verify the game in Steam. There is no
  checksum-bypass option because applying bytecode patches to an unknown build
  is unsafe.
- **Legacy ARM64 backup found:** run the v1.0.0 `uninstall.sh` first, confirm
  Steam launches the original game, then install v1.1.0.
- **Game is running:** quit it completely and retry.
- **Custom Steam library not detected:** pass the full `.app` path as shown
  above.
- **Crash reports:** see `~/Library/Logs/DiagnosticReports/`.

## Build and release checks

Release maintainers prepare the pinned JREs and build both artifacts with:

```bash
./scripts/prepare-zulu-jres.sh
./scripts/prepare-patch-overlay.sh
./build.sh
```

Pinned Azul archives:

| Architecture | Archive SHA-256 |
| --- | --- |
| arm64 | `1769ea082fa13ba29403363425716451b04b10f5ae6dba07f7f0a69666197f15` |
| x86_64 | `b2a195c418fe926e5c2032bfd3fb23ed93b1133f50b99cb2c0e47dc618130e5d` |

`build.sh` rejects missing architectures, payload checksum failures,
AppleDouble metadata, and obvious game-content paths. It emits SHA-256 files
for the Universal PKG and ZIP. Build formal public assets from a clean checkout
and do not publish an artifact that fails these gates.

## License and disclaimer

This project is not affiliated with Mega Crit or Valve. LWJGL, libGDX, and
their components retain their upstream licenses. Azul Zulu OpenJDK is provided
under GPLv2 with the Classpath Exception; its license files are included in the
runtime payload.
