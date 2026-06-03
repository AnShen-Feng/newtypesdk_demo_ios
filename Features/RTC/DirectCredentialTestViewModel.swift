// Relative path: newtypesdk_demo_ios/Features/RTC/DirectCredentialTestViewModel.swift

import Foundation
import NewTypeSDK

@MainActor
final class DirectCredentialTestViewModel: ObservableObject {
    @Published var sessionId: String = ""
    @Published var roomName: String = ""
    @Published var connectionUrl: String = "wss://livekit.squady.app:11000"
    @Published var connectionToken: String = ""
    @Published var identity: String = ""
    @Published var expiresIn: String = "3600"
    @Published var vadMode: VadMode = .off
    @Published var vadPreset: VADPreset = .natural
    @Published private(set) var statusText: String = ""
    @Published private(set) var transcriptText: String = "暂无消息"
    @Published private(set) var summaryText: String = "暂无总结"
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String = ""

    private var client: NewTypeSessionClient?
    private var latestState = DirectCredentialRoomState()
    private var isPushToTalkActive = false

    init() {
        renderState(latestState)
    }

    var canJoin: Bool {
        latestState.phase == .idle && requiredCredentialFieldsArePresent
    }

    var canLeave: Bool {
        latestState.phase == .connected
    }

    var canHoldToTalk: Bool {
        latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
    }

    var canInterrupt: Bool {
        latestState.phase == .connected &&
            !latestState.leaveRequested &&
            latestState.participantCount > 1 &&
            !latestState.recording &&
            (latestState.turnBusy || latestState.agentPhase.isInterruptible)
    }

    var isLeaving: Bool {
        latestState.leaveRequested
    }

    func joinTapped() {
        Task { await join() }
    }

    func leaveTapped() {
        Task { await leave() }
    }

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

    func interruptTapped() {
        Task { await interruptCurrentTurn() }
    }

    func vadModeChanged(_ mode: VadMode) {
        vadMode = mode
        client?.setVadMode(mode)
        renderState(latestState)
    }

    func vadPresetChanged(_ preset: VADPreset) {
        vadPreset = preset
        client?.setVadPreset(preset)
        renderState(latestState)
    }

    private var requiredCredentialFieldsArePresent: Bool {
        !trimmed(sessionId).isEmpty &&
            !trimmed(roomName).isEmpty &&
            !trimmed(connectionUrl).isEmpty &&
            !trimmed(connectionToken).isEmpty &&
            !trimmed(identity).isEmpty
    }

    private func join() async {
        do {
            lastError = ""
            let credential = try buildCredential()
            client?.close()

            let client = NewTypeSessionClient.create(config: NewTypeConfig())
            self.client = client
            client.setVadMode(vadMode)
            client.setVadPreset(vadPreset)
            bind(client: client)

            log("direct connect start sessionId=\(credential.sessionId) room=\(credential.roomName) identity=\(credential.identity) mode=\(vadMode.logLabel) preset=\(vadPreset.logLabel)")
            try await client.connect(credential)
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func leave() async {
        guard let client = client else { return }
        do {
            log("leave requested")
            try await client.endSession(reason: "user-leave")
        } catch {
            handleError(error.localizedDescription)
        }
    }

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

    private func interruptCurrentTurn() async {
        guard let client = client else { return }
        do {
            log("interrupt requested")
            isPushToTalkActive = false
            try await client.interrupt(target: .tts, reason: .userCancel)
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func buildCredential() throws -> NewTypeConnectionCredential {
        let normalizedSessionId = try required(sessionId, name: "Session ID")
        let normalizedRoomName = try required(roomName, name: "Room Name")
        let normalizedConnectionUrl = try required(connectionUrl, name: "Connection URL")
        let normalizedConnectionToken = try required(connectionToken, name: "Connection Token")
        let normalizedIdentity = try required(identity, name: "Identity")
        let normalizedExpiresIn = try parseExpiresIn(expiresIn)

        return NewTypeConnectionCredential(
            sessionId: normalizedSessionId,
            roomName: normalizedRoomName,
            connectionUrl: normalizedConnectionUrl,
            connectionToken: normalizedConnectionToken,
            identity: normalizedIdentity,
            expiresIn: normalizedExpiresIn
        )
    }

    private func parseExpiresIn(_ input: String) throws -> Int? {
        let normalized = trimmed(input)
        guard !normalized.isEmpty else { return nil }
        guard let value = Int(normalized), value > 0 else {
            throw DirectCredentialInputError.invalidPositiveInteger("Expires In")
        }
        return value
    }

    private func required(_ input: String, name: String) throws -> String {
        let normalized = trimmed(input)
        guard !normalized.isEmpty else {
            throw DirectCredentialInputError.missingField(name)
        }
        return normalized
    }

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

    private func apply(state: NewTypeClientState) {
        latestState = DirectCredentialRoomState(state)
        if let errorMessage = state.errorMessage {
            lastError = errorMessage
        }
        renderState(latestState)
        log(
            "state phase=\(state.phase.logLabel) connection=\(state.connectionStatus.logLabel) " +
                "participants=\(state.participantCount) agent=\(state.agentPhase.logLabel)"
        )
    }

    private func renderState(_ state: DirectCredentialRoomState) {
        isRecording = state.recording
        statusText = [
            "phase=\(state.phase.logLabel)",
            "agent=\(state.agentPhase.displayText) \(state.agentMessage)",
            "participants=\(state.participantCount) \(state.participantCount > 1 ? "(Agent 已入房)" : "(等待 Agent 入房...)")",
            "session=\(state.sessionId ?? "-")",
            "mode=\(vadMode.displayText)",
            "preset=\(vadPreset.displayText)",
            "",
            "=== 连接状态 ===",
            "房间：\(state.roomName ?? "-")",
            "输入房间：\(trimmed(roomName).isEmpty ? "-" : trimmed(roomName))",
            "麦克风：\(state.micReady ? "就绪" : "未就绪")",
            "录音：\(state.recording ? "进行中" : "待机")"
        ].joined(separator: "\n")

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

    private func trimmed(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleError(_ message: String) {
        lastError = message
        log("error=\(message)")
    }

    private func log(_ message: String) {
        print("[NewTypeDirectCredentialTest] \(message)")
    }
}

private enum DirectCredentialInputError: LocalizedError {
    case missingField(String)
    case invalidPositiveInteger(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let name):
            return "\(name) 不能为空"
        case .invalidPositiveInteger(let name):
            return "\(name) 必须是正整数"
        }
    }
}

private struct DirectCredentialRoomState: Equatable {
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

    init() {
        self.sessionId = nil
        self.roomName = nil
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

private extension SessionPhase {
    var logLabel: String { rawValue.uppercased() }
}

private extension ConnectionStatus {
    var logLabel: String { rawValue.uppercased() }
}

private extension AgentPhase {
    var logLabel: String { rawValue.uppercased() }

    var displayText: String {
        switch self {
        case .waiting:
            return "等待中"
        case .opening:
            return "开场中"
        case .listening:
            return "聆听中"
        case .processing:
            return "处理中"
        case .closing:
            return "收尾中"
        case .error:
            return "错误"
        }
    }

    var isInterruptible: Bool {
        switch self {
        case .opening, .processing, .closing:
            return true
        case .waiting, .listening, .error:
            return false
        }
    }
}

private extension VadMode {
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

    var logLabel: String { rawValue.uppercased() }
}

private extension VADPreset {
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

    var logLabel: String { rawValue.uppercased() }
}
