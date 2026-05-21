# NewType iOS SDK 客户接入链路说明

本文面向客户 App 工程师，严格按照当前demo工程实现说明从登录客户后端、创建会话、获取媒体房间连接凭证、连接媒体房间、监听状态、发言控制到结束会话的完整接入链路。

核心边界：

- 客户 App 自己请求客户后端完成登录和业务会话创建。
- 客户后端返回媒体房间连接凭证给 App。
- App 将连接凭证传给 NewType SDK。
- NewType SDK 负责连接媒体房间、维护 WebSocket/实时音频链路、管理麦克风和 VAD、输出状态/转录/总结/错误。

当前 demo 的核心代码在 `Features/RTC/DemoViewModel.swift`，UI 在 `UI/ContentView.swift`。

## 1. 客户需要先准备什么

### 1.1 iOS 工程依赖

Demo 通过 CocoaPods 引入二进制 SDK：

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

| 项目 | 说明 |
|------|------|
| `NewTypeSDK.xcframework` | NewType iOS SDK 二进制包，放在 `libs/` 下。 |
| `NewTypeSDK-Binary.podspec` | 本地二进制 pod 声明。 |
| `platform :ios, "13.4"` | Demo 最低 iOS 版本。 |
| `use_frameworks! :linkage => :static` | Demo 当前使用静态 framework 链接。 |

执行：

```bash
cd newtypesdk_demo_ios
pod install
open newtypesdk_demo_ios.xcworkspace
```

安装后必须打开 `.xcworkspace`。

### 1.2 系统权限和网络

必须配置麦克风权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>用于英语口语陪练时采集孩子的语音。</string>
```

如果客户后端是局域网 HTTP，例如 `http://192.168.0.12:8090`，开发环境需要配置 ATS 明文流量例外。生产环境建议使用 HTTPS。

## 2. 整体链路

```text
1. App 展示客户后端地址、邮箱、密码等输入
2. App 调客户后端 POST /auth/login
3. App 保存客户 token 和用户信息
4. App 根据 token 调客户后端 POST /app/sessions 创建业务会话
5. 客户后端直接返回媒体房间凭证，或 App 再调 POST /app/sessions/{sessionId}/livekit-token 获取凭证
6. App 创建 NewTypeSessionClient
7. App 配置 VAD 模式和 VAD 预设
8. App 绑定 SDK 状态、信令和错误回调
9. App 调 client.connect(NewTypeConnectionCredential)
10. SDK 连接媒体房间并维护实时链路
11. App 从 SDK 状态中渲染连接阶段、参与者、麦克风、录音、转录、总结
12. 用户说话时 App 调 startSpeaking()/stopSpeaking()，全自动模式可不手动调用
13. 用户离开时 App 调 endSession(reason:) 并通知客户后端结束会话
14. 页面销毁或登出时 App 调 close() 释放资源
```

注意：当前 demo 不再让 SDK 直接登录客户后端或创建业务 session。登录、创建 session、结束 session 都在 demo 的 `CustomerBackendApi` 中由 App 层完成。

## 3. 哪些后端接口可以由客户自定义

Demo 中的客户后端路径、请求字段和响应包装结构只是演示实现，客户正式接入时可以使用自己的后端接口定义。SDK 不关心客户后端的路径叫什么，也不关心客户 App 如何登录、如何创建业务订单或如何组织业务字段；SDK 只关心 App 最终传给 `client.connect(...)` 的连接凭证是否完整。

