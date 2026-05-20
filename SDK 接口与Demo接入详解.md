# NewType iOS SDK 接口与 Demo 接入详解

本文只基于demo工程中的代码说明 SDK 的接入方式。客户端工程师可以直接对照 demo 文件复制接入逻辑。

本文重点解释：

- Demo 如何通过 CocoaPods 引入 `NewTypeSDK.xcframework`
- Demo 如何创建 SDK client、登录、加入会话、监听状态、结束会话
- Demo 中用到的 SDK 接口和数据类分别承担什么职责
- Demo 中每个 UI 字段和具体代码块如何对应

## 1. Demo 文件索引

客户接入时建议按下面顺序阅读 demo 文件：

| 文件 | 作用 |
|------|------|
| `Podfile` | 引入 `NewTypeSDK` 二进制 pod。 |
| `Podfile.lock` | 锁定 SDK 和媒体服务器客户端相关依赖版本。 |
| `libs/NewTypeSDK-Binary.podspec` | 声明 `NewTypeSDK.xcframework` 和二进制 SDK 依赖。 |
| `libs/NewTypeSDK.xcframework` | NewType iOS SDK 二进制包。 |
| `App/NewTypeDemoApp.swift` | Demo App 入口，挂载 SwiftUI 页面。 |
| `Features/RTC/DemoViewModel.swift` | SDK 调用主流程：登录、Join、VAD、状态监听、Leave、释放资源。 |
| `UI/ContentView.swift` | Demo SwiftUI 页面，输入框、按钮、状态展示。 |
| `SDK_INTEGRATION_GUIDE.md` | 现有快速接入指引。 |

## 2. Demo 的整体接入链路

Demo 采用的链路是：

```text
iOS Demo App
  -> 客户后端 Customer Backend
  -> NewType backend
  -> 媒体服务器房间
  -> NewType room agent
```

iOS 端只配置客户后端地址，例如：

```text
http://192.168.0.12:8090
```

iOS 端不需要配置 NewType backend 地址，也不需要在 App 内硬编码媒体服务器地址。媒体房间的 `url` 和 `token` 由客户后端在创建 session 后下发给 SDK。

Demo 中的完整流程：

```text
1. 用户填写 Customer Backend URL、Email、Password
2. 点击 Login
3. SDK 调用 client.login(CustomerLoginParams)
4. Demo 保存登录返回的 customer token 和用户信息
5. 用户填写 Product ID、External Session ID、Child Name、Age、Grade
6. 点击 Join
7. Demo 创建带 Authorization 的 NewTypeSessionClient
8. Demo 设置 VAD 模式和 VAD 预设
9. Demo 调用 client.startSession(StartSessionParams)
10. SDK 连接媒体房间并发送 session.ready
11. Demo 通过 onStateChanged 渲染连接状态、转录、AI 回复、总结
12. 用户点击 Leave 或页面销毁时释放资源
```

## 3. CocoaPods 接入

Demo 的依赖配置在 `Podfile`。

关键代码：

```ruby
source "https://cdn.cocoapods.org/"
source "https://github.com/livekit/podspecs.git"

platform :ios, "13.4"

use_frameworks! :linkage => :static

target "NewTypeDemo" do
  pod "NewTypeSDK", :path => "./libs/NewTypeSDK-Binary.podspec"
end
```

说明：

| 配置 | 说明 |
|------|------|
| `platform :ios, "13.4"` | Demo 最低支持 iOS 13.4。 |
| `use_frameworks! :linkage => :static` | 使用静态 framework 链接方式。 |
| `pod "NewTypeSDK"` | 引入 NewType SDK 二进制包。 |
| `source "https://github.com/livekit/podspecs.git"` | 依赖仓库源，属于 Pod 依赖配置，保留原始仓库名。 |

安装依赖：

```bash
cd newtypesdk_demo_ios
pod install
open newtypesdk_demo_ios.xcworkspace
```

注意：安装依赖后要用 `.xcworkspace` 打开工程，而不是只打开 `.xcodeproj`。

## 4. SDK 二进制 Podspec

Demo 的 SDK 二进制声明在 `libs/NewTypeSDK-Binary.podspec`。

关键代码：

```ruby
Pod::Spec.new do |s|
  s.name = "NewTypeSDK"
  s.version = "0.1.0"
  s.summary = "Type-safe iOS SDK for newtype realtime speaking sessions"
  s.description = <<-DESC
Binary iOS SDK wrapping newtype backend session APIs and media room flow.
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

说明：

| 配置 | 说明 |
|------|------|
| `s.vendored_frameworks = "NewTypeSDK.xcframework"` | 使用本地 SDK 二进制包。 |
| `s.frameworks = "Foundation", "AVFoundation"` | SDK 需要系统基础库和音频能力。 |
| `s.dependency "LiveKitClient"` | SDK 依赖的媒体房间客户端 Pod 名，属于依赖名，保留原文。 |
| `EXCLUDED_ARCHS` | 排除模拟器 i386 架构。 |
| `DEFINES_MODULE` | 确保 Swift 模块可导入。 |

发布到客户工程时通常需要把：

```text
libs/NewTypeSDK.xcframework
libs/NewTypeSDK-Binary.podspec
```

一起提供给客户。

## 5. App 入口

Demo App 入口在 `App/NewTypeDemoApp.swift`。

代码：

```swift
import SwiftUI
import UIKit

