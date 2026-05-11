//
//  ContentView.swift
//  NewTypeDemo
//
//  NewType iOS SDK Demo 主界面
//  展示 SDK 所有核心功能：会话管理、VAD 控制、状态观察等
//

import SwiftUI
import NewTypeSDK

/// Demo 主视图
/// 提供完整的 SDK 功能演示界面，包括：
/// - 后端配置（API Base URL、LiveKit URL、Token Path）
/// - 会话参数（房间名、儿童姓名、年龄、年级）
/// - VAD 模式选择（PTT/半自动/全自动）
/// - VAD Preset 选择（灵敏/自然/儿童）
/// - 状态显示、Transcript 流、Summary 总结
struct ContentView: View {
    /// ViewModel，管理所有业务逻辑和状态
    @StateObject private var vm = DemoViewModel()
    /// 按住说话按钮的按下状态
    @State private var isHoldingToTalk = false

    /// 主视图内容
    /// 使用 ScrollView 包裹垂直布局，展示所有配置项和状态信息
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - 标题
                Text("NewType iOS SDK Demo")
                    .font(.title3)
                    .fontWeight(.bold)

                // MARK: - 后端配置输入框
                // 配置 NewType 后端服务地址和 LiveKit 实时音视频服务
                DemoInputField(title: "API Base URL", text: $vm.apiBaseUrl)
                DemoInputField(title: "LiveKit URL", text: $vm.liveKitUrl)
                DemoInputField(title: "Token Path", text: $vm.tokenPath)
                
                // MARK: - 会话参数输入框
                // 设置房间信息和儿童个人信息，用于创建会话
                DemoInputField(title: "Room Name", text: $vm.roomName)
                DemoInputField(title: "Child Name", text: $vm.childName)
                DemoInputField(title: "Age", text: $vm.age)
                DemoInputField(title: "Grade", text: $vm.grade)

                // MARK: - 会话控制按钮
                // Join：开始会话，连接房间
                // Leave：结束会话，离开房间（仅在已连接时可用）
                HStack(spacing: 8) {
                    DemoActionButton(title: "Join", backgroundColor: .blue) {
                        vm.joinTapped()
                    }

                    DemoActionButton(title: "Leave", backgroundColor: .red) {
                        vm.leaveTapped()
                    }
                    .disabled(!vm.canLeave || vm.isLeaving)
                }

                // MARK: - VAD 模式选择
                // PTT (Push-to-Talk)：按下说话模式，完全手动控制
                // 半自动 (Semi-Auto)：VAD 检测语音，但需要手动确认
                // 全自动 (Full-Auto)：VAD 自动检测并开始/停止录音
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

                // MARK: - VAD Preset 选择
                // 灵敏：对声音更敏感，适合安静环境
                // 自然：平衡模式，适合一般环境
                // 儿童：针对儿童语音优化的检测参数
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

                // MARK: - 按住说话按钮（PTT 模式）
                // 仅在 PTT 或半自动模式下可用，长按录音，松开发送
                PressToTalkButton(
                    title: "Hold to Talk",
                    disabled: !vm.canHoldToTalk,
                    isPressed: $isHoldingToTalk,
                    onPress: { vm.startSpeakingTapped() },
                    onRelease: { vm.stopSpeakingTapped() }
                )

                // MARK: - 状态显示区域
                // 显示当前会话阶段、连接状态、Agent 状态、参与者数量等
                DemoSectionTitle("Status")
                DemoOutputBox(text: vm.statusText, monospaced: true, minHeight: 160)

                // MARK: - Transcript 流
                // 实时显示对话转录文本，包含 AI 和儿童的对话内容
                DemoSectionTitle("Transcript")
                DemoOutputBox(text: vm.transcriptText, monospaced: false, minHeight: 120)

                // MARK: - Summary 总结
                // 会话结束后显示 AI 生成的总结，包括表现评价和改进建议
                DemoSectionTitle("Summary")
                DemoOutputBox(text: vm.summaryText, monospaced: false, minHeight: 80)