| Demo 内容 | 客户是否可自定义 | SDK 是否直接依赖 | 说明 |
|-----------|------------------|------------------|------|
| `POST /auth/login` | 可以 | 不依赖 | 客户可使用已有登录体系、手机号登录、OAuth、匿名登录等；只要 App 能拿到后续调用客户后端所需的认证信息。 |
| 登录请求 `email/password` | 可以 | 不依赖 | Demo 只是用邮箱密码演示，生产可替换为客户自己的登录参数。 |
| 登录响应 `token/tokenType/expiresIn/user` | 可以 | 不直接依赖 | Demo 用这些字段保存登录态和展示 UI；SDK 不读取登录响应。 |
| `POST /app/sessions` | 可以 | 不依赖路径 | 客户可改成自己的创建会话接口；App 只需要最终拿到媒体房间连接凭证。 |
| 创建会话请求字段 | 可以 | 不依赖 | `appUserId`、`externalSessionId`、`childName`、`age`、`grade`、`topic`、`interests`、`identity` 是 demo 示例字段，客户可增删或改名。 |
| `POST /app/sessions/{sessionId}/livekit-token` | 可以 | 不依赖路径 | Demo 在创建会话响应没有直接返回凭证时才请求该接口；客户也可以在创建会话接口中一次性返回凭证。 |
| `POST /app/sessions/{sessionId}/end` | 可以 | 不依赖 | 业务结束上报由 App 自己调客户后端；SDK 只负责结束/断开实时会话。 |
| `NewTypeConnectionCredential` | 不可缺字段 | 直接依赖 | 这是 SDK 的连接入参，字段名和含义必须按 SDK 要求构造。 |

客户后端必须最终给 App 提供这些 SDK 连接字段：

| SDK 字段 | 必须 | 说明 |
|----------|------|------|
| `sessionId` | 是 | NewType 会话 ID，用于 SDK 状态、信令和结束流程关联。 |
| `roomName` | 是 | 媒体房间名称。 |
| `connectionUrl` | 是 | 媒体服务器 WebSocket 地址。 |
| `connectionToken` | 是 | App 进入媒体房间的连接凭证。 |
| `identity` | 是 | 当前用户在媒体房间中的身份。 |
| `expiresIn` | 否 | 凭证有效期，demo 透传给 SDK；没有时可传 `nil`。 |

也就是说，客户可以完全替换 `CustomerBackendApi`、接口路径、请求/响应 data class 和鉴权方式，但不能省略 `connect(...)` 所需的 `sessionId`、`roomName`、`connectionUrl`、`connectionToken`、`identity`。

## 4. 登录客户后端

UI 字段在 `UI/ContentView.swift`：

| UI | ViewModel 字段 | 说明 |
|----|----------------|------|
| Customer Backend URL | `apiBaseUrl` | 客户后端地址，默认 `http://localhost:8090`。 |
| Email | `loginEmail` | 登录邮箱。 |
| Password | `loginPassword` | 登录密码。 |
| Login | `loginTapped()` | 触发登录。 |
| Logout | `logoutTapped()` | 清理登录态并释放 SDK client。 |

登录入口：

```swift
func loginTapped() {
    Task { await login() }
}
```

Demo 实际调用客户后端：

```swift
private func login() async {
    do {
        lastError = ""
        loginBusy = true
        loginText = "正在登录客户后端..."
        let backend = try buildCustomerBackendApi()
        let response = try await backend.login(
            email: normalized(loginEmail) ?? "",
            password: loginPassword
        )
        auth = CustomerAuth(response: response)
        loginText = [
            "已登录：\(response.user.displayName ?? response.user.email)",
            "appUserId=\(response.user.appUserId)",
            "tokenExpiresIn=\(response.expiresIn)s",
            "token=\(response.tokenPreview)"
        ].joined(separator: "\n")
        if let displayName = response.user.displayName, !displayName.isEmpty {
            childName = displayName
        }
        renderState(latestState)
    } catch {
        auth = nil
        loginText = "登录失败"
        handleError(error.localizedDescription)
    }
    loginBusy = false
}
```

客户后端登录接口：

> 可自定义：`/auth/login`、请求体和响应体都是 demo 为了展示完整流程而定义的示例。客户正式接入时可以使用自己的登录接口，甚至可以不在此页面登录，而是直接复用业务 App 已有登录态。SDK 不直接调用该接口。

```text
POST /auth/login
Content-Type: application/json
Accept: application/json
```

