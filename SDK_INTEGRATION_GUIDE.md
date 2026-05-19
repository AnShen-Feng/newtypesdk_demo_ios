# NewType iOS SDK 接入指引

## 简介

NewType iOS SDK 用于在 iOS 应用中接入儿童英语口语陪练会话。SDK 负责登录客户后端、创建会话、获取媒体房间入房凭证、连接房间、管理麦克风与 VAD，并通过状态回调输出转录、AI 回复、会话总结和错误事件。

当前推荐链路：

```text
iOS App -> 客户后端 / customer-backend-demo -> NewType backend -> 媒体服务器
```

iOS 端不要直连 NewType backend，也不要在 App 内硬编码媒体服务器 URL。媒体服务器 URL 和 token 由客户后端按 session 下发。

## 环境要求

| 项目 | 要求 |
|------|------|
| iOS 版本 | iOS 13.4+ |
| Swift | Swift 5.9+ |
| Xcode | Xcode 15.0+ |
| 架构支持 | arm64 真机，arm64 / x86_64 模拟器 |
| 依赖管理 | CocoaPods 1.16+（推荐） |

必需权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>用于英语口语陪练时采集孩子的语音。</string>
```

如果客户后端使用局域网 HTTP，例如 `http://192.168.0.12:8090`，宿主 App 需要在 `Info.plist` 中允许对应域名或临时允许明文流量：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

生产环境建议只对指定域名配置 `NSExceptionDomains`，不要全局打开 `NSAllowsArbitraryLoads`。

CocoaPods 依赖：

```ruby
source "https://cdn.cocoapods.org/"
source "https://github.com/livekit/podspecs.git"

platform :ios, "13.4"

use_frameworks! :linkage => :static

target "YourApp" do
  pod "NewTypeSDK", :path => "./libs/NewTypeSDK-Binary.podspec"
end
```

`libs/NewTypeSDK-Binary.podspec` 推荐配置：

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
  s.platform = :ios, "13.4"
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

## SDK 获取和安装

### 方式一：CocoaPods 集成（推荐）

1. 将 `NewTypeSDK.xcframework` 和 `NewTypeSDK-Binary.podspec` 放到宿主工程的 `libs/` 目录。
2. 在 `Podfile` 中添加 `pod "NewTypeSDK", :path => "./libs/NewTypeSDK-Binary.podspec"`。
3. 执行 `pod install`。
4. 使用 `.xcworkspace` 打开工程。
5. 在业务代码中 `import NewTypeSDK`。

本 demo 已完成上述配置，直接执行：

```bash
cd newtypesdk_demo_ios
pod install
open newtypesdk_demo_ios.xcworkspace
```

### 方式二：手动添加 XCFramework

1. 将 `NewTypeSDK.xcframework` 复制到宿主工程目录，例如 `Frameworks/`。
2. 在 Xcode 中选择 App Target。
3. 进入 **General** -> **Frameworks, Libraries, and Embedded Content**。
4. 点击 **+**，选择 `NewTypeSDK.xcframework`。
5. 将 Embed 设置为 **Embed & Sign**。
6. 额外确保 `LiveKitClient` 及其依赖已通过 CocoaPods / SPM / 手动方式集成。

除非有特殊发布要求，否则推荐使用 CocoaPods，避免遗漏 LiveKit 相关依赖。

## 快速开始

```swift
import NewTypeSDK

@MainActor
final class SessionManager: ObservableObject {
    private var client: NewTypeSessionClient?

    @Published var state: NewTypeClientState?
    @Published var lastError: String?

    func start() async throws {
        let endpoint = try EndpointUrl.parse("http://192.168.0.12:8090")
        let config = NewTypeConfig(
            backendBaseUrl: endpoint,
            sessionPath: "/app/sessions",
            tokenPath: "/app/sessions/{sessionId}/livekit-token",
            liveKitTokenMode: .userTokenInBody
        )

        let client = NewTypeSessionClient.create(config: config)
        self.client = client

        let stateHandler: NewTypeSessionClient.StateHandler = { [weak self] state in
            Task { @MainActor in
                self?.state = state
            }
        }
        let errorHandler: NewTypeSessionClient.ErrorHandler = { [weak self] message in
            Task { @MainActor in
                self?.lastError = message
            }
        }
        client.onStateChanged = stateHandler
        client.onError = errorHandler

        let login = try await client.login(
            CustomerLoginParams(
                email: "demo@example.com",
                password: "demo-password-change-me"
            )
        )

        let authorizedClient = NewTypeSessionClient.create(
            config: config,
            authHeaderProvider: AnyAuthHeaderProvider {
                login.authorizationHeaderValue
            }
        )
        self.client = authorizedClient
        authorizedClient.onStateChanged = stateHandler
        authorizedClient.onError = errorHandler

        authorizedClient.setVadMode(.fullAuto)
        authorizedClient.setVadPreset(.natural)

        try await authorizedClient.startSession(
            StartSessionParams(
                appUserId: login.user.appUserId,
                externalSessionId: "ios-demo-\(Int(Date().timeIntervalSince1970))",
                childName: login.user.displayName ?? "Leo",
                age: "9",
                grade: "Grade 3",
                topic: "speaking",
                interests: []
            )
        )
    }

    func stop() async throws {
        try await client?.endSession(reason: "user-leave")
        client?.close()
        client = nil
    }
}
```

