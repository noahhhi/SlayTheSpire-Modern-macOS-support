# 《杀戮尖塔》现代 macOS 适配补丁

[English](README.md)

这是面向 Steam macOS 版《杀戮尖塔》的社区兼容补丁。v1.1.0 使用同一份
Universal 发布包支持 Intel 与 Apple Silicon Mac，最低系统为 macOS 11。

## 功能

- 内置 `x86_64` 与 `arm64` 两套 Azul Zulu OpenJDK 8 原生运行时。
- 窗口、无边框和 macOS 原生 Space 全屏均支持 Retina 渲染。
- 窗口可自由缩放；输入保持逻辑点坐标，OpenGL viewport 与字体按物理像素渲染，
  4:3 到 21:9 之间可连续自由调整，仅拦截会破坏布局的极窄/极宽比例（最小
  800×450）；调整时不会重建 UI，也不会重新叠加菜单 BGM/环境音。
- 游戏“全屏”、“无边框全屏”和窗口绿色按钮使用一致的原生 Space 全屏行为。
- 自动查找默认 Steam 库及 `libraryfolders.vdf` 中的附加库。
- 安装前严格校验原版 jar SHA-256 与补丁 payload，备份原文件，失败自动回滚。

Release 只包含补丁文件及允许再分发的运行时，不包含 `desktop-1.0.jar`、游戏
App、存档、美术、音频或其他游戏本体内容。使用前必须已拥有并安装 Steam 版。

## 安装

### PKG（推荐）

1. 从 [Releases](../../releases) 下载
   `SlayTheSpire-Modern-macOS-v1.1.0-universal.pkg` 和对应 `.sha256`。
2. 可选：校验下载文件：

   ```bash
   cd ~/Downloads
   shasum -a 256 -c SlayTheSpire-Modern-macOS-v1.1.0-universal.pkg.sha256
   ```

3. 打开安装包。PKG 会找到当前登录用户，并以该用户身份修改其 Steam 游戏目录，
   不会用 root 身份直接操作用户游戏文件。

当前安装包未使用 Developer ID 签名/公证。如被拦截，请进入“系统设置 → 隐私与
安全性”选择“仍要打开”；不要全局关闭 Gatekeeper。

### ZIP 回退包

下载、校验并解压 `SlayTheSpire-Modern-macOS-v1.1.0-universal.zip`，双击
`Install SlayTheSpire Modern macOS.command`，或在终端执行：

```bash
./install.sh
```

若 Steam 库位置特殊，可显式指定：

```bash
./install.sh "/Volumes/Games/SteamLibrary/steamapps/common/SlayTheSpire/SlayTheSpire.app"
```

建议先运行 `./install.sh --dry-run`。它会只读校验 Release payload、Steam 原版
jar、当前架构的 Zulu JRE，并在临时目录构造候选 jar 和 Universal natives；不会
修改游戏 App。

## Universal 实现

发布包内置同版本 Azul Zulu 8.96.0.205 的 arm64/x86_64 JRE，安装器依据
`uname -m` 选择原生运行时。

新的全屏 Java 代码在两种架构都需要新增 JNI，因此 payload 会包含从同一开源源码
构建的 Universal `liblwjgl.dylib`。其余 native 为避免发布游戏原始二进制，只携带
补丁生成的 arm64 slice。原版 Steam jar 通过精确 SHA-256 白名单后，安装器才会从
用户自己的 jar 提取 x86_64 libGDX/OpenAL/Steamworks slice，并用系统
`/usr/bin/lipo` 在临时目录合成 Universal dylib；绝不会拿未修改的原版 LWJGL x86
slice 代替新 JNI。工具、新 JNI 或架构 slice 缺失都会在移动游戏文件前失败。

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
  再安装 v1.1.0。
- **提示游戏正在运行：** 完全退出游戏后重试。
- **未找到自定义库：** 按上例传入 `.app` 的完整路径。
- **崩溃报告：** 位于 `~/Library/Logs/DiagnosticReports/`。

## 构建与发布校验

维护者执行：

```bash
./scripts/prepare-zulu-jres.sh
./scripts/prepare-patch-overlay.sh
./build.sh
```

Zulu 固定下载件 SHA-256：

| 架构 | SHA-256 |
| --- | --- |
| arm64 | `1769ea082fa13ba29403363425716451b04b10f5ae6dba07f7f0a69666197f15` |
| x86_64 | `b2a195c418fe926e5c2032bfd3fb23ed93b1133f50b99cb2c0e47dc618130e5d` |

`build.sh` 会拒绝缺少架构、payload 校验失败、AppleDouble 元数据和明显游戏本体
路径，并为 PKG/ZIP 生成 SHA-256 文件。正式资产应在干净 checkout 构建；任何
未通过门禁的产物都不应发布。

## 声明

本项目与 Mega Crit、Valve 无关。LWJGL、libGDX 等组件沿用各自上游许可证；Azul
Zulu OpenJDK 使用 GPLv2 + Classpath Exception，相关许可证随运行时一起提供。
