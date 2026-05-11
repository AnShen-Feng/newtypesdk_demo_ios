import Foundation
import NewTypeSDK

@MainActor
final class DemoViewModel: ObservableObject {
    @Published var apiBaseUrl: String = "https://newtype.squady.app:11000"
    @Published var liveKitUrl: String = "wss://livekit.squady.app:11000"
    @Published var tokenPath: String = "/api/livekit/token"
    @Published var roomName: String = "speaking-demo"
    @Published var childName: String = "Leo"
    @Published var age: String = "9"
    @Published var grade: String = "Grade 3"
    @Published var vadMode: VadMode = .fullAuto
    @Published var vadPreset: VADPreset = .natural
    @Published private(set) var statusText: String = ""
    @Published private(set) var transcriptText: String = "暂无消息"
    @Published private(set) var summaryText: String = "暂无总结"
    @Published var lastError: String = ""

    private var client: NewTypeSessionClient?
    private var latestState = DemoRoomState()

    init() {
        renderState(latestState)
    }

    func joinTapped() {
        Task { await join() }
    }

    func leaveTapped() {
        Task { await leave() }
    }

    func startSpeakingTapped() {
        Task { await startSpeaking() }
    }

    func stopSpeakingTapped() {
        Task { await stopSpeaking() }
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

    var canLeave: Bool {
        latestState.phase == .connected
    }

    var canHoldToTalk: Bool {
        latestState.phase == .connected && !latestState.turnBusy && vadMode != .fullAuto
    }

    var isLeaving: Bool {
        latestState.leaveRequested
    }

    var isRecording: Bool {
        latestState.recording
    }

    private func join() async {
        let trimmedChildName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            lastError = ""
            guard !trimmedChildName.isEmpty else {
                handleError("Child Name 不能为空")
                return
            }

            let endpoint = try EndpointUrl.parse(apiBaseUrl)
            let config = try buildConfig(backendBaseUrl: endpoint)

            client?.close()
            let client = NewTypeSessionClient.create(config: config)
            self.client = client
            client.setVadMode(vadMode)
            client.setVadPreset(vadPreset)
            bind(client: client)

            let identity = trimmedChildName.isEmpty ? "ios-child" : trimmedChildName
            log("join start room=\(normalized(roomName) ?? "-") child=\(trimmedChildName) mode=\(vadMode.logLabel) preset=\(vadPreset.logLabel)")
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

    private func leave() async {
        guard let client else { return }
        do {
            log("leave requested")
            try await client.endSession(reason: "user-leave")
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func startSpeaking() async {
        guard let client else { return }
        do {
            log("ptt start")
            try await client.startSpeaking()
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func stopSpeaking() async {
        guard let client else { return }
        do {
            log("ptt stop")
            try await client.stopSpeaking()
        } catch {
            handleError(error.localizedDescription)
        }
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

    private func renderState(_ state: DemoRoomState) {
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

    private func buildConfig(backendBaseUrl: EndpointUrl) throws -> NewTypeConfig {
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

    private func blankAsNil(_ input: String) -> String? {
        normalized(input)
    }

    private func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handleError(_ message: String) {
        lastError = message
        log("error=\(message)")
    }

    private func log(_ message: String) {
        print("[MainActivity] \(message)")
    }
}

private struct DemoRoomState: Equatable {
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

private extension SessionPhase {
    var logLabel: String { rawValue.uppercased() }
}

private extension ConnectionStatus {
    var logLabel: String { rawValue.uppercased() }
}

private extension AgentPhase {
    var logLabel: String { rawValue.uppercased() }
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