                // MARK: - 错误信息显示
                // 当发生错误时显示红色错误提示
                if !vm.lastError.isEmpty {
                    DemoSectionTitle("Error")
                    DemoOutputBox(text: vm.lastError, monospaced: false, minHeight: 44, foregroundColor: .red)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        // 视图消失时，如果正在按住说话，则停止录音
        .onDisappear {
            if isHoldingToTalk {
                vm.stopSpeakingTapped()
                isHoldingToTalk = false
            }
        }
        // 监听录音状态变化，录音结束时重置按住说话状态
        .onChange(of: vm.isRecording) { recording in
            if !recording {
                isHoldingToTalk = false
            }
        }
    }
}

// MARK: - 自定义视图组件

/// 章节标题视图
/// 用于在界面中分隔不同功能区域，使用 headline 字体加粗显示
private struct DemoSectionTitle: View {
    /// 标题文本
    let title: String

    /// 初始化章节标题
    /// - Parameter title: 标题文本
    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}

/// 配置输入框视图
/// 带标题的文本输入框，用于配置后端地址、房间名等参数
private struct DemoInputField: View {
    /// 输入框标题
    let title: String
    /// 绑定的文本内容
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 标题使用 caption 字体和次要颜色显示
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            // 输入框配置：
            // - 禁用自动大写
            // - 禁用自动纠正
            // - 使用圆角边框样式
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// 操作按钮视图
/// 用于 Join/Leave 等控制按钮，支持自定义背景色
private struct DemoActionButton: View {
    /// 按钮标题
    let title: String
    /// 背景颜色
    let backgroundColor: Color
    /// 点击触发的动作
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

/// 按住说话按钮视图（PTT 模式）
/// 使用拖动手势实现长按录音、松开发送的功能
private struct PressToTalkButton: View {
    /// 按钮标题
    let title: String
    /// 是否禁用
    let disabled: Bool
    /// 当前是否按下状态
    @Binding var isPressed: Bool
    /// 按下时触发的回调
    let onPress: () -> Void
    /// 松开时触发的回调

    var body: some View {
        // 根据状态动态设置背景色：
        // - 禁用：灰色半透明
        // - 按下：橙色
        // - 未按下：绿色
        let backgroundColor: Color = disabled ? .gray.opacity(0.5) : (isPressed ? .orange : .green)

        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            // 设置点击区域为整个矩形
            .contentShape(Rectangle())
            // 添加拖动手势实现 PTT 功能
            .gesture(
                DragGesture(minimumDistance: 0)
                    // 手势开始：如果未禁用且未按下，则开始录音
                    .onChanged { _ in
                        guard !disabled, !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    // 手势结束：如果已按下，则停止录音
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            // 禁用时降低透明度
            .opacity(disabled ? 0.6 : 1)
    }
}

/// 输出显示框视图
/// 用于显示状态、Transcript、Summary 等信息，支持等宽字体和文本选择
private struct DemoOutputBox: View {
    /// 显示的文本内容
    let text: String
    /// 是否使用等宽字体（适合显示状态信息）
    let monospaced: Bool
    /// 最小高度
    let minHeight: CGFloat
    /// 前景色
    let foregroundColor: Color

    /// 初始化输出框
    /// - Parameters:
    ///   - text: 显示的文本内容
    ///   - monospaced: 是否使用等宽字体
    ///   - minHeight: 最小高度
    ///   - foregroundColor: 前景色，默认为 primary
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
            // 设置最小高度，左对齐
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(12)
            // 使用次要系统背景色
            .background(Color(.secondarySystemBackground))
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
            // 根据 monospaced 参数选择字体：等宽字体适合显示状态日志
            .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
            .multilineTextAlignment(.leading)
            // 启用文本选择，方便复制
            .textSelection(.enabled)
    }
}
