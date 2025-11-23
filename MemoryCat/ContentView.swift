import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) var modelContext
    
    @State private var selection: SidebarItem? = .focus
    @State private var showAddSheet = false
    
    enum SidebarItem {
        case focus
        case todo
        case review
        case allList
        case stats
        case screenTime // 👈 1. 新增枚举
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Focus") {
                    Label(globalState.isTimerRunning ? "专注中" : "番茄钟",
                          systemImage: globalState.isTimerRunning ? "timer.circle.fill" : "timer")
                    .tag(SidebarItem.focus)
                    // 修复逻辑：只有在 [没被选中] 且 [倒计时运行中] 时才变绿
                    // 否则使用 .primary (选中时系统会自动处理成高对比度的白色)
                    .foregroundStyle(
                        (globalState.isTimerRunning && selection != .focus) ? .green : .primary
                    )
                    Label("待办清单", systemImage: "checkmark.square.fill")
                        .tag(SidebarItem.todo)
                        .foregroundStyle(.blue)
                }
                
                Section("Memory") {
                    Label("复习", systemImage: "brain.head.profile").tag(SidebarItem.review)
                    Label("知识库", systemImage: "books.vertical").tag(SidebarItem.allList)
                }
                
                Section("Data") {
                    Label("学习统计", systemImage: "chart.xyaxis.line").tag(SidebarItem.stats)
                    Label("屏幕时间", systemImage: "laptopcomputer").tag(SidebarItem.screenTime)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            
            // 👇👇👇【新增代码】在这里插入底部卡片 👇👇👇
            .safeAreaInset(edge: .bottom) {
                SidebarStatsCard()
            }
            // 👆👆👆【新增结束】👆👆👆
            
            
            .toolbar {
                ToolbarItem {
                    Button(action: { showAddSheet = true }) { Label("新建", systemImage: "plus") }
                }
            }
        } detail: {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                    .ignoresSafeArea()
                
                switch selection {
                case .focus: PomodoroView()
                case .todo: TodoListView()
                case .review: ReviewSessionView()
                case .allList: AllItemsListView()
                case .stats: StatsView()
                case .screenTime: ScreenTimeView()
                case .none: Text("请选择左侧菜单")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { AddItemView() }
        .onAppear {
            globalState.sharedContext = modelContext
            globalState.startScreenMonitoring(context: modelContext)
        }
    }
}

