import SwiftUI
import SwiftData

struct MiniTimerView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) private var modelContext
    
    @State private var showAddForm = false
    
    @State private var inputType: ItemType = .textOnly
    @State private var content = ""
    @State private var answer = ""
    @State private var tagString = ""
    
    @State private var inputDuration: Double = 25
    
    var body: some View {
        VStack(spacing: 18) {

            // MARK: - 顶部番茄钟
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(globalState.isTimerRunning ? "Focusing..." : "Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if globalState.isTimerRunning {
                        Text(formatTime(globalState.timeRemaining))
                            .font(.system(size: 32, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    } else {
                        HStack(spacing: 4) {
                            TextField("25", value: $inputDuration, format: .number)
                                .font(.system(size: 32, weight: .medium, design: .monospaced))
                                .textFieldStyle(.plain)
                                .frame(width: 55)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: inputDuration) { _, v in
                                    globalState.setDuration(v)
                                }
                            
                            Text("min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if globalState.isTimerRunning {
                    HStack(spacing: 10) {
                        iconButton("pause.circle.fill", color: .orange) {
                            globalState.pauseTimer()
                        }
                        iconButton("stop.circle.fill", color: .red) {
                            globalState.stopTimer(finished: false)
                        }
                    }
                } else {
                    iconButton("play.circle.fill", color: .green, size: 44) {
                        globalState.setDuration(inputDuration)
                        globalState.startTimer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            // MARK: - 添加区
            if showAddForm {

                VStack(alignment: .leading, spacing: 10) {

                    Picker("类型", selection: $inputType) {
                        Text("文本").tag(ItemType.textOnly)
                        Text("Q&A").tag(ItemType.qa)
                    }
                    .pickerStyle(.segmented)

                    // 使用修复后的输入框
                    RoundedEditor(text: $content)

                    if inputType == .qa {
                        RoundedEditor(text: $answer)
                    }

                    TextField("标签（逗号分隔）", text: $tagString)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("取消") { showAddForm = false }
                            .buttonStyle(.bordered)

                        Spacer()

                        Button("保存") { saveItem() }
                            .buttonStyle(.borderedProminent)
                            .disabled(content.isEmpty)
                    }
                }
                .padding(.horizontal, 12)

            } else {
                Button {
                    showAddForm = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("快速添加记忆条目")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider()

            // MARK: - 底部
            HStack {
                if globalState.isTimerRunning {
                    Text("加油喵～继续保持！")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("点击上方数字修改时长")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("打开主界面") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 320)
        // 👇 修复1：改为使用系统窗口背景色，自动适配黑夜模式
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    func saveItem() {
        let tags = tagString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        globalState.lastUsedTags = tags
        
        let newItem = MemoryItem(type: inputType, content: content, answer: answer, tags: tags)
        modelContext.insert(newItem)
        
        content = ""
        answer = ""
        
        showAddForm = false
    }
}


// MARK: - 💠 复用组件（圆角编辑框 - 已修复黑夜模式和遮挡问题）
struct RoundedEditor: View {
    @Binding var text: String
    
    var body: some View {
        // 👇 修复2：显式指定 Font，防止行高塌陷
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden) // 让 TextEditor 透明，以便显示下面的背景
            .frame(minHeight: 80, maxHeight: 200)
            .padding(8) // 这个 Padding 是给文字和边框之间的距离
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            // 👇 修复3：使用 textBackgroundColor，黑夜模式下是深色，白天是白色
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            )
    }
}


// MARK: - 🎯 按钮组件
func iconButton(_ icon: String, color: Color, size: CGFloat = 36, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: size))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.3), radius: 4, y: 2)
    }
    .buttonStyle(.plain)
}


// MARK: - 工具函数
func formatTime(_ totalSeconds: Double) -> String {
    let m = Int(totalSeconds) / 60
    let s = Int(totalSeconds) % 60
    return String(format: "%02d:%02d", m, s)
}