监听状态和事件：

```swift
client.onStateChanged = { state in
    Task { @MainActor in
        renderState(state)
    }
}

client.onSignal = { signal in
    print("signal kind=\(signal.kind) sessionId=\(signal.sessionId)")
}

client.onError = { message in
    showError(message)
}
```

结束会话：

```swift
try await client.endSession(reason: "user-leave")
client.close()
```

## 推荐接入流程

```text
1. 配置 Info.plist：麦克风权限，必要时配置 ATS 明文流量例外
2. 通过 CocoaPods 集成 NewTypeSDK.xcframework
3. 创建 NewTypeConfig，指向客户后端地址和路径
4. 创建 NewTypeSessionClient
5. 调用 client.login(CustomerLoginParams) 登录客户后端
6. 保存 login.user 和 login.authorizationHeaderValue
7. 使用 AuthHeaderProvider 创建带 Authorization 的 client
8. 展示 login.user 的用户信息，让用户确认 childName / age / grade / topic
9. 调用 client.startSession(StartSessionParams)
10. 监听 onStateChanged / onSignal / onError 渲染连接状态、转录和总结
11. 按 VAD 模式控制 startSpeaking() / stopSpeaking()
12. 结束时调用 endSession(reason:)，页面销毁时调用 close()
```

## SDK 接口总览

| 接口 | 作用 | 主要输入 | 主要输出 |
|------|------|----------|----------|
| `EndpointUrl.parse(...)` | 校验并创建 URL 类型 | URL 字符串 | `EndpointUrl` |
| `NewTypeConfig(...)` | 配置客户后端地址和路径 | 客户后端 URL、路径、token 模式 | 配置对象 |
| `AnyAuthHeaderProvider(...)` | 提供 Authorization 头 | 异步闭包 | `AuthHeaderProvider` |
| `NewTypeSessionClient.create(...)` | 创建 SDK 客户端 | `NewTypeConfig`、可选认证提供器 | `NewTypeSessionClient` |
| `client.login(...)` | 登录客户后端 | email、password | `CustomerLoginResponse` |
| `client.startSession(...)` | 创建会话、获取媒体 token、连接房间 | `StartSessionParams` | `SessionRecord` |
| `client.endSession(...)` | 结束并离开会话 | reason | 无 |
| `client.startSpeaking()` | 开始一轮发言 | 无 | 无 |
| `client.stopSpeaking()` | 结束一轮发言 | 无 | 无 |
| `client.startTurn(...)` | 高级接口，发送 turn.start | `TurnSource` | 无 |
| `client.stopTurn(...)` | 高级接口，发送 turn.stop | `TurnSource` | 无 |
| `client.setVadMode(...)` | 设置发言控制模式 | `VadMode` | 无 |
| `client.setVadPreset(...)` | 设置 VAD 预设 | `VADPreset` | 无 |
| `client.setVadOptions(...)` | 设置自定义 VAD 参数 | `VADOptions` | 无 |
| `client.getVadMode()` | 获取当前 VAD 模式 | 无 | `VadMode` |
| `client.getVadPreset()` | 获取当前 VAD 预设 | 无 | `VADPreset?` |
| `client.getVadOptions()` | 获取当前 VAD 参数 | 无 | `VADOptions` |
| `client.interrupt(...)` | 中断 TTS / ASR / 全部任务 | target、reason | 无 |
| `client.disconnect()` | 断开媒体房间连接 | 无 | 无 |
| `client.close()` | 释放 SDK 资源 | 无 | 无 |
| `client.state` | 获取当前状态快照 | 属性读取 | `NewTypeClientState` |
| `client.onStateChanged` | 监听状态变化 | 回调闭包 | `NewTypeClientState` |
| `client.onSignal` | 监听 Agent 信令 | 回调闭包 | `AgentSignal` |
| `client.onError` | 监听错误事件 | 回调闭包 | `String` |

## API 详细说明

### EndpointUrl

作用：封装并校验后端 URL。

```swift
let endpoint = try EndpointUrl.parse("http://192.168.0.12:8090")
let optionalEndpoint = EndpointUrl.parseOrNull("http://192.168.0.12:8090")
```

