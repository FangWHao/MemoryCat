// 📄 TodoListView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FileOpener {
    static func openAttachment(_ attachment: AttachmentItem) {
        // 1. 检查有没有数据
        guard let data = attachment.data else { return }
        
        // 2. 创建临时文件路径
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(attachment.fileName)
        
        do {
            // 3. 写入文件
            try data.write(to: fileURL)
            
            // 4. 调用系统打开
            NSWorkspace.shared.open(fileURL)
        } catch {
            print("打开文件失败: \(error)")
        }
    }
}

struct TodoListView: View {
    @Environment(\.modelContext) var context
    @Query var allTodos: [TodoItem]
    
    @State private var showAddSheet = false
    @State private var sortOption: SortOption = .priority
    
    // 排序选项
    enum SortOption: String, CaseIterable {
        case priority = "按重要性"
        case date = "按截止时间"
        case created = "按创建时间"
    }
    
    // 动态分类和排序
    var sortedTodos: [TodoItem] {
        let sorted = allTodos.sorted { t1, t2 in
            switch sortOption {
            case .priority:
                // 优先级高的在前 (数值越大越重要)
                if t1.priorityRaw != t2.priorityRaw {
                    return t1.priorityRaw > t2.priorityRaw
                }
                return t1.createdDate > t2.createdDate
            case .date:
                // 有截止日期的在前，且日期越早越急
                if let d1 = t1.dueDate, let d2 = t2.dueDate { return d1 < d2 }
                if t1.dueDate != nil { return true }
                if t2.dueDate != nil { return false }
                return t1.createdDate < t2.createdDate
            case .created:
                return t1.createdDate > t2.createdDate
            }
        }
        return sorted
    }
    