@UIApplicationMain
final class NewTypeDemoApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: ContentView(viewModel: DemoViewModel()))
        window.makeKeyAndVisible()
        self.window = window
    }
}
```

说明：

| 代码 | 说明 |
|------|------|
| `ContentView(viewModel: DemoViewModel())` | 创建 SwiftUI 页面并注入 ViewModel。 |
| `DemoViewModel` | 持有 SDK client，负责登录、Join、状态监听等逻辑。 |

## 6. DemoViewModel 中用到的 SDK 类

`Features/RTC/DemoViewModel.swift` 顶部引入 SDK：

```swift
import Foundation
import NewTypeSDK
```

Demo 中实际用到的 SDK 类和枚举：

| 类/枚举 | Demo 中的作用 |
|---------|---------------|
| `EndpointUrl` | 校验客户后端 URL。 |
| `NewTypeConfig` | 配置客户后端地址、接口路径、token 模式。 |
| `NewTypeSessionClient` | SDK 主入口，负责登录、Join、Leave、发言控制、状态输出。 |
| `AnyAuthHeaderProvider` / `AuthHeaderProvider` | 给创建 session 等请求提供 Authorization 头。 |
| `CustomerLoginParams` | 登录客户后端的参数。 |
| `CustomerLoginResponse` | 登录客户后端的返回结果，包含 token 和用户信息。 |
| `CustomerUser` | 登录返回的用户信息。 |
| `StartSessionParams` | Join 时传给 SDK 的会话参数。 |
| `NewTypeClientState` | SDK 输出的完整会话状态。 |
| `SessionPhase` | 会话阶段，用于按钮状态和状态展示。 |
| `ConnectionStatus` | 媒体连接状态，用于日志和排查。 |
| `AgentPhase` | Agent 阶段，用于状态展示。 |
| `TranscriptEntry` | 对话转录和 AI 回复条目。 |
| `SessionSummary` | 会话总结。 |
| `VadMode` | 发言控制模式：PTT、半自动、全自动。 |
| `VADPreset` | VAD 灵敏度预设：灵敏、自然、儿童。 |

## 7. DemoViewModel 中的成员变量

`DemoViewModel.swift` 中和 SDK 接入相关的状态：

```swift
@Published var apiBaseUrl: String = "http://localhost:8090"
@Published var loginEmail: String = "demo@example.com"
@Published var loginPassword: String = "demo-password-change-me"
@Published var productId: String = "speaking"
@Published var externalSessionId: String = ""
@Published var childName: String = "Leo"
@Published var age: String = "9"
@Published var grade: String = "Grade 3"
@Published var vadMode: VadMode = .off
@Published var vadPreset: VADPreset = .natural
@Published private(set) var loginText: String = "未登录客户后端"
@Published private(set) var statusText: String = ""
@Published private(set) var transcriptText: String = "暂无消息"
@Published private(set) var summaryText: String = "暂无总结"
@Published private(set) var isRecording: Bool = false
@Published var lastError: String = ""

private var client: NewTypeSessionClient?
private var auth: CustomerAuth?
private var latestState = DemoRoomState()
private var loginBusy = false
private var isPushToTalkActive = false
```

说明：

| 变量 | 说明 |
|------|------|
| `apiBaseUrl` | 客户后端地址，模拟器默认 `http://localhost:8090`，真机需改成局域网 IP。 |
| `loginEmail` / `loginPassword` | demo 登录账号和密码。 |
| `productId` | 产品/主题，默认 `speaking`。 |
| `externalSessionId` | 客户业务侧 session ID，可为空。 |
| `childName` / `age` / `grade` | 孩子基础信息。 |
| `vadMode` | 当前发言控制模式。 |
| `vadPreset` | 当前 VAD 预设。 |
| `loginText` | 登录状态展示文本。 |
| `statusText` | 连接状态展示文本。 |
| `transcriptText` | 对话转录展示文本。 |
| `summaryText` | 会话总结展示文本。 |
| `lastError` | 错误展示文本。 |
| `client` | 当前 SDK client。 |
| `auth` | Demo 自己保存的登录态。 |
| `latestState` | 最近一次 SDK 状态。 |
| `loginBusy` | 防止重复登录。 |
| `isPushToTalkActive` | PTT 按住状态。 |

## 8. Demo 自定义登录态：CustomerAuth

Demo 没有把完整 SDK 登录返回直接塞到 UI，而是转换成自己的登录态：

```swift
private struct CustomerAuth: Equatable {
    let token: String
    let tokenType: String
    let expiresIn: Int
    let user: CustomerUser

    var authorizationHeader: String {
        "\(tokenType) \(token)"
    }

    init(response: CustomerLoginResponse) {
        self.token = response.token
        self.tokenType = response.tokenType
        self.expiresIn = response.expiresIn
        self.user = response.user
    }
}
```

字段说明：

| 字段 | Demo 用途 |
|------|-----------|
| `token` | 保存客户后端 token。 |
| `tokenType` | token 类型，通常是 `Bearer`。 |
| `expiresIn` | token 有效期，用于 UI 展示。 |
| `user` | 保存 `appUserId`、email、displayName。 |
| `authorizationHeader` | 创建带认证的 SDK client 时使用。 |

## 9. 创建 SDK 配置：NewTypeConfig

Demo 中通过 `makeClient(authHeader:)` 创建 SDK client，其中包含 `NewTypeConfig`：

```swift
private func makeClient(authHeader: String?) throws -> NewTypeSessionClient {
    let endpoint = try EndpointUrl.parse(apiBaseUrl)
    let config = NewTypeConfig(
        backendBaseUrl: endpoint,
        sessionPath: "/app/sessions",
        tokenPath: "/app/sessions/{sessionId}/livekit-token",
        liveKitTokenMode: .userTokenInBody
    )
    let authProvider: AuthHeaderProvider? = authHeader.map { header in
        AnyAuthHeaderProvider { header }
    }
    return NewTypeSessionClient.create(config: config, authHeaderProvider: authProvider)
}
```

调用点解释：

| 代码 | 说明 |
|------|------|
| `EndpointUrl.parse(apiBaseUrl)` | 校验客户后端 URL。 |
| `backendBaseUrl: endpoint` | 指向客户后端地址。 |
| `sessionPath: "/app/sessions"` | 客户后端创建 session 路径。 |
| `tokenPath: "/app/sessions/{sessionId}/livekit-token"` | 客户后端获取媒体房间 token 路径；接口路径中保留原始 `livekit`。 |
| `liveKitTokenMode: .userTokenInBody` | SDK 参数名，表示获取媒体房间 token 时把用户 token 放在 body 中。 |
| `AnyAuthHeaderProvider { header }` | 将登录得到的 Authorization 传给 SDK。 |
| `NewTypeSessionClient.create(...)` | 创建 SDK client。 |

