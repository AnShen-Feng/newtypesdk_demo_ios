// Relative path: newtypesdk_demo_ios/Features/RTC/DemoViewModel.swift

import Foundation
import NewTypeSDK

@MainActor
final class DemoViewModel: ObservableObject {
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

    init() {
        renderState(latestState)
    }

    func loginTapped() {
        Task { await login() }
    }

    func logoutTapped() {
        guard latestState.phase == .idle else { return }
        auth = nil
        loginText = "未登录客户后端"
        lastError = ""
        client?.close()
        client = nil
        renderState(latestState)
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

    private func blankAsNil(_ input: String) -> String? {
        normalized(input)
    }

    private func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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

    private func handleError(_ message: String) {
        lastError = message
        log("error=\(message)")
    }

    private func log(_ message: String) {
        print("[NewTypeSDKDemo] \(message)")
    }
}

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