| 接口 | 返回 | 含义 |
|------|------|------|
| `parse(_:)` | `EndpointUrl` | URL 无效时抛出 `EndpointUrlError.invalidUrl`。 |
| `parseOrNull(_:)` | `EndpointUrl?` | URL 无效时返回 `nil`。 |
| `value` | `String` | 原始 URL 字符串。 |

### NewTypeConfig

作用：配置 SDK 访问客户后端的地址、接口路径和 token 获取模式。

```swift
let config = NewTypeConfig(
    backendBaseUrl: try EndpointUrl.parse("http://192.168.0.12:8090"),
    sessionPath: "/app/sessions",
    tokenPath: "/app/sessions/{sessionId}/livekit-token",
    liveKitTokenMode: .userTokenInBody,
    summaryFallbackTimeoutMs: 20_000
)
```

| 字段 | 类型 | 必填 | 默认值 | 含义 |
|------|------|------|--------|------|
| `backendBaseUrl` | `EndpointUrl` | 是 | 无 | 客户后端基础地址，例如 `http://192.168.0.12:8090`。 |
| `sessionPath` | `String` | 否 | `/api/sessions` | 创建会话路径。对齐客户后端 demo 时使用 `/app/sessions`。 |
| `tokenPath` | `String` | 否 | `/api/livekit/token` | 获取媒体服务器 token 的路径。对齐客户后端 demo 时使用 `/app/sessions/{sessionId}/livekit-token`。 |
| `liveKitTokenMode` | `NewTypeConfig.LiveKitTokenMode` | 否 | `.userTokenAuthorization` | 获取 LiveKit token 时如何携带用户 token。 |
| `summaryFallbackTimeoutMs` | `UInt64` | 否 | `20_000` | 结束会话后等待总结的兜底超时时间。 |

`LiveKitTokenMode`：

| 值 | 含义 | 适用场景 |
|----|------|----------|
| `.userTokenAuthorization` | 通过 `Authorization` 头传递用户 token。 | 后端从请求头读取 customer JWT。 |
| `.userTokenInBody` | 将用户 token 放入请求 body。 | 当前客户后端 demo 推荐模式。 |
| `.serviceAuthorization` | 使用服务级 Authorization。 | 服务端代理或内部集成场景。 |

注意：这里不配置媒体服务器 URL。媒体服务器 URL 必须由客户后端的 token 接口返回。

### AuthHeaderProvider / AnyAuthHeaderProvider

作用：为需要认证的请求提供 `Authorization` 头，例如 `Bearer <customer-jwt>`。

```swift
let provider = AnyAuthHeaderProvider {
    login.authorizationHeaderValue
}

let client = NewTypeSessionClient.create(
    config: config,
    authHeaderProvider: provider
)
```

| 接口 | 含义 |
|------|------|
| `AuthHeaderProvider.getAuthorizationHeaderValue()` | 异步返回 Authorization header value。 |
| `AnyAuthHeaderProvider { ... }` | 用闭包快速创建认证提供器。 |

生产建议：业务 App 自己完成登录并安全存储 customer JWT，然后通过 `AuthHeaderProvider` 传给 SDK。Demo 为了演示完整链路，直接调用 `client.login(...)` 获取 JWT。

### NewTypeSessionClient.create

作用：创建 SDK 主客户端。

```swift
let client = NewTypeSessionClient.create(
    config: config,
    authHeaderProvider: provider,
    urlSession: .shared
)
```

| 参数 | 类型 | 含义 |
|------|------|------|
| `config` | `NewTypeConfig` | SDK 配置对象。 |
| `authHeaderProvider` | `AuthHeaderProvider?` | 可选认证提供器，用于创建 session、获取 token、结束 session。 |
| `urlSession` | `URLSession` | 可选网络会话，默认 `.shared`。 |

返回：`NewTypeSessionClient`。

注意：`NewTypeSessionClient` 是 `@MainActor` 类型，建议在主线程 / `@MainActor` ViewModel 中创建和调用。

### client.login

作用：登录客户后端，获取 customer JWT 和客户侧用户信息。推荐先登录，再创建带认证的 client 调用 `startSession()`。

```swift
let response = try await client.login(
    CustomerLoginParams(
        email: "demo@example.com",
        password: "demo-password-change-me"
    )
)
```

入参：

```swift
public struct CustomerLoginParams: Sendable, Hashable {
    public let email: String
    public let password: String
}
```

| 参数 | 类型 | 含义 |
|------|------|------|
| `email` | `String` | 登录邮箱，业务层建议先 trim。 |
| `password` | `String` | 登录密码。 |

出参：

```swift
public struct CustomerLoginResponse: Sendable, Codable, Hashable {
    public let token: String
    public let tokenType: String
    public let expiresIn: Int
    public let user: CustomerUser
    public var authorizationHeaderValue: String { get }
}

public struct CustomerUser: Sendable, Codable, Hashable {
    public let appUserId: String
    public let email: String
    public let displayName: String?
    public let created: Bool
}
```