`apiBaseUrl` 来自 UI 输入：

```swift
@Published var apiBaseUrl: String = "http://localhost:8090"
```

在 `ContentView.swift` 中对应输入框：

```swift
DemoInputField(title: "Customer Backend URL", text: $vm.apiBaseUrl)
```

真机调试时不要使用 `localhost`，应改成后端机器的局域网 IP，例如：

```text
http://192.168.0.12:8090
```

## 10. 登录客户后端：client.login

### 10.1 UI 输入

登录输入框在 `UI/ContentView.swift`：

```swift
DemoSectionTitle("Customer Login")
DemoInputField(title: "Customer Backend URL", text: $vm.apiBaseUrl)
DemoInputField(title: "Email", text: $vm.loginEmail)
DemoSecureInputField(title: "Password", text: $vm.loginPassword)

HStack(spacing: 8) {
    DemoActionButton(title: "Login", backgroundColor: .blue) {
        vm.loginTapped()
    }
    .disabled(!vm.canLogin)

    DemoActionButton(title: "Logout", backgroundColor: .gray) {
        vm.logoutTapped()
    }
    .disabled(!vm.canLogout)
}

DemoOutputBox(text: vm.loginText, monospaced: true, minHeight: 72)
```

按钮点击进入 ViewModel：

```swift
func loginTapped() {
    Task { await login() }
}
```

### 10.2 登录实现

登录逻辑在 `DemoViewModel.login()`：

```swift
private func login() async {
    do {
        lastError = ""
        loginBusy = true
        loginText = "正在登录客户后端..."
        let client = try makeClient(authHeader: nil)
        let response = try await client.login(
            CustomerLoginParams(
                email: normalized(loginEmail) ?? "",
                password: loginPassword
            )
        )
        auth = CustomerAuth(response: response)
        loginText = [
            "已登录：\(response.user.displayName ?? response.user.email)",
            "appUserId=\(response.user.appUserId)",
            "tokenExpiresIn=\(response.expiresIn)s"
        ].joined(separator: "\n")
        if let displayName = response.user.displayName, !displayName.isEmpty {
            childName = displayName
        }
        self.client = client
        bind(client: client)
        renderState(latestState)
    } catch {
        auth = nil
        loginText = "登录失败"
        handleError(error.localizedDescription)
    }
    loginBusy = false
}
```

调用点解释：

| 代码 | 说明 |
|------|------|
| `makeClient(authHeader: nil)` | 登录接口不需要 Authorization，先创建未认证 client。 |
| `client.login(CustomerLoginParams(...))` | 调用客户后端登录接口。 |
| `normalized(loginEmail) ?? ""` | 去掉邮箱前后空白。 |
| `auth = CustomerAuth(response: response)` | 保存 token、用户和过期时间。 |
| `childName = displayName` | 如果登录返回 displayName，自动填到孩子名称。 |
| `self.client = client` | 保存当前 client。 |
| `bind(client: client)` | 绑定状态和错误回调。 |
| `loginBusy = false` | 登录结束，恢复按钮状态。 |

### 10.3 登录返回：CustomerLoginResponse

Demo 中使用了登录返回的这些字段：

```swift
auth = CustomerAuth(response: response)
loginText = [
    "已登录：\(response.user.displayName ?? response.user.email)",
    "appUserId=\(response.user.appUserId)",
    "tokenExpiresIn=\(response.expiresIn)s"
].joined(separator: "\n")
if let displayName = response.user.displayName, !displayName.isEmpty {
    childName = displayName
}
```

由 demo 可见登录返回至少包含：

| 字段 | Demo 用途 |
|------|-----------|
| `token` | 保存到 `CustomerAuth.token`，后续创建 Authorization。 |
| `tokenType` | 和 token 拼接成 Authorization header。 |
| `expiresIn` | 展示 token 过期时间。 |
| `user.appUserId` | Join 时传给 `StartSessionParams.appUserId`。 |
| `user.email` | 没有 displayName 时作为 UI 展示名。 |
| `user.displayName` | 自动填入 `childName`。 |

## 11. 加入会话：client.startSession

### 11.1 UI 输入

Session 输入区在 `ContentView.swift`：

```swift
DemoSectionTitle("Session")
DemoInputField(title: "Product ID", text: $vm.productId)
DemoInputField(title: "External Session ID", text: $vm.externalSessionId)
DemoInputField(title: "Child Name", text: $vm.childName)
DemoInputField(title: "Age", text: $vm.age)
DemoInputField(title: "Grade", text: $vm.grade)

HStack(spacing: 8) {
    DemoActionButton(title: "Join", backgroundColor: .blue) {
        vm.joinTapped()
    }
    .disabled(!vm.canJoin)

    DemoActionButton(title: "Leave", backgroundColor: .red) {
        vm.leaveTapped()
    }
    .disabled(!vm.canLeave || vm.isLeaving)
}
```

点击 Join：

```swift
func joinTapped() {
    Task { await join() }
}
```

### 11.2 Join 实现

Join 逻辑在 `DemoViewModel.join()`：

```swift
private func join() async {
    let trimmedChildName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
        lastError = ""
        guard let auth = auth else {
            handleError("请先登录客户后端")
            return
        }
        guard !trimmedChildName.isEmpty else {
            handleError("Child Name 不能为空")
            return
        }

        client?.close()
        let client = try makeClient(authHeader: auth.authorizationHeader)
        self.client = client
        client.setVadMode(vadMode)
        client.setVadPreset(vadPreset)
        bind(client: client)

        log("join start appUser=\(auth.user.appUserId) child=\(trimmedChildName) mode=\(vadMode.logLabel) preset=\(vadPreset.logLabel)")
        _ = try await client.startSession(
            StartSessionParams(
                appUserId: auth.user.appUserId,
                externalSessionId: blankAsNil(externalSessionId) ?? createLocalExternalSessionId(childName: trimmedChildName),
                childName: trimmedChildName,
                age: blankAsNil(age),
                grade: blankAsNil(grade),
                topic: blankAsNil(productId) ?? "speaking",
                interests: []
            )
        )
    } catch {
        handleError(error.localizedDescription)
    }
}
```

