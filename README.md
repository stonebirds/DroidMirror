# DroidMirror

DroidMirror 是一个基于 [scrcpy](https://github.com/Genymobile/scrcpy) 的原生 macOS
Android 镜像启动器。连接手机后，可以在 Mac 上低延迟查看并控制 Android 设备。

## 下载

当前版本：**1.2.0**

[下载 DroidMirror 1.2.0 Universal DMG](releases/DroidMirror-1.2.0-universal.dmg)

- 支持 Apple Silicon 与 Intel Mac
- 最低系统版本：macOS 13
- DMG 大小：约 37 MB
- SHA-256：`cb7c65214ca8178adc7c80c9958ebe795a696cd399af7e0a8c35168c91ba32b1`

该安装包使用临时签名，尚未经过 Apple notarization。首次打开时，请右键点击
`DroidMirror.app` 并选择“打开”；也可以在“系统设置 > 隐私与安全性”中允许打开。

## 功能

- 自动检测 USB 和已配对的无线 Android 设备
- 一键启动、停止低延迟手机镜像
- 内置 Universal `adb 37.0.1`
- 内置 Apple Silicon 与 Intel 两套 `scrcpy 5.0.1`
- 支持手动选择其他 adb 路径，并记住用户选择
- 可调最大分辨率、视频码率、最大帧率与音频
- 支持镜像时关闭手机屏幕、保持手机唤醒
- 支持同步录制 MP4
- 提供返回、桌面、最近任务悬浮控制条
- 主窗口同步提供导航按钮，作为悬浮控制条的备用入口

## 安装与连接

1. 下载并打开 DMG。
2. 将 `DroidMirror.app` 拖入“应用程序”文件夹。
3. 在 Android 手机上开启“开发者选项”和“USB 调试”。
4. 使用支持数据传输的 USB 线连接手机与 Mac。
5. 解锁手机并允许这台 Mac 进行 USB 调试。
6. 在 DroidMirror 中选择设备，点击“开始镜像”。

Android 的首次调试授权必须在手机上确认，这是系统安全限制。确认一次后，后续 USB
连接通常只需在 DroidMirror 中点击一次即可启动镜像。

## 导航控制

镜像启动后，DroidMirror 会显示一个可拖动、始终置顶的控制条：

- 返回
- 返回桌面
- 最近任务

同样的三个按钮也会出现在 DroidMirror 主窗口底部。停止镜像后，悬浮控制条会自动关闭。

## adb 路径

安装包已经内置 adb，不需要安装 Android Studio 或 Android Platform Tools。若需要使用
其他 adb，可点击侧栏 adb 状态旁的文件夹按钮选择可执行文件。自选路径优先于内置 adb；
如果该文件失效，应用会自动回退到内置版本。

## 无线连接

手机与 Mac 需要处于同一网络，并提前完成 Android“无线调试”配对。在 DroidMirror 中
点击工具栏的 Wi-Fi 按钮，输入无线调试页面显示的 `IP:端口` 即可连接。

## 从源码构建

要求：

- macOS 13 或更高版本
- Apple Command Line Tools，Swift 5.8 或更高版本
- 制作安装包时可以访问 GitHub 与 Google 官方下载地址

不需要安装完整 Xcode。生成全内置 Universal App 和 DMG：

```bash
./scripts/package_app.sh
```

若目标电脑已经安装 scrcpy，可以生成不内置 scrcpy 的较小版本：

```bash
./scripts/package_app.sh --system-scrcpy
```

构建结果位于 `dist/`。脚本会校验官方 Platform Tools 和 scrcpy 下载文件的 SHA-256，
并同时编译 `arm64`、`x86_64` 两个应用切片。

标准 Swift Package 环境也可以运行：

```bash
swift run DroidMirror
swift test
```

## 分发说明

仓库中的 DMG 使用 ad-hoc 签名，适合内部测试和直接分发。正式公开发行建议配置 Apple
Developer ID、Hardened Runtime 和 Apple notarization。

## 第三方组件

DroidMirror 是独立图形启动器，与 Genymobile 无隶属或背书关系。安装包包含：

- scrcpy，Apache License 2.0
- Android SDK Platform Tools 中的 adb，遵循 Android SDK 条款

完整说明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)，官方 Platform Tools
`NOTICE.txt` 也随应用一并提供。
