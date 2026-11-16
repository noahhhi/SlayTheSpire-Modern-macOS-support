# v1.2.7 — No top letterbox band when switching to fullscreen

## English

- Fixes the extra black band at the top after switching windowed → fullscreen.
  The logical canvas (`Settings.WIDTH/HEIGHT`) is computed once at startup from
  the real window size (windowed: `1470x895`). The old build applied fullscreen
  live, growing the window to the `1470x923` visible area while the canvas
  stayed `1470x895`; the `FitViewport` preserved that aspect and centered the
  frame, which shows as a top/bottom band (the top one is what you saw).
- Fullscreen / borderless-fullscreen / resolution changes now save the setting
  and show the vanilla **Restart Required** text instead of resizing the window
  mid-session. The next launch builds the canvas from the real fullscreen size,
  so it fills edge to edge without a band.
- This keeps the saved mode stable (`Settings.SAVED_*`, no shrinking
  `info.displayconfig`) and avoids the UI misalignment that a live canvas resize
  causes, because cached UI positions are computed from `Settings.WIDTH/HEIGHT`
  at startup.
- Windowed resizing still follows the canvas aspect; live fullscreen layout
  changes remain restart-scoped, matching the game's own design.

## 中文

- 修复“窗口切到全屏后顶部多出一条黑边”。逻辑画布 `Settings.WIDTH/HEIGHT` 在启动
  时按真实窗口尺寸计算（窗口模式 `1470x895`）。旧版本会实时应用全屏，把窗口
  拉高到可见区 `1470x923`，但画布仍是 `1470x895`，`FitViewport` 保持该比例并
  居中，于是上下各留一条 letterbox，顶部那条就是看到的黑边。
- 现在全屏 / 无边框全屏 / 分辨率切换只保存设置，并显示原版的
  **Restart Required** 提示，不再在运行中改变窗口；下次启动用真实全屏尺寸
  重新构建画布，直接铺满，没有黑边。
- 同时保持 `info.displayconfig` 不再递减（写 `Settings.SAVED_*`），也避免了
  实时改画布导致的 UI 错位（UI 位置是在启动时按 `Settings.WIDTH/HEIGHT` 算好并
  缓存的）。
- 窗口模式的缩放仍按画布比例跟随；全屏布局变更按原版设计走重启生效。

---

# v1.2.6 — Crisp BaseMod text, idle background, stable display state

## English

- Fixes the blurred text that appeared only after loading BaseMod. BaseMod's
  `ApplyScreenPostProcessor` always rendered the frame into a logical-size
  `1470x895` FBO and then upscaled it to the `2940x1790` Retina backbuffer, even
  when no post-processor was registered. The installer now patches that
  Workshop class so the FBO path is skipped while `postProcessors` is empty.
  Verified by screenshot: menu edge energy went from `82` back to `145`
  (vanilla `147`), logo from `185` to `380` (vanilla `387`).
- The patch is applied to the user's own `BaseMod.jar`, with the original kept
  next to the installer backup and restored by `uninstall.sh`. Unknown BaseMod
  builds are left untouched with a warning; the hash of the supported build is
  pinned in `supported-basemod.sha256`.
- Window focus loss now stops rendering: `backgroundFPS` is set to `-1`, so an
  unfocused/paused game does not keep drawing frames. The loop still ticks at a
  low rate only to process events.
- Fullscreen/borderless toggles no longer write the live window height into
  `info.displayconfig`. They write `Settings.SAVED_WIDTH/SAVED_HEIGHT`, so the
  saved resolution no longer shrinks by the title-bar height on every toggle
  and switching back to windowed mode survives restarts.

## 中文

- 修复只有加载 BaseMod 后文字才发糊的问题。BaseMod 的
  `ApplyScreenPostProcessor` 在没有任何 post-processor 时也会把整帧画到逻辑尺寸
  `1470x895` 的 FBO，再放大到 `2940x1790` 的 Retina drawable。安装器现在会
  修改 Workshop 里的这个类：`postProcessors` 为空时跳过 FBO 路径。截图实测：
  菜单边缘强度 `82 → 145`（原版 `147`），Logo `185 → 380`（原版 `387`）。
- 只修改用户本机的 `BaseMod.jar`，原文件保留在安装器备份目录，
  `uninstall.sh` 会原样恢复；未知版本只给出警告不改动。支持版本哈希固定在
  `supported-basemod.sha256`。
- 窗口失焦后停止绘制：`backgroundFPS` 设为 `-1`，后台/暂停时不再持续出帧，
  仅保留低频事件循环。
- 全屏/无边框切换不再把当前窗口高度写进 `info.displayconfig`，改用
  `Settings.SAVED_WIDTH/SAVED_HEIGHT`，避免每次切换高度递减（标题栏高度），
  并修复“全屏退出后重启无法切回窗口模式”的状态问题。

---

# v1.2.5 — HiDPI fill on notch MacBooks

## English

- Fixes the thick left/right black bars reported on the new notch MacBook. The
  overlay kept the logical canvas at the saved window size (`1470x956`) while
  macOS clamps the real window to `1470x895` (or `1470x923` in fullscreen), so
  the `FitViewport` preserved the wrong aspect ratio. `LwjglGraphics` now copies
  the real window size into the logical canvas right after the window is
  created; the viewport fills the whole drawable area.
- Fullscreen and borderless-fullscreen now request an **undecorated** window, so
  the 28 pt title bar is no longer wasted and the game fills everything below
  the menu-bar/notch strip.