调用点解释：

| 代码 | 说明 |
|------|------|
| `guard let auth = auth` | 必须先登录客户后端。 |
| `guard !trimmedChildName.isEmpty` | 孩子名称不能为空。 |
| `client?.close()` | 如果已有旧 client，先释放。 |
| `makeClient(authHeader: auth.authorizationHeader)` | 创建带 Authorization 的 SDK client。 |
| `setVadMode(vadMode)` | 设置发言控制模式。 |
| `setVadPreset(vadPreset)` | 设置 VAD 预设。 |
| `bind(client: client)` | 先绑定状态回调，再 startSession，避免漏掉早期状态。 |
| `StartSessionParams(...)` | 组装会话参数。 |
| `client.startSession(...)` | 创建 session、获取媒体房间 token、连接媒体房间。 |

### 11.3 StartSessionParams 字段说明

Demo 中实际使用的字段：

```swift
StartSessionParams(
    appUserId: auth.user.appUserId,
    externalSessionId: blankAsNil(externalSessionId) ?? createLocalExternalSessionId(childName: trimmedChildName),
    childName: trimmedChildName,
    age: blankAsNil(age),
    grade: blankAsNil(grade),
    topic: blankAsNil(productId) ?? "speaking",
    interests: []
)
```

字段解释：

| 字段 | Demo 来源 | 说明 |
|------|-----------|------|
| `appUserId` | `auth.user.appUserId` | 客户侧用户 ID，建议传。 |
| `externalSessionId` | 页面输入或本地生成 | 客户业务系统自己的 session ID；为空时 demo 自动生成。 |
| `childName` | `childName` 输入框 | 孩子姓名或昵称，demo 要求非空。 |
| `age` | `age` 输入框 | 年龄，空字符串会转成 `nil`。 |
| `grade` | `grade` 输入框 | 年级，空字符串会转成 `nil`。 |
| `topic` | `productId` 输入框 | 产品/主题，空时默认 `speaking`。 |
| `interests` | demo 固定空数组 | 兴趣标签，客户可按业务传入。 |

空字符串处理：

```swift
private func blankAsNil(_ input: String) -> String? {
    normalized(input)
}

private func normalized(_ input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
```

本地生成 externalSessionId：

```swift
private func createLocalExternalSessionId(childName: String) -> String {
    let slug = childName
        .lowercased()
        .map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "." || character == ":" || character == "-") ? character : "-"
        }
    let normalizedSlug = String(slug).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let safeSlug = normalizedSlug.isEmpty ? "child" : normalizedSlug
    return "ios-\(safeSlug)-\(Int(Date().timeIntervalSince1970 * 1000))"
}
```

客户可扩展示例：

```swift
try await client.startSession(
    StartSessionParams(
        appUserId: auth.user.appUserId,
        externalSessionId: "classroom-session-20260520-001",
        childName: "Leo",
        age: "9",
        grade: "Grade 3",
        topic: "speaking",
        interests: ["football", "drawing"]
    )
)
```

## 12. 绑定 SDK 回调：onStateChanged / onSignal / onError

Demo 在 `bind(client:)` 中绑定回调：

```swift
private func bind(client: NewTypeSessionClient) {
    client.onStateChanged = { [weak self] state in
        Task { @MainActor in
            self?.apply(state: state)
        }
    }
    client.onSignal = { [weak self] signal in
        Task { @MainActor in
            self?.log("signal=\(String(reflecting: signal))")
        }
    }
    client.onError = { [weak self] message in
        Task { @MainActor in
            self?.handleError(message)
        }
    }
}
```

说明：

| 回调 | Demo 处理方式 | 适合用途 |
|------|---------------|----------|
| `onStateChanged` | 转回主线程后调用 `apply(state:)` | 渲染连接状态、转录、总结、按钮状态。 |
| `onSignal` | 打印信令日志 | 调试或高级场景观察细粒度事件。 |
| `onError` | 转回主线程后写入 `lastError` | toast、弹窗、错误区域展示。 |

多数业务界面只需要使用 `onStateChanged` 和 `onError`。`onSignal` 更适合日志或调试。

## 13. 接收并转换状态：NewTypeClientState -> DemoRoomState

SDK 回调进入 `apply(state:)`：

```swift
private func apply(state: NewTypeClientState) {
    latestState = DemoRoomState(state)
    if let errorMessage = state.errorMessage {
        lastError = errorMessage
    }
    renderState(latestState)
    log(
        "state phase=\(state.phase.logLabel) connection=\(state.connectionStatus.logLabel) " +
        "participants=\(state.participantCount) agent=\(state.agentPhase.logLabel)"
    )
}
```

Demo 自己定义了轻量状态 `DemoRoomState`：

```swift
private struct DemoRoomState: Equatable {
    let sessionId: String?
    let roomName: String?
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

    init(_ state: NewTypeClientState) {
        self.sessionId = state.sessionId
        self.roomName = state.roomName
        self.phase = state.phase
        self.connectionStatus = state.connectionStatus
        self.agentPhase = state.agentPhase
        self.agentMessage = state.agentMessage
        self.participantCount = state.participantCount
        self.micReady = state.micReady
        self.recording = state.recording
        self.turnBusy = state.turnBusy
        self.leaveRequested = state.leaveRequested
        self.transcript = state.transcript
        self.summary = state.summary
    }
}
```

Demo 中使用的 `NewTypeClientState` 字段：

| 字段 | Demo 用途 |
|------|-----------|
| `sessionId` | 展示当前 session ID。 |
| `roomName` | 展示当前媒体房间名称。 |
| `phase` | 展示会话阶段，控制按钮可用性。 |
| `connectionStatus` | 打印连接状态日志。 |
| `agentPhase` | 展示 Agent 当前阶段。 |
| `agentMessage` | 展示 Agent 当前提示文案。 |
| `participantCount` | 判断 Agent 是否入房，大于 1 显示“Agent 已入房”。 |
| `micReady` | 展示麦克风是否就绪。 |
| `recording` | 展示当前是否正在录音。 |
| `turnBusy` | 禁用 PTT，避免重复提交。 |
| `leaveRequested` | 禁用 Leave，避免重复离开。 |
| `transcript` | 渲染孩子转录和 AI 回复。 |
| `summary` | 渲染会话总结。 |
| `errorMessage` | 写入错误展示。 |

