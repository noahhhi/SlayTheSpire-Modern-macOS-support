# Slay the Spire modern macOS support

[简体中文](README.zh-CN.md)

A community compatibility patch for the Steam macOS release of *Slay the
Spire*. Version 1.2.9 is one Universal distribution for Intel and Apple
Silicon Macs running macOS 11 or later.

## Features

- Native `x86_64` and `arm64` Azul Zulu OpenJDK 8 runtimes.
- A real Universal Mach-O Steam launcher. Apple Silicon runs the launcher,
  JRE, and game-native libraries without Rosetta; Intel uses the same package's
  `x86_64` path. The installer thins the launcher to the host architecture so
  Steam's legacy x86 preference cannot select an Intel slice on a Mac without
  Rosetta.
- Retina-aware windowed, borderless, and native macOS Space fullscreen modes.
- Retina backing follows macOS's HiDPI scale up to 2× instead of being capped to
  the panel's physical pixel count. A 1440×900 logical canvas therefore renders
  into a full 2880×1800 OpenGL backing surface for sharp text and UI.
- Windows remain continuously resizable from 4:3 through 21:9 rather than being
  locked to one ratio. Only layout-breaking extremes and sizes beyond the
  current display's logical desktop are clamped (1440×900 maximum in this
  configuration, 800×450 minimum). Other ratios use a centered safe viewport,
  with matching point-based input mapping and no UI/audio reconstruction.
- One fullscreen behavior for the in-game Fullscreen toggle, Borderless
  Fullscreen toggle, and the green window button.
- Automatic Steam library discovery, including additional libraries listed in
  `libraryfolders.vdf`.
- Strict original-jar SHA-256 validation, payload checksum verification,
  exact-file backup, and automatic rollback on installation failure. Repeating
  the exact installed build fully revalidates the JAR, JRE, launcher,
  and `Info.plist`, then returns success instead of a false PKG failure. Mutable
  game preferences may change normally after launch without being mistaken for
  patch corruption.

The release contains patch files and redistributable runtimes only. It does
not contain `desktop-1.0.jar`, the game app, saves, art, audio, or other game
content. You must own and install the Steam version first.

When macOS is set to “Looks like 1440×900,” WindowServer still composites at
2880×1800 before scaling to the 2560×1600 panel. The patch intentionally uses
that complete 2× backing surface: game/input coordinates stay at 1440×900 while
OpenGL and fonts rasterize at 2880×1800. WindowServer performs the final panel
resampling, just as it does for other Retina-aware apps.

## Install

### PKG (recommended)

1. Download `SlayTheSpire-Modern-macOS-v1.2.9-universal.pkg` and its `.sha256`
   file from [Releases](../../releases).
2. Optional integrity check:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c SlayTheSpire-Modern-macOS-v1.2.9-universal.pkg.sha256
   ```

3. Open the package. It finds the logged-in user's Steam library and runs the
   patch as that user, not as root against the game directory.

The package is currently ad-hoc/unsigned. If macOS blocks it, open System
Settings > Privacy & Security and choose **Open Anyway**. Do not disable
Gatekeeper globally.

A verified v1.2.1-v1.2.3 installation upgrades in place: the installer builds v1.2.9
from the preserved original jar, keeps the original backup, and restores the
previous patch automatically if the upgrade fails. Unknown or modified
older builds are refused without changing the game.

### ZIP fallback

1. Download and verify `SlayTheSpire-Modern-macOS-v1.2.9-universal.zip`.
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
candidate patched jar, verifies the selected Zulu JRE, and verifies that every
installed macOS native matches the detected host architecture without changing
the app.

### Terminal download helper

Requires macOS 11 or later and an existing Steam installation of the game.
Quit the game before running this command. It downloads the **v1.2.9** Universal
ZIP (about 83 MB), verifies its release `.sha256` against the hash pinned in the script, extracts it into a temporary
directory, and runs the included `install.sh`. Without `--dry-run`, the installer
backs up and replaces game files.

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/noahhhi/SlayTheSpire-Modern-macOS-support/main/install-oneline.sh | bash )
```

To validate first, pass `--dry-run`:

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/noahhhi/SlayTheSpire-Modern-macOS-support/main/install-oneline.sh | bash -s -- --dry-run )
```

For a custom Steam library, set `STS_APP_PATH` on the **bash side** of the pipe:

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/noahhhi/SlayTheSpire-Modern-macOS-support/main/install-oneline.sh | STS_APP_PATH="/Volumes/Games/SteamLibrary/steamapps/common/SlayTheSpire/SlayTheSpire.app" bash -s -- --dry-run )
```

Remove `--dry-run` to install. The existing dry run builds temporary candidates
beside the game and cleans them up; it does not replace files inside the app.
The helper stops if the checksum cannot be downloaded, is malformed, or does
not match. It removes its download/extraction directory on exit. Download and
extract the ZIP again when you need `uninstall.sh`; keep the original backup.

These commands execute code from this repository. You can download and inspect
`install-oneline.sh` before running it. The checksum checks the ZIP's integrity;
it is not an independent signature of the release or the helper. `pipefail` also
reports failures while downloading the helper itself. This entry point adds no
`sudo` or Gatekeeper commands; the existing v1.2.9 installer does clear quarantine
attributes on the replacement JRE, JAR, and launcher during a normal install.
The helper downloads only the patch release, not the game.


## Universal implementation