| 字段 | 含义 |
|------|------|
| `token` | customer JWT，后续创建 session 使用。 |
| `tokenType` | token 类型，通常为 `Bearer`。 |
| `expiresIn` | token 有效期，当前 demo 语义为秒。 |
| `authorizationHeaderValue` | 拼好的 Authorization 值，例如 `Bearer <token>`。 |
| `user.appUserId` | 客户侧用户 ID。 |
| `user.email` | 用户邮箱。 |
| `user.displayName` | 用户显示名，可作为默认 `childName`。 |
| `user.created` | 是否本次登录创建了新用户。 |

异常：网络失败、HTTP 非 2xx、响应 JSON 不匹配时会抛出异常。

### client.startSession

作用：创建 NewType 会话、获取媒体服务器 token、连接媒体房间，并发送 `session.ready`。

```swift
let session = try await client.startSession(
    StartSessionParams(
        appUserId: login.user.appUserId,
        externalSessionId: "ios-demo-001",
        childName: "Leo",
        age: "9",
        grade: "Grade 3",
        topic: "speaking",
        interests: ["animals", "football"]
    )
)
```

入参：

```swift
public struct StartSessionParams: Sendable, Hashable {
    public let appUserId: String?
    public let externalUserId: String?
    public let externalSessionId: String?
    public let childName: String
    public let age: String?
    public let grade: String?
    public let topic: String?
    public let interests: [String]
}
```

| 字段 | 类型 | 建议 | 含义 |
|------|------|------|------|
| `appUserId` | `String?` | 推荐填写 | 客户侧用户 ID，通常使用 `login.user.appUserId`。 |
| `externalUserId` | `String?` | 可选 | 客户业务系统自己的用户 ID。 |
| `externalSessionId` | `String?` | 可选 | 客户业务系统自己的会话 ID。 |
| `childName` | `String` | 必填 | 孩子姓名或显示名。 |
| `age` | `String?` | 推荐填写 | 年龄，例如 `9`。 |
| `grade` | `String?` | 推荐填写 | 年级，例如 `Grade 3`。 |
| `topic` | `String?` | 推荐填写 | 产品/场景/会话主题。Web demo 常用 `speaking`。 |
| `interests` | `[String]` | 可选 | 兴趣标签。 |

执行过程：

1. `POST /app/sessions` 创建 session。
2. `POST /app/sessions/{sessionId}/livekit-token` 获取媒体服务器 URL/token。
3. 连接媒体服务器。
4. 发布 `session.ready` 到控制信令 topic。
5. 通过 `state` 和 `onStateChanged` 输出连接状态和会话数据。

返回：`SessionRecord`。连接后续状态、转录、AI 回复和总结通过回调观察。

### client.endSession

作用：发送结束信令、通知客户后端结束 session，并断开媒体房间。

```swift
try await client.endSession(reason: "user-leave")
```

| 参数 | 类型 | 含义 |
|------|------|------|
| `reason` | `String` | 离开原因，例如 `user-leave`。默认值为 `user-leave`。 |

可选 reason：

| 值 | 含义 |
|----|------|
| `user-leave` | 用户主动离开。 |
| `session-complete` | 会话自然完成。 |
| `timeout` | 超时结束。 |
| `error` | 因错误结束。 |

返回：无。结束期间状态通常会进入 `.leaving`，结束后回到 `.idle` 或断开状态。

### client.startSpeaking

作用：开始一轮用户发言。

```swift
try await client.startSpeaking()
```

| 当前模式 | 行为 |
|----------|------|
| `.off` | PTT 模式，打开麦克风并发送 `turn.start`。 |
| `.semiAuto` | 开始半自动 VAD 检测，检测到语音后发送 `turn.start`。 |
| `.fullAuto` | 通常无需手动调用。 |

返回：无。状态通过 `state.recording`、`state.agentPhase`、`state.turnBusy` 输出。

### client.stopSpeaking

作用：结束一轮用户发言。

```swift
try await client.stopSpeaking()
```

| 当前模式 | 行为 |
|----------|------|
| `.off` | PTT 模式，发送 `turn.stop` 并关闭麦克风。 |
| `.semiAuto` | 停止半自动 VAD 并发送 `turn.stop`。 |
| `.fullAuto` | 通常无需手动调用。 |

返回：无。状态通过 `state.recording`、`state.turnBusy` 输出。

### client.startTurn / client.stopTurn

作用：高级接口，直接发送 turn 边界信令。一般推荐使用 `startSpeaking()` / `stopSpeaking()`。

```swift
try await client.startTurn(source: .ptt)
try await client.stopTurn(source: .ptt)
```

| 参数 | 类型 | 值 |
|------|------|----|
| `source` | `TurnSource` | `.ptt` 或 `.vad`。默认 `.ptt`。 |

### client.setVadMode

作用：设置发言控制模式。