## 14. 渲染连接状态

状态渲染在 `renderState(_:)`：

```swift
private func renderState(_ state: DemoRoomState) {
    isRecording = state.recording
    statusText = [
        "phase=\(state.phase.logLabel)",
        "agent=\(state.agentPhase.logLabel) \(state.agentMessage)",
        "participants=\(state.participantCount) \(state.participantCount > 1 ? "(Agent 已入房)" : "(等待 Agent 入房...)")",
        "session=\(state.sessionId ?? "-")",
        "mode=\(vadMode.displayText)",
        "preset=\(vadPreset.displayText)",
        "",
        "=== 连接状态 ===",
        "房间：\(state.roomName ?? "-")",
        "客户后端：\(apiBaseUrl)",
        "登录：\(auth == nil ? "未登录" : "已登录")",
        "麦克风：\(state.micReady ? "就绪" : "未就绪")",
        "录音：\(state.recording ? "进行中" : "待机")"
    ].joined(separator: "\n")

    ...
}
```

对应 UI 展示在 `ContentView.swift`：

```swift
DemoSectionTitle("Status")
DemoOutputBox(text: vm.statusText, monospaced: true, minHeight: 160)
```

状态文本中最重要的字段：

| 文案 | 来源 | 说明 |
|------|------|------|
| `phase` | `state.phase` | 会话阶段。 |
| `agent` | `agentPhase` + `agentMessage` | Agent 当前状态和提示。 |
| `participants` | `participantCount` | 大于 1 通常表示 Agent 已入房。 |
| `session` | `sessionId` | 当前 session ID。 |
| `房间` | `roomName` | 当前媒体房间名称。 |
| `麦克风` | `micReady` | 麦克风是否就绪。 |
| `录音` | `recording` | 当前是否正在采集语音。 |

## 15. 渲染转录：TranscriptEntry

Demo 通过 `state.transcript` 渲染消息列表：

```swift
transcriptText = state.transcript
    .map { entry in
        let speaker = entry.speaker == .ai ? "AI" : "Child"
        let metaSuffix = (entry.meta?.isEmpty == false) ? "\n\(entry.meta ?? "")" : ""
        let streamingSuffix = entry.streaming ? " [streaming]" : ""
        return "\(speaker): \(entry.text)\(streamingSuffix)\(metaSuffix)"
    }
    .joined(separator: "\n\n")
if transcriptText.isEmpty {
    transcriptText = "暂无消息"
}
```

对应 UI：

```swift
DemoSectionTitle("Transcript")
DemoOutputBox(text: vm.transcriptText, monospaced: false, minHeight: 120)
```

由 demo 可见每条 transcript 至少包含：

| 字段 | Demo 用途 |
|------|-----------|
| `speaker` | 判断显示 `AI` 还是 `Child`。 |
| `text` | 显示消息正文。 |
| `meta` | 显示 IPA、纠错等补充信息。 |
| `streaming` | AI 流式回复时显示 `[streaming]`。 |

## 16. 渲染总结：SessionSummary

Demo 通过 `state.summary` 渲染总结：

```swift
summaryText = state.summary.map { summary in
    [
        summary.summary,
        "",
        "Did well: \(summary.didWell)",
        "Tip: \(summary.oneTip)",
        "Next: \(summary.nextTopic)",
        "Pronunciation: \(summary.pronunciationFocus)"
    ].joined(separator: "\n")
} ?? "暂无总结"
```

对应 UI：

```swift
DemoSectionTitle("Summary")
DemoOutputBox(text: vm.summaryText, monospaced: false, minHeight: 80)
```

Demo 中使用的 summary 字段：

| 字段 | 说明 |
|------|------|
| `summary` | 本次会话总结。 |
| `didWell` | 孩子做得好的地方。 |
| `oneTip` | 一个轻量建议。 |
| `nextTopic` | 下次话题。 |
| `pronunciationFocus` | 发音关注点。 |

`SessionSummary` 还包含 `learnedSentences`，demo 当前没有展示，但客户 App 建议展示为“今天学会的句子”：

```swift
if let summary = state.summary {
    learnedSentencesText = summary.learnedSentences
        .map { "• \($0)" }
        .joined(separator: "\n")
}
```

## 17. 控制按钮状态：SessionPhase 和 turnBusy

Demo 用计算属性控制按钮：

```swift
var isAuthenticated: Bool {
    auth != nil
}

var canLogin: Bool {
    !loginBusy && auth == nil && latestState.phase == .idle
}

var canLogout: Bool {
    auth != nil && latestState.phase == .idle
}

var canJoin: Bool {
    auth != nil && latestState.phase == .idle
}

var canLeave: Bool {
    latestState.phase == .connected
}

var canHoldToTalk: Bool {
    latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
}

var isLeaving: Bool {
    latestState.leaveRequested
}
```

UI 中使用这些属性：

```swift
DemoActionButton(title: "Login", backgroundColor: .blue) {
    vm.loginTapped()
}
.disabled(!vm.canLogin)

DemoActionButton(title: "Join", backgroundColor: .blue) {
    vm.joinTapped()
}
.disabled(!vm.canJoin)

DemoActionButton(title: "Leave", backgroundColor: .red) {
    vm.leaveTapped()
}
.disabled(!vm.canLeave || vm.isLeaving)

PressToTalkButton(
    title: "Hold to Talk",
    disabled: !vm.canHoldToTalk,
    isPressed: $isHoldingToTalk,
    onPress: { vm.startSpeakingTapped() },
    onRelease: { vm.stopSpeakingTapped() }
)
```

逻辑解释：

