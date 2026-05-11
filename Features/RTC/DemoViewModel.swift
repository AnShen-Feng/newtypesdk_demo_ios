//
//  DemoViewModel.swift
//  NewTypeDemo
//
//  Demo ViewModel，展示 NewType SDK 核心功能的使用方式
//  包含会话管理、VAD 控制、状态观察等完整示例
//

import Foundation
import NewTypeSDK

/// Demo ViewModel
/// 管理所有业务逻辑和状态，与 NewTypeSessionClient 交互
/// 使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
final class DemoViewModel: ObservableObject {
    // MARK: - 配置属性（可从界面修改）
    
    /// API Base URL - NewType 后端服务地址
    /// 默认值：https://newtype.squady.app:11000
    @Published var apiBaseUrl: String = "https://newtype.squady.app:11000"
    
    /// LiveKit URL - 实时音视频服务 WebSocket 地址
    /// 默认值：wss://livekit.squady.app:11000
    @Published var liveKitUrl: String = "wss://livekit.squady.app:11000"
    
    /// Token Path - 获取 LiveKit Token 的 API 路径
    /// 默认值：/api/livekit/token
    @Published var tokenPath: String = "/api/livekit/token"
    
    /// Room Name - 房间名称，用于创建或加入会话
    @Published var roomName: String = "speaking-demo"
    
    /// Child Name - 儿童姓名，用于标识会话参与者
    @Published var childName: String = "Leo"
    
    /// Age - 年龄，用于 AI 个性化交互
    @Published var age: String = "9"
    
    /// Grade - 年级，用于 AI 个性化交互
    @Published var grade: String = "Grade 3"
    
    // MARK: - VAD 配置属性
    
    /// VAD Mode - 语音检测模式
    /// - .off (PTT): 按下说话模式，完全手动控制
    /// - .semiAuto: 半自动模式，VAD 检测但需确认
    /// - .fullAuto: 全自动模式，VAD 自动检测录音
    @Published var vadMode: VadMode = .fullAuto
    
    /// VAD Preset - 语音检测预设参数
    /// - .sensitive: 灵敏模式，适合安静环境
    /// - .natural: 自然模式，平衡检测参数
    /// - .child: 儿童模式，针对儿童语音优化
    @Published var vadPreset: VADPreset = .natural
    
    // MARK: - 状态显示属性
    
    /// Status Text - 状态显示文本，包含连接状态、参与者数量等
    @Published private(set) var statusText: String = ""
    
    /// Transcript Text - 对话转录文本，实时显示 AI 和儿童的对话
    @Published private(set) var transcriptText: String = "暂无消息"
    
    /// Summary Text - 会话总结文本，会话结束后显示 AI 生成的评价
    @Published private(set) var summaryText: String = "暂无总结"
    
    /// Last Error - 最后错误信息，发生错误时显示
    @Published var lastError: String = ""

    // MARK: - 私有属性
    
    /// NewType Session Client - 核心会话客户端，管理所有 SDK 交互
    private var client: NewTypeSessionClient?
    
    /// Latest State - 最新状态缓存，用于界面渲染
    private var latestState = DemoRoomState()

    /// 初始化 ViewModel
    /// 渲染初始空状态
    init() {
        renderState(latestState)
    }

    // MARK: - 公开方法（UI 事件响应）
    
    /// 点击 Join 按钮时调用
    /// 启动异步 join 流程，创建会话并连接房间
    func joinTapped() {
        Task { await join() }
    }

    /// 点击 Leave 按钮时调用
    /// 结束当前会话，离开房间
    func leaveTapped() {
        Task { await leave() }
    }

    /// 开始说话（PTT 模式）
    /// 手动触发录音开始
    func startSpeakingTapped() {
        Task { await startSpeaking() }
    }

    /// 停止说话（PTT 模式）
    /// 手动触发录音结束
    func stopSpeakingTapped() {
        Task { await stopSpeaking() }
    }

    /// VAD 模式变更回调
    /// - Parameter mode: 新的 VAD 模式
    func vadModeChanged(_ mode: VadMode) {
        vadMode = mode
        client?.setVadMode(mode)
        renderState(latestState)
    }

    /// VAD Preset 变更回调
    /// - Parameter preset: 新的 VAD Preset
    func vadPresetChanged(_ preset: VADPreset) {
        vadPreset = preset
        client?.setVadPreset(preset)
        renderState(latestState)
    }

    // MARK: - 计算属性（状态判断）
    
    /// 是否可以离开房间
    /// 仅在会话已连接时允许离开
    var canLeave: Bool {
        latestState.phase == .connected
    }

    /// 是否可以使用按住说话功能
    /// 条件：已连接 + 非忙碌状态 + 非全自动模式
    var canHoldToTalk: Bool {
        latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
    }

    /// 是否正在离开中
    /// 用于禁用 Leave 按钮防止重复点击
    var isLeaving: Bool {
        latestState.leaveRequested
    }

    /// 是否正在录音中
    /// 用于更新界面状态
    var isRecording: Bool {
        latestState.recording
    }