请求体：

```json
{
  "email": "demo@example.com",
  "password": "demo-password-change-me"
}
```

Demo 需要的响应字段：

```json
{
  "token": "customer-token",
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

Demo 保存的登录态：

```swift
private struct CustomerAuth: Equatable {
    let token: String
    let tokenType: String
    let expiresIn: Int
    let user: DemoCustomerUser

    var authorizationHeader: String {
        "\(tokenType) \(token)"
    }
}
```

当前 demo 在创建 session 时实际使用 `auth.token`，并在请求头中拼成：

```text
Authorization: Bearer <customer-token>
```

这里的 `customer-token` 只用于 App 请求客户自己的后端。SDK 不读取该 token；SDK 只使用后面构造出来的媒体房间连接凭证。

## 5. 创建会话并获取媒体房间连接凭证

用户点击 Join 后进入：

```swift
func joinTapped() {
    Task { await join() }
}
```

Join 前 demo 会做这些事：

1. 检查是否已登录。
2. 检查 `childName` 非空。
3. 关闭旧 client：`client?.close()`。
4. 创建新的 SDK client：`NewTypeSessionClient.create(config: NewTypeConfig())`。
5. 设置 VAD 模式和预设。
6. 绑定 SDK 回调。
7. 调客户后端创建会话并拿到连接凭证。
8. 调 SDK `connect(...)` 进入媒体房间。

核心代码：

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
        let backend = try buildCustomerBackendApi()
        let client = NewTypeSessionClient.create(config: NewTypeConfig())
        self.client = client
        client.setVadMode(vadMode)
        client.setVadPreset(vadPreset)
        bind(client: client)

        let credential = try await backend.startRealtimeSession(
            customerToken: auth.token,
            request: StartRealtimeSessionRequest(
                appUserId: auth.user.appUserId,
                externalSessionId: blankAsNil(externalSessionId) ?? createLocalExternalSessionId(childName: trimmedChildName),
                childName: trimmedChildName,
                age: blankAsNil(age),
                grade: blankAsNil(grade),
                topic: blankAsNil(productId) ?? "speaking",
                interests: [],
                identity: trimmedChildName
            )
        )
        activeSessionId = credential.sessionId
        try await client.connect(
            .init(
                sessionId: credential.sessionId,
                roomName: credential.roomName,
                connectionUrl: credential.connectionUrl,
                connectionToken: credential.connectionToken,
                identity: credential.identity,
                expiresIn: credential.expiresIn
            )
        )
    } catch {
        handleError(error.localizedDescription)
    }
}
```

### 5.1 创建会话请求

接口：

> 可自定义：`/app/sessions` 是 demo 的客户后端示例路径。客户可以改成自己的创建会话接口，也可以把创建订单、选择课程、风控校验、创建 NewType 会话等逻辑合并在客户自己的后端流程中。SDK 不直接调用该接口。

```text
POST /app/sessions
Authorization: Bearer <customer-token>
Content-Type: application/json
Accept: application/json
```

Demo 请求模型如下，正式接入时可替换为客户自己的请求模型：

```swift
private struct StartRealtimeSessionRequest: Encodable {
    let appUserId: String
    let externalSessionId: String?
    let childName: String?
    let age: String?
    let grade: String?
    let topic: String
    let interests: [String]
    let identity: String
}
```

字段说明：

| 字段 | Demo 来源 | 说明 |
|------|-----------|------|
| `appUserId` | 登录返回的 `user.appUserId` | 客户侧用户 ID。 |
| `externalSessionId` | UI 输入或本地生成 | 客户业务会话 ID；空时 demo 生成 `ios-<child>-<timestamp>`。 |
| `childName` | Child Name | 孩子姓名或昵称，Join 时要求非空。 |
| `age` | Age | 年龄，空字符串转为 `nil`。 |
| `grade` | Grade | 年级，空字符串转为 `nil`。 |
| `topic` | Product ID | 产品或主题，空时默认 `speaking`。 |
| `interests` | demo 固定空数组 | 兴趣标签，客户可按业务传。 |
| `identity` | `childName` | 当前用户在媒体房间中的身份。 |