| 控件 | 启用条件 |
|------|----------|
| Login | 未登录、未登录中、会话处于 idle。 |
| Logout | 已登录、会话处于 idle。 |
| Join | 已登录、会话处于 idle。 |
| Leave | 会话处于 connected，且没有正在离开。 |
| Hold to Talk | 已连接、后端不忙、当前不是全自动模式。 |

常见 `SessionPhase`：

| 阶段 | UI 建议 |
|------|---------|
| `.idle` | 可登录、可 Join。 |
| `.requestingToken` | 禁用登录和 Join，显示加载。 |
| `.connecting` | 禁用登录和 Join，显示连接中。 |
| `.connected` | 启用 Leave，可按模式说话。 |
| `.leaving` | 显示离开中。 |
| `.error` | 展示错误，可允许重新登录/Join。 |

## 18. VAD 模式和发言控制

Demo 支持三种模式：

| UI 文案 | SDK 枚举 | 行为 |
|---------|----------|------|
| PTT | `VadMode.off` | 按住按钮说话，松开结束。 |
| 半自动 | `VadMode.semiAuto` | 手动启动，VAD 判断语音开始/结束。 |
| 全自动 | `VadMode.fullAuto` | VAD 自动检测语音开始/结束。 |

### 18.1 VAD Mode UI

`ContentView.swift` 中的模式选择：

```swift
DemoSectionTitle("VAD Mode")
Picker(
    "VAD Mode",
    selection: Binding(
        get: { vm.vadMode },
        set: { vm.vadModeChanged($0) }
    )
) {
    Text("PTT").tag(VadMode.off)
    Text("半自动").tag(VadMode.semiAuto)
    Text("全自动").tag(VadMode.fullAuto)
}
.pickerStyle(.segmented)
```

ViewModel 中切换模式：

```swift
func vadModeChanged(_ mode: VadMode) {
    vadMode = mode
    client?.setVadMode(mode)
    renderState(latestState)
}
```

### 18.2 VAD Preset UI

Demo 支持三种 VAD 预设：

| UI 文案 | SDK 枚举 | 建议场景 |
|---------|----------|----------|
| 灵敏 | `VADPreset.sensitive` | 安静环境、声音较小。 |
| 自然 | `VADPreset.natural` | 默认推荐。 |
| 儿童 | `VADPreset.child` | 儿童声音、停顿较长的场景。 |

`ContentView.swift` 中的预设选择：

```swift
DemoSectionTitle("VAD Preset")
Picker(
    "VAD Preset",
    selection: Binding(
        get: { vm.vadPreset },
        set: { vm.vadPresetChanged($0) }
    )
) {
    Text("灵敏").tag(VADPreset.sensitive)
    Text("自然").tag(VADPreset.natural)
    Text("儿童").tag(VADPreset.child)
}
.pickerStyle(.segmented)
```

ViewModel 中切换预设：

```swift
func vadPresetChanged(_ preset: VADPreset) {
    vadPreset = preset
    client?.setVadPreset(preset)
    renderState(latestState)
}
```

Join 前也会设置一次：

```swift
client.setVadMode(vadMode)
client.setVadPreset(vadPreset)
```

### 18.3 PTT 按钮

`ContentView.swift` 中的 PTT 按钮：

```swift
PressToTalkButton(
    title: "Hold to Talk",
    disabled: !vm.canHoldToTalk,
    isPressed: $isHoldingToTalk,
    onPress: { vm.startSpeakingTapped() },
    onRelease: { vm.stopSpeakingTapped() }
)
```

按钮内部用 `DragGesture(minimumDistance: 0)` 模拟按住说话：

```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in
            guard !disabled, !isPressed else { return }
            isPressed = true
            onPress()
        }
        .onEnded { _ in
            guard isPressed else { return }
            isPressed = false
            onRelease()
        }
)
```

ViewModel 对应入口：

```swift
func startSpeakingTapped() {
    guard !isPushToTalkActive else { return }
    isPushToTalkActive = true
    Task { await startSpeaking() }
}

func stopSpeakingTapped() {
    guard isPushToTalkActive || latestState.recording else { return }
    isPushToTalkActive = false
    Task { await stopSpeaking() }
}
```

实际调用 SDK：

```swift
private func startSpeaking() async {
    guard let client = client else { return }
    do {
        log("ptt start")
        try await client.startSpeaking()
    } catch {
        isPushToTalkActive = false
        handleError(error.localizedDescription)
    }
}

private func stopSpeaking() async {
    guard let client = client else {
        isPushToTalkActive = false
        return
    }
    do {
        log("ptt stop")
        try await client.stopSpeaking()
    } catch {
        handleError(error.localizedDescription)
    }
}
```

不同模式下建议：

| 模式 | 是否需要 PTT 按钮 |
|------|-------------------|
| `.off` | 需要，按下开始、松开结束。 |
| `.semiAuto` | 可用，按下开始半自动监听，松开/取消结束。 |
| `.fullAuto` | 不需要，demo 会禁用 PTT 按钮。 |

页面消失时，如果还处于按住说话状态，demo 会主动停止：

```swift
.onDisappear {
    if isHoldingToTalk {
        vm.stopSpeakingTapped()
        isHoldingToTalk = false
    }
}
```

## 19. 结束会话和释放资源

### 19.1 用户主动结束：endSession

`ContentView.swift` 中 Leave 按钮：

```swift
DemoActionButton(title: "Leave", backgroundColor: .red) {
    vm.leaveTapped()
}
.disabled(!vm.canLeave || vm.isLeaving)
```

ViewModel 入口：

```swift
func leaveTapped() {
    Task { await leave() }
}
```

实现：

```swift
private func leave() async {
    guard let client = client else { return }
    do {
        log("leave requested")
        try await client.endSession(reason: "user-leave")
    } catch {
        handleError(error.localizedDescription)
    }
}
```

说明：

- `endSession(reason: "user-leave")` 会结束当前 session 并断开媒体房间。
- `reason` 可以按业务自定义，例如 `user-leave`、`timeout`、`page-close`。

### 19.2 登出：logoutTapped

Demo 只允许 idle 状态下登出：