    // MARK: - 私有方法 - 会话控制
    
    /// 加入房间
    /// 创建 NewTypeSessionClient，配置 VAD 参数，启动会话
    private func join() async {
        // 去除儿童姓名两端空白字符
        let trimmedChildName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            lastError = ""
            // 验证儿童姓名不能为空
            guard !trimmedChildName.isEmpty else {
                handleError("Child Name 不能为空")
                return
            }

            // 解析后端地址
            let endpoint = try EndpointUrl.parse(apiBaseUrl)
            let config = try buildConfig(backendBaseUrl: endpoint)

            // 关闭旧客户端（如果有），创建新客户端
            client?.close()
            let client = NewTypeSessionClient.create(config: config)
            self.client = client
            // 应用当前 VAD 配置
            client.setVadMode(vadMode)
            client.setVadPreset(vadPreset)
            // 绑定状态回调
            bind(client: client)

            // 生成身份标识
            let identity = trimmedChildName.isEmpty ? "ios-child" : trimmedChildName
            log("join start room=\(normalized(roomName) ?? "-") child=\(trimmedChildName) mode=\(vadMode.logLabel) preset=\(vadPreset.logLabel)")
            // 启动会话，传入儿童信息和房间参数
            _ = try await client.startSession(
                StartSessionParams(
                    childName: trimmedChildName,
                    age: blankAsNil(age),
                    grade: blankAsNil(grade),
                    roomName: blankAsNil(roomName),
                    identity: identity
                )
            )
        } catch {
            handleError(error.localizedDescription)
        }
    }

    /// 离开房间
    /// 调用 endSession 结束当前会话
    private func leave() async {
        guard let client else { return }
        do {
            log("leave requested")
            // 使用 user-leave 原因结束会话
            try await client.endSession(reason: "user-leave")
        } catch {
            handleError(error.localizedDescription)
        }
    }

    /// 开始说话（PTT 模式）
    /// 手动触发 SDK 开始录音
    private func startSpeaking() async {
        guard let client else { return }
        do {
            log("ptt start")
            try await client.startSpeaking()
        } catch {
            handleError(error.localizedDescription)
        }
    }

    /// 停止说话（PTT 模式）
    /// 手动触发 SDK 停止录音
    private func stopSpeaking() async {
        guard let client else { return }
        do {
            log("ptt stop")
            try await client.stopSpeaking()
        } catch {
            handleError(error.localizedDescription)
        }
    }

    // MARK: - 私有方法 - 状态绑定
    
    /// 绑定客户端回调
    /// 设置 onStateChanged、onSignal、onError 回调函数
    /// 所有回调都在主线程执行以更新 UI
    private func bind(client: NewTypeSessionClient) {
        // 状态变化回调：应用新状态到界面
        client.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.apply(state: state)
            }
        }
        // 信号回调：记录 SDK 内部信号事件
        client.onSignal = { [weak self] signal in
            Task { @MainActor in
                self?.log("signal=\(String(reflecting: signal))")
            }
        }
        // 错误回调：显示错误信息
        client.onError = { [weak self] message in
            Task { @MainActor in
                self?.handleError(message)
            }
        }
    }

    // MARK: - 私有方法 - 状态处理
    
    /// 应用新状态
    /// 将 SDK 状态同步到本地缓存，更新错误信息，记录日志
    private func apply(state: NewTypeClientState) {
        // 更新本地状态缓存
        latestState = DemoRoomState(state)
        // 如果有错误消息，更新错误显示
        if let errorMessage = state.errorMessage {
            lastError = errorMessage
        }
        // 渲染状态到界面
        renderState(latestState)
        // 记录详细状态日志
        log(
            "state phase=\(state.phase.logLabel) connection=\(state.connectionStatus.logLabel) " +
            "participants=\(state.participantCount) agent=\(state.agentPhase.logLabel)"
        )
    }

    /// 渲染状态到界面文本
    /// 构建 Status、Transcript、Summary 显示内容
    private func renderState(_ state: DemoRoomState) {
        // 构建状态文本，包含会话阶段、Agent 状态、参与者数量等
        statusText = [
            "phase=\(state.phase.logLabel)",
            "agent=\(state.agentPhase.logLabel) \(state.agentMessage)",
            "participants=\(state.participantCount) \(state.participantCount > 1 ? "(Agent 已入房 ✅)" : "(等待 Agent 入房...)")",
            "session=\(state.sessionId ?? "-")",
            "mode=\(vadMode.displayText)",
            "preset=\(vadPreset.displayText)",
            "",
            "=== 连接状态 ===",
            "房间：\(roomName)",
            "LiveKit: \(liveKitUrl)",
            "API: \(apiBaseUrl)",
            "麦克风：\(state.micReady ? "就绪 ✅" : "未就绪")",
            "录音：\(state.recording ? "进行中 🎤" : "待机")"
        ].joined(separator: "\n")

        // 构建 Transcript 文本，遍历每个转录条目
        transcriptText = state.transcript
            .map { entry in
                // 判断说话者：AI 或 Child
                let speaker = entry.speaker == .ai ? "AI" : "Child"
                // 如果有 meta 信息，附加到末尾
                let metaSuffix = (entry.meta?.isEmpty == false) ? "\n\(entry.meta ?? "")" : ""
                // 如果是流式传输中，添加标记
                let streamingSuffix = entry.streaming ? " [streaming]" : ""
                return "\(speaker): \(entry.text)\(streamingSuffix)\(metaSuffix)"
            }
            .joined(separator: "\n\n")
        if transcriptText.isEmpty {
            transcriptText = "暂无消息"
        }

        // 构建 Summary 文本，显示 AI 生成的会话总结
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
    }

    // MARK: - 私有方法 - 辅助函数
    
    /// 构建 NewType 配置
    /// 处理 LiveKit URL 的可选覆盖
    private func buildConfig(backendBaseUrl: EndpointUrl) throws -> NewTypeConfig {
        // 尝试解析 LiveKit URL，如果为空则使用 SDK 默认
        let liveKitOverride: EndpointUrl?
        if let normalizedLiveKitUrl = normalized(liveKitUrl) {
            liveKitOverride = try EndpointUrl.parse(normalizedLiveKitUrl)
        } else {
            liveKitOverride = nil
        }

        return NewTypeConfig(
            backendBaseUrl: backendBaseUrl,
            liveKitUrlOverride: liveKitOverride,
            tokenPath: normalized(tokenPath) ?? "/api/livekit/token"
        )
    }

    /// 将空字符串转换为 nil
    private func blankAsNil(_ input: String) -> String? {
        normalized(input)
    }

    /// 标准化字符串：去除空白，空字符串返回 nil
    private func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 处理错误
    /// 更新错误显示并记录日志
    private func handleError(_ message: String) {
        lastError = message
        log("error=\(message)")
    }

    /// 记录日志
    private func log(_ message: String) {
        print("[MainActivity] \(message)")
    }
}