这些创建会话请求字段都属于客户 App 与客户后端之间的业务协议，不是 SDK 强制字段。客户可按自己的业务传 `lessonId`、`courseId`、`childId`、订单号、设备信息、风控字段等。客户后端需要基于这些业务字段创建 NewType 会话，并把 SDK 连接所需字段返回给 App。

### 5.2 创建会话响应

Demo 支持两种返回方式。

> 可自定义：创建会话响应的外层结构也可以由客户自定义。Demo 使用 `session + realtime` 或 `session + userToken` 只是为了展示两种常见方式。客户后端可以一次性返回 SDK 连接字段，也可以分两步返回；App 只需要最终映射出 `NewTypeConnectionCredential`。

方式 A：`POST /app/sessions` 直接返回媒体房间连接信息：

```json
{
  "session": {
    "sessionId": "session-123",
    "roomName": "room-123"
  },
  "realtime": {
    "token": "media-room-token",
    "url": "wss://media.example.com",
    "identity": "Leo",
    "roomName": "room-123",
    "expiresIn": 3600
  }
}
```

方式 B：`POST /app/sessions` 返回 `userToken`，App 再请求媒体房间连接凭证：

```json
{
  "session": {
    "sessionId": "session-123",
    "roomName": "room-123"
  },
  "userToken": {
    "token": "customer-user-token",
    "tokenType": "Bearer",
    "expiresIn": 3600
  }
}
```

然后 demo 调用：

```text
POST /app/sessions/{sessionId}/livekit-token
Authorization: Bearer <customer-token>
Content-Type: application/json
Accept: application/json
```

请求体：

```json
{
  "userToken": "customer-user-token"
}
```

响应体：

```json
{
  "token": "media-room-token",
  "url": "wss://media.example.com",
  "identity": "Leo",
  "roomName": "room-123",
  "expiresIn": 3600
}
```

## 6. 传给 SDK 的连接凭证

Demo 把客户后端返回转换为 SDK 入参：

```swift
try await client.connect(
    .init(
        sessionId: credential.sessionId,
        roomName: credential.roomName,
        connectionUrl: credential.connectionUrl,
        connectionToken: credential.connectionToken,
        identity: credential.identity,
        expiresIn: credential.expiresIn
    )
)
```

SDK 需要的字段：

| 字段 | 必须 | Demo 来源 | 说明 |
|------|------|-----------|------|
| `sessionId` | 是 | `session.sessionId` | NewType 会话 ID，SDK 用它关联状态、信令和结束流程。 |
| `roomName` | 是 | 凭证或 `session.roomName` | 媒体房间名称，SDK 用它进入正确房间。 |
| `connectionUrl` | 是 | 凭证 `url` | 媒体服务器 WebSocket 地址，SDK 用它建立实时连接。 |
| `connectionToken` | 是 | 凭证 `token` | 进入媒体房间的连接凭证，SDK 用它完成鉴权。 |
| `identity` | 是 | 凭证 `identity` | 当前用户在媒体房间中的身份，需与后端签发凭证时一致。 |
| `expiresIn` | 否 | 凭证 `expiresIn` | 凭证有效期，demo 透传给 SDK；没有时可传 `nil`。 |

客户 App 正式接入时可以替换自己的网络层、接口路径和响应结构，只要最终能构造出这个连接凭证并调用 `connect(...)`。如果客户后端返回字段名不同，例如 `wsUrl`、`accessToken`、`room`，App 层需要映射为 SDK 要求的 `connectionUrl`、`connectionToken`、`roomName`。

最小可用响应示例，客户后端字段名可不同，但语义必须完整：

