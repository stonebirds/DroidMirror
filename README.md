# DroidMirror

DroidMirror 是一个基于 [scrcpy](https://github.com/Genymobile/scrcpy) server 的
原生 macOS Android 镜像与控制应用。手机画面可以直接显示在 DroidMirror 中，
也可以切换到悬浮窗口或全屏。

## 下载

当前版本：**2.1.3**

[下载 DroidMirror 2.1.3 Universal PKG（推荐，自动安装到“应用程序”）](releases/DroidMirror-2.1.3-universal.pkg)

[下载 DroidMirror 2.1.3 Universal DMG（手动拖拽安装）](releases/DroidMirror-2.1.3-universal.dmg)

- 支持 Apple Silicon 与 Intel Mac
- 最低系统版本：macOS 13
- PKG 大小：约 34 MB
- DMG 大小：约 38 MB
- 安装后大小：约 81 MB
- PKG SHA-256：`4fd5aec589678bfb803283e14aa7e73231c906959c5f529a1138caf0d72de040`
- DMG SHA-256：`6a7cc45c07e19f958591c1279089f4a212ba1ed684c399f27a3700df31ae9706`

Finder 会为 `.pkg` 文件统一显示 macOS Installer 的系统纸箱图标，这是正常的文件类型图标。
安装完成后，“应用程序”中的 `DroidMirror.app` 以及 DMG 内的应用使用 DroidMirror 自有图标。

应用使用 ad-hoc 签名，安装包尚未经过 Apple notarization。首次安装或打开时，请右键点击
PKG 或 `DroidMirror.app` 并选择“打开”；也可以在“系统设置 > 隐私与安全性”中允许打开。

## 功能

- 应用内低延迟 Android 镜像与控制
- 内嵌、始终置顶悬浮窗、全屏三种显示模式
- 模式切换时保持同一镜像会话，不重新连接手机
- 镜像控制栏跟随独立窗口，并支持随时显示或隐藏
- 鼠标点击、拖动和滚轮映射为 Android 触摸事件
- 键盘输入与 Mac 剪贴板粘贴
- Android 剪贴板自动同步到 Mac
- 返回、桌面、最近任务、音量、旋转、锁屏和唤醒控制
- H.264 与 H.265，H.265 不可用时自动回退 H.264
- 使用 macOS 系统视频解码，不依赖 FFmpeg 或 VLC
- Android 音频传输（Android 11 或更高版本）
- 截图、MP4 录制、分辨率、码率和帧率设置
- 选择或拖放 APK 安装到手机
- USB 与无线设备自动检测
- 保存最近连接设备，无线历史地址支持一键重连
- USB 一键转无线，无需开启 Android“无线调试”开关
- 连接中断后自动尝试恢复
- 内置 Universal adb 37.0.1
- 支持选择并记住自定义 adb 路径
- 保留官方 scrcpy 独立窗口兼容模式
- 查看、复制和清理本地运行日志
- 一键导出诊断信息和最近一次 macOS 崩溃报告
- 提供 PKG 安装器，确认后自动安装到“应用程序”

## 安装与 USB 连接

1. 下载 PKG，右键点击并选择“打开”。
2. 在 macOS Installer 中确认安装，应用会自动放入“应用程序”文件夹。
3. 在 Android 手机上开启“开发者选项”和“USB 调试”。
4. 使用支持数据传输的 USB 线连接手机与 Mac。
5. 解锁手机并允许这台 Mac 进行 USB 调试。
6. 选择设备和镜像设置，点击“开始镜像”。

DMG 仍作为备用安装方式提供；使用 DMG 时需要手动将 `DroidMirror.app` 拖入“应用程序”。

Android 的首次调试授权必须在手机上确认，这是系统安全限制。DroidMirror 无法绕过
PIN、图案、密码或生物识别锁屏。

## 镜像模式

### 应用内镜像

这是默认模式。DroidMirror 直接连接 scrcpy Android server，使用
`AVSampleBufferDisplayLayer` 和 macOS 系统媒体框架显示 H.264/H.265 视频。

### 悬浮模式

镜像显示在可调整大小、始终置顶的窗口中，并可以显示在其他 Space 和全屏应用上方。

### 全屏模式

镜像进入 macOS 原生全屏窗口。退出后可以回到内嵌或悬浮模式。

### 兼容模式

若特定设备与内嵌模式不兼容，可以选择“兼容模式”，由官方 scrcpy 客户端创建独立窗口。
录制 MP4 时当前版本会自动使用兼容模式，以保证音视频封装和同步稳定。

## APK 安装

选择一台已连接设备后，点击设备标题右侧的“安装 APK”，或直接将 `.apk` 文件从 Finder
拖到设备详情区域。应用会先打开确认窗口，可在窗口内选择路径、重新选择或拖入 APK；只有
点击“确认安装”后才会执行。DroidMirror 使用 `adb install -r` 安装，可以覆盖升级已存在的应用。

## 设备历史与诊断

已授权连接过的设备会保存在侧栏“最近连接”中。无线设备断开后可以点击历史记录重新连接；
USB 设备会保留名称和最后连接时间，重新插线后自动恢复为在线设备。

工具栏“运行日志”可以查看、复制或清空最近日志。“导出诊断”生成单个文本文件，包含
应用设置、adb 状态、设备列表、运行日志和最近一份 DroidMirror 系统崩溃报告。日志文件
限制在约 2 MB，避免长期使用造成磁盘占用持续增长。

## 无线连接

DroidMirror 提供两种无线连接方式。

### USB 转无线

不需要开启 Android 11 的“无线调试”开关：

1. 先通过 USB 连接并完成 USB 调试授权。
2. 点击工具栏 Wi-Fi 按钮。
3. 选择“USB 转无线”，点击“启用并连接”。
4. 连接成功后可以拔掉 USB 线。

手机重启后通常需要重新执行一次。手机与 Mac 必须处于可以互相访问的同一网络。
企业 Wi-Fi、访客网络或 AP 隔离可能阻止连接。界面中可以随时关闭无线 ADB。

### 输入地址

如果手机已经通过 Android“无线调试”完成配对，选择“输入地址”，填写无线调试页面
显示的 `IP:端口`。

## adb 路径

安装包已内置 adb，不需要安装 Android Studio 或 Android Platform Tools。点击侧栏 adb
状态旁的文件夹按钮可以选择其他 adb。查找顺序如下：

1. `DROIDMIRROR_ADB_PATH` 环境变量
2. 用户选择的 adb
3. 应用内置 adb
4. `~/Library/Android/sdk/platform-tools/adb`
5. Homebrew 与系统 PATH

自定义文件失效时，应用会自动回退到内置版本。

## 编解码与依赖

内嵌模式的视频由 macOS 自带的 AVFoundation、CoreMedia 和 VideoToolbox 处理；音频使用
AVFoundation 播放 48 kHz 双声道 PCM。H.264、H.265 和音频不会引入额外第三方依赖。

安装包内的两套 scrcpy 运行文件用于 Intel/Apple Silicon 兼容模式，也是安装包体积的主要
部分。内置 adb 只增加少量体积。

## 从源码构建

要求：

- macOS 13 或更高版本
- Apple Command Line Tools，Swift 5.8 或更高版本
- 制作安装包时可以访问 GitHub 与 Google 官方下载地址

不需要安装完整 Xcode。生成内置依赖的 Universal 2 App 和 DMG：

```bash
./scripts/package_app.sh
```

若目标电脑已经安装 scrcpy，可以生成不内置 scrcpy 的较小版本：

```bash
./scripts/package_app.sh --system-scrcpy
```

构建结果位于 `dist/`。脚本校验 Platform Tools 和 scrcpy 官方归档的 SHA-256，分别编译
`arm64` 与 `x86_64`，再使用 `lipo` 合并应用主程序。

标准 Swift Package 环境也可以运行：

```bash
swift run DroidMirror
swift test
```

完整架构与协议说明见
[`docs/SWIFTUI_IMPLEMENTATION_PLAN.md`](docs/SWIFTUI_IMPLEMENTATION_PLAN.md)。

## 分发说明

仓库中的 DMG 使用 ad-hoc 签名，适合内部测试和直接分发。正式公开发行建议配置 Apple
Developer ID、Hardened Runtime 和 Apple notarization。

## 第三方组件

DroidMirror 是独立图形客户端，与 Genymobile 无隶属或背书关系。安装包包含：

- scrcpy，Apache License 2.0
- Android SDK Platform Tools 中的 adb，遵循 Android SDK 条款

完整说明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)，官方 Platform Tools
`NOTICE.txt` 也随应用一并提供。
