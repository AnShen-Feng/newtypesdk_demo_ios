// Relative path: newtypesdk_demo_ios/UI/DirectCredentialTestView.swift

import SwiftUI
import NewTypeSDK

struct DirectCredentialTestView: View {
    @ObservedObject private var vm: DirectCredentialTestViewModel
    @State private var isHoldingToTalk = false

    init(viewModel: DirectCredentialTestViewModel) {
        self.vm = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("NewType Direct Credential Test")
                    .font(.headline)
                    .fontWeight(.bold)

                Text("直接输入 NewTypeConnectionCredential 参数加入房间，不调用登录或客户后端接口。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                DirectCredentialSectionTitle("Connection Credential")
                DirectCredentialInputField(title: "Session ID", text: $vm.sessionId)
                DirectCredentialInputField(title: "Room Name", text: $vm.roomName)
                DirectCredentialInputField(title: "Connection URL", text: $vm.connectionUrl)
                DirectCredentialSecureInputField(title: "Connection Token", text: $vm.connectionToken)
                DirectCredentialInputField(title: "Identity", text: $vm.identity)
                DirectCredentialInputField(title: "Expires In (optional seconds)", text: $vm.expiresIn)

                HStack(spacing: 8) {
                    DirectCredentialActionButton(title: "Join", backgroundColor: .blue) {
                        vm.joinTapped()
                    }
                    .disabled(!vm.canJoin)

                    DirectCredentialActionButton(title: "Leave", backgroundColor: .red) {
                        vm.leaveTapped()
                    }
                    .disabled(!vm.canLeave || vm.isLeaving)
                }

                DirectCredentialSectionTitle("VAD Mode")
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

                DirectCredentialSectionTitle("VAD Preset")
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

                DirectCredentialPressToTalkButton(
                    title: "Hold to Talk",
                    disabled: !vm.canHoldToTalk,
                    isPressed: $isHoldingToTalk,
                    onPress: { vm.startSpeakingTapped() },
                    onRelease: { vm.stopSpeakingTapped() }
                )

                DirectCredentialSectionTitle("Status")
                DirectCredentialOutputBox(text: vm.statusText, monospaced: true, minHeight: 160)

                DirectCredentialSectionTitle("Transcript")
                DirectCredentialOutputBox(text: vm.transcriptText, monospaced: false, minHeight: 120)

                DirectCredentialSectionTitle("Summary")
                DirectCredentialOutputBox(text: vm.summaryText, monospaced: false, minHeight: 80)

                if !vm.lastError.isEmpty {
                    DirectCredentialSectionTitle("Error")
                    DirectCredentialOutputBox(text: vm.lastError, monospaced: false, minHeight: 44, foregroundColor: .red)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .onDisappear {
            if isHoldingToTalk {
                vm.stopSpeakingTapped()
                isHoldingToTalk = false
            }
        }
    }
}

private struct DirectCredentialSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}

private struct DirectCredentialInputField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(title, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct DirectCredentialSecureInputField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField(title, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct DirectCredentialActionButton: View {
    let title: String
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .foregroundColor(.white)
        .cornerRadius(8)
    }
}

private struct DirectCredentialPressToTalkButton: View {
    let title: String
    let disabled: Bool
    @Binding var isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        let backgroundColor: Color = disabled ? .gray.opacity(0.5) : (isPressed ? .orange : .green)

        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .contentShape(Rectangle())
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
            .opacity(disabled ? 0.6 : 1)
    }
}

private struct DirectCredentialOutputBox: View {
    let text: String
    let monospaced: Bool
    let minHeight: CGFloat
    let foregroundColor: Color

    init(
        text: String,
        monospaced: Bool,
        minHeight: CGFloat,
        foregroundColor: Color = .primary
    ) {
        self.text = text
        self.monospaced = monospaced
        self.minHeight = minHeight
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
            .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
            .multilineTextAlignment(.leading)
    }
}