```json
{
  "sessionId": "session-123",
  "roomName": "room-123",
  "connectionUrl": "wss://media.example.com",
  "connectionToken": "media-room-token",
  "identity": "Leo",
  "expiresIn": 3600
}
```

## 7. SDK client 生命周期

Demo 中的生命周期策略：

| 场景 | 代码 | 说明 |
|------|------|------|
| Join 前 | `client?.close()` | 关闭旧 client，避免复用旧房间/旧状态。 |
| Join 时 | `NewTypeSessionClient.create(config: NewTypeConfig())` | 创建新的 SDK client。 |
| Join 前 | `client.setVadMode(vadMode)` / `client.setVadPreset(vadPreset)` | 连接前先设置发言控制。 |
| Join 前 | `bind(client: client)` | 先绑定回调再 connect，避免漏早期状态。 |
| Leave 时 | `client.endSession(reason: "user-leave")` | SDK 结束并离开媒体房间。 |
| Logout 时 | `client?.close()` | 清理 SDK 资源。 |
| ViewModel 销毁时 | 建议 `client?.close()` | 防止麦克风和实时链路未释放。 |

当前 demo 在 `logoutTapped()` 中调用 `close()`，在重新 Join 前也调用 `close()`。

## 8. 监听 SDK 状态、信令和错误

Demo 绑定回调：

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

建议客户产品优先使用：

- `onStateChanged`：渲染 UI 的主入口，包含连接状态、参与者、麦克风、录音、转录、总结。
- `onError`：展示错误 toast、弹窗或错误区域。
- `onSignal`：高级日志或排查使用，业务 UI 通常不需要直接依赖。

Demo 收到状态后转换为 `DemoRoomState`：

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

## 9. 状态字段怎么用

Demo 使用的 `NewTypeClientState` 字段：

| 字段 | Demo 用途 | 客户接入建议 |
|------|-----------|--------------|
| `sessionId` | 展示当前 session | 作为业务排查 ID。 |
| `roomName` | 展示当前房间 | 排查媒体房间问题。 |
| `phase` | 控制 Login/Join/Leave/PTT 按钮 | UI 主状态机。 |
| `connectionStatus` | 打印日志 | 排查连接过程。 |
| `agentPhase` | 展示 Agent 阶段 | 告诉用户当前是等待、开场、聆听、处理或收尾。 |
| `agentMessage` | 展示提示文案 | 可直接作为状态提示。 |
| `participantCount` | 判断 Agent 是否入房 | 大于 1 时 demo 显示“Agent 已入房”。 |
| `micReady` | 展示麦克风是否就绪 | 未就绪时提示授权或重试。 |
| `recording` | 展示是否录音中 | 控制录音动效。 |
| `turnBusy` | 禁用 PTT | 后端正在处理上一轮时避免重复提交。 |
| `leaveRequested` | 禁用 Leave | 防止重复离开。 |
| `transcript` | 渲染对话文本 | 展示孩子转录和 AI 回复。 |
| `summary` | 渲染会话总结 | 结束后展示学习反馈。 |
| `errorMessage` | 写入错误区 | 兜底错误展示。 |

Demo 展示状态：

```swift
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
```

常用阶段：

| `SessionPhase` | 说明 | UI 建议 |
|----------------|------|---------|
| `.idle` | 空闲或已断开 | 可 Login、Join。 |
| `.requestingToken` | 正在准备连接凭证或连接前置请求 | 禁用 Join，显示加载。 |
| `.connecting` | 正在连接媒体房间 | 禁用 Join，显示连接中。 |
| `.connected` | 已连接 | 启用 Leave，按模式允许说话。 |
| `.leaving` | 正在离开 | 禁用 Leave，显示离开中。 |
| `.error` | 错误 | 展示错误，允许用户重试。 |

## 10. 转录和总结

转录渲染：

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

`TranscriptEntry` 关键字段：

| 字段 | 说明 |
|------|------|
| `speaker` | `.child` 或 `.ai`。 |
| `text` | 文本内容。 |
| `meta` | 补充信息，例如发音或纠错信息。 |
| `streaming` | 是否为流式中的临时文本。 |