```swift
client.setVadMode(.fullAuto)
```

```swift
public enum VadMode: String, Sendable, Codable {
    case off
    case semiAuto
    case fullAuto
}
```

| 值 | 含义 | 适用场景 |
|----|------|----------|
| `.off` | 关闭 VAD，使用 PTT。 | 需要手动控制开始/结束。 |
| `.semiAuto` | 手动启动一轮，VAD 检测开始，手动结束。 | 噪声环境或需要手动收口。 |
| `.fullAuto` | VAD 自动检测开始和结束。 | 自然对话。 |

### client.setVadPreset

作用：设置内置 VAD 灵敏度预设。

```swift
client.setVadPreset(.natural)
```

```swift
public enum VADPreset: String, Sendable, Codable {
    case sensitive
    case natural
    case child
}
```

| 值 | 含义 |
|----|------|
| `.sensitive` | 更容易触发，适合安静环境和轻声说话。 |
| `.natural` | 平衡灵敏度，默认推荐。 |
| `.child` | 对儿童声音和停顿更宽容。 |

### client.setVadOptions

作用：设置自定义 VAD 参数。调用后当前 preset 会变为 `nil`。

```swift
client.setVadOptions(
    VADOptions(
        sampleRate: 16_000,
        positiveSpeechThreshold: 0.5,
        negativeSpeechThreshold: 0.35,
        minSpeechFramesMs: 100,
        minSilenceFramesMs: 500,
        speechPadMs: 100,
        speechPreRollMs: 400
    )
)
```

```swift
public struct VADOptions: Sendable, Codable, Hashable {
    public let sampleRate: Int
    public let positiveSpeechThreshold: Float
    public let negativeSpeechThreshold: Float
    public let minSpeechFramesMs: Int
    public let minSilenceFramesMs: Int
    public let speechPadMs: Int
    public let speechPreRollMs: Int
}
```

| 字段 | 含义 |
|------|------|
| `sampleRate` | VAD 目标采样率，SDK 内部标准化为 `16000`。 |
| `positiveSpeechThreshold` | 开始说话阈值，越低越容易触发。 |
| `negativeSpeechThreshold` | 停止说话阈值。 |
| `minSpeechFramesMs` | 最短有效语音时长。 |
| `minSilenceFramesMs` | 判定一轮结束所需静音时长。 |
| `speechPadMs` | 尾部保留音频时长。 |
| `speechPreRollMs` | 起始前预录音时长，避免吞字。 |

可使用内置预设生成参数：

```swift
let options = VADOptions.preset(.child)
client.setVadOptions(options)
```

### client.getVadMode / getVadPreset / getVadOptions

作用：读取当前 VAD 配置。

```swift
let mode = client.getVadMode()
let preset = client.getVadPreset()
let options = client.getVadOptions()
```

| 接口 | 返回 | 含义 |
|------|------|------|
| `getVadMode()` | `VadMode` | 当前 VAD 模式。 |
| `getVadPreset()` | `VADPreset?` | 当前预设；`nil` 表示使用自定义参数。 |
| `getVadOptions()` | `VADOptions` | 当前生效的 VAD 参数。 |

### client.interrupt

作用：中断正在进行的 TTS、ASR 或全部任务。适用于用户取消播放、打断 AI 回复或退出会话前清理。

```swift
try await client.interrupt(target: .tts, reason: .userCancel)
```

| 参数 | 类型 | 可选值 | 含义 |
|------|------|--------|------|
| `target` | `InterruptTarget` | `.tts` / `.asr` / `.all` | 中断目标，默认 `.tts`。 |
| `reason` | `InterruptReason` | `.bargeIn` / `.userCancel` / `.sessionEnd` | 中断原因，默认 `.userCancel`。 |

### client.disconnect / close

作用：断开连接或释放资源。

```swift
await client.disconnect()
client.close()
```

| 接口 | 行为 |
|------|------|
| `disconnect()` | 断开媒体房间连接，不一定释放全部 SDK 资源。 |
| `close()` | 停止 VAD、释放音频/房间资源、取消内部任务。 |

建议在 ViewModel `deinit`、页面销毁或用户退出流程中调用 `close()`。

## 状态和事件模型

### client.state

```swift
@MainActor var state: NewTypeClientState { get }
```

`state` 是当前状态快照。状态变化建议通过 `onStateChanged` 监听。

### client.onStateChanged

```swift
client.onStateChanged = { state in
    Task { @MainActor in
        renderState(state)
    }
}
```

`NewTypeClientState`：

