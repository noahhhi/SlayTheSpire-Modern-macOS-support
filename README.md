# Slay the Spire - Apple Silicon (ARM64) Native Patch

让 Steam 版《杀戮尖塔》在 Apple Silicon Mac 上原生运行的补丁：去掉 Rosetta，Retina HiDPI 清晰渲染，修复全屏/无边框的诸多问题。

English version below / 英文版见下文。

## 效果

- **原生 ARM64 运行**：内置 Azul Zulu OpenJDK 8 (aarch64) 运行时，LWJGL2 / libGDX / steamworks4j 全部重编为 arm64，不再经过 Rosetta 翻译
- **Retina HiDPI**：窗口/无边框模式按 2x 物理像素渲染，文字锐利
- **全屏 = macOS 原生 Space**：可以 Cmd+Tab、四指滑动切换，不再是独占黑屏
- **全屏分辨率读取物理像素**：内屏最高 2560x1600（而不是浪费性能的 2880x1800 HiDPI 模式），渲染与面板 1:1
- **无边框窗口正确覆盖菜单栏**，并自动跟随当前桌面逻辑分辨率
- **设置里切换显示模式立即生效**，无需重启游戏
- **窗口绿灯全屏按钮可用**

## 要求

- Apple Silicon Mac（M1/M2/M3/M4...），macOS 11 或更高
- Steam 版《Slay the Spire》（未修改过的原版；安装器会校验 `desktop-1.0.jar` 的 SHA-256，Steam 更新游戏后需等待补丁更新，或用 `--force` 强行安装）

## 安装

### 方式 A：pkg 安装包（推荐）

1. 从 [Releases](../../releases) 下载 `SlayTheSpire-ARM64-macOS-v*.pkg`
2. 双击打开；如果 Gatekeeper 提示未公证，右键 → 打开
3. 安装器会自动找到 Steam 库中的游戏并完成补丁

### 方式 B：zip + 双击

1. 从 [Releases](../../releases) 下载 `SlayTheSpire-ARM64-macOS-v*.zip` 并解压
2. 双击 `Install SlayTheSpire ARM64.command`；如果被拦截，在文件夹上右键 → 打开，或先执行 `xattr -dr com.apple.quarantine` 该目录
3. 也可以在终端里手动执行：`./install.sh`

安装器会自动解析 `~/Library/Application Support/Steam/config/libraryfolders.vdf`，支持自定义 Steam 库位置；也可以手动指定：

```bash
./install.sh "/path/to/SlayTheSpire.app"
```

安装过程：备份原始文件（移动到游戏旁的 `SlayTheSpire-ARM64-backup/`，零额外磁盘占用）→ 原地修补 jar（APFS clone，只更新差异条目）→ 安装 ARM64 JRE 与启动器 → ad-hoc 重签名。任何一步失败都会自动回滚。

## 卸载

运行 zip 中的 `uninstall.sh`（或重新下载），会从备份完整还原原版文件。也可以在 Steam 里"验证游戏文件完整性"强制恢复。

## 工作原理

| 部分 | 内容 |
| --- | --- |
| `payload/jre/` | Azul Zulu OpenJDK 8 ARM64 运行时 |
| `payload/jar/` | 793 个 jar 差异条目：JDK8 重编的 LWJGL2/libGDX 类、arm64 natives、显示修复补丁类 |
| `payload/launcher` | 替换 x86_64 启动器的 bash 脚本，转发 Steam 启动参数 |
| `payload/jar-delete.txt` | 从 jar 中移除的 5 个 x86 native 条目 |

关键显示修复：全屏不再切换显示模式（Apple Silicon 已禁止软件模式切换），改用 `kCGLCPSurfaceBackingSize` 把 GL drawable 固定在所选物理分辨率，由 WindowServer 合成缩放。

## 故障排查

- 安装日志会直接打印；pkg 安装日志在 `/var/log/install.log`：`grep sts-arm64 /var/log/install.log`
- 崩溃报告在 `~/Library/Logs/DiagnosticReports/`
- 游戏更新后校验失败：等待新版补丁，或 `./install.sh --force`（风险自负）

## 声明

