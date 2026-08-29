# v1.2.1 — Full 2× Retina backing and post-launch-safe PKG

## 中文

- 同一 Universal PKG/ZIP 支持 Intel (`x86_64`) 与 Apple Silicon (`arm64`)，
  两种架构均使用 Azul Zulu OpenJDK 8.96.0.205 原生 JRE。
- 窗口、无边框、设置内全屏与绿色按钮统一为支持 Retina 的 macOS 原生 Space
  全屏路径。
- 1440×900 游戏逻辑画布使用完整 2× HiDPI backing，窗口与全屏均以
  2880×1800 OpenGL backing/viewport 渲染；输入仍保持 1440×900 point 坐标。
- 普通窗口最大尺寸跟随当前逻辑桌面（当前配置为 1440×900），不再按面板
  2560×1600 物理像素反推 1280×800 上限。窗口比例仍可在 4:3–21:9 内连续调整；
  安全 viewport 与输入映射会对其他比例居中适配，不再拉伸或错位 UI。
- 同一 build 重复运行 PKG 会严格复核 payload fingerprint、原版备份、当前 JAR、
  JRE 全文件、启动器和 Info.plist；完全一致时返回成功，损坏、半安装或同版本
  不同 build 仍安全拒绝。游戏正常改写 `info.displayconfig` 后也可安全重复安装。
- Retina drawable 跟随 macOS backing scale，最高使用完整 2×；在“看起来像
  1440×900”模式下允许 2880×1800 backing，再由 WindowServer 缩放到物理面板。
- 窗口现在可自由缩放；UI/输入继续使用逻辑点，OpenGL 与字体使用 Retina backing
  像素。4:3 到 21:9 之间可连续自由调整，仅拦截会破坏布局的极窄/极宽比例
  （最小 800×450）；同时修复重复创建菜单 BGM/环境音，以及退出动画误写窗口
  尺寸的问题。resize 不再重建任何游戏 UI/音频对象，而是保持固定逻辑画布并
  映射输入与物理 viewport。
- 新安装链会自动查找 Steam 库、严格校验原版 jar SHA-256、校验自身 payload、
  备份原文件，并在失败时自动回滚；不再提供危险的 `--force` 绕过。
- Release 不含游戏本体。新增 JNI 的 LWJGL 从源码构建为 Universal；其余 x86_64
  native slice 从用户已校验的原版 jar 本地提取，再与补丁 arm64 slice 合成。
  Intel 逐字节保留官方签名的 Steam API；arm64 bridge 以独立文件名加载 ABI 匹配
  的可再分发 API，避免破坏 Rosetta 签名或混用 SDK。

安装优先下载 `SlayTheSpire-Modern-macOS-v1.2.1-universal.pkg`；若 PKG 无法使用，
下载 ZIP 并双击 `Install SlayTheSpire Modern macOS.command`。卸载运行
`uninstall.sh`。

## English

- One Universal PKG/ZIP supports Intel (`x86_64`) and Apple Silicon (`arm64`),
  with native Azul Zulu OpenJDK 8.96.0.205 JREs for both architectures.
- Windowed, borderless, in-game fullscreen, and the green window button share
  the Retina-aware native macOS Space fullscreen path.
- A 1440×900 game canvas now uses a complete 2× HiDPI surface, rendering
  windowed and fullscreen OpenGL backing/viewports at 2880×1800 while input
  remains in 1440×900 point coordinates.
- Normal-window maximum size follows the current logical desktop (1440×900 in
  this configuration), rather than deriving a 1280×800 cap from the panel's
  2560×1600 physical pixels. Windows remain continuously adjustable from 4:3
  through 21:9, with a centered safe viewport and matching input transform.
- Repeating the exact PKG build now validates the payload fingerprint, original
  backup, current JAR, every JRE file, launcher, and `Info.plist`, then returns
  success. Corrupt, partial, or same-version/different-build states are still
  rejected safely, while normal post-launch `info.displayconfig` changes remain
  accepted.
- Retina drawables follow the macOS backing scale up to a complete 2×. In
  “Looks like 1440×900” mode, the game may use a 2880×1800 backing surface and
  lets WindowServer perform the final resampling to the physical panel.
- Windows are freely resizable: UI/input remain in logical points while OpenGL
  and fonts use Retina backing pixels. Ratios remain continuously adjustable
  from 4:3 through 21:9; only layout-breaking extremes are clamped (minimum
  800×450). Resizing no longer duplicates menu music/ambience or persists
  teardown-animation dimensions: it keeps a stable logical canvas and maps
  input/backing viewports without reconstructing game UI or audio objects.
- The installer discovers Steam libraries, strictly validates the original jar
  and its own payload, preserves exact originals, and automatically rolls back
  failures. The unsafe checksum-bypass option has been removed.
- No game content is shipped. LWJGL with the new JNI is built Universal from
  source; other x86_64 slices come from the user's validated original jar.
  Intel preserves the officially signed Steam API byte-for-byte, while the
  arm64 bridge loads its ABI-matched redistributable API under a separate name.

Prefer the Universal PKG. Use the ZIP and double-click command as a fallback;
run `uninstall.sh` to restore the originals.