// MARK: - 🧠 复习界面 (已升级标签筛选功能 + 美化)
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) var colorScheme // 👈 加这行，放在 context 下面
    @Query(sort: \MemoryItem.nextReviewDate) var allItems: [MemoryItem]
    
    // ... 状态定义保持不变 ...
    enum SessionState { case idle, active, completed }
    enum ReviewMode: String, CaseIterable {
        case dueToday = "今日到期"
        case new24h = "新学一遍 (24h)"
        case reviewAhead = "提前复习"
    }
    
    @State private var reviewMode: ReviewMode = .dueToday
    @State private var sessionState: SessionState = .idle
    @State private var isFlipped = false
    @State private var sessionQueue: [MemoryItem] = []
    @State private var currentIndex: Int = 0
    @State private var selectedTags: Set<String> = []
    
    // 动画状态
    @State private var startButtonScale: CGFloat = 1.0
    
    var allTags: [String] { Array(Set(allItems.flatMap { $0.tags })).sorted() }
    
    var progressText: String {
        guard !sessionQueue.isEmpty else { return "0/0" }
        return "\(currentIndex + 1)/\(sessionQueue.count)"
    }
    
    var potentialItems: [MemoryItem] {
        let timeFilteredItems: [MemoryItem]
        switch reviewMode {
        case .dueToday:
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
            timeFilteredItems = allItems.filter { $0.nextReviewDate <= endOfDay }
        case .new24h:
            let yesterday = Date.now.addingTimeInterval(-86400)
            timeFilteredItems = allItems.filter { $0.createdDate >= yesterday }
        case .reviewAhead:
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
            timeFilteredItems = Array(allItems.filter { $0.nextReviewDate > endOfDay }.prefix(20))
        }
        
        if selectedTags.isEmpty { return timeFilteredItems }
        else { return timeFilteredItems.filter { item in
            !Set(item.tags).isDisjoint(with: selectedTags)
        } }
    }
    
    // 🎨 动态背景色
    var bgGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        ZStack {
            // 背景层
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            bgGradient.ignoresSafeArea()
            let orbOpacity = colorScheme == .dark ? 0.03 : 0.1
            // 氛围光斑
            Circle().fill(Color.blue.opacity(0.03)).frame(width: 400).offset(x: -200, y: -200).blur(radius: 50)
            Circle().fill(Color.purple.opacity(0.03)).frame(width: 300).offset(x: 200, y: 200).blur(radius: 50)
            
            VStack(spacing: 0) {
                
                // 👇👇👇 核心修改区域 Start 👇👇👇
                // 只有在 idle (准备) 状态下，才渲染顶部的控制栏
                // 这样开始专注后，它们会被物理移除，不占空间
                if sessionState == .idle {
                    VStack(spacing: 16) {
                        
                        // 1. 模式选择器
                        ModernReviewPicker(selection: $reviewMode)
                        
                        // 2. 标签筛选栏
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                TagChip(title: "全部", isSelected: selectedTags.isEmpty, icon: "tray.full.fill") {
                                    withAnimation { selectedTags.removeAll() }
                                }
                                
                                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 20)
                                
                                ForEach(allTags, id: \.self) { tag in
                                    TagChip(title: tag, isSelected: selectedTags.contains(tag), icon: "tag.fill") {
                                        withAnimation(.spring()) {
                                            if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                            else { selectedTags.insert(tag) }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 40)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)
                    .overlay(Divider(), alignment: .bottom)
                    .zIndex(10)
                    // 👇 加一个过渡动画，让消失更自然，不要突然闪没
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // 👆👆👆 核心修改区域 End 👆👆👆
                
                Spacer()
                
                // 内容切换区
                switch sessionState {
                case .idle:
                    idleView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .active:
                    activeReviewView
                    // 进入时从右边滑入，退出时向左滑出
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .completed:
                    completedView
                        .transition(.opacity)
                }
                
                Spacer()
            }
        }
        // 监听模式变化，重置状态
        .onChange(of: reviewMode) { _, _ in
            sessionState = .idle
            selectedTags.removeAll()
        }
        // 显式添加动画，让 if sessionState == .idle 的切换有动画效果
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: sessionState)
    }
    
    // MARK: - 🏠 准备界面 (任务简报卡片)
    var idleView: some View {
        VStack(spacing: 30) {
            
            // 卡片容器
            ZStack {
                // 1. 背景层：根据模式自动切换材质
                if colorScheme == .dark {
                    // 🌙 深色模式：保持磨砂玻璃，高级！
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
                } else {
                    // ☀️ 浅色模式：改用纯白陶瓷，干净！
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                    // 白天阴影要重一点，不然看不清边界
                        .shadow(color: .black.opacity(0.1), radius: 15, y: 8)
                }
                
                // 2. 边框层：浅色模式下稍微减弱一点描边
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.2 : 0.6),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                
                VStack(spacing: 24) {
                    // 图标区
                    ZStack {
                        // 浅色模式下，图标背景也改用纯白，防透
                        Circle()
                            .fill(colorScheme == .dark ? Color.blue.opacity(0.1) : Color.blue.opacity(0.05))
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .padding(.top, 10)
                    
                    VStack(spacing: 4) {
                        Text(reviewMode.rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        
                        if !selectedTags.isEmpty {
                            Text("筛选: " + selectedTags.joined(separator: " + "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("全科目覆盖")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider().padding(.horizontal, 40)
                    
                    // 数据展示
                    if potentialItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title)
                            Text("暂无任务").font(.headline)
                            Text("去休息一下或者换个模式吧喵~").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 20)
                    } else {
                        VStack(spacing: 4) {
                            Text("\(potentialItems.count)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            
                            Text("个待处理项")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 20)
                        }
                        
                        // 开始按钮
                        Button(action: startSession) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("开始专注")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 180, height: 50)
                            .background(
                                LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(startButtonScale)
                        .onHover { isHover in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                startButtonScale = isHover ? 1.05 : 1.0
                            }
                        }
                    }
                }
                .padding(40)
            }
            .frame(width: 400, height: 420)
        }
    }
    
    // MARK: - 📖 进行中界面 (保持之前的逻辑，微调样式)
    var activeReviewView: some View {
        VStack {
            // 顶部进度指示器
            HStack(spacing: 12) {
                ProgressView(value: Double(currentIndex), total: Double(sessionQueue.count))
                    .progressViewStyle(.linear)
                    .tint(.blue)
                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 300)
            .padding(.bottom, 30)
            
            if currentIndex < sessionQueue.count {
                let item = sessionQueue[currentIndex]
                
                // 卡片翻转容器
                ZStack {
                    // 卡片背景
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
                        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.1), lineWidth: 1))
                    
                    VStack {
                        // 顶部：标签
                        HStack {
                            ForEach(item.tags.prefix(3), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            // 难度指示器 (假设 item 有 easeFactor)
                            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(24)
                        
                        Spacer()
                        
                        // 中间：内容
                        VStack(spacing: 24) {
                            Text(item.content)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .padding(.horizontal)
                            
                            if isFlipped && item.type == .qa {
                                Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 1).padding(.horizontal, 40)
                                
                                Text(item.answer)
                                    .font(.system(size: 22, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        
                        Spacer()
                        
                        // 底部：提示
                        if item.type == .qa && !isFlipped {
                            Text("点击卡片查看背面")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.bottom, 24)
                        } else {
                            // 占位，保持布局稳定
                            Color.clear.frame(height: 16).padding(.bottom, 24)
                        }
                    }
                }
                .frame(maxWidth: 650, maxHeight: 480)
                .contentShape(Rectangle())
                .onTapGesture {
                    if item.type == .qa { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isFlipped.toggle() } }
                }
                
                // 底部操作区 (分离式设计)
                HStack(spacing: 40) {
                    if item.type == .qa && !isFlipped {
                        Button(action: { withAnimation(.spring()) { isFlipped = true } }) {
                            Text("显示答案")
                                .font(.headline)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                                .shadow(color: .black.opacity(0.05), radius: 5)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 忘记按钮
                        FeedbackBtn(icon: "xmark", title: "忘记", color: .red) {
                            processAnswer(item, remembered: false)
                        }
                        // 记得按钮
                        FeedbackBtn(icon: "checkmark", title: "记得", color: .green) {
                            processAnswer(item, remembered: true)
                        }
                    }
                }
                .padding(.top, 40)
                .frame(height: 80)
            }
        }
    }
    
    // MARK: - ✅ 完成界面 (奖章风格)
    var completedView: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.yellow.opacity(0.2), .orange.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 150, height: 150)
                    .blur(radius: 10)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .orange.opacity(0.4), radius: 10, y: 10)
            }
            
            VStack(spacing: 8) {
                Text("太棒了！")
                    .font(.largeTitle.bold())
                
                Text("本次复习已全部完成")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 20) {
                Button("返回首页") { sessionState = .idle }
                    .buttonStyle(SecondaryBtnStyle())
                
                Button("再来一组") {
                    if !potentialItems.isEmpty { startSession() } else { sessionState = .idle }
                }
                .buttonStyle(PrimaryBtnStyle())
                .disabled(potentialItems.isEmpty)
            }
            .padding(.top, 20)
        }
    }
    
    // ... 逻辑函数 (startSession, processAnswer, deleteCurrentItem) 保持不变，直接复制之前的即可 ...
    func startSession() {
        sessionQueue = potentialItems
        currentIndex = 0
        isFlipped = false
        withAnimation { sessionState = .active }
    }
    
    func processAnswer(_ item: MemoryItem, remembered: Bool) {
        withAnimation {
            item.processReview(remembered: remembered, context: context)
            try? context.save()
            isFlipped = false
            currentIndex += 1
            if currentIndex >= sessionQueue.count { sessionState = .completed }
        }
    }
    
    func deleteCurrentItem(_ item: MemoryItem) {
        withAnimation {
            context.delete(item)
            try? context.save()
            if currentIndex < sessionQueue.count { sessionQueue.remove(at: currentIndex) }
            isFlipped = false
            if sessionQueue.isEmpty || currentIndex >= sessionQueue.count { sessionState = .completed }
        }
    }
}

