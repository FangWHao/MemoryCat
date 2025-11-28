import SwiftUI
import SwiftData

struct MiniTimerView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) private var modelContext
    
    // 👇 获取所有条目以生成标签云
    @Query private var allItems: [MemoryItem]
    
    @State private var showAddForm = false
    @State private var inputType: ItemType = .textOnly
    @State private var content = ""
    @State private var answer = ""
    @State private var tagString = ""
    
    @State private var inputDuration: Double = 25
    @State private var showToast = false
    
    // 计算去重后的所有标签
    var existingTags: [String] {
        Array(Set(allItems.flatMap { $0.tags })).sorted()
    }
    
    // 动态窗口高度：收紧数值，去除底部留白
    var windowHeight: CGFloat {
        if !showAddForm {
            return 160
        } else {
            // 👇 修改了这里：QA模式 520，文本模式 380
            // 这样既能容纳内容，又不会有“大下巴”
            return inputType == .qa ? 480 : 370
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            VStack(spacing: 0) {
                
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
                .padding(16)
                
                Divider()
                
                // MARK: - 添加区 / 底部状态
                if showAddForm {
                    VStack(alignment: .leading, spacing: 14) {
                        
                        // 类型选择
                        Picker("类型", selection: $inputType) {
                            Text("文本").tag(ItemType.textOnly)
                            Text("Q&A").tag(ItemType.qa)
                        }
                        .pickerStyle(.segmented)
                        
                        // 中间滚动区 (防溢出)
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                
                                // 内容输入
                                RoundedEditor(text: $content, placeholder: "内容 / 问题...")
                                
                                if inputType == .qa {
                                    // 答案输入
                                    RoundedEditor(text: $answer, placeholder: "答案...")
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                                
                                // 🏷️ 标签输入与选择区
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("标签 (逗号分隔)", text: $tagString)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    if !existingTags.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(existingTags, id: \.self) { tag in
                                                    MiniTagChip(
                                                        title: tag,
                                                        isSelected: currentTags.contains(tag)
                                                    ) {
                                                        toggleTag(tag)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 底部按钮组
                        HStack {
                            Button("取消") {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    showAddForm = false
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Button("保存") { saveItem() }
                                .buttonStyle(.borderedProminent)
                                .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                } else {
                    // 收起状态下的底部条
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showAddForm = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("快速添加条目")
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button("打开主界面") {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .transition(.opacity)
                }
                
                Spacer(minLength: 0)
            }
            
            // Toast 提示
            if showToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("添加成功喵！✨")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.8)).shadow(radius: 5))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .frame(width: 340)
        .frame(height: windowHeight) // 动态高度
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: windowHeight)
    }
    
    // MARK: - 逻辑处理
    
    var currentTags: [String] {
        tagString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
    
    func toggleTag(_ tag: String) {
        var tags = currentTags
        if tags.contains(tag) {
            tags.removeAll { $0 == tag }
        } else {
            tags.append(tag)
        }
        tagString = tags.joined(separator: ", ")
    }
    
    func saveItem() {
        let tags = currentTags.filter { !$0.isEmpty }
        globalState.lastUsedTags = tags
        let newItem = MemoryItem(type: inputType, content: content, answer: answer, tags: tags)
        modelContext.insert(newItem)
        try? modelContext.save()
        
        content = ""
        answer = ""
        
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showAddForm = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - 📦 增强版组件

struct RoundedEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: $text)
                .font(.body)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 100)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

struct MiniTagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? .clear : .gray.opacity(0.2), lineWidth: 0.5))
        }.buttonStyle(.plain)
    }
}

func iconButton(_ icon: String, color: Color, size: CGFloat = 36, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: size))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.3), radius: 4, y: 2)
    }
    .buttonStyle(.plain)
}

func formatTime(_ totalSeconds: Double) -> String {
    let m = Int(totalSeconds) / 60
    let s = Int(totalSeconds) % 60
    return String(format: "%02d:%02d", m, s)
}
