# v1.2.3 — Local Workshop modded launch

## English

- Replaces only `MtsFinder.class` in the installed `mts-launcher.jar` with a
  Java 8 shim. The existing `Main.class` still links; no SteamAPI/SteamUGC calls
  occur in the finder, and the launcher's old native libraries remain untouched.
- Finds downloaded ModTheSpire in the game/default Steam library and modern or
  legacy `libraryfolders.vdf` paths. Writes `steam_appid.txt=646570` and logs the
  local Workshop path with actionable missing-download diagnostics.
- Both PKG and curl use the same installer. Preserves the original MTS JAR,
  records original/installed hashes, detects tampering, and restores it during
  rollback or uninstall. Supports verified v1.2.1/v1.2.2 upgrades.
- Ships only the replacement class and source, not the original launcher JAR.
  The curl installer pins v1.2.3 and the release ZIP SHA-256.
- Acceptance: bundled Java 8 resolved the actual downloaded Workshop path, then
  handed a controlled child JAR to `Main.class` and exited 0 in under 10 seconds.
  The launcher path contained no SteamAPI/UnsatisfiedLinkError. The real
  ModTheSpire/game child was not allowed to play audio during this test, so this
  is launcher acceptance rather than a gameplay claim. ModTheSpire's own
  child-process Steam discovery remains outside this shim.

## 中文

- 仅替换 `mts-launcher.jar` 内的 `MtsFinder.class`，保持 Java 8 和原方法签名；
  不调用 SteamAPI/SteamUGC，不替换旧 native，也不改动 `Main.class`。
- 从本地 Steam Workshop 内容和 `libraryfolders.vdf` 新旧路径查找已下载的
  ModTheSpire，写入 `steam_appid.txt=646570` 并记录实际路径及缺失提示。
- PKG/curl 共用安装路径；原版 MTS JAR 备份、安装状态校验、失败回滚和卸载恢复
  均覆盖本次修改。支持已验证的 v1.2.1/v1.2.2 原地升级。
- 真实 bundled Java 测试先解析出本机已下载的 Workshop 路径，再向 `Main.class`
  交接一个受控子 JAR，10 秒内退出码为 0，日志无
  SteamAPI/UnsatisfiedLinkError。测试期间未让真实游戏子进程播放音频，因此这
  是 launcher 验收，不声称已完成游戏内测试。ModTheSpire 子进程自身的 Steam
  查询仍不在本次 shim 修改范围。

---

# v1.2.2 — 无 Rosetta 原生启动修复

## 中文

- 将 Steam 游戏入口从 Bash 脚本改为最低支持 macOS 11 的 Universal
  (`arm64` + `x86_64`) Mach-O 启动器。新版原生 Apple Silicon Steam 客户端现在
  可以直接创建游戏进程；Apple Silicon 不再要求安装 Rosetta。启动器仍会继承
  Steam 上下文、转发启动参数，并选择安装器放入的本机架构 Zulu JRE。安装时会
  只保留主机 launcher slice，避免该游戏的 Steam 旧元数据强制选择 Intel。
- 重新构建 ARM64 OpenAL Soft 并强制 `minos 11.0`；发布门禁现在会检查启动器与
  所有补丁 native 的最低系统版本，防止在新系统构建时意外抬高兼容下限。
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
- 已验证的正式 v1.2.1 可直接升级到 v1.2.2。升级从原版备份重建候选，不叠加旧
  补丁；失败自动恢复 v1.2.1，成功后仍保留同一份原版备份供卸载还原。
- Retina drawable 跟随 macOS backing scale，最高使用完整 2×；在“看起来像
  1440×900”模式下允许 2880×1800 backing，再由 WindowServer 缩放到物理面板。
- 窗口现在可自由缩放；UI/输入继续使用逻辑点，OpenGL 与字体使用 Retina backing
  像素。4:3 到 21:9 之间可连续自由调整，仅拦截会破坏布局的极窄/极宽比例
  （最小 800×450）；同时修复重复创建菜单 BGM/环境音，以及退出动画误写窗口
  尺寸的问题。resize 不再重建任何游戏 UI/音频对象，而是保持固定逻辑画布并
  映射输入与物理 viewport。
- 新安装链会自动查找 Steam 库、严格校验原版 jar SHA-256、校验自身 payload、
  备份原文件，并在失败时自动回滚；不再提供危险的 `--force` 绕过。
- Release 不含游戏本体。新增 JNI 的 LWJGL 从源码构建为 Universal；安装器根据
  主机只写入 arm64 或 x86_64 slice。Intel 所需的其他 native 来自用户已校验的
  原版 jar；arm64 bridge 以独立文件名加载 ABI 匹配的 API。安装后的 JRE、启动器
  与所有 macOS native 均只包含当前处理器架构；Intel 路径会移除三个 i386-only
  旧 libGDX 条目，只保留 x86_64 对应库。

安装优先下载 `SlayTheSpire-Modern-macOS-v1.2.2-universal.pkg`；若 PKG 无法使用，
下载 ZIP 并双击 `Install SlayTheSpire Modern macOS.command`。卸载运行
`uninstall.sh`。

## English

- Replaces the Bash Steam entry point with a Universal (`arm64` + `x86_64`)
  Mach-O launcher targeting macOS 11. The native Apple Silicon Steam client can
  now spawn the game without Rosetta. The launcher preserves Steam's process
  context, forwards launch arguments, and executes the architecture-matched
  bundled Zulu JRE. Installation keeps only the host launcher slice so this
  game's legacy Steam metadata cannot force the Intel path on Apple Silicon.
- Rebuilds arm64 OpenAL Soft with a macOS 11.0 deployment target. Release gates
  now reject launchers or patch-native libraries whose minimum OS drifts above
  the documented macOS 11 baseline.
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
- A verified official v1.2.1 install upgrades in place. The candidate is rebuilt
  from the preserved original rather than layered over the old patch; failure
  restores v1.2.1, while success retains the same original backup for uninstall.
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
  source, then the installer writes only the host slice. Other Intel natives
  come from the user's validated original jar; the arm64 bridge loads its
  ABI-matched API under a separate name. The installed JRE, launcher, and every
  macOS native contain only the detected processor architecture. The Intel
  path removes three obsolete i386-only libGDX entries and keeps the x86_64
  counterparts.

Prefer the Universal PKG. Use the ZIP and double-click command as a fallback;
run `uninstall.sh` to restore the originals.