```swift
func logoutTapped() {
    guard latestState.phase == .idle else { return }
    auth = nil
    loginText = "未登录客户后端"
    lastError = ""
    client?.close()
    client = nil
    renderState(latestState)
}
```

### 19.3 释放资源：close

Demo 在登出和重新 Join 前会调用：

```swift
client?.close()
```

建议客户 App 在 ViewModel `deinit`、页面销毁或用户退出流程中也调用：

```swift
deinit {
    client?.close()
}
```

说明：

| 代码 | 说明 |
|------|------|
| `client?.close()` | 释放 SDK 内部资源、断开连接、停止音频/VAD。 |
| `client = nil` | 清空引用，避免继续使用旧 client。 |

## 20. Demo 页面字段与代码对应表

| UI 控件 | ViewModel 字段/方法 | 作用 |
|---------|---------------------|------|
| Customer Backend URL | `apiBaseUrl` / `makeClient()` | 创建 `NewTypeConfig.backendBaseUrl`。 |
| Email | `loginEmail` / `login()` | 传给 `CustomerLoginParams.email`。 |
| Password | `loginPassword` / `login()` | 传给 `CustomerLoginParams.password`。 |
| Login | `loginTapped()` | 触发客户后端登录。 |
| Logout | `logoutTapped()` | 清理登录态并释放 client。 |
| 登录状态框 | `loginText` | 展示登录用户、appUserId、token 过期时间。 |
| Product ID | `productId` | 传给 `StartSessionParams.topic`。 |
| External Session ID | `externalSessionId` | 传给 `StartSessionParams.externalSessionId`，为空时本地生成。 |
| Child Name | `childName` | 传给 `StartSessionParams.childName`。 |
| Age | `age` | 传给 `StartSessionParams.age`。 |
| Grade | `grade` | 传给 `StartSessionParams.grade`。 |
| Join | `joinTapped()` | 创建并加入会话。 |
| Leave | `leaveTapped()` | 结束会话。 |
| VAD Mode | `vadMode` / `vadModeChanged()` | 切换 PTT、半自动、全自动。 |
| VAD Preset | `vadPreset` / `vadPresetChanged()` | 切换灵敏、自然、儿童。 |
| Hold to Talk | `startSpeakingTapped()` / `stopSpeakingTapped()` | 手动发言控制。 |
| Status | `statusText` | 展示连接和 Agent 状态。 |
| Transcript | `transcriptText` | 展示转录和 AI 回复。 |
| Summary | `summaryText` | 展示会话总结。 |
| Error | `lastError` | 展示错误。 |

## 21. 客户后端接口返回约定

虽然 demo 不直接实现客户后端，但从 demo 的 SDK 调用可以看出客户后端需要支持以下能力。

### 21.1 登录接口

Demo 调用：

```swift
client.login(
    CustomerLoginParams(
        email: normalized(loginEmail) ?? "",
        password: loginPassword
    )
)
```

默认路径由 SDK 配置决定。Demo 的登录逻辑使用 `NewTypeSessionClient.login(...)`，客户后端需返回 demo 使用到的字段：

```swift
token
tokenType
expiresIn
user.appUserId
user.email
user.displayName
```

推荐返回示例：

```json
{
  "token": "customer-jwt",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "appUserId": "user-123",
    "email": "demo@example.com",
    "displayName": "Leo",
    "created": false
  }
}
```

### 21.2 创建 Session 接口

Demo 调用：

```swift
client.startSession(StartSessionParams(...))
```

Demo 配置的路径：

```text
POST /app/sessions
Authorization: Bearer <customerToken>
```

请求中的业务字段来自 `StartSessionParams`：

```text
appUserId
externalSessionId
childName
age
grade
topic
interests
```

### 21.3 获取媒体房间 Token 接口

Join 内部还会请求媒体房间 token。Demo 配置的路径：

```text
POST /app/sessions/{sessionId}/livekit-token
Authorization: Bearer <customerToken>
```

客户后端需要返回媒体房间连接信息，关键字段包括：

| 字段 | 说明 |
|------|------|
| `token` | 媒体房间入房 token。 |
| `url` | 媒体房间 WebSocket 地址，例如 `wss://media.example.com`。 |
| `identity` | 当前用户身份。 |
| `roomName` | 房间名。 |
| `expiresIn` | token 有效期。 |

### 21.4 结束 Session 接口

Demo 调用：

```swift
client.endSession(reason: "user-leave")
```

SDK 会通知客户后端结束 session。通常对应：

```text
POST /app/sessions/{sessionId}/end
Authorization: Bearer <customerToken>
```

## 22. 常见问题排查

### 22.1 Login 按钮不可用

Demo 中 Login 按钮启用条件：

```swift
var canLogin: Bool {
    !loginBusy && auth == nil && latestState.phase == .idle
}
```

如果已经登录、正在登录或会话不是 idle，Login 会被禁用。

### 22.2 Join 按钮不可用

Demo 中 Join 按钮启用条件：

```swift
var canJoin: Bool {
    auth != nil && latestState.phase == .idle
}
```

因此必须先登录客户后端，并且当前会话处于 idle。

### 22.3 登录客户后端失败

检查：

1. `apiBaseUrl` 是否填写客户后端地址。
2. 模拟器访问本机可用 `http://localhost:8090`，真机不能使用 `localhost`。
3. 真机需要填写后端机器在同一局域网中的 IP。
4. 客户后端是否监听 `0.0.0.0`。
5. 如果是 HTTP，iOS 工程是否配置 ATS 明文流量例外。
6. 手机 Safari 是否能访问客户后端健康检查地址。
7. Email 和 Password 是否符合客户后端 demo 账号要求。

### 22.4 登录成功但 Join 失败

检查：

1. `auth.authorizationHeader` 是否正常生成。
2. `makeClient(authHeader: auth.authorizationHeader)` 是否执行。
3. `sessionPath` 是否为客户后端路径 `/app/sessions`。
4. `tokenPath` 是否为 `/app/sessions/{sessionId}/livekit-token`。
5. `liveKitTokenMode` 是否与后端一致，当前 demo 使用 `.userTokenInBody`。
6. customer token 是否过期。