    var pendingTodos: [TodoItem] { sortedTodos.filter { !$0.isCompleted } }
    var completedTodos: [TodoItem] { sortedTodos.filter { $0.isCompleted } }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // 1. 顶部控制栏
                HStack {
                    Text("待办事项")
                        .font(.largeTitle.bold())
                    
                    Spacer()
                    
                    Picker("排序", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    Button(action: { showAddSheet = true }) {
                        Label("新建任务", systemImage: "plus")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)
                
                // 2. 未完成区域
                VStack(alignment: .leading, spacing: 12) {
                    Label("进行中 (\(pendingTodos.count))", systemImage: "list.bullet.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    
                    if pendingTodos.isEmpty {
                        ContentUnavailableView("真棒！", systemImage: "balloon.2.fill", description: Text("当前没有待办任务"))
                            .frame(height: 150)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(pendingTodos) { todo in
                                TodoCard(todo: todo)
                            }
                        }
                    }
                }
                
                Divider().padding(.vertical, 10)
                
                // 3. 已完成区域
                VStack(alignment: .leading, spacing: 12) {
                    Label("已完成 (\(completedTodos.count))", systemImage: "checkmark.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    
                    if !completedTodos.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(completedTodos) { todo in
                                TodoCard(todo: todo)
                            }
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(Color(nsColor: .controlBackgroundColor)) // 稍微深一点的底色
        .sheet(isPresented: $showAddSheet) {
            AddTodoSheet()
        }
    }
}

// MARK: - 📝 单个任务卡片
struct TodoCard: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) var context
    
    // 🎨 颜色逻辑
    var mainColor: Color {
        if todo.isCompleted { return .gray }
        return todo.priority.color
    }
    
    var backgroundColor: Color {
        if todo.isCompleted { return Color(nsColor: .windowBackgroundColor) }
        return todo.priority.color.opacity(0.05)
    }
    
    @State private var isEditing = false
    @State private var showAttachmentsPopover = false // ✨ 新增：控制气泡显示
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            
            // 左侧圆圈 (完成状态切换)
            Button(action: toggleStatus) {
                ZStack {
                    if todo.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(mainColor)
                    } else {
                        Circle()
                            .stroke(mainColor.opacity(0.45), lineWidth: 2)
                            .frame(width: 22, height: 22)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            
            // 中间文本区域
            VStack(alignment: .leading, spacing: 6) {
                Text(todo.content)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { isEditing = true } // 双击编辑
                
                HStack(spacing: 10) {
                    // 优先级标签
                    if !todo.isCompleted {
                        Text(todo.priority.title)
                            .font(.caption2.bold())
                            .foregroundStyle(mainColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(mainColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    // ✨✨✨ 附件气泡按钮 (修改了这里) ✨✨✨
                    if !todo.attachments.isEmpty {
                        Button {
                            showAttachmentsPopover = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "paperclip")
                                Text("\(todo.attachments.count)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1)) // 稍微深一点的底色
                            .cornerRadius(4)
                            // 增加 hover 效果提示可点击
                            .onHover { isHover in
                                if isHover { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                        .buttonStyle(.plain)
                        // 👇 核心：点击弹出的气泡
                        .popover(isPresented: $showAttachmentsPopover, arrowEdge: .bottom) {
                            AttachmentPopoverList(attachments: todo.attachments)
                        }
                    }

                    // 截止日期
                    if let date = todo.dueDate {
                        Text(date.formatted(date: .numeric, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(date < Date() && !todo.isCompleted ? .red : .secondary)
                    }
                }
            }
            .animation(.easeInOut, value: todo.isCompleted)
            
            Spacer()
            
            // 删除按钮
            Button {
                context.delete(todo)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.6)
        )
        .sheet(isPresented: $isEditing) {
            TodoEditorView(todo: todo)
        }
    }
    
    private func toggleStatus() {
        todo.isCompleted.toggle()
    }
}

// MARK: - 📎 气泡里的文件列表视图
// 把这个放在 TodoListView.swift 的末尾
struct AttachmentPopoverList: View {
    let attachments: [AttachmentItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Label("附件列表", systemImage: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(attachments.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Divider()
            
            // 列表
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(attachments) { file in
                        Button {
                            // 点击直接打开
                            FileOpener.openAttachment(file)
                        } label: {
                            HStack(spacing: 8) {
                                // 根据类型显示简单图标
                                Image(systemName: getIcon(for: file.fileType))
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                
                                Text(file.fileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                // 打开箭头
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.clear) // 占位用于 Hover
                            .contentShape(Rectangle()) // 让整行都可点击
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            // 简单的 Hover 变色效果可以通过 modifier 实现，
                            // 但在 List/ScrollView 里 buttonStyle(.plain) + contentShape 配合通常就够了
                            // 如果想要更明显的 hover 背景，可以在这里加 .background
                        }
                    }
                }
            }
            .frame(maxHeight: 200) // 限制高度，文件太多时滚动
        }
        .padding(16)
        .frame(width: 280) // 气泡宽度
    }
    
    func getIcon(for ext: String) -> String {
        if ["jpg", "png", "jpeg", "heic"].contains(ext) { return "photo" }
        if ["pdf"].contains(ext) { return "doc.text.fill" }
        return "doc"
    }
}

// MARK: - ➕ 新建任务弹窗

struct AddTodoSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    
    // ... (其他状态变量 content, priority 等保持不变) ...
    @State private var content = ""
    @State private var priority: TodoPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    
    // 附件状态
    @State private var tempAttachments: [AttachmentItem] = []
    @State private var isImporting: Bool = false
    @State private var isTargeted: Bool = false // ✨ 新增：拖拽悬停状态
    
    var body: some View {
        VStack(spacing: 0) {
            // ... (顶部标题栏代码保持不变) ...
            HStack {
                Text("新建任务")
                    .font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(.ultraThinMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // ... (内容输入框、优先级、时间选择代码 保持不变) ...
                    VStack(alignment: .leading, spacing: 8) {
                        Text("要做什么？")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：看完 SwiftData 文档...", text: $content, axis: .vertical)
                            .font(.system(size: 18, weight: .medium))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(12)
                            .lineLimit(2...5)
                    }

                    HStack(alignment: .top, spacing: 20) {
                        // 优先级
                        VStack(alignment: .leading, spacing: 8) {
                            Text("优先级").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(TodoPriority.allCases) { p in
                                    PriorityChip(priority: p, isSelected: priority == p) {
                                        withAnimation { priority = p }
                                    }
                                }
                            }
                        }
                        // 时间
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("截止时间").font(.caption).foregroundStyle(.secondary)
                                Toggle("", isOn: $hasDueDate).labelsHidden().toggleStyle(.switch).scaleEffect(0.7)
                            }
                            if hasDueDate {
                                DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden().datePickerStyle(.compact)
                            } else {
                                Text("无截止日期").font(.subheadline).foregroundStyle(.tertiary).frame(height: 24)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 4. 📎 附件区域 (✨ 已增强：支持拖拽 & 打开)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("附件", systemImage: "paperclip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !tempAttachments.isEmpty {
                                Text("\(tempAttachments.count) 个文件")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // ✨ 拖拽接收区
                        ZStack {
                            if tempAttachments.isEmpty {
                                Button { isImporting = true } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "arrow.up.doc")
                                            .font(.title2)
                                        Text("点击添加 或 拖拽文件到这里")
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(isTargeted ? .blue : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80) // 加高一点，方便拖拽
                                    .background(isTargeted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                            .foregroundStyle(isTargeted ? .blue : .secondary.opacity(0.2))
                                    )
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // 已有附件
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(tempAttachments) { file in
                                            // ✨ 这里调用了修改后的 Chip，支持点击打开
                                            AttachmentPreviewChip(file: file) {
                                                if let idx = tempAttachments.firstIndex(of: file) {
                                                    withAnimation { tempAttachments.remove(at: idx) }
                                                }
                                            }
                                        }
                                        Button { isImporting = true } label: {
                                            Image(systemName: "plus")
                                                .frame(width: 40, height: 40)
                                                .background(Color.gray.opacity(0.1))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        // ✨✨✨ 核心：支持拖拽 ✨✨✨
                        .onDrop(of: [.item], isTargeted: $isTargeted) { providers in
                            loadProviders(providers)
                            return true
                        }
                    }
                }
                .padding(24)
            }
            
            // ... (底部按钮栏保持不变) ...
            HStack {
                Spacer()
                Button("添加任务") { saveTodo() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .top)
        }
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
    }
    
    // ... (saveTodo, handleFileImport 保持不变) ...
    func saveTodo() {
        let todo = TodoItem(content: content, priority: priority, dueDate: hasDueDate ? dueDate : nil)
        todo.attachments = tempAttachments
        context.insert(todo)
        dismiss()
    }
    
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    let newItem = AttachmentItem(fileName: url.lastPathComponent, data: data)
                    withAnimation { tempAttachments.append(newItem) }
                } catch { print("读取失败: \(error)") }
            }
        case .failure(let error): print("选择失败: \(error)")
        }
    }
    
    // ✨✨✨ 处理拖拽文件的逻辑 ✨✨✨
    func loadProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            // 尝试加载为 URL (文件)
            if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                _ = provider.loadDataRepresentation(for: UTType.item) { data, error in
                    if let data = data {
                        // 这是一个异步回调，且通常只能拿到 Data，拿不到文件名（有些复杂）
                        // 为了简化，我们尝试加载文件名属性
                        let fileName = provider.suggestedName ?? "未知文件_\(Date().timeIntervalSince1970)"
                        
                        // 回到主线程更新 UI
                        Task { @MainActor in
                            let newItem = AttachmentItem(fileName: fileName, data: data)
                            withAnimation {
                                self.tempAttachments.append(newItem)
                            }
                        }
                    }
                }
            }
        }
    }
}
// MARK: - ✨ 美化组件：优先级选择胶囊
struct PriorityChip: View {
    let priority: TodoPriority
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: priority.icon)
                        .font(.caption)
                }
                Text(priority.title)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? priority.color : priority.color.opacity(0.1))
            .foregroundStyle(isSelected ? .white : priority.color)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(priority.color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
            .shadow(color: isSelected ? priority.color.opacity(0.4) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ✨ 美化组件：附件预览胶囊
struct AttachmentPreviewChip: View {
    let file: AttachmentItem
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var iconName: String {
        let ext = file.fileType
        if ["jpg", "png", "jpeg", "heic"].contains(ext) { return "photo" }
        if ["pdf"].contains(ext) { return "doc.text.fill" }
        if ["doc", "docx", "txt", "md"].contains(ext) { return "doc.text" }
        return "doc"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 90) // 稍微宽一点
                
                if let size = file.data?.count {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.scale)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(isHovering ? 0.2 : 0.1)) // Hover 变色
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        // ✨✨✨ 双击打开文件 ✨✨✨
        .onTapGesture(count: 2) {
            FileOpener.openAttachment(file)
        }
        .help("双击打开预览") // 鼠标悬停提示
    }
}

// 在 TodoListView.swift 中

struct TodoEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Bindable var todo: TodoItem
    
    // 拖拽和文件选择状态
    @State private var isTargeted: Bool = false
    @State private var isImporting: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. 顶部标题栏 (磨砂玻璃)
            HStack {
                Text("编辑任务")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .bottom)
            
            // 2. 内容滚动区
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 📝 内容输入 (大号文本框)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("要做什么？")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("任务内容...", text: $todo.content, axis: .vertical)
                            .font(.system(size: 18, weight: .medium))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.08)) // 统一的浅灰背景
                            .cornerRadius(12)
                            .lineLimit(2...8) // 允许稍微长一点
                    }
                    
                    // 🔥 优先级 & ⏰ 时间 (并排布局)
                    HStack(alignment: .top, spacing: 20) {
                        // 优先级
                        VStack(alignment: .leading, spacing: 8) {
                            Text("优先级").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(TodoPriority.allCases) { p in
                                    PriorityChip(priority: p, isSelected: todo.priority == p) {
                                        withAnimation { todo.priority = p }
                                    }
                                }
                            }
                        }
                        
                        // 时间选择 (这里我们需要一点逻辑来处理 Date? 的绑定)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("截止时间").font(.caption).foregroundStyle(.secondary)
                                Toggle("", isOn: Binding(
                                    get: { todo.dueDate != nil },
                                    set: { if $0 { todo.dueDate = Date() } else { todo.dueDate = nil } }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                            }
                            
                            if let date = todo.dueDate {
                                DatePicker("", selection: Binding(
                                    get: { date },
                                    set: { todo.dueDate = $0 }
                                ), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                            } else {
                                Text("无截止日期")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 24)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 📎 附件区域 (支持拖拽添加！)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("附件", systemImage: "paperclip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(todo.attachments.count) 个文件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 拖拽接收区
                        ZStack {
                            // 背景 (拖拽悬停时变色)
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isTargeted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                        .foregroundStyle(isTargeted ? .blue : .clear) // 平时隐藏边框，拖拽时显示
                                )
                            
                            if todo.attachments.isEmpty {
                                // 空状态
                                Button { isImporting = true } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "arrow.up.doc")
                                            .font(.title2)
                                        Text("点击添加 或 拖拽文件到这里")
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // 附件列表
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(todo.attachments) { file in
                                            AttachmentPreviewChip(file: file) {
                                                // 删除逻辑
                                                if let idx = todo.attachments.firstIndex(of: file) {
                                                    withAnimation {
                                                        // 显式从 Context 删除，防止留下孤儿数据
                                                        context.delete(file)
                                                        // 数组也会自动更新
                                                    }
                                                }
                                            }
                                        }
                                        
                                        // 列表末尾的添加按钮
                                        Button { isImporting = true } label: {
                                            Image(systemName: "plus")
                                                .frame(width: 40, height: 40)
                                                .background(Color.gray.opacity(0.1))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(12)
                                }
                            }
                        }
                        .frame(minHeight: 80) // 确保有足够的高度接收拖拽
                        // ✨ 拖拽核心
                        .onDrop(of: [.item], isTargeted: $isTargeted) { providers in
                            loadProviders(providers)
                            return true
                        }
                    }
                }
                .padding(24)
            }
            
            // 3. 底部完成按钮
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large) // 更大的按钮
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .top)
        }
        .frame(width: 500, height: 600) // 保持和新建界面一致的尺寸
        .background(Color(nsColor: .windowBackgroundColor))
        // 文件选择器
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
    }
    
    // MARK: - 逻辑处理 (复用 AddTodoSheet 的逻辑，但直接操作 todo 对象)
    
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    let newItem = AttachmentItem(fileName: url.lastPathComponent, data: data)
                    // ✨ 直接加到当前的 todo 里，SwiftData 会自动保存
                    withAnimation { todo.attachments.append(newItem) }
                } catch { print("读取失败: \(error)") }
            }
        case .failure(let error): print("选择失败: \(error)")
        }
    }
    
    func loadProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                _ = provider.loadDataRepresentation(for: UTType.item) { data, error in
                    if let data = data {
                        let fileName = provider.suggestedName ?? "新文件_\(Date().timeIntervalSince1970)"
                        Task { @MainActor in
                            let newItem = AttachmentItem(fileName: fileName, data: data)
                            withAnimation { todo.attachments.append(newItem) }
                        }
                    }
                }
            }
        }
    }
}