// MARK: - 🎨 美化组件

// 1. 胶囊标签组件
struct TagChip: View {
    let title: String
    let isSelected: Bool
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.primary.opacity(0.05)
                    }
                }
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? .clear : .primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// 2. 只有图标和文字的大按钮 (用于记得/忘记)
struct FeedbackBtn: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isHovering ? 0.2 : 0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.title2.bold())
                        .foregroundStyle(color)
                }
                .scaleEffect(isHovering ? 1.1 : 1.0)
                
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(), value: isHovering)
    }
}

// 3. 通用按钮样式
struct PrimaryBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut, value: configuration.isPressed)
    }
}

struct SecondaryBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
// MARK: - 📚 知识库视图
struct AllItemsListView: View {
    @Environment(\.modelContext) var context
    // 排序默认按创建时间倒序
    @Query(sort: \MemoryItem.createdDate, order: .reverse) var items: [MemoryItem]
    
    @State private var selection = Set<MemoryItem.ID>()
    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var sortOrder = [KeyPathComparator(\MemoryItem.createdDate, order: .reverse)]
    
    // 👇 控制编辑弹窗的变量
    @State private var editingItem: MemoryItem?
    
    var allTags: [String] { Array(Set(items.flatMap { $0.tags })).sorted() }
    
