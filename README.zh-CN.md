# 《杀戮尖塔》现代 macOS 适配补丁

[English](README.md)

这是面向 Steam macOS 版《杀戮尖塔》的社区兼容补丁。v1.2.2 使用同一份
Universal 发布包支持 Intel 与 Apple Silicon Mac，最低系统为 macOS 11。

## 功能

- 内置 `x86_64` 与 `arm64` 两套 Azul Zulu OpenJDK 8 原生运行时。
- Steam 主入口为真正的 Universal Mach-O 可执行文件。Apple Silicon 的启动器、
  JRE 与游戏 native 库均原生运行，不需要 Rosetta；Intel 使用同一发布包中的
  `x86_64` 路径。安装器会把启动器瘦身为主机架构，避免 Steam 的旧 x86 偏好在
  无 Rosetta 的 Mac 上误选 Intel slice。
- 窗口、无边框和 macOS 原生 Space 全屏均支持 Retina 渲染。
- Retina backing 跟随 macOS HiDPI scale，最高使用完整 2×，不再受面板物理像素
  上限约束；1440×900 逻辑画布会使用 2880×1800 OpenGL backing，让文字与 UI
  保持清晰锐利。
- 普通窗口可在 4:3 到 21:9 内连续自由调整，不锁定单一比例；仅限制会破坏布局
  的极端比例和超过当前逻辑桌面的尺寸（当前配置最大 1440×900、最小
  800×450）。其他比例使用居中的安全 viewport，不拉伸 UI；输入保持 point-based
  同步映射，调整时不会重建 UI 或重新叠加菜单 BGM/环境音。
- 游戏“全屏”、“无边框全屏”和窗口绿色按钮使用一致的原生 Space 全屏行为。
- 自动查找默认 Steam 库及 `libraryfolders.vdf` 中的附加库。
- 安装前严格校验原版 jar SHA-256 与补丁 payload，备份原文件，失败自动回滚；
  重复运行完全相同的已安装 build 会完整复核 JAR/JRE/启动器/Info.plist 后返回
  成功；游戏启动后正常改写的显示偏好不会被误判为补丁损坏。

Release 只包含补丁文件及允许再分发的运行时，不包含 `desktop-1.0.jar`、游戏
App、存档、美术、音频或其他游戏本体内容。使用前必须已拥有并安装 Steam 版。

注意：当 macOS 桌面选择“看起来像 1440×900”时，WindowServer 自身仍使用
2880×1800 合成后缩放到 2560×1600 面板。补丁会有意使用完整 2× backing：游戏与
输入坐标保持 1440×900，OpenGL 与字体按 2880×1800 rasterize，最后的面板重采样
由 WindowServer 完成，与其他支持 Retina 的 App 一致。

## 安装

### PKG（推荐）

1. 从 [Releases](../../releases) 下载
   `SlayTheSpire-Modern-macOS-v1.2.2-universal.pkg` 和对应 `.sha256`。
2. 可选：校验下载文件：

   ```bash
   cd ~/Downloads
   shasum -a 256 -c SlayTheSpire-Modern-macOS-v1.2.2-universal.pkg.sha256
   ```

3. 打开安装包。PKG 会找到当前登录用户，并以该用户身份修改其 Steam 游戏目录，
   不会用 root 身份直接操作用户游戏文件。

当前安装包未使用 Developer ID 签名/公证。如被拦截，请进入“系统设置 → 隐私与
安全性”选择“仍要打开”；不要全局关闭 Gatekeeper。

已完整验证的 v1.2.1 可直接原地升级：安装器从保存的原版 jar 构造 v1.2.2，继续
保留原版备份；若升级失败则自动恢复可用的 v1.2.1。未知或被修改的旧 build 会在
零写入状态下拒绝，不会改动游戏。

### ZIP 回退包

下载、校验并解压 `SlayTheSpire-Modern-macOS-v1.2.2-universal.zip`，双击
`Install SlayTheSpire Modern macOS.command`，或在终端执行：

```bash
./install.sh
```

若 Steam 库位置特殊，可显式指定：

```bash
./install.sh "/Volumes/Games/SteamLibrary/steamapps/common/SlayTheSpire/SlayTheSpire.app"
```

建议先运行 `./install.sh --dry-run`。它会只读校验 Release payload、Steam 原版
jar、当前架构的 Zulu JRE，并在临时目录构造候选 jar，确认所有 macOS native 都
只含检测到的主机架构；不会修改游戏 App。

## Universal 实现

发布包内置同版本 Azul Zulu 8.96.0.205 的 arm64/x86_64 JRE，安装器依据
`uname -m` 选择原生运行时。
发布包中的启动器本身为 Universal，但安装到游戏 App 时会同样只保留当前主机
架构。这是因为该游戏的 Steam 旧启动元数据在同时看到 `x86_64` slice 时会优先
选择 Intel 路径，即使当前机器是 Apple Silicon。

