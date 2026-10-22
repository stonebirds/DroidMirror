# DroidMirror SwiftUI 实施方案

## 1. 项目目标

DroidMirror 定位为原生 macOS Android 镜像与控制工具，基于 SwiftUI 构建，
同时兼容 Apple Silicon 和 Intel Mac。

目标功能：

- USB 连接 Android 手机
- 无线连接 Android 手机
- USB 一键切换为无线连接，不要求开启 Android“无线调试”
- 内置 adb，同时允许用户选择自定义 adb
- 镜像画面可在应用内显示
- 支持内嵌、独立悬浮窗口和全屏三种显示模式
- 支持鼠标点击、拖动、滚动和键盘输入
- 支持返回、桌面、最近任务、锁屏和唤醒等快捷控制
- 支持 H.264 和 H.265，并在不兼容时自动回退
- 支持手机音频、录屏和常用画质设置
- 保留外部 scrcpy 窗口作为兼容模式

本方案仅针对 macOS。SwiftUI 不能直接构建 Windows 应用，当前不引入
Flutter、KMP 或其他跨平台框架。

## 2. 实施状态

本文档中的主体方案已在 DroidMirror 2.0.0 实现：

- 原生 SwiftUI macOS 主界面
- 自动检测 USB 和无线设备
- 内置 Universal adb 37.0.1
- 支持选择并记住自定义 adb 路径
- 分别内置 arm64 和 x86_64 scrcpy 5.0.1
- 应用内 scrcpy 5.0.1 视频、音频与控制协议
- H.264/H.265 系统解码和 H.264 自动回退
- 内嵌、悬浮、全屏无断流切换
- 鼠标、滚轮、键盘和双向剪贴板
- USB 一键转无线与关闭无线 ADB
- 断线自动重连、截图和诊断导出
- 外部 scrcpy 兼容与 MP4 录制模式
- 分辨率、码率、帧率和音频设置
- 关闭手机屏幕和保持唤醒
- 返回、桌面、最近任务、音量、旋转、锁屏和唤醒按钮
- Universal 2 应用，支持 Apple Silicon 和 Intel

MP4 录制当前自动使用外部 scrcpy 兼容模式，以复用其成熟的音视频封装和同步能力。
正式公开发行所需的 Developer ID 签名与 Apple notarization 尚未配置。

## 3. 总体架构

应用分为五层：

```text
SwiftUI 界面
    |
AppModel / MirrorSession
    |
+----------------------+----------------------+
| 设备与连接           | 镜像与控制           |
| DeviceService        | EmbeddedSession      |
| ADBService           | ExternalSession      |
+----------------------+----------------------+
    |
内置或自定义 adb + scrcpy Android server
    |
Android 手机
```

核心抽象：

```swift
protocol MirrorSession: AnyObject {
    var state: MirrorSessionState { get }
    func start(device: AndroidDevice, settings: MirrorSettings) async throws
    func stop() async
    func send(_ controlEvent: AndroidControlEvent) async throws
}
```

实现两种会话：

- `EmbeddedScrcpySession`：应用内解码、渲染和控制
- `ExternalScrcpySession`：启动官方 scrcpy，作为兼容和故障回退模式

## 4. 建议模块

```text
Sources/DroidMirror/
├── App/
│   ├── DroidMirrorApp.swift
│   └── AppModel.swift
├── Device/
│   ├── AndroidDevice.swift
│   ├── ADBService.swift
│   └── DeviceDiscoveryService.swift
├── Connection/
│   ├── USBConnectionService.swift
│   └── WirelessConnectionService.swift
├── Mirror/
│   ├── MirrorSession.swift
│   ├── ExternalScrcpySession.swift
│   └── EmbeddedScrcpySession.swift
├── Media/
│   ├── ScrcpyVideoStream.swift
│   ├── VideoDecoder.swift
│   ├── VideoRenderer.swift
│   └── AudioPlayer.swift
├── Control/
│   ├── ScrcpyControlChannel.swift
│   └── InputEventMapper.swift
└── UI/
    ├── ContentView.swift
    ├── MirrorView.swift
    ├── MirrorToolbar.swift
    └── FloatingMirrorWindow.swift
```