本补丁由社区制作，与 MegaCrit 无关。发布内容**不包含任何游戏本体**，仅包含补丁文件，需要你已经拥有 Steam 版游戏。LWJGL / libGDX / steamworks4j 遵循各自开源许可；JRE 为 Azul Zulu OpenJDK（GPLv2 + Classpath Exception）。

---

# Slay the Spire - Apple Silicon (ARM64) Native Patch

A community patch that makes the Steam version of Slay the Spire run natively on Apple Silicon Macs: no Rosetta, crisp Retina HiDPI rendering, and proper fullscreen/borderless behavior.

## What you get

- **Native ARM64 runtime**: bundled Azul Zulu OpenJDK 8 (aarch64); LWJGL2, libGDX and steamworks4j rebuilt for arm64 - no Rosetta translation
- **Retina HiDPI**: windowed/borderless modes render at 2x physical pixels, sharp text
- **Fullscreen as a native macOS Space**: Cmd+Tab and trackpad gestures work; no more exclusive black-screen mode
- **Physical-pixel fullscreen resolutions**: up to the panel's native size (e.g. 2560x1600 instead of the wasteful 2880x1800 HiDPI mode), rendering 1:1 with the panel
- **Borderless window properly covers the menu bar** and always tracks the current desktop size
- **Display mode changes apply instantly**, no restart required
- **The green traffic-light fullscreen button works**

## Requirements

- An Apple Silicon Mac running macOS 11 or later
- The Steam version of Slay the Spire, unmodified (the installer verifies the SHA-256 of `desktop-1.0.jar`; after a Steam update, wait for a patch update or use `--force` at your own risk)

## Install

### Option A: pkg installer (recommended)

1. Download `SlayTheSpire-ARM64-macOS-v*.pkg` from [Releases](../../releases)
2. Open it; if Gatekeeper complains, right-click -> Open
3. The installer locates the game in your Steam library automatically and applies the patch

### Option B: zip + double-click

1. Download and unzip `SlayTheSpire-ARM64-macOS-v*.zip` from [Releases](../../releases)
2. Double-click `Install SlayTheSpire ARM64.command`; if blocked, right-click -> Open, or run `xattr -dr com.apple.quarantine` on the folder first
3. Or run `./install.sh` in a terminal

Custom Steam library locations are detected via `libraryfolders.vdf`; you can also pass the app path explicitly:

```bash
./install.sh "/path/to/SlayTheSpire.app"
```

What the installer does: backs up the original files (moved to `SlayTheSpire-ARM64-backup/` next to the game - zero extra disk), patches the jar in place (APFS clone, only changed entries), installs the ARM64 JRE and launcher, and ad-hoc re-signs the app. Any failure triggers an automatic rollback.

## Uninstall

Run `uninstall.sh` from the zip to restore the original files from the backup. Steam's "Verify integrity of game files" also works.

## How it works

| Part | Contents |
| --- | --- |
| `payload/jre/` | Azul Zulu OpenJDK 8 ARM64 runtime |
| `payload/jar/` | 793 jar diff entries: LWJGL2/libGDX classes recompiled with JDK8, arm64 natives, display-fix patch classes |
| `payload/launcher` | bash script replacing the x86_64 launcher binary, forwarding Steam launch options |
| `payload/jar-delete.txt` | 5 x86 native entries removed from the jar |

Key display fix: fullscreen no longer switches display modes (Apple Silicon forbids software mode switching); instead `kCGLCPSurfaceBackingSize` pins the GL drawable to the selected physical resolution and lets the WindowServer composite it.

## Troubleshooting

- Installer output is printed directly; pkg logs go to `/var/log/install.log`: `grep sts-arm64 /var/log/install.log`
- Crash reports live in `~/Library/Logs/DiagnosticReports/`
- Checksum mismatch after a game update: wait for a patch update, or `./install.sh --force` (at your own risk)

## Disclaimer

This is a community patch, not affiliated with MegaCrit. The release contains **no game content** - patch files only - and requires that you own the game on Steam. LWJGL / libGDX / steamworks4j are under their respective open-source licenses; the JRE is Azul Zulu OpenJDK (GPLv2 + Classpath Exception).