    var filteredItems: [MemoryItem] {
        var result = items
        if let tag = selectedTag { result = result.filter { $0.tags.contains(tag) } }
        if !searchText.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部筛选栏 (保持不变)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterChip(title: "全部", isSelected: selectedTag == nil) { selectedTag = nil }
                    ForEach(allTags, id: \.self) { tag in
                        FilterChip(title: tag, isSelected: selectedTag == tag) { selectedTag = tag }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            // 👇👇👇 升级后的表格
            Table(filteredItems, selection: $selection, sortOrder: $sortOrder) {
                
                // 1. 创建日期列
                TableColumn("创建日期", value: \.createdDate) { item in
                    Text(item.createdDate.formatted(date: .numeric, time: .omitted))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle()) // 扩大点击区域
                        .onTapGesture(count: 2) { editingItem = item } // 双击编辑
                }
                .width(min: 80, ideal: 100, max: 100)
                
                // 2. 类型列
                TableColumn("类型", value: \.type.rawValue) { item in
                    Text(item.type == .qa ? "QA" : "文本")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.type == .qa ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                        .cornerRadius(4)
                        .onTapGesture(count: 2) { editingItem = item }
                }
                .width(50)
                
                // 3. 内容列 (只显示Q或Text)
                TableColumn("内容 / 问题", value: \.content) { item in
                    HStack {
                        if item.type == .qa {
                            Image(systemName: "q.circle.fill").foregroundStyle(.blue.opacity(0.7))
                        }
                        Text(item.content)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingItem = item }
                }
                
                // 4. 记忆进度列 (新增！)
                TableColumn("记忆进度", value: \.nextReviewDate) { item in
                    HStack(spacing: 6) {
                        // 等级图标
                        if item.repetition == 0 {
                            Text("🌱 新手").font(.caption).foregroundStyle(.secondary)
                        } else if item.repetition < 3 {
                            Text("🪵 入门").font(.caption).foregroundStyle(.orange)
                        } else if item.repetition < 6 {
                            Text("🔥 熟练").font(.caption).foregroundStyle(.blue)
                        } else {
                            Text("💎 大师").font(.caption).foregroundStyle(.purple)
                        }
                        
                        Spacer()
                        
                        // 下次复习时间提示
                        if item.nextReviewDate <= Date() {
                            Text("待复习").font(.caption2).bold().foregroundStyle(.red)
                        } else {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: item.nextReviewDate).day ?? 0
                            Text("\(days)天后").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingItem = item }
                }
                .width(min: 100, ideal: 120, max: 150)
                
                // 5. 标签列
                TableColumn("标签") { item in
                    Text(item.tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .onTapGesture(count: 2) { editingItem = item }
                }
            }
            .searchable(text: $searchText)
            
            // 底部操作栏 (保持不变)
            if !selection.isEmpty {
                HStack {
                    Text("已选 \(selection.count)")
                    Spacer()
                    Button("删除", role: .destructive) { deleteSelected() }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("知识库")
        // 👇 绑定弹窗
        .sheet(item: $editingItem) { item in
            EditItemView(item: item)
        }
        .contextMenu(forSelectionType: MemoryItem.ID.self) { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                Button("编辑内容") { editingItem = item }
                Divider()
            }
            Button("删除") { deleteSelected() }
        }
    }
    
    func deleteSelected() {
        withAnimation {
            let toDel = items.filter { selection.contains($0.id) }
            toDel.forEach { context.delete($0) }
            selection.removeAll()
        }
    }
}
// MARK: - 📊 统计视图 (包含今日专注时间)
struct StatsView: View {
    // 数据源
    @Query(sort: \PomodoroRecord.date) var pomoRecords: [PomodoroRecord]
    @Query(sort: \ReviewLog.date) var reviewLogs: [ReviewLog]
    @Query(sort: \MemoryItem.createdDate) var allItems: [MemoryItem]
    @Query(sort: \MemoryItem.nextReviewDate) var pendingItems: [MemoryItem]
    
    @State private var chartType: ChartType = .review
    @State private var visualizationMode: VisMode = .trend
    
    // 👇👇👇 新增：年份选择状态，默认当前年份
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // ... (Enum 和 DateValue 结构体保持不变) ...
    enum ChartType: String, CaseIterable {
        case review = "复习量"
        case added = "新增量"
        case focus = "专注时长"
    }
    
    enum VisMode: String, CaseIterable {
        case trend = "趋势图"
        case activity = "热力图"
    }
    
    struct DateValue: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
    
    // ... (getData 函数保持不变) ...
    func getData(for type: ChartType) -> [DateValue] {
        let grouped: [Date: Double]
        switch type {
        case .review:
            grouped = Dictionary(grouping: reviewLogs) { Calendar.current.startOfDay(for: $0.date) }
                .mapValues { Double($0.count) }
        case .added:
            grouped = Dictionary(grouping: allItems) { Calendar.current.startOfDay(for: $0.createdDate) }
                .mapValues { Double($0.count) }
        case .focus:
            grouped = Dictionary(grouping: pomoRecords) { Calendar.current.startOfDay(for: $0.date) }
                .mapValues { $0.reduce(0) { $0 + $1.duration } / 60 }
        }
        return grouped.map { DateValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }
    
    // 👇👇👇 核心逻辑修改 👇👇👇
    // 1. 今日已复习 (从 Log 获取)
    var todayReviewedCount: Int {
        reviewLogs.filter { Calendar.current.isDateInToday($0.date) }.count
    }
    
    // 2. 今日剩余 (从 Item 获取)
    var todayRemainingCount: Int {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date.now) ?? Date.now
        return pendingItems.filter { $0.nextReviewDate <= endOfToday }.count
    }
    
    // 3. 今日新创建 (从 Item 获取)
    var todayCreatedCount: Int {
        allItems.filter { Calendar.current.isDateInToday($0.createdDate) }.count
    }
    
    // 👇👇👇 4. 修正后的计划总量逻辑
    var todayPlanTotal: Int {
        // 公式：(剩下的) + (已经做的)
        // ❌ 之前减去了 todayCreatedCount，但如果您今天新建并复习了，其实也算一种“计划外的工作量”。
        // 如果您希望“计划”只显示“旧债”，可以保留减法。
        // 但为了防止奇怪的 0，建议直接用这个简单逻辑：
        // 这样“计划”会随着您添加新卡片而动态增加，看起来更合理（因为新卡片也是今天要背的嘛！）
        
        return todayRemainingCount + todayReviewedCount
    }
    
    // 5. 遗忘率
    var forgettingRate: Double {
        guard !reviewLogs.isEmpty else { return 0.0 }
        let forgottenCount = reviewLogs.filter { !$0.remembered }.count
        return Double(forgottenCount) / Double(reviewLogs.count)
    }
    
    // 6. 专注时间
    var todayFocusMinutes: Int {
        let todayRecords = pomoRecords.filter { Calendar.current.isDateInToday($0.date) }
        return Int(todayRecords.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("数据中心").font(.largeTitle.bold()).padding(.top)
                
                // 📊 数据卡片区域
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    
                    // 修改了这里的 Label
                    StatCard(
                        title: "今日进度 (已做 / 计划)",
                        value: "\(todayReviewedCount) / \(todayPlanTotal)",
                        icon: "checklist",
                        color: todayReviewedCount >= todayPlanTotal ? .green : .orange
                    )
                    
                    StatCard(
                        title: "今日专注",
                        value: "\(todayFocusMinutes) m",
                        icon: "timer",
                        color: .purple
                    )
                    
                    StatCard(
                        title: "累计条目",
                        value: "\(allItems.count)",
                        icon: "doc.on.doc",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "平均遗忘率",
                        value: String(format: "%.1f%%", forgettingRate * 100),
                        icon: "exclamationmark.triangle",
                        color: forgettingRate > 0.3 ? .red : .green
                    )
                }
                
                Divider()
                
                // 图表保持不变...
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Picker("View", selection: $visualizationMode) { ForEach(VisMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) } }.pickerStyle(.segmented).frame(width: 200)
                        Spacer()
                        Picker("Type", selection: $chartType) { ForEach(ChartType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) } }.pickerStyle(.segmented).frame(width: 300)
                    }
                    Group {
                        if visualizationMode == .trend {
                            // 📈 折线图：必须显式给高度，不然它就扁了！
                            ChartBlock(type: chartType, data: getData(for: chartType))
                                .frame(height: 350)
                        } else {
                            // 🔥 热力图：高度自动适应，不用管它
                            GitHubHeatMap(
                                data: getData(for: chartType),
                                selectedYear: $selectedYear
                            )
                        }
                    }
                }.padding()
            }.padding(40)
        }
    }
}