## 5. 内嵌镜像实现

不能直接把 scrcpy 已创建的外部窗口稳定地嵌入 SwiftUI。正确方案是使用
scrcpy Android server 建立视频、音频和控制通道，由 DroidMirror 自己完成
解码、渲染和输入转发。

数据流程：

```text
Android 屏幕
  -> scrcpy server
  -> ADB socket tunnel
  -> H.264/H.265 packet parser
  -> VideoToolbox
  -> CVPixelBuffer
  -> Metal / AVSampleBufferDisplayLayer
  -> SwiftUI NSViewRepresentable
```

推荐使用 `NSViewRepresentable` 包装原生渲染视图。优先使用 Metal 渲染，
保留 `AVSampleBufferDisplayLayer` 作为较简单的首期实现。

应用只维持一个镜像会话。切换内嵌、悬浮或全屏模式时更换显示容器，
不重新连接手机。

## 6. H.264、H.265 与音频

H.264 和 H.265 均使用 macOS 自带 VideoToolbox，不需要引入 FFmpeg、
VLC 或第三方解码库，因此不会明显增加安装包体积。

策略：

1. 默认使用 H.264，获得最广泛兼容性。
2. 用户选择 H.265 时先检查手机编码能力和 Mac 解码能力。
3. H.265 初始化失败时自动回退 H.264，并在界面显示一次提示。
4. 解码失败达到阈值后重建解码会话，避免画面永久卡住。

音频让 scrcpy server 输出 48 kHz 双声道 PCM，再使用 AVAudioEngine 播放。
这样不需要额外音频解码器，也避免引入大型媒体依赖。

## 7. 三种显示模式

### 内嵌模式

镜像画面显示在 DroidMirror 主窗口中，顶部显示设备和连接状态，底部提供
必要的控制按钮。

### 悬浮模式

使用 `NSPanel` 承载镜像视图：

- 始终置顶
- 可以拖动和调整大小
- 可加入所有 Space
- 支持全屏应用上方显示
- 可调节透明度

### 全屏模式

将镜像视图放入独立 `NSWindow`，调用 macOS 原生全屏能力。退出全屏后回到
进入全屏前的内嵌或悬浮模式。

## 8. 输入与导航

鼠标和键盘事件通过 scrcpy 控制通道发送到手机：

- 单击：触摸按下和抬起
- 拖动：连续触摸移动
- 滚轮：Android 滚动事件
- 键盘：Android 按键或文本输入
- 剪贴板：Mac 与 Android 双向同步

工具栏建议提供：

- 返回
- 桌面
- 最近任务
- 电源/锁屏
- 唤醒
- 音量加减
- 旋转屏幕
- 关闭手机屏幕
- 截图
- 开始/停止录制
- 内嵌、悬浮、全屏切换

锁屏后可发送电源键或唤醒事件点亮屏幕，但不能绕过 Android 的 PIN、
图案、密码或生物识别，这是 Android 安全边界。

## 9. USB 一键转无线

该模式不要求开启 Android 11 的“无线调试”，但首次仍必须：

- 开启开发者选项
- 开启 USB 调试
- 通过 USB 连接并在手机上确认授权

流程：

```text
选择 USB 设备
  -> adb -s SERIAL tcpip 5555
  -> 读取手机 WLAN IP
  -> adb connect IP:5555
  -> 验证无线设备在线
  -> 可提示用户拔掉 USB
```

限制：

- 手机重启后通常需要重新通过 USB 开启 TCP 模式
- 手机与 Mac 必须位于可互访的同一网络
- 企业 Wi-Fi 或访客网络可能禁止设备间通信
- TCP 5555 安全性低于 Android 官方无线调试，连接结束时应提供关闭入口

关闭无线 ADB：

```text
adb -s DEVICE usb
```

界面应明确区分“无线调试配对”和“USB 转无线”两种连接方式。

## 10. adb 路径策略

查找优先级：