总结渲染：

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

`SessionSummary` 常用字段：

| 字段 | 说明 |
|------|------|
| `summary` | 本次会话总结。 |
| `didWell` | 做得好的地方。 |
| `oneTip` | 一个建议。 |
| `nextTopic` | 下次话题。 |
| `pronunciationFocus` | 发音关注点。 |
| `learnedSentences` | 学到的句子，demo 当前未展示。 |

## 11. VAD 模式和发言控制

Demo 支持三种模式：

| UI | SDK 枚举 | 行为 |
|----|----------|------|
| PTT | `.off` | 按住按钮开始说话，松开结束。 |
| 半自动 | `.semiAuto` | 手动启动一轮，VAD 辅助判断。 |
| 全自动 | `.fullAuto` | SDK 自动检测开始和结束，demo 禁用 PTT 按钮。 |

切换模式：

```swift
func vadModeChanged(_ mode: VadMode) {
    vadMode = mode
    client?.setVadMode(mode)
    renderState(latestState)
}
```

切换预设：

```swift
func vadPresetChanged(_ preset: VADPreset) {
    vadPreset = preset
    client?.setVadPreset(preset)
    renderState(latestState)
}
```

预设：

| UI | SDK 枚举 | 建议场景 |
|----|----------|----------|
| 灵敏 | `.sensitive` | 安静环境、轻声说话。 |
| 自然 | `.natural` | 默认平衡方案。 |
| 儿童 | `.child` | 儿童语音和停顿较多场景。 |

PTT 按钮入口：

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
try await client.startSpeaking()
try await client.stopSpeaking()
```

按钮启用条件：

```swift
var canHoldToTalk: Bool {
    latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
}
```

客户 UI 建议：

- 只有 `phase == .connected` 时允许说话。
- `turnBusy == true` 时禁用 PTT，避免重复提交。
- `vadMode == .fullAuto` 时不展示或禁用 PTT。
- `recording == true` 时展示录音动效。

## 12. 结束会话

用户点击 Leave：

```swift
func leaveTapped() {
    Task { await leave() }
}
```

Demo 实现：

```swift
private func leave() async {
    guard let client = client else { return }
    let sessionId = activeSessionId
    let auth = auth
    do {
        try await client.endSession(reason: "user-leave")
        if let sessionId = sessionId, let auth = auth {
            let backend = try buildCustomerBackendApi()
            try await backend.endRealtimeSession(customerToken: auth.token, sessionId: sessionId)
        }
        activeSessionId = nil
    } catch {
        handleError(error.localizedDescription)
    }
}
```

这里分两步：

1. `client.endSession(reason: "user-leave")`：SDK 结束当前实时会话并离开媒体房间。
2. `POST /app/sessions/{sessionId}/end`：App 通知客户后端业务会话结束。

结束接口：

```text
POST /app/sessions/{sessionId}/end
Authorization: Bearer <customer-token>
Content-Type: application/json
Accept: application/json
```

请求体：

```json
{}
```

## 13. 最小接入代码骨架

```swift
import Foundation
import NewTypeSDK

@MainActor
final class SpeakingSessionViewModel: ObservableObject {
    private var client: NewTypeSessionClient?
    private var activeSessionId: String?
    private var customerToken: String?

    @Published var statusText = ""
    @Published var transcriptText = "暂无消息"
    @Published var summaryText = "暂无总结"
    @Published var lastError = ""

