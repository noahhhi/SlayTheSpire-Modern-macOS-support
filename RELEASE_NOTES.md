# v1.1.1 — Fullscreen Retina and PKG reliability fix

## 中文

- 同一 Universal PKG/ZIP 支持 Intel (`x86_64`) 与 Apple Silicon (`arm64`)，
  两种架构均使用 Azul Zulu OpenJDK 8.96.0.205 原生 JRE。
- 窗口、无边框、设置内全屏与绿色按钮统一为支持 Retina 的 macOS 原生 Space
  全屏路径。
- 修复进入全屏 Space 时 viewport 短暂保留 2880×1800、而物理 drawable 已限制为
  2560×1600 所造成的裁切与错误分辨率。
- 修复 PKG 在补丁成功后仍错误返回安装失败的问题；重复安装仍会为保护原版备份而拒绝。
- Retina drawable 以显示面板的原生物理像素为上限；本机 2560×1600 面板不再
  按系统的 2880×1800 缩放虚拟模式渲染。
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

安装优先下载 `SlayTheSpire-Modern-macOS-v1.1.1-universal.pkg`；若 PKG 无法使用，
下载 ZIP 并双击 `Install SlayTheSpire Modern macOS.command`。卸载运行
`uninstall.sh`。

## English

- One Universal PKG/ZIP supports Intel (`x86_64`) and Apple Silicon (`arm64`),
  with native Azul Zulu OpenJDK 8.96.0.205 JREs for both architectures.
- Windowed, borderless, in-game fullscreen, and the green window button share
  the Retina-aware native macOS Space fullscreen path.
- Fixed fullscreen Space transitions retaining a 2880x1800 viewport after the
  physical drawable had been capped to 2560x1600.
- Fixed the PKG reporting failure after a successful patch; repeat installs are
  still rejected to protect the original backup.
- Retina drawables are capped to each panel's native physical pixels, avoiding
  a 2880×1800 scaled-mode render surface on a 2560×1600 panel.
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