| 字段 | 类型 | 含义 |
|------|------|------|
| `sessionId` | `String?` | 当前 NewType session ID。 |
| `roomName` | `String?` | 当前媒体房间名称。 |
| `phase` | `SessionPhase` | 当前会话阶段。 |
| `connectionStatus` | `ConnectionStatus` | 媒体连接状态。 |
| `agentPhase` | `AgentPhase` | Agent 状态。 |
| `agentMessage` | `String` | Agent 状态提示文案。 |
| `participantCount` | `Int` | 媒体房间参与者数量。 |
| `micReady` | `Bool` | 麦克风是否已初始化可用。 |
| `recording` | `Bool` | 当前是否正在采集一轮用户发言。 |
| `turnBusy` | `Bool` | AI/后端是否正在处理当前 turn。 |
| `leaveRequested` | `Bool` | 是否已请求离开。 |
| `transcript` | `[TranscriptEntry]` | 对话转录列表。 |
| `summary` | `SessionSummary?` | 会话总结。 |
| `contextSummary` | `SessionContextSummary?` | 当前会话上下文摘要。 |
| `errorMessage` | `String?` | 当前错误信息。 |
| `vadMode` | `VadMode` | 当前 VAD 模式。 |
| `vadPreset` | `VADPreset?` | 当前 VAD 预设。 |
| `vadOptions` | `VADOptions` | 当前 VAD 参数。 |

### SessionPhase

```swift
public enum SessionPhase: String, Sendable, Codable {
    case idle
    case requestingToken
    case connecting
    case connected
    case leaving
    case error
}
```

| 值 | 含义 |
|----|------|
| `.idle` | 空闲或已断开。 |
| `.requestingToken` | 正在创建 session / 获取媒体服务器 token。 |
| `.connecting` | 正在连接媒体服务器。 |
| `.connected` | 已连接并可对话。 |
| `.leaving` | 正在离开。 |
| `.error` | 发生错误。 |

### ConnectionStatus

```swift
public enum ConnectionStatus: String, Sendable, Codable {
    case idle
    case requestingToken
    case connecting
    case connected
    case reconnecting
    case disconnected
    case error
}
```

| 值 | 含义 |
|----|------|
| `.idle` | 未开始连接。 |
| `.requestingToken` | 正在获取媒体服务器 token。 |
| `.connecting` | 正在连接媒体服务器。 |
| `.connected` | 已连接。 |
| `.reconnecting` | 正在重连。 |
| `.disconnected` | 已断开。 |
| `.error` | 连接错误。 |

### AgentPhase

```swift
public enum AgentPhase: String, Sendable, Codable {
    case waiting
    case opening
    case listening
    case processing
    case closing
    case error
}
```

| 值 | 含义 |
|----|------|
| `.waiting` | 等待用户或等待下一步。 |
| `.opening` | Agent 正在或已经发送开场。 |
| `.listening` | 正在听用户说话。 |
| `.processing` | 正在处理用户发言或生成回复。 |
| `.closing` | 正在收尾或生成总结。 |
| `.error` | Agent 或链路发生错误。 |

### TranscriptEntry