// MARK: - DemoRoomState 状态结构体

/// Demo 房间状态模型
/// 封装 NewTypeClientState，用于界面渲染
private struct DemoRoomState: Equatable {
    /// 会话 ID
    let sessionId: String?
    /// 会话阶段：idle, connecting, connected, ending, ended
    let phase: SessionPhase
    /// 连接状态：idle, connecting, connected, disconnected
    let connectionStatus: ConnectionStatus
    /// Agent 阶段：waiting, joining, joined, leaving, left
    let agentPhase: AgentPhase
    /// Agent 状态消息
    let agentMessage: String
    /// 房间参与者数量
    let participantCount: Int
    /// 麦克风是否就绪
    let micReady: Bool
    /// 是否正在录音
    let recording: Bool
    /// 是否忙碌（turn 占用）
    let turnBusy: Bool
    /// 是否已请求离开
    let leaveRequested: Bool
    /// 转录条目列表
    let transcript: [TranscriptEntry]
    /// 会话总结
    let summary: SessionSummary?

    /// 初始化空状态
    /// 用于 ViewModel 初始化时的默认状态
    init() {
        self.sessionId = nil
        self.phase = .idle
        self.connectionStatus = .idle
        self.agentPhase = .waiting
        self.agentMessage = "Waiting for room connection."
        self.participantCount = 0
        self.micReady = false
        self.recording = false
        self.turnBusy = false
        self.leaveRequested = false
        self.transcript = []
        self.summary = nil
    }

    /// 从 NewTypeClientState 初始化
    /// 将 SDK 状态映射到 Demo 状态模型
    init(_ state: NewTypeClientState) {
        self.sessionId = state.sessionId
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

// MARK: - SDK 枚举类型扩展（日志标签）

/// SessionPhase 日志标签扩展
private extension SessionPhase {
    var logLabel: String { rawValue.uppercased() }
}

/// ConnectionStatus 日志标签扩展
private extension ConnectionStatus {
    var logLabel: String { rawValue.uppercased() }
}

/// AgentPhase 日志标签扩展
private extension AgentPhase {
    var logLabel: String { rawValue.uppercased() }
}

// MARK: - VadMode 扩展

/// VadMode 显示文本和日志标签扩展
private extension VadMode {
    /// 界面显示文本（中文）
    var displayText: String {
        switch self {
        case .off:
            return "PTT 按下说话"
        case .semiAuto:
            return "VAD 半自动"
        case .fullAuto:
            return "VAD 全自动"
        }
    }

    /// 日志显示标签（英文大写）
    var logLabel: String { rawValue.uppercased() }
}

// MARK: - VADPreset 扩展

/// VADPreset 显示文本和日志标签扩展
private extension VADPreset {
    /// 界面显示文本（中文）
    var displayText: String {
        switch self {
        case .sensitive:
            return "灵敏"
        case .natural:
            return "自然"
        case .child:
            return "儿童"
        }
    }

    /// 日志显示标签（英文大写）
    var logLabel: String { rawValue.uppercased() }
}
