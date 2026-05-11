# NewType iOS SDK 对接指南

本文档详细说明如何将 NewType iOS SDK 集成到您的 iOS 项目中。

## 目录

- [环境要求](#环境要求)
- [SDK 获取](#sdk-获取)
- [集成方式](#集成方式)
  - [方式一：CocoaPods 集成（推荐）](#方式一-cocoapods-集成推荐)
  - [方式二：手动添加 XCFramework](#方式二手动添加-xcframework)
- [快速开始](#快速开始)
- [核心概念](#核心概念)
- [API 使用详解](#api-使用详解)
  - [1. 创建配置](#1-创建配置)
  - [2. 初始化客户端](#2-初始化客户端)
  - [3. 启动会话](#3-启动会话)
  - [4. VAD 控制](#4-vad-控制)
  - [5. 状态观察](#5-状态观察)
  - [6. 结束会话](#6-结束会话)
- [类型说明](#类型说明)
- [最佳实践](#最佳实践)
- [常见问题](#常见问题)

---

## 环境要求

| 项目 | 要求 |
|------|------|
| iOS 版本 | iOS 15.0+ |
| Swift 版本 | Swift 5.9+ |
| Xcode 版本 | Xcode 15.0+ |
| 架构支持 | arm64 (真机), x86_64/arm64 (模拟器) |

## SDK 获取

SDK 以 XCFramework 二进制文件形式提供，不包含源码。

### 方式一：从构建脚本生成

```bash
# 在 newtypesdk_ios 项目中
cd newtypesdk_ios/scripts
./build_xcframework.sh

# 生成的 XCFramework 位于
# newtypesdk_ios/dist/NewTypeSDK.xcframework
```

### 方式二：从 Artifact 仓库下载

从内部 artifact 仓库下载已编译的 `NewTypeSDK.xcframework` 文件。

## 集成方式

### 方式一：CocoaPods 集成（推荐）

#### 步骤 1：创建 Podspec

在项目的 `libs/` 目录下创建 `NewTypeSDK-Binary.podspec`：

```ruby
Pod::Spec.new do |s|
  s.name = "NewTypeSDK"
  s.version = "0.1.0"
  s.summary = "Type-safe iOS SDK for newtype realtime speaking sessions"
  s.description = <<-DESC
Binary iOS SDK wrapping newtype backend session APIs and LiveKit realtime room flow.
Provides session management, VAD control, and transcript streaming.
  DESC
  s.homepage = "https://github.com/squady/newtype"
  s.license = { :type => "MIT", :text => "Internal use only" }
  s.author = { "Squady" => "dev@squady.app" }
  s.platform = :ios, "15.0"
  s.swift_versions = ["5.9"]
  s.source = { :path => "." }
  s.vendored_frameworks = "NewTypeSDK.xcframework"
  s.frameworks = "Foundation", "AVFoundation"
  s.dependency "LiveKitClient"
  s.pod_target_xcconfig = {
    "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386",
    "DEFINES_MODULE" => "YES",
  }
end
```

#### 步骤 2：配置 Podfile

在项目根目录的 `Podfile` 中添加：

```ruby
source "https://cdn.cocoapods.org/"
source "https://github.com/livekit/podspecs.git"

platform :ios, "15.0"

use_frameworks! :linkage => :static

target "YourApp" do
  pod "NewTypeSDK", :path => "./libs/NewTypeSDK-Binary.podspec"
end
```

#### 步骤 3：安装依赖

```bash
pod install
```

#### 步骤 4：导入 SDK

在需要使用 SDK 的 Swift 文件中导入：

```swift
import NewTypeSDK
```

---

### 方式二：手动添加 XCFramework

#### 步骤 1：复制 XCFramework

将 `NewTypeSDK.xcframework` 复制到项目目录：

```bash
cp -r NewTypeSDK.xcframework /path/to/YourProject/Frameworks/
```

#### 步骤 2：添加 Framework 到 Xcode

1. 在 Xcode 中选择项目 Target
2. 进入 **General** → **Frameworks, Libraries, and Embedded Content**
3. 点击 **+** 按钮，选择 **Add Other...** → **Add Files...**
4. 选择 `NewTypeSDK.xcframework`

#### 步骤 3：配置 Embed

确保 Framework 的 Embed 设置为 **Embed & Sign**

---

## 快速开始

### 完整示例

```swift
import Foundation
import NewTypeSDK

class SessionManager: ObservableObject {
    private var client: NewTypeSessionClient?
    
    @Published var phase: SessionPhase = .idle
    @Published var transcript: [TranscriptEntry] = []
    @Published var summary: SessionSummary?
    
    func startSession() async throws {
        // 1. 创建配置
        let config = NewTypeConfig(
            backendBaseUrl: try EndpointUrl.parse("https://newtype.squady.app:11000"),
            liveKitUrlOverride: nil,
            tokenPath: "/api/livekit/token"
        )
        
        // 2. 创建客户端
        let client = NewTypeSessionClient.create(config: config)
        self.client = client
        
        // 3. 配置 VAD
        client.setVadMode(.fullAuto)
        client.setVadPreset(.natural)
        
        // 4. 绑定状态回调
        client.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.phase = state.phase
                self?.transcript = state.transcript
                self?.summary = state.summary
            }
        }
        
        // 5. 启动会话
        let result = try await client.startSession(
            StartSessionParams(
                childName: "Leo",
                age: "9",
                grade: "Grade 3",
                roomName: "speaking-demo",
                identity: "Leo"
            )
        )
    }
    
    func endSession() async throws {
        try await client?.endSession(reason: "user-leave")
    }
}
```

---

## 核心概念

### SessionPhase（会话阶段）

| 阶段 | 说明 |
|------|------|
| `.idle` | 空闲状态，未开始会话 |
| `.connecting` | 正在连接后端和房间 |
| `.connected` | 已连接，可以进行对话 |
| `.ending` | 正在结束会话 |
| `.ended` | 会话已结束 |

### ConnectionStatus（连接状态）

| 状态 | 说明 |
|------|------|
| `.idle` | 未开始连接 |
| `.connecting` | 正在连接 |
| `.connected` | 已连接 |
| `.disconnected` | 已断开 |

### AgentPhase（Agent 阶段）

| 阶段 | 说明 |
|------|------|
| `.waiting` | 等待 Agent 加入 |
| `.joining` | Agent 正在加入 |
| `.joined` | Agent 已加入房间 |
| `.leaving` | Agent 正在离开 |
| `.left` | Agent 已离开 |

### VadMode（语音检测模式）

| 模式 | 说明 | 使用场景 |
|------|------|----------|
| `.off` | PTT 模式，完全手动控制 | 需要精确控制录音时机 |
| `.semiAuto` | 半自动，VAD 检测但需确认 | 需要一定自动化但仍保留控制 |
| `.fullAuto` | 全自动，VAD 自动检测 | 儿童自由对话场景 |

### VADPreset（VAD 预设）

| 预设 | 说明 | 适用场景 |
|------|------|----------|
| `.sensitive` | 灵敏模式 | 安静环境，检测微弱声音 |
| `.natural` | 自然模式 | 一般环境，平衡参数 |
| `.child` | 儿童模式 | 针对儿童语音优化 |

---

## API 使用详解

### 1. 创建配置

```swift
let config = NewTypeConfig(
    backendBaseUrl: try EndpointUrl.parse("https://newtype.squady.app:11000"),
    liveKitUrlOverride: nil,  // 可选：覆盖 LiveKit URL
    tokenPath: "/api/livekit/token"
)
```

**参数说明：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `backendBaseUrl` | `EndpointUrl` | 是 | NewType 后端服务地址 |
| `liveKitUrlOverride` | `EndpointUrl?` | 否 | 覆盖 LiveKit WebSocket 地址 |
| `tokenPath` | `String` | 是 | 获取 LiveKit Token 的 API 路径 |

---

### 2. 初始化客户端

```swift
let client = NewTypeSessionClient.create(config: config)
```

**注意：** 客户端创建后需要尽快调用 `startSession`，避免资源闲置。

---

### 3. 启动会话

```swift
let result = try await client.startSession(
    StartSessionParams(
        childName: "Leo",           // 儿童姓名（必填）
        age: "9",                   // 年龄（可选）
        grade: "Grade 3",           // 年级（可选）
        roomName: "speaking-demo",  // 房间名（可选）
        identity: "Leo"             // 身份标识（可选，默认使用 childName）
    )
)
```

**参数说明：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `childName` | `String` | 是 | 儿童姓名，用于 AI 个性化交互 |
| `age` | `String?` | 否 | 年龄，帮助 AI 调整对话难度 |
| `grade` | `String?` | 否 | 年级，帮助 AI 调整对话内容 |
| `roomName` | `String?` | 否 | 房间名称，不填则自动生成 |
| `identity` | `String` | 否 | 身份标识，用于区分用户 |

---

### 4. VAD 控制

#### 设置 VAD 模式

```swift
// PTT 模式（手动控制）
client.setVadMode(.off)

// 半自动模式
client.setVadMode(.semiAuto)

// 全自动模式
client.setVadMode(.fullAuto)
```

#### 设置 VAD Preset

```swift
client.setVadPreset(.sensitive)  // 灵敏
client.setVadPreset(.natural)    // 自然
client.setVadPreset(.child)      // 儿童
```

#### 自定义 VAD 参数

```swift
client.setVadOptions(VADOptions(
    threshold: 0.5,      // 检测阈值 (0.0-1.0)
    minSpeechMs: 500,    // 最小说话时长 (毫秒)
    minSilenceMs: 300    // 最小静音时长 (毫秒)
))
```

#### PTT 模式控制

```swift
// 开始录音
try await client.startSpeaking()

// 停止录音
try await client.stopSpeaking()
```

---

### 5. 状态观察

#### 状态变化回调

```swift
client.onStateChanged = { state in
    print("会话阶段：\(state.phase)")
    print("连接状态：\(state.connectionStatus)")
    print("Agent 阶段：\(state.agentPhase)")
    print("参与者数量：\(state.participantCount)")
    print("转录文本：\(state.transcript)")
    print("会话总结：\(state.summary)")
}
```

#### 信号回调

```swift
client.onSignal = { signal in
    print("SDK 内部信号：\(signal)")
}
```

#### 错误回调

```swift
client.onError = { message in
    print("错误：\(message)")
}
```

---

### 6. 结束会话

```swift
try await client.endSession(reason: "user-leave")
```

**可选的 reason 值：**

| 原因 | 说明 |
|------|------|
| `"user-leave"` | 用户主动离开 |
| `"session-complete"` | 会话自然完成 |
| `"error"` | 因错误结束 |
| `"timeout"` | 超时结束 |

---

## 类型说明

### TranscriptEntry（转录条目）

```swift
struct TranscriptEntry {
    let speaker: SpeakerRole      // 说话者角色 (.ai 或 .child)
    let text: String              // 转录文本
    let meta: String?             // 元数据（可选）
    let streaming: Bool           // 是否流式传输中
}
```

### SessionSummary（会话总结）

```swift
struct SessionSummary {
    let summary: String           // 总体评价
    let didWell: String           // 做得好的地方
    let oneTip: String            // 改进建议
    let nextTopic: String         // 下一个话题建议
    let pronunciationFocus: String // 发音重点
}
```

### NewTypeClientState（客户端状态）

```swift
struct NewTypeClientState {
    let sessionId: String?
    let phase: SessionPhase
    let connectionStatus: ConnectionStatus
    let agentPhase: AgentPhase
    let agentMessage: String
    let participantCount: Int
    let micReady: Bool
    let recording: Bool
    let turnBusy: Bool
    let leaveRequested: Bool
    let transcript: [TranscriptEntry]
    let summary: SessionSummary?
    let errorMessage: String?
}
```

---

## 最佳实践

### 1. ViewModel 模式管理 SDK

使用 SwiftUI 的 `ObservableObject` 管理 SDK 状态：

```swift
@MainActor
final class SessionViewModel: ObservableObject {
    @Published var phase: SessionPhase = .idle
    @Published var transcript: [TranscriptEntry] = []
    
    private var client: NewTypeSessionClient?
    
    func join() async {
        // 创建和配置客户端
    }
    
    func leave() async {
        // 结束会话
    }
}
```

### 2. 在主线程更新 UI

SDK 回调可能不在主线程，使用 `Task { @MainActor in }` 确保 UI 更新：

```swift
client.onStateChanged = { [weak self] state in
    Task { @MainActor in
        self?.updateUI(state: state)
    }
}
```

### 3. 清理资源

在视图消失或对象销毁时关闭客户端：

```swift
deinit {
    client?.close()
}

func onDisappear() {
    if client != nil {
        Task {
            try? await client?.endSession(reason: "user-leave")
        }
    }
}
```

### 4. 错误处理

使用 do-catch 块处理异步错误：

```swift
do {
    try await client.startSession(params)
} catch {
    print("启动会话失败：\(error.localizedDescription)")
}
```

### 5. 日志记录

在生产环境中启用详细日志：

```swift
// 在应用启动时
NewTypeSDK.setLogLevel(.debug)
```

---

## 常见问题

### Q1: SDK 支持模拟器吗？

**A:** 支持。XCFramework 包含 arm64（真机）和 x86_64/arm64（模拟器）架构。

### Q2: 如何调试 SDK 问题？

**A:** 启用 SDK 日志并查看控制台输出：
```swift
// 查看 [MainActivity] 前缀的日志
```

### Q3: VAD 不灵敏怎么办？

**A:** 尝试以下方法：
1. 切换到 `.sensitive` preset
2. 降低 threshold 值
3. 减少 minSpeechMs 时长

### Q4: 如何确认 Agent 已入房？

**A:** 观察 `state.participantCount > 1` 或 `state.agentPhase == .joined`

### Q5: Transcript 为空怎么办？

**A:** 检查：
1. 麦克风权限是否已授权
2. `state.micReady` 是否为 true
3. 网络连接是否正常

### Q6: 如何切换后端环境？

**A:** 修改 `NewTypeConfig` 的 `backendBaseUrl`：
```swift
// 开发环境
let config = NewTypeConfig(
    backendBaseUrl: try EndpointUrl.parse("https://dev.newtype.squady.app:11000"),
    ...
)

// 生产环境
let config = NewTypeConfig(
    backendBaseUrl: try EndpointUrl.parse("https://newtype.squady.app:11000"),
    ...
)
```

---

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1.0 | 2025-05 | 初始版本，包含核心会话管理和 VAD 控制 |

---

## 联系支持

如有问题，请联系：dev@squady.app