The archive bundles matching Azul Zulu 8.96.0.205 JREs for `arm64` and
`x86_64`; the installer selects the native runtime using `uname -m`.
The archive's launcher is Universal, but the installed launcher is thinned to
the same host architecture. This is required because this game's legacy Steam
launch metadata otherwise prefers an available `x86_64` slice even on Apple
Silicon.

The payload includes a from-source Universal `liblwjgl.dylib`, because the new
fullscreen Java code requires matching new JNI implementations on both
architectures. To avoid redistributing other binaries from the game, the
remaining patch-native payload carries arm64 slices only. After the original
Steam jar passes an exact SHA-256 allowlist check, the installer creates a
host-native-only jar: arm64 uses the patch slices, while x86_64 uses the
verified original libGDX/OpenAL/Steamworks slices plus the patched LWJGL slice.
The Intel path removes the three obsolete i386-only libGDX entries and keeps
their x86_64 `*64` counterparts; no 32-bit code is installed on macOS 11+.
Missing tools, patched JNI, or slices fail during preflight, before any game
file is moved.

The Steam jar's original `libsteam_api.dylib` supplies the host slice locally;
it is never redistributed. The migrated arm64 bridge loads its ABI-matched API
under a separate arm-only name, while Intel uses the original x86_64 code. All
installed Mach-O natives are reduced to the detected host architecture,
ad-hoc signed, and verified before they enter the candidate jar.

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
  Steam launches the original game, then install v1.2.9.
- **Steam reports AppError 46 / Failed to spawn process:** v1.2.1 used a shell
  script as the app executable, which the native Apple Silicon Steam client
  could not spawn. Install v1.2.9 or later; installing Rosetta is not required.
- **Game is running:** quit it completely and retry.
- **Direct launch crashes in `SteamAppsNative_getAppBuildId`:** Steamworks was
  not initialized, so the game's integration dereferenced a null `SteamApps`
  interface. Launch from the Steam client for runtime acceptance; direct Java
  or Finder launch is not a valid Steam-integration test.
- **Custom Steam library not detected:** pass the full `.app` path as shown
  above.
- **Crash reports:** see `~/Library/Logs/DiagnosticReports/`.

## Build and release checks

Release maintainers prepare the pinned JREs and build both artifacts with:

```bash
./scripts/prepare-zulu-jres.sh
./scripts/prepare-openal.sh
./scripts/prepare-patch-overlay.sh
./scripts/prepare-mts-shim.sh "/path/to/original/mts-launcher.jar"
./build.sh
STS_ORIGINAL_MTS="/path/to/original/mts-launcher.jar" ./scripts/verify-with-original.sh \
  "/path/to/SlayTheSpire-Modern-backup" \
  "/path/to/SlayTheSpire-Modern-macOS-v1.2.2-universal.zip"
```

Pinned Azul archives:

| Architecture | Archive SHA-256 |
| --- | --- |
| arm64 | `1769ea082fa13ba29403363425716451b04b10f5ae6dba07f7f0a69666197f15` |
| x86_64 | `b2a195c418fe926e5c2032bfd3fb23ed93b1133f50b99cb2c0e47dc618130e5d` |

`build.sh` also runs the launcher, install-state, and PackageKit status
regressions; it rejects missing architectures, payload checksum failures,
AppleDouble metadata, and obvious game-content paths. The separate
original-Steam gate constructs both host candidates without adding the game to
the release, and optionally verifies an official prior-release upgrade. It emits
SHA-256 files for the Universal PKG and ZIP. Build formal public assets from a
clean checkout and do not publish an artifact that fails these gates.

## License and disclaimer

This project is not affiliated with Mega Crit or Valve. LWJGL, libGDX, and
their components retain their upstream licenses. Azul Zulu OpenJDK is provided
under GPLv2 with the Classpath Exception; its license files are included in the
runtime payload.

## Modded launch in v1.2.9

The old `mts-launcher.jar` uses a Steamworks Java/native pairing that cannot be
fixed by swapping in the newer arm64 native alone. The installer replaces only
`com/megacrit/mtslauncher/MtsFinder.class` with our Java 8 shim. It preserves
`Main.class`, the method signature, and every old native library in that JAR.
The shim finds a downloaded `ModTheSpire.jar` in local Workshop content, using
the game library, the default macOS Steam library, and modern/legacy paths in
`steamapps/libraryfolders.vdf` and `config/libraryfolders.vdf`. It writes
`steam_appid.txt=646570` and logs the selected path to `sendToDevs/mts_launcher.log`.
Subscribe to ModTheSpire and finish its download before selecting Steam's
modded launch option. This lookup does not download mods or query subscriptions.

PKG and curl installations both use the same `install.sh` patch path. Original
and installed MTS JAR hashes are recorded; upgrades, failed installs, and
uninstall restore the appropriate preserved copy. Unknown MTS JARs are refused.
The release ships only our replacement class and its source, not the game or
original launcher JAR. Its bytecode is tested on Java 8 and verified against source.

The bounded real-runtime test resolved the actual downloaded Workshop path, then
handed a controlled child JAR to `Main.class` and exited cleanly in under 10
seconds. The real game child was not allowed to play audio during acceptance, so
this is launcher validation, not a gameplay test. ModTheSpire's child process
still performs its own Steam discovery; outside Steam it can warn that it cannot
connect. That separate behavior is unchanged by this shim.