    func start() async {
        do {
            let backend = try CustomerBackendApi(apiBaseUrl: EndpointUrl.parse("http://localhost:8090"))
            let login = try await backend.login(email: "demo@example.com", password: "demo-password-change-me")
            customerToken = login.token

            let client = NewTypeSessionClient.create(config: NewTypeConfig())
            self.client = client
            client.setVadMode(.fullAuto)
            client.setVadPreset(.child)
            client.onStateChanged = { [weak self] state in
                Task { @MainActor in
                    self?.statusText = "phase=\(state.phase.rawValue) participants=\(state.participantCount)"
                    self?.transcriptText = state.transcript
                        .map { "\($0.speaker): \($0.text)" }
                        .joined(separator: "\n\n")
                    if let summary = state.summary {
                        self?.summaryText = summary.summary
                    }
                }
            }
            client.onError = { [weak self] message in
                Task { @MainActor in self?.lastError = message }
            }

            let credential = try await backend.startRealtimeSession(
                customerToken: login.token,
                request: StartRealtimeSessionRequest(
                    appUserId: login.user.appUserId,
                    externalSessionId: "ios-demo-\(Int(Date().timeIntervalSince1970))",
                    childName: login.user.displayName ?? "Leo",
                    age: "9",
                    grade: "Grade 3",
                    topic: "speaking",
                    interests: [],
                    identity: login.user.displayName ?? "Leo"
                )
            )
            activeSessionId = credential.sessionId
            try await client.connect(
                .init(
                    sessionId: credential.sessionId,
                    roomName: credential.roomName,
                    connectionUrl: credential.connectionUrl,
                    connectionToken: credential.connectionToken,
                    identity: credential.identity,
                    expiresIn: credential.expiresIn
                )
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        do {
            try await client?.endSession(reason: "user-leave")
            // 如需业务上报，再调用客户后端 /app/sessions/{sessionId}/end
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

> 上面的 `CustomerBackendApi`、请求/响应模型请参考 demo 的 `Features/RTC/DemoViewModel.swift`。客户正式接入时可替换为自己的网络层。

## 14. 接入检查清单

- 已集成 `NewTypeSDK.xcframework` 和 `NewTypeSDK-Binary.podspec`。
- 已执行 `pod install` 并使用 `.xcworkspace` 打开工程。
- 已配置 `NSMicrophoneUsageDescription`。
- HTTP 调试环境已配置 ATS 例外，生产使用 HTTPS。
- App 已完成客户自己的登录流程；如使用 demo 后端，可请求 `POST /auth/login` 并保存客户 token。
- App 已完成客户自己的创建会话流程；如使用 demo 后端，可请求 `POST /app/sessions` 创建业务会话。
- 客户后端已返回 SDK 必须字段：`sessionId`、`roomName`、`connectionUrl`、`connectionToken`、`identity`。
- 如客户后端字段名不同，App 已把它们映射为 SDK `connect(...)` 入参；`expiresIn` 可选。
- 已先绑定 `onStateChanged` / `onError`，再调用 `connect(...)`。
- UI 已基于 `phase`、`participantCount`、`micReady`、`recording`、`turnBusy` 控制展示和按钮。
- 已根据产品场景设置 `VadMode` 和 `VADPreset`。
- 用户离开时调用 `endSession(reason:)`，页面销毁时调用 `close()`。

## 15. 常见问题

### 真机连不上客户后端

- 真机不能使用 `localhost` 访问电脑上的服务，需要使用局域网 IP。
- 客户后端需监听 `0.0.0.0`。
- HTTP 调试需要 ATS 例外。
- 可先用手机 Safari 访问客户后端健康检查地址。

### Join 后没有 Agent 或没有回复

- 查看 `phase` 是否为 `.connected`。
- 查看 `participantCount` 是否大于 1。
- 查看 `agentMessage`、`errorMessage` 或 `onError`。
- 查看麦克风权限和 `micReady`。
- PTT 模式下确认按下和松开都调用了 SDK。
- 儿童停顿较长时建议使用 `.child` 预设。

### PTT 不可点

Demo 的启用条件是：

```swift
latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
```

如果正在连接、上一轮还在处理、或当前为全自动模式，PTT 会被禁用。

### 退出页面后仍占用麦克风

确认页面销毁、ViewModel 释放、登出或重新 Join 前调用：

```swift
client?.close()
```
