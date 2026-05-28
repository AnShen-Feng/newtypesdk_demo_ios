// Relative path: newtypesdk_demo_ios/UI/ContentView.swift

import SwiftUI
import NewTypeSDK

struct ContentView: View {
    @ObservedObject private var vm: DemoViewModel
    @State private var isHoldingToTalk = false

    init(viewModel: DemoViewModel) {
        self.vm = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("NewType iOS SDK Demo")
                    .font(.headline)
                    .fontWeight(.bold)

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

                PressToTalkButton(
                    title: "Hold to Talk",
                    disabled: !vm.canHoldToTalk,
                    isPressed: $isHoldingToTalk,
                    onPress: { vm.startSpeakingTapped() },
                    onRelease: { vm.stopSpeakingTapped() }
                )

                DemoActionButton(title: "Interrupt", backgroundColor: .orange) {
                    if isHoldingToTalk {
                        vm.stopSpeakingTapped()
                        isHoldingToTalk = false
                    }
                    vm.interruptTapped()
                }
                .disabled(!vm.canInterrupt)

                DemoSectionTitle("Status")
                DemoOutputBox(text: vm.statusText, monospaced: true, minHeight: 160)

                DemoSectionTitle("Transcript")
                DemoOutputBox(text: vm.transcriptText, monospaced: false, minHeight: 120)

                DemoSectionTitle("Summary")
                DemoOutputBox(text: vm.summaryText, monospaced: false, minHeight: 80)

                if !vm.lastError.isEmpty {
                    DemoSectionTitle("Error")
                    DemoOutputBox(text: vm.lastError, monospaced: false, minHeight: 44, foregroundColor: .red)
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

private struct DemoSectionTitle: View {
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

private struct DemoInputField: View {
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

private struct DemoSecureInputField: View {
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

private struct DemoActionButton: View {
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

private struct PressToTalkButton: View {
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

private struct DemoOutputBox: View {
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