### 22.5 已连接但没有 AI 回复

检查：

1. `statusText` 中 `phase` 是否为 `CONNECTED`。
2. `participants` 是否大于 1。大于 1 表示 Agent 已入房。
3. `agentMessage` 或 `lastError` 是否提示错误。
4. 是否授权麦克风权限。
5. 如果当前是 PTT 模式，是否按下并松开了 Hold to Talk。
6. 如果当前是全自动模式，是否尝试切换 `VADPreset.child`。
7. 客户后端返回的媒体房间 `url` 和 `token` 是否正确。

### 22.6 PTT 按钮不可用

Demo 中 PTT 按钮启用条件：

```swift
var canHoldToTalk: Bool {
    latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
}
```

因此以下情况会禁用：

- 未连接成功。
- 后端正在处理上一轮，即 `turnBusy=true`。
- 当前是 `VadMode.fullAuto`。

### 22.7 VAD 太早截断孩子说话

Demo 可切到“儿童”预设：

```swift
client?.setVadPreset(.child)
```

UI 操作是在 VAD Preset 中选择“儿童”。

### 22.8 退出页面后仍占用麦克风

确认业务侧在页面销毁或 ViewModel 释放时调用：

```swift
client?.close()
```

如果用户主动退出，也应调用：

```swift
try await client.endSession(reason: "user-leave")
```

## 23. 客户 App 最小接入代码

下面是一份基于 demo 写法整理的最小接入骨架：

```swift
import SwiftUI
import NewTypeSDK

@MainActor
final class SpeakingViewModel: ObservableObject {
    @Published var statusText = ""
    @Published var transcriptText = "暂无消息"
    @Published var summaryText = "暂无总结"
    @Published var lastError = ""

    private var client: NewTypeSessionClient?
    private var authHeader: String?

    func start() async {
        do {
            let endpoint = try EndpointUrl.parse("https://customer-api.example.com")
            let config = NewTypeConfig(
                backendBaseUrl: endpoint,
                sessionPath: "/app/sessions",
                tokenPath: "/app/sessions/{sessionId}/livekit-token",
                liveKitTokenMode: .userTokenInBody
            )

            let loginClient = NewTypeSessionClient.create(config: config)
            let login = try await loginClient.login(
                CustomerLoginParams(
                    email: "demo@example.com",
                    password: "demo-password-change-me"
                )
            )
            authHeader = "\(login.tokenType) \(login.token)"
            loginClient.close()

            let provider = AnyAuthHeaderProvider { [authHeader] in
                authHeader ?? ""
            }
            let client = NewTypeSessionClient.create(
                config: config,
                authHeaderProvider: provider
            )
            self.client = client

            client.onStateChanged = { [weak self] state in
                Task { @MainActor in
                    self?.statusText = "phase=\(state.phase.rawValue) agent=\(state.agentPhase.rawValue)"
                    self?.transcriptText = state.transcript
                        .map { "\($0.speaker): \($0.text)" }
                        .joined(separator: "\n\n")
                    if let summary = state.summary {
                        self?.summaryText = summary.summary
                    }
                }
            }
            client.onError = { [weak self] message in
                Task { @MainActor in
                    self?.lastError = message
                }
            }

            client.setVadMode(.fullAuto)
            client.setVadPreset(.child)

            try await client.startSession(
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
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        do {
            try await client?.endSession(reason: "user-leave")
        } catch {
            lastError = error.localizedDescription
        }
        client?.close()
        client = nil
    }

    deinit {
        client?.close()
    }
}
```

如果客户产品使用 PTT 模式：

```swift
client.setVadMode(.off)

func pressToTalkDown() {
    Task {
        try await client.startSpeaking()
    }
}

func pressToTalkUp() {
    Task {
        try await client.stopSpeaking()
    }
}
```

## 24. 生产接入建议

1. 生产环境建议业务 App 自己完成登录，然后把 customer token 传给 SDK，不建议在 SDK 内保存固定账号密码。
2. `apiBaseUrl` 生产环境建议使用 HTTPS。
3. 不要在 UI 或日志中输出完整 token。
4. 先调用 `bind(client:)` 或设置 `onStateChanged`，再调用 `startSession(...)`，避免漏掉早期状态。
5. UI 应基于 `state.phase`、`state.turnBusy`、`state.recording` 控制按钮。
6. 儿童自然对话建议默认 `VadMode.fullAuto + VADPreset.child`。
7. 现场演示或噪声环境建议使用 `VadMode.off` PTT。
8. 用户主动结束调用 `endSession(reason:)`，页面销毁调用 `close()`。
9. 真机 HTTP 调试只在开发环境打开 ATS 明文流量例外，生产使用 HTTPS。
10. `childName`、`age`、`grade`、`topic` 在调用 `startSession()` 前做 trim 和非空校验。

## 25. 最小交付清单

客户 App 接入时至少需要完成：

- 在 Podfile 中引入 `NewTypeSDK`。
- 放置 `NewTypeSDK.xcframework` 和 `NewTypeSDK-Binary.podspec`。
- 执行 `pod install` 并使用 `.xcworkspace` 打开工程。
- 配置麦克风权限 `NSMicrophoneUsageDescription`。
- 如果客户后端是 HTTP，配置 ATS 明文流量例外。
- 创建 `NewTypeConfig(backendBaseUrl: ...)`。
- 创建 `NewTypeSessionClient`。
- 调用 `client.login(CustomerLoginParams(...))` 或由业务登录后提供 customer token。
- 使用 `AnyAuthHeaderProvider` 创建带 Authorization 的 client。
- 构造 `StartSessionParams`。
- 调用 `client.startSession(...)`。
- 监听 `client.onStateChanged` 渲染连接状态、对话转录、会话总结。
- 监听 `client.onError` 展示错误事件。
- 根据产品体验设置 `VadMode` 和 `VADPreset`。
- 用户结束时调用 `endSession(reason:)`。
- 页面销毁时调用 `close()`。