// MARK: - 辅助组件 (已修复报错)
struct ChartBlock: View {
    let type: StatsView.ChartType; let data: [StatsView.DateValue]
    var body: some View {
        if data.isEmpty { ContentUnavailableView("暂无数据", systemImage: "chart.xyaxis.line", description: Text("开始学习后将显示趋势")) } else {
            Chart(data) { item in
                LineMark(x: .value("日期", item.date, unit: .day), y: .value("数值", item.value)).interpolationMethod(.catmullRom).foregroundStyle(getColor()).symbol(by: .value("Type", type.rawValue))
                AreaMark(x: .value("日期", item.date, unit: .day), y: .value("数值", item.value)).foregroundStyle(getColor().opacity(0.1)).interpolationMethod(.catmullRom)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day()) } }
        }
    }
    func getColor() -> LinearGradient { switch type { case .focus: return LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing); case .review: return LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing); case .added: return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing) } }
}

struct GitHubHeatMap: View {
    let data: [StatsView.DateValue]
    @Binding var selectedYear: Int // 👈 双向绑定年份
    
    // 基础配置
    private let calendar = Calendar.current
    private let cellSize: CGFloat = 11 // GitHub 方块更小一点
    private let spacing: CGFloat = 3
    private let weekDays = ["", "Mon", "", "Wed", "", "Fri", ""] // 只有 1,3,5 显示标签
    
    // 转换数据为字典以便快速查找
    var dataMap: [Date: Int] {
        let dict = Dictionary(grouping: data) { calendar.startOfDay(for: $0.date) }
        return dict.mapValues { Int($0.first?.value ?? 0) } // 这里假设同一天只有一条汇总记录
    }
    
    // 获取当前数据中包含的所有年份（用于 Picker）
    var availableYears: [Int] {
        let years = Set(data.map { calendar.component(.year, from: $0.date) })
        var list = Array(years)
        if !list.contains(selectedYear) { list.append(selectedYear) }
        return list.sorted(by: >) // 倒序，最近的年份在前面
    }
    
    // ⭐ 核心算法：生成全年的网格数据
    // 返回结构：[WeekIndex: [DayIndex: Date]]
    var yearGrid: [[Date?]] {
        var grid = [[Date?]]()
        let year = selectedYear
        
        // 1. 找到当年的第一天和最后一天
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return []
        }
        
        // 2. 计算第一天是周几 (1=Sun, 2=Mon... 7=Sat)
        // GitHub 通常周日是第一行(索引0)，或者周一。这里我们按周日为第一天(索引0)处理
        let weekdayOfJan1 = calendar.component(.weekday, from: startOfYear) // 1~7
        let offset = weekdayOfJan1 - 1 // 需要填充的空位
        
        var currentWeek: [Date?] = Array(repeating: nil, count: offset)
        
        // 3. 遍历全年每一天
        var currentDate = startOfYear
        while currentDate <= endOfYear {
            currentWeek.append(currentDate)
            
            // 如果填满了7天，或者已经是最后一天了，就封包这一周
            if currentWeek.count == 7 {
                grid.append(currentWeek)
                currentWeek = []
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // 4. 补齐最后一周
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            grid.append(currentWeek)
        }
        
        return grid
    }
    