新的全屏 Java 代码在两种架构都需要新增 JNI，因此 payload 会包含从同一开源源码
构建的 Universal `liblwjgl.dylib`。其余 native 为避免发布游戏原始二进制，只携带
补丁生成的 arm64 slice。原版 Steam jar 通过精确 SHA-256 白名单后，安装器会构造
只含主机架构的 jar：ARM 使用补丁 arm64 slice；Intel 使用用户原版中的 x86_64
libGDX/OpenAL/Steamworks 与补丁 LWJGL x86_64 slice。工具、新 JNI 或架构 slice
缺失都会在移动游戏文件前失败。Intel 路径会删除原版三个仅含 i386 的旧 libGDX
条目，只保留对应的 x86_64 `*64` 库；macOS 11+ 不会安装 32 位代码。

原版 jar 的 `libsteam_api.dylib` 只在用户本机提供当前主机 slice，不会被补丁发布。
迁移后的 arm64 bridge 会用独立的 arm-only 文件名加载与其 ABI 匹配的 API；Intel
使用原版 x86_64 代码。安装后的所有 macOS Mach-O native 都只保留检测到的处理器
架构，并在进入候选 jar 前重新 ad-hoc 签名和验证。

## 备份、回滚与卸载

安装器将原 JRE、jar、启动器与 `Info.plist` 保存在游戏旁的
`SlayTheSpire-Modern-backup`。候选 jar/JRE 完整构造并验证后才开始替换；替换后
若发生错误或收到退出信号，自动恢复原文件。

还原命令：

```bash
./uninstall.sh
```

卸载器恢复原文件并复核原 jar SHA-256，确认成功后才删除备份。Steam 的“验证
游戏文件完整性”也可作为额外恢复手段。

## 故障排查

保存 ZIP 安装日志：

```bash
./install.sh 2>&1 | tee ~/Desktop/SlayTheSpire-install.log
```

保存 PKG 相关日志：

```bash
grep 'sts-modern' /var/log/install.log > ~/Desktop/SlayTheSpire-pkg-install.log
```

- **原版 jar 不受支持或已修改：** 在 Steam 验证游戏文件。本项目不提供跳过校验
  的参数，避免把字节码补丁应用到未知版本。
- **发现旧 ARM64 备份：** 先用 v1.0.0 的 `uninstall.sh` 还原并确认原版能启动，
  再安装 v1.2.2。
- **Steam 显示 AppError 46 / Failed to spawn process：** v1.2.1 使用脚本作为
  App 主可执行文件，原生 Apple Silicon Steam 客户端无法创建该进程。安装
  v1.2.2 或更高版本即可，不需要为此安装 Rosetta。
- **提示游戏正在运行：** 完全退出游戏后重试。
- **直接启动崩溃在 `SteamAppsNative_getAppBuildId`：** Steamworks 未初始化，游戏
  随后解引用了空的 `SteamApps` 接口。运行验收应从 Steam 客户端启动；直接执行
  Java 或 Finder App 不能验证 Steam 集成。
- **未找到自定义库：** 按上例传入 `.app` 的完整路径。
- **崩溃报告：** 位于 `~/Library/Logs/DiagnosticReports/`。

## 构建与发布校验

维护者执行：

```bash
./scripts/prepare-zulu-jres.sh
./scripts/prepare-openal.sh
./scripts/prepare-patch-overlay.sh
./build.sh
```

Zulu 固定下载件 SHA-256：

| 架构 | SHA-256 |
| --- | --- |
| arm64 | `1769ea082fa13ba29403363425716451b04b10f5ae6dba07f7f0a69666197f15` |
| x86_64 | `b2a195c418fe926e5c2032bfd3fb23ed93b1133f50b99cb2c0e47dc618130e5d` |

`build.sh` 会运行启动器、安装状态与 PackageKit 状态回归测试，并拒绝缺少架构、
payload 校验失败、AppleDouble 元数据和明显游戏本体路径。发布前还应使用用户本机
已校验的原版备份运行：

```bash
./scripts/verify-with-original.sh \
  "/path/to/SlayTheSpire-Modern-backup" \
  "/path/to/SlayTheSpire-Modern-macOS-v1.2.1-universal.zip"
```

该门禁只在临时目录构造 ARM/Intel 候选与 v1.2.1 升级路径，不会把游戏本体加入
Release。构建会为 PKG/ZIP 生成 SHA-256；任何未通过门禁的产物都不应发布。

## 声明

本项目与 Mega Crit、Valve 无关。LWJGL、libGDX 等组件沿用各自上游许可证；Azul
Zulu OpenJDK 使用 GPLv2 + Classpath Exception，相关许可证随运行时一起提供。