- Verified on a MacBook Air M2 (`2560x1664`, notch): window `1470x923`, backing
  `2940x1846`, GL viewport `0,0 2940x1846`, pixel scale `2.0`. No side bars and
  no title bar; HiDPI is active at 2x.
- The 33 pt menu-bar strip (which contains the notch) remains visible: hiding
  it needs `NSApplicationPresentationHideMenuBar` through a native helper,
  which is outside this build. Everything the game can draw below that strip is
  filled edge to edge.
- Adds `tests/test-display-overlay.sh` and `display-overlay.sha256`; the release
  build fails if the two patched display classes drift.

## 中文

- 修复新刘海屏 MacBook 上全屏时左右两条粗黑边。原因是 overlay 把逻辑画布固定
  在保存的窗口尺寸 `1470x956`，而 macOS 实际窗口是 `1470x895`（全屏时
  `1470x923`），`FitViewport` 按错误比例做 letterbox。现在 `LwjglGraphics`
  在窗口创建后把真实窗口尺寸写回逻辑画布，viewport 会铺满整个 drawable。
- 全屏 / 无边框全屏改为请求 **无标题栏** 窗口，不再浪费 28 pt 的标题栏，游戏
  会一直铺到菜单栏/刘海条下方。
- 在 MacBook Air M2（`2560x1664`，刘海屏）实测：窗口 `1470x923`，backing
  `2940x1846`，GL viewport `0,0 2940x1846`，像素比例 `2.0`。没有左右黑边，
  也没有标题栏，HiDPI 为 2 倍渲染。
- 顶部 33 pt 菜单栏（刘海所在条带）仍然显示：要让它隐藏需要原生
  `NSApplicationPresentationHideMenuBar` 辅助库，不在本次构建范围内；除此之外的区域已铺满。
- 新增 `tests/test-display-overlay.sh` 与 `display-overlay.sha256`，两个
  显示类被改动时发布会直接失败。

---

# v1.2.4 — BaseMod patch compatibility for the modded launch

## English

- Fixes the arm64 modded launch failing while BaseMod patches
  `CardCrawlGame.loadPostCombat`:
  `javassist.CannotCompileException: [source error] no such field: i`.
- Root cause was the game overlay, not the curl download. The upstream HiDPI
  port recompiled `CardCrawlGame` from decompiled source. That class kept the
  game logic but lost its `LocalVariableTable` and shifted every source line
  number. ModTheSpire inserts patches by line and binds named locals; BaseMod's
  `CustomRewardLoad` reads the local `i`, so javassist fell back to field
  lookup and aborted. PKG and curl installs shared the same broken class.
- Rebuilds `CardCrawlGame.class` from the unmodified Steam bytecode and inserts
  only the required `StsDisplay.onWindowResize` call in `resize(int, int)`.
  Line numbers, locals, and every other method stay byte-identical to the
  Steam 12-18-2022 jar.
- Stops shipping recompiled copies of helper classes that are identical to the
  original (`CardCrawlGame$1`, `CardCrawlGame$2`, `CardCrawlGame$GameMode`,
  `Settings$1`, `Settings$GameLanguage`, `ToggleButton$1`,
  `ToggleButton$ToggleBtnType`). The untouched originals keep their debug
  metadata.
- Adds `tests/test-overlay-debug-info.py` to the release build. It parses the
  shipped class and fails if `loadPostCombat` loses its `LocalVariableTable`
  or the local `i`, or if the resize hook disappears.
- Verified offline with ModTheSpire 3.30.3 and BaseMod 5.56.0: the old class
  reproduces `no such field: i` at the locator's line; the rebuilt class binds
  `i` and the two other `CardCrawlGame` insert patches (`sb`, `camera`) cleanly.
- Verified v1.2.1-v1.2.3 installations upgrade in place. Unknown builds are
  still refused without touching the game.

## 中文

- 修复 Apple Silicon 模组启动在 BaseMod 打补丁阶段中止的问题：
  `javassist.CannotCompileException: [source error] no such field: i`。
- 根因不是 curl 下载，而是游戏 class overlay：上游 HiDPI 版本用反编译源码
  重新编译了 `CardCrawlGame`，逻辑虽然保留，但 `LocalVariableTable` 丢失、
  源码行号整体改变。ModTheSpire 按行号插入补丁并按名字绑定局部变量，
  BaseMod 的 `CustomRewardLoad` 需要局部变量 `i`，javassist 只能当作字段
  查找，于是报错。PKG 和 curl 安装共用同一份有问题的 class。
- 改为直接从 Steam 原版字节码构造 `CardCrawlGame.class`，仅在
  `resize(int, int)` 中插入必要的 `StsDisplay.onWindowResize` 调用；行号、
  局部变量表以及其余方法都与 12-18-2022 Steam jar 完全一致。
- 不再覆盖与原版完全相同、但被重新编译过的辅助类（`CardCrawlGame$1`、
  `$2`、`$GameMode`、`Settings$1`、`Settings$GameLanguage`、
  `ToggleButton$1`、`ToggleButton$ToggleBtnType`），保留原版调试信息。
- 构建新增 `tests/test-overlay-debug-info.py`：解析发布 class，检查
  `loadPostCombat` 是否仍有 `LocalVariableTable` 和局部变量 `i`，以及 resize
  钩子是否存在，缺失即失败。
- 使用 ModTheSpire 3.30.3 + BaseMod 5.56.0 离线验证：旧 class 在定位行复现
  `no such field: i`；新 class 可绑定 `i`，另外两个 `CardCrawlGame` 插入补丁
  （`sb`、`camera`）同样通过。
- 已验证 v1.2.1 至 v1.2.3 可原地升级；未知 build 仍会在零写入状态下拒绝。

---

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