    // 计算月份标签的位置
    func getMonthHeaders(grid: [[Date?]]) -> [(String, CGFloat)] {
        var headers: [(String, CGFloat)] = []
        var lastMonth = -1
        
        for (index, week) in grid.enumerated() {
            // 找这一周里第一个非空的日期
            if let firstDateInWeek = week.compactMap({ $0 }).first {
                let month = calendar.component(.month, from: firstDateInWeek)
                if month != lastMonth {
                    // 只有当月份变化时才添加标签
                    let monthName = calendar.shortMonthSymbols[month - 1]
                    // 计算 x 偏移量
                    let xOffset = CGFloat(index) * (cellSize + spacing)
                    headers.append((monthName, xOffset))
                    lastMonth = month
                }
            }
        }
        return headers
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // 1. 顶部栏：年份选择器
            HStack {
                Text("\(data.count) contributions in \(String(selectedYear))")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    ForEach(availableYears, id: \.self) { year in
                        Button("\(String(year))") {
                            withAnimation { selectedYear = year }
                        }
                    }
                } label: {
                    HStack {
                        Text("Year: \(String(selectedYear))")
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
            }
            
            // 2. 热力图主体
            let grid = yearGrid
            let months = getMonthHeaders(grid: grid)
            
            HStack(alignment: .top, spacing: 8) {
                // 左侧：星期标签 (Mon, Wed, Fri)
                VStack(alignment: .leading, spacing: spacing) {
                    // 顶部留空给月份标签
                    Text(" ").font(.caption2).frame(height: 12)
                    
                    ForEach(0..<7, id: \.self) { row in
                        if row % 2 == 1 { // 只显示 1, 3, 5
                            Text(weekDays[row])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(height: cellSize)
                        } else {
                            Spacer().frame(height: cellSize)
                        }
                    }
                }
                .padding(.top, 4) // 微调对齐
                
                // 右侧：网格
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: spacing) {
                        
                        // A. 月份标签行
                        ZStack(alignment: .leading) {
                            ForEach(months, id: \.0) { (name, offset) in
                                Text(name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .offset(x: offset)
                            }
                        }
                        .frame(height: 12)
                        
                        // B. 贡献方块网格
                        HStack(spacing: spacing) {
                            ForEach(0..<grid.count, id: \.self) { colIndex in
                                VStack(spacing: spacing) {
                                    ForEach(0..<7, id: \.self) { rowIndex in
                                        if let date = grid[colIndex][rowIndex] {
                                            let count = dataMap[date] ?? 0
                                            
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(GitHubTheme.getColor(count: count))
                                                .frame(width: cellSize, height: cellSize)
                                            // 鼠标悬停显示详情
                                                .help("\(date.formatted(date: .numeric, time: .omitted)): \(count) 次")
                                        } else {
                                            // 占位符（例如这一周的开头几天属于上一年）
                                            Rectangle()
                                                .fill(.clear)
                                                .frame(width: cellSize, height: cellSize)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // 3. 底部图例
            HStack(spacing: 4) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                GitHubTheme.level0.frame(width: 10, height: 10).cornerRadius(2)
                GitHubTheme.level1.frame(width: 10, height: 10).cornerRadius(2)
                GitHubTheme.level2.frame(width: 10, height: 10).cornerRadius(2)
                GitHubTheme.level3.frame(width: 10, height: 10).cornerRadius(2)
                GitHubTheme.level4.frame(width: 10, height: 10).cornerRadius(2)
                
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor)) // 这里的背景色用系统的
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// 修复：将 Color(hex:) 的逻辑内联或使用 RGB，这里为了稳妥直接用 RGB 初始化
func getColor(value: Double) -> Color {
    if value == 0 { return Color.gray.opacity(0.2) }
    if value <= 2 { return Color(red: 0.6, green: 0.9, blue: 0.65) } // #9be9a8
    if value <= 5 { return Color(red: 0.25, green: 0.77, blue: 0.39) } // #40c463
    if value <= 10 { return Color(red: 0.19, green: 0.63, blue: 0.3) } // #30a14e
    return Color(red: 0.13, green: 0.43, blue: 0.22) // #216e39
}


struct StatCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View { HStack { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title.bold()).foregroundStyle(.primary) }; Spacer(); Image(systemName: icon).font(.title2).foregroundStyle(color).padding(10).background(color.opacity(0.1)).clipShape(Circle()) }.padding().background(Color(nsColor: .textBackgroundColor)).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 4, y: 2) }
}

struct ActionBtn: View {
    let icon: String; let label: String; let color: Color; let action: () -> Void
    @State private var h = false
    var body: some View { Button(action: action) { VStack(spacing: 8) { ZStack { Circle().fill(color).frame(width: 64, height: 64).shadow(color: color.opacity(0.4), radius: 8, y: 4); Image(systemName: icon).font(.title2.bold()).foregroundStyle(.white) }.scaleEffect(h ? 1.1 : 1.0).animation(.spring(), value: h); Text(label).font(.callout.bold()).foregroundStyle(color) } }.buttonStyle(.plain).onHover { h = $0 } }
}

struct BigControlBtn: View {
    let icon: String; let label: String; let color: Color; let action: () -> Void
    @State private var h = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(h ? 0.2 : 0.1)).frame(width: 80, height: 80)
                    Image(systemName: icon).font(.system(size: 36, weight: .medium)).foregroundStyle(color)
                }
                .scaleEffect(h ? 1.05 : 1.0).animation(.spring(), value: h)
                // 修复 Font.body.medium 报错
                Text(label).font(.body).fontWeight(.medium).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain).onHover { h = $0 }
    }
}