1. 用户选择的 adb
2. 应用内置 adb
3. `~/Library/Android/sdk/platform-tools/adb`
4. Homebrew 和系统 PATH

自定义 adb 不存在、不可执行或版本过低时，自动回退到内置 adb，并向用户
显示具体原因。

内置 adb 对 DMG 的体积影响较小。当前完整 DMG 约 37 MB，安装后的应用
约 79 MB，主要空间仍由两套 scrcpy 运行文件占用。

## 11. 状态与错误处理

建议使用明确的状态机：

```swift
enum MirrorSessionState {
    case idle
    case preparing
    case connecting
    case streaming
    case reconnecting
    case stopping
    case failed(String)
}
```

体验优化：

- USB 插拔后自动刷新
- 设备断开时短暂等待并尝试恢复
- 应用启动时恢复上一次画质和显示模式
- 明确显示 USB、无线、未授权、离线状态
- 错误提示附带可执行操作
- 收集 adb、server、解码器日志，支持一键导出诊断包
- 应用退出或崩溃后清理残留 server 和 socket

## 12. 依赖、体积与构建

继续使用系统框架：

- SwiftUI
- AppKit
- VideoToolbox
- CoreMedia
- CoreVideo
- Metal
- AVFoundation / AudioToolbox
- Network

不引入大型第三方 UI 或媒体框架。开发环境继续使用 Apple Command Line
Tools，不强制安装完整 Xcode。

发布包继续构建 Universal 2：

- Swift 主程序：arm64 + x86_64
- adb：Universal 2
- scrcpy 兼容模式：分别内置 arm64 和 x86_64

正式对外分发还需要 Developer ID 签名、Hardened Runtime 和 Apple
Notarization。

## 13. 实施记录

### 阶段一：架构整理（已完成）

- 引入 `MirrorSession`
- 将当前逻辑迁移为 `ExternalScrcpySession`
- 建立统一状态机和错误模型
- 保持现有行为不变

原计划估算：2～3 个工作日。

### 阶段二：USB 一键转无线（已完成）

- 实现 TCP 模式开启、IP 检测和自动连接
- 增加关闭无线 ADB
- 增加安全提示和网络错误诊断

原计划估算：1～2 个工作日。

### 阶段三：内嵌 H.264 视频（已完成）

- 启动 scrcpy server
- 实现 socket 和视频包解析
- 接入 VideoToolbox
- 在 SwiftUI 中显示 Metal/原生视频视图
- 实现触摸和键盘控制

原计划估算：7～10 个工作日。

### 阶段四：模式切换、H.265 和音频（已完成）

- 内嵌、悬浮、全屏无断流切换
- H.265 能力检测和 H.264 自动回退
- PCM 音频播放
- 截图和录制

原计划估算：5～8 个工作日。

### 阶段五：稳定性与发布（部分完成）

- 多品牌手机兼容测试
- USB 插拔、休眠和网络切换恢复
- 性能、功耗和内存优化
- 签名、公证、升级和诊断能力

代码签名验证、Universal 2 构建、DMG 校验和协议真机测试已经完成。Developer ID、
notarization、更多品牌设备的长期稳定性验证仍属于正式公开发布工作。

## 14. 验收标准

- Apple Silicon 和 Intel Mac 均能安装和启动
- USB 授权后可以在应用内看到并控制手机
- 内嵌、悬浮和全屏切换不会断开设备
- H.265 不可用时自动回退 H.264
- USB 转无线流程无需开启 Android“无线调试”
- 手机重启、USB 拔出、Wi-Fi 切换时有明确状态反馈
- 外部 scrcpy 兼容模式始终可用
- 1080p/60 FPS 下交互流畅，无持续增长的内存占用
- 安装包不依赖 Android Studio、完整 Xcode、Homebrew 或外部 adb

## 15. 实际实施顺序

本次先完成 `MirrorSession` 架构和 USB 一键转无线，再实现 H.264 内嵌视频，最后增加
H.265、音频和多窗口模式。

外部 scrcpy 模式被保留为兼容和 MP4 录制方案，确保用户始终有可工作的回退路径。
