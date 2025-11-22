// 📄 TodoListView.swift
import SwiftUI
import SwiftData

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
// 📄 TodoListView.swift 中的 TodoCard
struct TodoCard: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) var context

    var mainColor: Color {
        if todo.isCompleted { return .gray }
        return todo.priority.color
    }

    var backgroundColor: Color {
        if todo.isCompleted { return Color(nsColor: .windowBackgroundColor) }
        return todo.priority.color.opacity(0.05)
    }

    @State private var isEditing = false    // 控制编辑弹窗

    var body: some View {
        HStack(alignment: .center, spacing: 14) {

            // 左侧圆圈（唯一点击切换完成状态的区域）
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
                .contentShape(Circle())   // 扩大命中区域
            }
            .buttonStyle(.plain)

            // 文本内容（双击进入编辑界面）
            VStack(alignment: .leading, spacing: 6) {

                Text(todo.content)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }

                HStack(spacing: 10) {
                    if !todo.isCompleted {
                        Text(todo.priority.title)
                            .font(.caption2.bold())
                            .foregroundStyle(mainColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(mainColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

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

// MARK: - ➕ 新建任务弹窗
struct AddTodoSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    
    @State private var content = ""
    @State private var priority: TodoPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    
    var body: some View {
        Form {
            Section("任务详情") {
                TextField("要做什么？", text: $content, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.body)
                
                Picker("重要性", selection: $priority) {
                    ForEach(TodoPriority.allCases) { p in
                        Label(p.title, systemImage: p.icon)
                            .foregroundStyle(p.color)
                            .tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("时间安排") {
                Toggle("设置截止时间", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("截止时间", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("添加") {
                    let todo = TodoItem(
                        content: content,
                        priority: priority,
                        dueDate: hasDueDate ? dueDate : nil
                    )
                    context.insert(todo)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
        .navigationTitle("新任务")
    }
}

struct TodoEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var todo: TodoItem
    
    let priorities = TodoPriority.allCases
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            Text("编辑事项")
                .font(.title2.bold())
                .padding(.bottom, 10)
            
            // 内容输入
            TextField("内容", text: $todo.content)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 6)
            
            // 优先级选择
            HStack {
                Text("优先级")
                Spacer()
            }
            Picker("", selection: $todo.priority) {
                ForEach(priorities) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
            
            // 截止日期
            DatePicker(
                "截止时间",
                selection: Binding(
                    get: { todo.dueDate ?? Date() },
                    set: { todo.dueDate = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            
            Spacer()
            
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