//struct AddItemView: View {
//    @Environment(\.modelContext) var context
//    @Environment(\.dismiss) var dismiss
//    // 👇 引入全局状态
//    @EnvironmentObject var globalState: GlobalState
//
//    @State private var t: ItemType = .textOnly
//    @State private var c = ""
//    @State private var a = ""
//    @State private var tag = ""
//
//    var body: some View {
//        Form {
//            Picker("类型", selection: $t) {
//                Text("文本").tag(ItemType.textOnly)
//                Text("Q&A").tag(ItemType.qa)
//            }
//            .pickerStyle(.segmented)
//
//            // 👇👇👇 修改这里：使用 Section 分组，视觉更清晰
//            Section("内容信息") {
//                TextField("输入内容", text: $c, axis: .vertical)
//                    .lineLimit(3...8) // 默认3行，最大8行
//                    .textFieldStyle(.roundedBorder) // 放在 Form 里最好用 plain
//                    .padding(.vertical, 4)
//
//                if t == .qa {
//                    Divider() // 加一条线隔开
//                    TextField("输入答案", text: $a, axis: .vertical)
//                        .lineLimit(3...8)
//                        .textFieldStyle(.roundedBorder)
//                        .padding(.vertical, 4)
//                }
//            }
//
//            Section("分类") {
//                TextField("标签 (逗号分隔)", text: $tag)
//            }
//
//            HStack {
//                Button("取消") { dismiss() }
//                Button("保存") {
//                    // ... 保存逻辑不变 ...
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(c.isEmpty)
//            }
//        }
//        .padding()
//        .frame(width: 450) //稍微加宽一点点
//        .onAppear {
//            if !globalState.lastUsedTags.isEmpty {
//                tag = globalState.lastUsedTags.joined(separator: ", ")
//            }
//        }
//    }
//}
struct AddItemView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var globalState: GlobalState
    
    @State private var t: ItemType = .textOnly
    @State private var c = ""
    @State private var a = ""
    @State private var tag = ""
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Picker 顶部横条
            Picker("类型", selection: $t) {
                Text("文本").tag(ItemType.textOnly)
                Text("Q&A").tag(ItemType.qa)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 10)
            
            // 内容输入卡片
            VStack(alignment: .leading, spacing: 12) {
                Text("内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                RoundedTextEditor(text: $c, minHeight: 120)
                
                if t == .qa {
                    Divider().padding(.vertical, 4)
                    
                    Text("答案")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    RoundedTextEditor(text: $a, minHeight: 120)
                }
            }
            .padding(20)
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            .padding(.horizontal)
            
            // 标签卡片
            VStack(alignment: .leading, spacing: 8) {
                Text("标签（逗号分隔）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("", text: $tag)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(20)
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            .padding(.horizontal)
            
            // 按钮
            HStack {
                Button("取消") { dismiss() }
                
                Spacer()
                
                Button("保存") {
                    saveItem()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(c.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 20)
        .frame(width: 520)
        .onAppear {
            if !globalState.lastUsedTags.isEmpty {
                tag = globalState.lastUsedTags.joined(separator: ", ")
            }
        }
    }
    
    func saveItem() {
        let tagList = tag
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let newItem = MemoryItem(
            type: t,
            content: c,
            answer: t == .qa ? a : "",
            tags: tagList
        )
        context.insert(newItem)
        try? context.save()
        globalState.updateLastUsedTags(tag)
    }
}


struct RoundedTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 100
    
    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.25))
            )
            .background(.white)
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var item: MemoryItem // 使用 @Bindable 直接修改数据
    
    @State private var tagString: String = ""
    
    var body: some View {
        Form {
            Section("基本信息") {
                Picker("类型", selection: $item.type) {
                    Text("文本").tag(ItemType.textOnly)
                    Text("Q&A").tag(ItemType.qa)
                }
                
                TextField("内容 / 问题", text: $item.content, axis: .vertical)
                    .lineLimit(5...20) // 编辑的时候可以让它更大一点！
                    .textFieldStyle(.plain) // 加上 plain 样式防止被系统样式压缩
                
                if item.type == .qa {
                    Divider()
                    Text("答案").font(.caption).foregroundStyle(.secondary)
                    TextField("输入答案", text: $item.answer, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            
            Section("标签管理") {
                TextField("标签 (逗号分隔)", text: $tagString)
                    .onChange(of: tagString) { _, newValue in
                        item.tags = newValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    }
            }
            
            Section("数据调试 (慎改)") {
                LabeledContent("创建时间", value: item.createdDate.formatted())
                LabeledContent("下次复习", value: item.nextReviewDate.formatted())
                LabeledContent("熟练度 (Rep)", value: "\(item.repetition)")
            }
            
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
            }
        }
        .padding()
        .frame(width: 450, height: 500)
        .onAppear {
            tagString = item.tags.joined(separator: ", ")
        }
    }
}


// 📄 ContentView.swift -> 替换整个 PomodoroView

struct PomodoroView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) var modelContext
    
    // 👇 1. 新增：获取所有专注记录，用于统计
    @Query(sort: \PomodoroRecord.date) var records: [PomodoroRecord]
    
    @State private var inputDuration: Double = 25
    @State private var showStopAlert = false
    
    // 👇 2. 新增：计算今日专注时长 (分钟)
    var todayMinutes: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todayRecords = records.filter { $0.date >= startOfToday }
        return Int(todayRecords.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var body: some View {
        VStack(spacing: 50) {
            // 🕒 倒计时圆环区域
            ZStack {
                // 底圈
                Circle()
                    .stroke(lineWidth: 20)
                    .opacity(0.1)
                    .foregroundStyle(Color.primary)
                
                // 进度圈
                Circle()
                    .trim(from: 0.0, to: globalState.timerProgress)
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [.blue, .cyan, .mint, .green, .blue]), center: .center),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.linear(duration: 1.0), value: globalState.timerProgress)
                    .shadow(color: .blue.opacity(0.3), radius: 10)
                
                // 中间文字
                VStack(spacing: 8) {
                    // 倒计时数字
                    Text(String(format: "%02d:%02d", Int(globalState.timeRemaining)/60, Int(globalState.timeRemaining)%60))
                        .font(.system(size: 80, weight: .light, design: .monospaced))
                        .contentTransition(.numericText())
                    
                    // 👇👇👇 修改这里：显示今日专注时长
                    if globalState.isTimerRunning {
                        // 专注中：显示状态
                        Text("FOCUS MODE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    } else {
                        // 未开始：显示今日累计
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("今日累计: \(todayMinutes) min")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(width: 320, height: 320)
            .padding(.top, 20)
            
            // 🎮 控制区域
            VStack(spacing: 30) {
                // 只有未开始时才显示时间设置
                if !globalState.isTimerRunning {
                    HStack {
                        Text("专注时长").foregroundStyle(.secondary)
                        TextField("25", value: $inputDuration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                        Text("分钟").foregroundStyle(.secondary)
                    }
                    .onChange(of: inputDuration) { _, n in
                        globalState.setDuration(n)
                    }
                } else {
                    // 专注中显示一句鼓励的话
                    Text("加油！保持专注喵！🐱")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(height: 24) // 占位防止跳动
                }
                
                // 按钮组
                HStack(spacing: 50) {
                    if globalState.isTimerRunning {
                        BigControlBtn(icon: "pause.fill", label: "暂停", color: .orange) {
                            globalState.pauseTimer()
                        }
                        
                        BigControlBtn(icon: "stop.fill", label: "放弃", color: .red) {
                            showStopAlert = true
                        }
                    } else {
                        BigControlBtn(icon: "play.fill", label: "开始", color: .green) {
                            // 确保开始前同步时间
                            globalState.setDuration(inputDuration)
                            // 传入 context 以便保存
                            globalState.startTimer(context: modelContext)
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            // 每次进来把时间同步给输入框
            inputDuration = globalState.timerDuration / 60
        }
        .alert("要放弃吗？", isPresented: $showStopAlert) {
            Button("继续专注", role: .cancel) { }
            Button("结束", role: .destructive) {
                globalState.stopTimer(finished: false)
            }
        } message: {
            Text("放弃的话，这次的努力就不会被记录咯😿")
        }
    }
}

struct FilterChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View { Button(action: action) { Text(title).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6).background(isSelected ? Color.blue : Color(nsColor: .controlColor)).foregroundStyle(isSelected ? .white : .primary).clipShape(Capsule()).overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1)) }.buttonStyle(.plain) }
}


// MARK: - 🐱 左下角侧边栏统计卡片
struct SidebarStatsCard: View {
    // 1. 获取所有专注记录 (用于计算今日)
    @Query var pomoRecords: [PomodoroRecord]
    
    // 2. 获取所有记忆条目 (用于计算待复习)
    @Query var memoryItems: [MemoryItem]
    
    // 🗓️ 计算今日数据
    var todayFocusMinutes: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todayRecords = pomoRecords.filter { $0.date >= startOfToday }
        return Int(todayRecords.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var todayFocusCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return pomoRecords.filter { $0.date >= startOfToday }.count
    }
    
    var pendingReviewCount: Int {
        // 截止到今天结束前的都算待复习
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        return memoryItems.filter { $0.nextReviewDate <= endOfToday }.count
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题栏
            HStack {
                Text("今日总览")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            
            // 数据三列布局
            HStack(spacing: 0) {
                // 1. 专注时长
                StatColumn(
                    value: "\(todayFocusMinutes)",
                    unit: "分钟",
                    icon: "hourglass",
                    color: .blue
                )
                
                Divider().frame(height: 20).padding(.horizontal, 8)
                
                // 2. 专注次数
                StatColumn(
                    value: "\(todayFocusCount)",
                    unit: "次",
                    icon: "flame.fill",
                    color: .orange
                )
                
                Divider().frame(height: 20).padding(.horizontal, 8)
                
                // 3. 待办/待复习
                StatColumn(
                    value: "\(pendingReviewCount)",
                    unit: "待学",
                    icon: "books.vertical.fill",
                    color: .green
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial) // 磨砂玻璃质感
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10) // 离底部的距离
    }
}

// 小小的列组件，复用代码让主视图更整洁
struct StatColumn: View {
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(height: 16)
            
            Text(value)
                .font(.system(.body, design: .rounded).bold())
                .foregroundStyle(.primary)
            
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}



// MARK: - 🎨 GitHub 风格配色
struct GitHubTheme {
    static let level0 = Color(red: 0.92, green: 0.93, blue: 0.94) // #ebedf0 (空)
    static let level1 = Color(red: 0.61, green: 0.91, blue: 0.66) // #9be9a8
    static let level2 = Color(red: 0.25, green: 0.77, blue: 0.39) // #40c463
    static let level3 = Color(red: 0.19, green: 0.63, blue: 0.30) // #30a14e
    static let level4 = Color(red: 0.13, green: 0.43, blue: 0.22) // #216e39
    
    // 根据数值获取颜色
    static func getColor(count: Int) -> Color {
        switch count {
        case 0: return level0
        case 1...2: return level1
        case 3...5: return level2
        case 6...9: return level3
        default: return level4
        }
    }
}

// MARK: - 🎨 丝滑胶囊选择器 (替代系统 Picker)
struct ModernReviewPicker: View {
    @Binding var selection: ReviewSessionView.ReviewMode
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReviewSessionView.ReviewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = mode
                    }
                } label: {
                    ZStack {
                        // 1. 选中状态背景 (滑块)
                        if selection == mode {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.blue, Color(red: 0.3, green: 0.3, blue: 1.0)], // 稍微深邃一点的蓝
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .matchedGeometryEffect(id: "ActiveTab", in: animation)
                                .padding(2) // ⭐ 关键：让滑块比轨道小一圈，更有层次感
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        }
                        
                        // 2. 文字
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .medium)) // 字体稍微改小一点点
                            .foregroundStyle(selection == mode ? .white : .secondary)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    // ⭐ 关键：强制最大宽度撑满，实现三等分
                    .frame(maxWidth: .infinity)
                    .frame(height: 32) // ⭐ 关键：锁死高度，拒绝“大馒头”
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2) // 轨道内边距
        .background(Color.black.opacity(0.2)) // 轨道背景深一点，对比度更好
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5) // 极细的高光描边
        )
        .frame(width: 360) // ⭐ 整体宽度限制，稍微紧凑一点
    }
}
