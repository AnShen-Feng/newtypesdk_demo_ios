# NewType iOS Demo

本工程用于演示 NewType iOS SDK 的使用，SDK 以 XCFramework 二进制文件形式集成，不暴露源码。最低支持 iOS 13.4。

## 目录说明

- `App/`: Demo App 入口
- `Features/RTC/`: Demo ViewModel
- `UI/`: SwiftUI 界面
- `libs/`: SDK 二进制文件及 Podspec

## 运行步骤

### 1. 准备 XCFramework

首先需要将 XCFramework 文件放置到 `libs/` 目录下：

```bash
# 从 newtypesdk_ios 构建 XCFramework
cd ../newtypesdk_ios/scripts
./build_xcframework.sh

# 复制 XCFramework 到 demo 项目
cp -r ../dist/NewTypeSDK.xcframework ../../newtypesdk_demo_ios/libs/
```

或者从 artifact 仓库下载 XCFramework 并解压到 `libs/` 目录。

### 2. 更新 Podspec

编辑 `libs/NewTypeSDK-Binary.podspec`，将 `source` 指向实际的 XCFramework 下载地址，或使用本地路径：

```ruby
# 本地开发模式
s.source = { :path => "." }
s.vendored_frameworks = "NewTypeSDK.xcframework"
```

### 3. 安装依赖

```bash
cd newtypesdk_demo_ios
pod install
```

### 4. 打开工程

```bash
open newtypesdk_demo_ios.xcworkspace
```

### 5. 运行 Demo

选择 `NewTypeDemo` Scheme，运行到真机或模拟器。

## SDK 接口

Demo 使用以下 SDK 接口：

### 会话管理

```swift
let config = NewTypeConfig(
    backendBaseUrl: try EndpointUrl.parse("https://newtype.squady.app:11000"),
    liveKitUrlOverride: nil,
    tokenPath: "/api/livekit/token"
)

let client = NewTypeSessionClient.create(config: config)
client.setVadMode(.fullAuto)
client.setVadPreset(.natural)

let result = try await client.startSession(
    StartSessionParams(
        childName: "Leo",
        age: "9",
        grade: "Grade 3",
        roomName: "speaking-demo",
        identity: "Leo"
    )
)
```

### VAD 控制

```swift
// PTT 模式
try await client.startSpeaking()
try await client.stopSpeaking()

// VAD 模式配置
client.setVadMode(.semiAuto)
client.setVadPreset(.sensitive)
client.setVadOptions(VADOptions(threshold: 0.5, minSpeechMs: 500, minSilenceMs: 300))
```

### 状态观察

```swift
client.onStateChanged = { state in
    print("phase: \(state.phase)")
    print("connection: \(state.connectionStatus)")
    print("agent: \(state.agentPhase)")
    print("transcript: \(state.transcript)")
}

client.onSignal = { signal in
    print("signal: \(signal)")
}

client.onError = { message in
    print("error: \(message)")
}
```

### 结束会话

```swift
try await client.endSession(reason: "user-leave")
```

## 类型安全

SDK 提供完整的类型安全：

- `SessionPhase`: `.idle`, `.connecting`, `.connected`, `.ending`, `.ended`
- `ConnectionStatus`: `.idle`, `.connecting`, `.connected`, `.disconnected`
- `AgentPhase`: `.waiting`, `.joining`, `.joined`, `.leaving`, `.left`
- `VadMode`: `.off`, `.semiAuto`, `.fullAuto`
- `VADPreset`: `.sensitive`, `.natural`, `.child`
- `TranscriptEntry`: 包含 `speaker`, `text`, `meta`, `streaming` 字段
- `SessionSummary`: 包含 `summary`, `didWell`, `oneTip`, `nextTopic`, `pronunciationFocus` 字段

## 后端配置

Demo 默认配置：

- API Base URL: `https://newtype.squady.app:11000`
- LiveKit URL: `wss://livekit.squady.app:11000`
- Token Path: `/api/livekit/token`

可在界面中修改这些配置。

## 与 Android SDK 对齐

iOS SDK 与 Android SDK 保持 API 对齐：

| Android | iOS |
|---------|-----|
| `NewTypeSessionClient` | `NewTypeSessionClient` |
| `VadMode` | `VadMode` |
| `VADPreset` | `VADPreset` |
| `startSpeaking()` | `startSpeaking()` |
| `stopSpeaking()` | `stopSpeaking()` |
| `setVadMode()` | `setVadMode()` |
| `setVadPreset()` | `setVadPreset()` |