```swift
public struct TranscriptEntry: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let speaker: TranscriptSpeaker
    public let text: String
    public let meta: String?
    public let streaming: Bool
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | `String` | 本地生成的转录条目 ID。 |
| `speaker` | `TranscriptSpeaker` | `.child` 或 `.ai`。 |
| `text` | `String` | 文本内容。 |
| `meta` | `String?` | 补充信息，例如 IPA 或纠错候选。 |
| `streaming` | `Bool` | 是否为 AI 流式回复中的临时文本。 |

### SessionSummary

```swift
public struct SessionSummary: Sendable, Codable, Hashable {
    public let summary: String
    public let didWell: String
    public let learnedSentences: [String]
    public let oneTip: String
    public let nextTopic: String
    public let pronunciationFocus: String
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `summary` | `String` | 本次会话一句话总结。 |
| `didWell` | `String` | 正向反馈。 |
| `learnedSentences` | `[String]` | 本次学到的可复用句子。 |
| `oneTip` | `String` | 一个轻量建议。 |
| `nextTopic` | `String` | 下次建议话题。 |
| `pronunciationFocus` | `String` | 发音关注点。 |

### SessionContextSummary

```swift
public struct SessionContextSummary: Sendable, Codable, Hashable {
    public let now: String
    public let goal: String
    public let focus: String
    public let teacherNote: String
}
```

| 字段 | 含义 |
|------|------|
| `now` | 当前会话状态摘要。 |
| `goal` | 会话目标。 |
| `focus` | 当前教学关注点。 |
| `teacherNote` | 给教学/展示层的补充说明。 |

### client.onSignal

```swift
client.onSignal = { signal in
    switch signal {
    case .agentStatus(let envelope):
        print(envelope.payload.message)
    case .childTranscript(let envelope):
        print(envelope.payload.transcript)
    case .coachReply(let envelope):
        print(envelope.payload.text)
    case .sessionSummary(let envelope):
        print(envelope.payload.summary)
    default:
        break
    }
}
```

`AgentSignal`：

| 事件 | 负载 | 含义 |
|------|------|------|
| `.agentStatus` | `AgentStatusPayload` | Agent 阶段和提示文案。 |
| `.sessionContext` | `SessionContextSummary` | 会话上下文摘要。 |
| `.sessionOpening` | `SessionOpeningPayload` | Agent 开场内容。 |
| `.ttsStatus` | `TTSStatusPayload` | TTS 播放状态。 |
| `.childTranscript` | `ChildTranscriptPayload` | 孩子转录文本和发音信息。 |
| `.turnResult` | `TurnResultPayload` | 旧版 turn 结果聚合。 |
| `.coachReplyDelta` | `CoachReplyDeltaPayload` | AI 流式回复增量。 |
| `.coachReply` | `CoachReplyPayload` | AI 完整回复。 |
| `.sessionSummary` | `SessionSummary` | 会话总结。 |
| `.agentError` | `AgentErrorPayload` | Agent 错误。 |

多数业务界面只需要消费 `onStateChanged`。`onSignal` 适合日志、调试或需要细粒度事件的高级场景。

### client.onError

```swift
client.onError = { message in
    Task { @MainActor in
        showToast(message)
    }
}
```

| 事件 | 含义 |
|------|------|
| `onError` | 一次性错误事件，可用于 toast、错误弹窗或日志。 |

## 数据模型参考

### SessionRecord

`SessionRecord` 是客户后端 / NewType backend 返回的会话记录。`startSession()` 直接返回该对象，SDK 后续也会根据会话更新状态。

```swift
public struct SessionRecord: Sendable, Codable, Hashable {
    public let sessionId: String
    public let roomName: String?
    public let customerId: String?
    public let productId: String?
    public let externalUserId: String?
    public let externalSessionId: String?
    public let status: SessionStatus
    public let createdAt: String
    public let updatedAt: String
    public let endedAt: String?
    public let childName: String?
    public let age: String?
    public let grade: String?
    public let topic: String
    public let interests: [String]
    public let turns: [SessionTurn]
    public let summary: SessionSummary?
    public let profileMemory: ProfileMemorySnapshot?
    public let sessionMemory: SessionMemorySnapshot?
    public let agentMemory: AgentMemorySnapshot?
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `sessionId` | `String` | 会话 ID。 |
| `roomName` | `String?` | 媒体房间名称。 |
| `customerId` | `String?` | 客户 ID。 |
| `productId` | `String?` | 产品 ID。 |
| `externalUserId` | `String?` | 客户侧映射后的用户 ID。 |
| `externalSessionId` | `String?` | 客户侧会话 ID。 |
| `status` | `SessionStatus` | `.active` 或 `.ended`。 |
| `createdAt` / `updatedAt` / `endedAt` | `String` / `String?` | 会话时间字段。 |
| `childName` / `age` / `grade` | `String?` | 孩子基础信息。 |
| `topic` | `String` | 产品/会话主题。 |
| `interests` | `[String]` | 兴趣标签。 |
| `turns` | `[SessionTurn]` | 历史 turn。 |
| `summary` | `SessionSummary?` | 总结。 |
| `profileMemory` | `ProfileMemorySnapshot?` | 用户画像记忆。 |
| `sessionMemory` | `SessionMemorySnapshot?` | 学习记忆。 |
| `agentMemory` | `AgentMemorySnapshot?` | Agent 配置快照。 |

### SessionTurn

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | `String` | turn ID。 |
| `speaker` | `TranscriptSpeaker` | `.child` 或 `.ai`。 |
| `text` | `String` | turn 文本。 |
| `language` | `TurnLanguage` | `.en` / `.zh` / `.mixed` / `.unknown`。 |
| `createdAt` | `String` | 创建时间。 |
| `asr` | `TurnAsr?` | ASR 结果。 |
| `pronunciation` | `TurnPronunciation?` | 发音分析。 |
| `audioPath` | `String?` | 服务端归档音频路径。 |

### 记忆模型

| 类型 | 含义 |
|------|------|
| `ProfileMemorySnapshot` | 用户画像记忆，包含 `childName`、`age`、`grade`、`interests`、`preferredTopic`。 |
| `SessionMemorySnapshot` | 会话学习记忆，包含学习点、信号、临时记忆和 planner 信息。 |
| `SessionLearningMemory` | 语法/表达问题、学到的句子、复习候选和下次话题建议。 |
| `AgentMemorySnapshot` | Agent 人设、教学原则、纠错风格和语言策略。 |

## Demo 工程说明

`newtypesdk_demo_ios` 已经按当前推荐链路实现完整流程：

| 路径 | 作用 |
|------|------|
| `Podfile` | 引入 `NewTypeSDK` 二进制 pod。 |
| `libs/NewTypeSDK-Binary.podspec` | 声明 XCFramework 和 LiveKit 依赖。 |
| `libs/NewTypeSDK.xcframework` | SDK 二进制文件。 |
| `Features/RTC/DemoViewModel.swift` | 登录、建会话、VAD、状态绑定的核心示例。 |
| `UI/ContentView.swift` | SwiftUI 演示界面。 |
| `App/NewTypeDemoApp.swift` | App 入口。 |

Demo 默认值：

| 配置 | 默认值 | 说明 |
|------|--------|------|
| Customer Backend URL | `http://localhost:8090` | 模拟器可访问本机；真机需改成局域网 IP。 |
| Email | `demo@example.com` | demo 登录账号。 |
| Password | `demo-password-change-me` | demo 登录密码。 |
| Product / Topic | `speaking` | 与 Web / Android demo 对齐。 |
| VAD Mode | `.off` | 默认 PTT，界面可切换。 |
| VAD Preset | `.natural` | 默认自然模式。 |

真机调试时请将 `localhost` 改为后端机器在同一局域网下的 IP，例如 `http://192.168.0.12:8090`。

## 常见问题

### 连接客户后端失败

检查：

1. `backendBaseUrl` 是否指向客户后端，例如 `http://192.168.0.12:8090`。
2. 真机和后端机器是否在同一局域网。
3. 客户后端是否监听 `0.0.0.0:8090`，而不是只监听 `localhost`。
4. iOS 是否允许 HTTP 明文流量，`Info.plist` 是否配置 ATS 例外。
5. 手机 Safari 是否能打开客户后端健康检查地址。
6. 如果使用模拟器访问本机服务，`http://localhost:8090` 通常可用；真机不可用。

### 登录成功但 startSession 失败

检查：

1. 是否使用 `login.authorizationHeaderValue` 创建了 `AuthHeaderProvider`。
2. `NewTypeConfig.sessionPath` 是否为客户后端路径 `/app/sessions`。
3. `NewTypeConfig.tokenPath` 是否为 `/app/sessions/{sessionId}/livekit-token`。
4. `liveKitTokenMode` 是否与后端一致，当前 demo 推荐 `.userTokenInBody`。
5. customer JWT 是否过期。

### Join 后没有声音或没有转录

检查：

1. 麦克风权限是否授予。
2. `state.micReady` 是否为 `true`。
3. `state.participantCount` 是否大于 1，表示 Agent 已入房。
4. `state.agentMessage` 或 `state.errorMessage` 是否有错误提示。
5. VAD 模式是否符合预期。PTT 模式需要按住按钮调用 `startSpeaking()` / `stopSpeaking()`。
6. 真机静音开关、音量和蓝牙耳机路由是否影响播放。

### VAD 不触发或太敏感

建议：

1. 安静环境下可切换到 `.sensitive`。
2. 儿童语音和停顿较多时可切换到 `.child`。
3. 噪声环境可使用 `.semiAuto`，由用户手动开始/结束一轮。
4. 高级场景使用 `setVadOptions(...)` 调整阈值和静音时长。

### Topic 应该填什么

`topic` 是产品/场景标识。若与 Web 和 Android demo 对齐，建议填 `speaking`。之后有别的产品，就填对应的产品 ID。

### 生产环境是否可以在 App 中使用 email/password 登录

可以用于 demo 或内部测试，但生产不推荐让 SDK 直接持有业务登录密码。生产建议由业务 App 自己完成登录，然后将 customer JWT 传给 SDK：

```swift
let provider = AnyAuthHeaderProvider {
    customerJwtAuthorizationHeader
}

let client = NewTypeSessionClient.create(
    config: config,
    authHeaderProvider: provider
)
```

### 为什么不配置 LiveKit URL

当前推荐链路中，媒体服务器 URL 和 token 必须由客户后端按 session 下发。这样可以让后端统一控制房间、权限、过期时间和环境切换，App 只需要配置客户后端地址。

### 模拟器支持吗

支持。`NewTypeSDK.xcframework` 包含真机 arm64 和模拟器 arm64 / x86_64 slice。实际录音、扬声器和网络表现仍建议用真机验证。

## 最佳实践

1. 在 `@MainActor` ViewModel 中持有 `NewTypeSessionClient`，避免跨线程更新 SwiftUI 状态。
2. 业务 App 负责登录和 token 刷新，SDK 通过 `AuthHeaderProvider` 读取最新 Authorization。
3. 页面消失或对象销毁时调用 `close()`，防止麦克风和房间资源泄漏。
4. UI 渲染优先使用 `onStateChanged` 的聚合状态，日志和高级调试再使用 `onSignal`。
5. `childName`、`age`、`grade`、`topic` 在调用 `startSession()` 前做 trim 和非空校验。
6. 真机 HTTP 调试只在开发环境打开 ATS 明文流量例外，生产使用 HTTPS。

## 版本信息

- SDK 版本：0.1.0
- 文档更新日期：2026-05-19
