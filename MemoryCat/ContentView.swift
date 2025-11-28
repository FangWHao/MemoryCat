// 📄 ContentView.swift
import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import EventKit

enum CalendarViewMode: String, CaseIterable {
    case day = "日"
    case week = "周"
    case month = "月"
}

enum AppMode {
    case standard // 标准模式
    case calendar // 日历模式
}

struct ContentView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) var modelContext
    @Query var todos: [TodoItem]
    
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var eventEditState = EventEditState()
    
    @State private var appMode: AppMode = .standard
    @State private var calendarViewMode: CalendarViewMode = .day
    @State private var calendarCurrentDate = Date()
    @State private var selection: SidebarItem? = .home
    @State private var showAddSheet = false
    
    enum SidebarItem {
        case home       // 👈 新增
        case focus
        case todo
        case review
        case allList
        case stats
        case screenTime
    }
    
    var body: some View {
        NavigationSplitView {
            if appMode == .standard {
                List(selection: $selection) {
                    Section {
                        Label("主页", systemImage: "house.fill")
                            .tag(SidebarItem.home)
                    }
                    Section("Focus") {
                        Label(globalState.isTimerRunning ? "专注中" : "番茄钟", systemImage: globalState.isTimerRunning ? "timer.circle.fill" : "timer")
                            .tag(SidebarItem.focus).foregroundStyle((globalState.isTimerRunning && selection != .focus) ? .green : .primary)
                        Label("待办清单", systemImage: "checkmark.square.fill").tag(SidebarItem.todo).foregroundStyle(.blue)
                    }
                    Section("Calendar") {
                        Button { withAnimation(.easeInOut(duration: 0.2)) { appMode = .calendar } } label: { Label("日程日历", systemImage: "calendar").foregroundStyle(.primary) }.buttonStyle(.plain)
                    }
                    Section("Memory") { Label("复习", systemImage: "brain.head.profile").tag(SidebarItem.review); Label("知识库", systemImage: "books.vertical").tag(SidebarItem.allList) }
                    Section("Data") { Label("学习统计", systemImage: "chart.xyaxis.line").tag(SidebarItem.stats); Label("屏幕时间", systemImage: "laptopcomputer").tag(SidebarItem.screenTime) }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) { SidebarStatsCard() }
                .navigationTitle("MemoryCat")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button(action: { showAddSheet = true }) { Label("新建", systemImage: "plus") } } }
                
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach(calendarManager.calendarGroups) { group in
                            Section(group.sourceTitle) {
                                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                                    CalendarToggleRow(
                                        calendar: calendar,
                                        isSelected: Binding(
                                            get: { calendarManager.visibleCalendarIDs.contains(calendar.calendarIdentifier) },
                                            set: { _ in calendarManager.toggleCalendar(calendar.calendarIdentifier) }
                                        )
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    
                    Divider()
                    
                    // ✨ 替换为自定义的极简小日历
                    MiniCalendarView(currentDate: $calendarCurrentDate)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                }
                .navigationTitle("Calendar")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { appMode = .standard } }) { Label("返回", systemImage: "arrow.uturn.backward") }
                        .help("返回专注模式")
                    }
                }
            }
            
        } detail: {
            ZStack {
                if appMode == .standard {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor).ignoresSafeArea()
                        switch selection {
                        case .home: HomeDashboardView(tabSelection: $selection)
                        case .focus: PomodoroView()
                        case .todo: TodoListView()
                        case .review: ReviewSessionView()
                        case .allList: AllItemsListView()
                        case .stats: StatsView()
                        case .screenTime: ScreenTimeView()
                        case .none: Text("请选择左侧菜单")
                        }
                    }
                    .transition(.opacity)
                } else {
                    CalendarDetailWrapper(
                        manager: calendarManager,
                        editState: eventEditState,
                        viewMode: $calendarViewMode,
                        currentDate: $calendarCurrentDate,
                        todos: todos
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

// MARK: - 🎨 美化版日历开关行
struct CalendarToggleRow: View {
    let calendar: EKCalendar
    @Binding var isSelected: Bool
    
    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .blue))
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                .opacity(isSelected ? 1.0 : 0.4)
                
                Text(calendar.title).font(.body).foregroundStyle(.primary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - 🗓️ 日历详情页封装 (顶部栏大修)
struct CalendarDetailWrapper: View {
    @ObservedObject var manager: CalendarManager
    @ObservedObject var editState: EventEditState
    @Binding var viewMode: CalendarViewMode
    @Binding var currentDate: Date
    let todos: [TodoItem]
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // 顶部控制栏 (✨ 去掉了背景色，更干净)
                HStack(alignment: .center) {
                    // 左侧标题
                    VStack(alignment: .leading, spacing: 2) {
                        if viewMode == .day {
                            HStack(alignment: .firstTextBaseline) {
                                Text(currentDate.formatted(.dateTime.day()))
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(.primary)
                                Text(currentDate.formatted(.dateTime.weekday(.wide)))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Text(currentDate.formatted(.dateTime.month(.wide)))
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)
                                Text(currentDate.formatted(.dateTime.year()))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // ✨ 中间：模式切换 (样式微调)
                    ModernCalendarModePicker(selection: $viewMode)
                    
                    Spacer()
                    
                    // ✨ 右侧：翻页按钮 (完全复刻截图样式：圆形箭头 + 胶囊今天)
                    HStack(spacing: 12) {
                        Button { moveDate(-1) } label: {
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 32, height: 32)
                                .overlay(Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)))
                        }
                        .buttonStyle(.plain)
                        
                        Button { currentDate = Date() } label: {
                            Text("今天")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                        }
                        .buttonStyle(.plain)
                        
                        Button { moveDate(1) } label: {
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 32, height: 32)
                                .overlay(Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                // ✨ 这里不要背景色了，让它融入整体
                .overlay(Divider(), alignment: .bottom)
                
                // 主内容区
                ZStack {
                    Color(nsColor: .textBackgroundColor).ignoresSafeArea()
                    InteractiveTimelineContainer(
                        mode: viewMode,
                        currentDate: currentDate,
                        events: manager.displayEvents,
                        todos: todos,
                        editState: editState,
                        manager: manager
                    )
                }
            }
            
            // 右侧检查器 (保持不变)
            if editState.selectedEvent != nil || editState.isNewEvent {
                EventInspectorView(editState: editState, manager: manager)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
                    .zIndex(20)
            }
        }
    }
    
    private func moveDate(_ v: Int) {
        let comp: Calendar.Component
        switch viewMode {
        case .day: comp = .day
        case .week: comp = .weekOfYear
        case .month: comp = .month
        }
        currentDate = Calendar.current.date(byAdding: comp, value: v, to: currentDate) ?? currentDate
    }
}


// MARK: - ✨ 全新：极简小日历 (替代 Sidebar 的 DatePicker)
struct MiniCalendarView: View {
    @Binding var currentDate: Date
    @State private var displayMonth: Date = Date()
    private let calendar = Calendar.current
    
    // 生成网格数据
    var days: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayMonth) else { return [] }
        let monthStart = monthInterval.start
        
        let firstWeekDay = calendar.component(.weekday, from: monthStart) // 1=Sun, 2=Mon
        let offset = firstWeekDay - 1
        
        let totalDays = calendar.range(of: .day, in: .month, for: displayMonth)?.count ?? 30
        
        var grid: [Date?] = Array(repeating: nil, count: offset)
        for i in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: i, to: monthStart) {
                grid.append(date)
            }
        }
        return grid
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. 标题行 (2025年11月 + 箭头)
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(displayMonth.formatted(.dateTime.year().month()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            // 2. 星期头
            HStack(spacing: 0) {
                ForEach(["周日", "周一", "周二", "周三", "周四", "周五", "周六"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 3. 日期网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(0..<days.count, id: \.self) { index in
                    if let date = days[index] {
                        let isSelected = calendar.isDate(date, inSameDayAs: currentDate)
                        let isToday = calendar.isDateInToday(date)
                        
                        Button {
                            currentDate = date
                        } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : (isToday ? .red : .primary))
                                .frame(width: 26, height: 26)
                                .background(
                                    ZStack {
                                        if isSelected { Circle().fill(Color.red) }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
        }
        .onAppear { displayMonth = currentDate }
        .onChange(of: currentDate) { _, newVal in
            if !calendar.isDate(newVal, equalTo: displayMonth, toGranularity: .month) {
                displayMonth = newVal
            }
        }
    }
    
    func changeMonth(_ val: Int) {
        displayMonth = calendar.date(byAdding: .month, value: val, to: displayMonth) ?? displayMonth
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
        case new24h = "今日强化"
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
    
    // MARK: - 📖 进行中界面 (已修复文字跳动 bug + 快捷键逻辑)
    var activeReviewView: some View {
        VStack {
            // 1. 顶部进度条 (保持不变)
            HStack(spacing: 16) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2)).frame(height: 8)
                        let total = Double(max(sessionQueue.count, 1))
                        let current = Double(currentIndex) + (isFlipped ? 1.0 : 0.5)
                        let width = geo.size.width * CGFloat(current / total)
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: width, height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: current)
                    }
                }
                .frame(height: 8)
                Text(progressText)
                    .font(.system(.callout, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            .frame(width: 450)
            .padding(.top, 20)
            .padding(.bottom, 30)
            
            if currentIndex < sessionQueue.count {
                let item = sessionQueue[currentIndex]
                
                // 👇👇👇 核心变化：左右布局 👇👇👇
                HStack(alignment: .center, spacing: 40) {
                    
                    // ===========================
                    // 左侧：卡片区域
                    // ===========================
                    ZStack {
                        // 背景
                        RoundedRectangle(cornerRadius: 30)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
                            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.1), lineWidth: 1))
                        
                        VStack(spacing: 0) {
                            // 顶部标签
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
                                // 难度提示：根据重复次数变色
                                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                    .foregroundStyle(item.repetition > 3 ? .green : .orange)
                            }
                            .padding(24)
                            
                            // 中间内容
                            // 中间内容
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 24) {
                                    
                                    // 👇 定义一个临时的判断逻辑：
                                    // 只有当：是QA卡 + 没翻面 + 且内容没有换行符 时，才居中
                                    let shouldCenter = item.type == .qa && !isFlipped && !item.content.contains("\n")
                                    
                                    // 问题 (始终显示)
                                    SimpleMarkdownView(
                                        content: item.content,
                                        alignment: shouldCenter ? .center : .leading
                                    )
                                    // Frame 也要跟着变
                                    .frame(maxWidth: .infinity, alignment: shouldCenter ? .center : .leading)
                                    // 动画
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
                                    
                                    // 答案 (条件显示)
                                    if isFlipped && item.type == .qa {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Divider()
                                            Text("Answer")
                                                .font(.caption.bold())
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 4)
                                            
                                            SimpleMarkdownView(content: item.answer, alignment: .leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .transition(
                                            .asymmetric(
                                                insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity
                                            )
                                        )
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.bottom, 40)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .clipShape(Rectangle())
                            
                            // 底部提示文案
                            if item.type == .qa && !isFlipped {
                                Text("Space翻面 · ←忘记 · →记得")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.bottom, 24)
                                    .padding(.top, 10)
                            } else if item.type == .textOnly {
                                Text("←忘记 · →记得")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.bottom, 24)
                                    .padding(.top, 10)
                            } else {
                                Color.clear.frame(height: 24).padding(.bottom, 24)
                            }
                        }
                    }
                    .frame(maxWidth: 700, maxHeight: 600)
                    .contentShape(Rectangle())
                    // 👇 点击卡片也可以翻面/翻回
                    .onTapGesture {
                        if item.type == .qa {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isFlipped.toggle()
                            }
                        }
                    }
                    
                    // ===========================
                    // 右侧：竖排操作栏
                    // ===========================
                    VStack(spacing: 24) {
                        // 逻辑：如果是 QA 且没翻面，显示眼睛；否则（QA翻面了 或 纯文本）显示打分
                        if item.type == .qa && !isFlipped {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isFlipped = true }
                            }) {
                                VStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(.ultraThinMaterial)
                                            .frame(width: 70, height: 70)
                                            .shadow(color: .black.opacity(0.1), radius: 5)
                                        Image(systemName: "eye.fill").font(.title).foregroundStyle(.primary)
                                    }
                                    Text("看答案").font(.caption.bold()).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("快捷键：空格")
                            // ⚠️ 修复：加上 transition 避免切换时闪烁太生硬
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            
                        } else {
                            // 1. 记得
                            FeedbackBtn(icon: "checkmark", title: "记得", color: .green) {
                                processAnswer(item, remembered: true)
                            }
                            .help("快捷键：→")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            
                            // 2. 忘记
                            FeedbackBtn(icon: "xmark", title: "忘记", color: .red) {
                                processAnswer(item, remembered: false)
                            }
                            .help("快捷键：←")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(width: 80)
                }
            }
        }
        // 👇👇👇 修复：将快捷键监听移到最外层，保证 focus 不丢失 👇👇👇
        .background {
            // 1. 空格键：翻面 / 翻回
            Button(action: {
                if let item = sessionQueue[safe: currentIndex], item.type == .qa {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isFlipped.toggle() // ✅ 修复：支持 toggle，可以翻回去
                    }
                }
            }) { Text("") }
                .keyboardShortcut(.space, modifiers: [])
            
            // 2. 左箭头：忘记
            Button(action: {
                if let item = sessionQueue[safe: currentIndex] {
                    // ✅ 修复：如果是文本卡片，直接允许操作；如果是QA，必须翻面后才允许
                    if item.type == .textOnly || isFlipped {
                        processAnswer(item, remembered: false)
                    }
                }
            }) { Text("") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            
            // 3. 右箭头：记得
            Button(action: {
                if let item = sessionQueue[safe: currentIndex] {
                    if item.type == .textOnly || isFlipped {
                        processAnswer(item, remembered: true)
                    }
                }
            }) { Text("") }
                .keyboardShortcut(.rightArrow, modifiers: [])
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
// MARK: - 📚 知识库视图 (集成 JSON 导入导出)
struct AllItemsListView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \MemoryItem.createdDate, order: .reverse) var items: [MemoryItem]
    
    // 状态管理
    @State private var selection = Set<MemoryItem.ID>()
    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var sortOrder = [KeyPathComparator(\MemoryItem.createdDate, order: .reverse)]
    
    // 视图模式
    @State private var viewScope: ViewScope = .active
    
    enum ViewScope: String, CaseIterable {
        case active = "活跃知识库"
        case archived = "归档箱"
    }
    
    // 编辑与文件处理
    @State private var editingItem: MemoryItem?
    @State private var showFileExporter = false
    @State private var showFileImporter = false
    @State private var jsonDocument: JSONDocument?
    @State private var importCandidate: (name: String, items: [MemoryItemBackup])?
    @State private var showImportConfig = false
    
    var allTags: [String] { Array(Set(items.flatMap { $0.tags })).sorted() }
    
    // 筛选逻辑
    var filteredItems: [MemoryItem] {
        let scopeItems = items.filter { item in
            viewScope == .active ? !item.isArchived : item.isArchived
        }
        
        var result = scopeItems
        if let tag = selectedTag { result = result.filter { $0.tags.contains(tag) } }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.answer.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. 顶部控制区
            VStack(spacing: 0) {
                Picker("视图", selection: $viewScope) {
                    ForEach(ViewScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .onChange(of: viewScope) { _, _ in
                    selection.removeAll()
                    selectedTag = nil
                }
                
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
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            // 2. 数据表格
            if filteredItems.isEmpty {
                ContentUnavailableView {
                    Label(
                        viewScope == .active ? "没有相关条目" : "归档箱是空的",
                        systemImage: viewScope == .active ? "doc.text.magnifyingglass" : "archivebox"
                    )
                } description: {
                    Text(viewScope == .active ? "快去添加一些新知识吧喵！" : "被遗忘的知识会暂时存放在这里。")
                }
                .frame(maxHeight: .infinity)
            } else {
                Table(filteredItems, selection: $selection, sortOrder: $sortOrder) {
                    
                    TableColumn("创建日期", value: \.createdDate) { item in
                        Text(item.createdDate.formatted(date: .numeric, time: .omitted))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .width(min: 80, ideal: 100, max: 100)
                    
                    TableColumn("类型", value: \.type.rawValue) { item in
                        Text(item.type == .qa ? "QA" : "文本")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.type == .qa ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                    }
                    .width(50)
                    
                    TableColumn("内容 / 问题", value: \.content) { item in
                        HStack {
                            if item.type == .qa {
                                Image(systemName: "q.circle.fill").foregroundStyle(.blue.opacity(0.7))
                            }
                            Text(item.content)
                                .lineLimit(1)
                                .foregroundStyle(viewScope == .archived ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    
                    TableColumn("记忆进度", value: \.nextReviewDate) { item in
                        HStack(spacing: 6) {
                            if item.isArchived {
                                Text("⏹ 已停止").font(.caption).foregroundStyle(.secondary)
                            } else {
                                if item.repetition == 0 {
                                    Text("🌱 新手").font(.caption).foregroundStyle(.secondary)
                                } else if item.repetition < 3 {
                                    Text("🪵 入门").font(.caption).foregroundStyle(.orange)
                                } else {
                                    Text("💎 大师").font(.caption).foregroundStyle(.purple)
                                }
                                Spacer()
                                if item.nextReviewDate <= Date() {
                                    Text("待复习").font(.caption2).bold().foregroundStyle(.red)
                                } else {
                                    let days = Calendar.current.dateComponents([.day], from: Date(), to: item.nextReviewDate).day ?? 0
                                    Text("\(days)天后").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .width(min: 100, ideal: 120, max: 150)
                    
                    TableColumn("标签") { item in
                        Text(item.tags.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                }
                .searchable(text: $searchText, prompt: viewScope == .active ? "搜索知识库..." : "搜索归档...")
            }
            
            // 3. 底部操作栏 (这里调用拆分后的子视图)
            bottomToolBar
        }
        .navigationTitle(viewScope.rawValue)
        .sheet(item: $editingItem) { item in EditItemView(item: item) }
        .contextMenu(forSelectionType: MemoryItem.ID.self) { ids in
            contextMenuContent(for: ids)
        }
        .fileExporter(isPresented: $showFileExporter, document: jsonDocument, contentType: .json, defaultFilename: "Backup.json") { _ in selection.removeAll() }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) {result in
            handleFileImport(result)}
        .sheet(isPresented: $showImportConfig) {
             if let candidate = importCandidate { ImportConfigView(fileName: candidate.name, items: candidate.items) { performImport(backups: candidate.items, strategy: $0) } }
        }
    }
    
    // MARK: - 🧩 拆分的视图组件 (解决编译器超时问题)
    
    // 底部总工具栏
    @ViewBuilder
    var bottomToolBar: some View {
        HStack {
            if !selection.isEmpty {
                selectedActionsView
            } else {
                defaultActionsView
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
    
    // 选中状态下的按钮组
    @ViewBuilder
    var selectedActionsView: some View {
        Text("已选 \(selection.count) 项")
            .foregroundStyle(.secondary)
            .font(.callout)
        
        if selection.count == 1 {
            Button {
                if let id = selection.first, let item = items.first(where: { $0.id == id }) {
                    editingItem = item
                }
            } label: { Label("编辑", systemImage: "pencil") }
        }
        
        Spacer()
        
        // 归档/还原/删除 按钮组
        archiveOperationsView
        
        Button { prepareExport() } label: { Label("导出", systemImage: "square.and.arrow.up") }
    }
    
    // 默认状态下的按钮组
    @ViewBuilder
    var defaultActionsView: some View {
        Button { showFileImporter = true } label: { Label("导入", systemImage: "square.and.arrow.down") }
        Spacer()
        Button {
            selection = Set(filteredItems.map { $0.id })
            prepareExport()
        } label: { Label("导出全部", systemImage: "square.and.arrow.up") }
    }
    
    // 归档/还原/删除 逻辑视图
    @ViewBuilder
    var archiveOperationsView: some View {
        if viewScope == .active {
            Button {
                toggleArchiveStatus(to: true)
            } label: {
                Label("移入归档", systemImage: "archivebox")
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                toggleArchiveStatus(to: false)
            } label: {
                Label("还原", systemImage: "arrow.uturn.backward")
            }
            
            Button(role: .destructive) {
                deletePermanently()
            } label: {
                Label("彻底粉碎", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // 右键菜单内容
    @ViewBuilder
    func contextMenuContent(for ids: Set<MemoryItem.ID>) -> some View {
        let selectedObjects = items.filter { ids.contains($0.id) }
        
        if !selectedObjects.isEmpty {
            if viewScope == .active {
                Button("移入归档") {
                    withAnimation {
                        selectedObjects.forEach { $0.isArchived = true }
                    }
                }
            } else {
                Button("还原到知识库") {
                    withAnimation {
                        selectedObjects.forEach { $0.isArchived = false }
                    }
                }
                Divider()
                Button("彻底删除", role: .destructive) {
                    withAnimation {
                        selectedObjects.forEach { context.delete($0) }
                    }
                }
            }
        }
    }
    
    // MARK: - 逻辑处理
    
    func toggleArchiveStatus(to archived: Bool) {
        withAnimation(.spring()) {
            let targets = items.filter { selection.contains($0.id) }
            targets.forEach { $0.isArchived = archived }
            selection.removeAll()
        }
    }
    
    func deletePermanently() {
        withAnimation {
            let toDel = items.filter { selection.contains($0.id) }
            toDel.forEach { context.delete($0) }
            selection.removeAll()
        }
    }
    
    // 主线程执行导出
    @MainActor
    func prepareExport() {
        let targetItems = items.filter { selection.contains($0.id) }
        guard !targetItems.isEmpty else { return }
        let backups = targetItems.map { MemoryItemBackup(from: $0) }
        self.jsonDocument = JSONDocument(items: backups)
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.showFileExporter = true
        }
    }
    
    func handleFileImport(_ result: Result<URL, Error>) {
            switch result {
            case .success(let url):
                // 1. 安全访问权限
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    // 2. 直接读取这一个文件
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let backups = try decoder.decode([MemoryItemBackup].self, from: data)
                    
                    if !backups.isEmpty {
                        self.importCandidate = (name: url.lastPathComponent, items: backups)
                        self.showImportConfig = true
                    }
                } catch {
                    print("解析失败: \(error)")
                }
            case .failure(let error):
                print("读取失败: \(error)")
            }
        }
    
    func performImport(backups: [MemoryItemBackup], strategy: ImportConfigView.ImportStrategy) {
        var count = 0
        for backup in backups {
            var finalTags: [String] = []
            switch strategy.mode {
            case .append: finalTags = Array(Set(backup.tags + strategy.tags))
            case .override: finalTags = strategy.tags
            case .ignore: finalTags = backup.tags
            }
            let newItem = MemoryItem(type: backup.type, content: backup.content, answer: backup.answer, tags: finalTags)
            newItem.createdDate = backup.createdDate
            newItem.nextReviewDate = backup.nextReviewDate
            newItem.repetition = backup.repetition
            newItem.interval = backup.interval
            newItem.easeFactor = backup.easeFactor
            newItem.isArchived = viewScope == .archived // 导入到当前视图模式
            context.insert(newItem)
            count += 1
        }
        try? context.save()
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

// MARK: - ✨ 美化后的编辑界面 (最终版)
struct EditItemView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Bindable var item: MemoryItem
    
    // 👇 新增：查询所有现存标签，用于生成选择列表
    @Query var allItems: [MemoryItem]
    
    @State private var tagString: String = ""
    
    // 计算所有去重后的标签
    var existingTags: [String] {
        Array(Set(allItems.flatMap { $0.tags })).sorted()
    }
    
    // 界面常量
    private let cardPadding: CGFloat = 20
    private let cornerRadius: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. 顶部导航栏
            HStack {
                Text("编辑卡片")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // 类型切换
                Picker("类型", selection: $item.type) {
                    Text("文本").tag(ItemType.textOnly)
                    Text("Q&A").tag(ItemType.qa)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .bottom)
            
            // 2. 内容滚动区
            ScrollView {
                VStack(spacing: 24) {
                    
                    // ✨ 卡片 A: 核心内容 (合并了问题和答案)
                    VStack(alignment: .leading, spacing: 0) {
                        
                        // 区域 1: 内容/问题
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(item.type == .qa ? "问题 (Front)" : "内容 (Content)", systemImage: "doc.text.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            EditStyledTextEditor(text: $item.content, minHeight: 120)
                        }
                        .padding(cardPadding)
                        
                        // 区域 2: 答案 (仅 QA 显示，用分割线连接)
                        if item.type == .qa {
                            // 分割线
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 1)
                                .padding(.horizontal, cardPadding)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("答案 (Back)", systemImage: "lightbulb.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                    Spacer()
                                }
                                
                                EditStyledTextEditor(text: $item.answer, minHeight: 120)
                            }
                            .padding(cardPadding)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(cardBackground)
                    .cornerRadius(cornerRadius)
                    .shadow(color: shadowColor, radius: 8, y: 4)
                    
                    // ✨ 卡片 B: 智能标签管理
                    VStack(alignment: .leading, spacing: 16) {
                        Label("标签管理", systemImage: "tag.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                        
                        // 1. 输入框
                        HStack {
                            Image(systemName: "number")
                                .foregroundStyle(.secondary)
                            TextField("手动输入标签 (逗号分隔)...", text: $tagString)
                                .textFieldStyle(.plain)
                                .onChange(of: tagString) { _, newValue in
                                    // 手动输入时同步更新 tags 数组
                                    updateTags(fromString: newValue)
                                }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        Divider()
                        
                        // 2. 现有标签云 (点击选择/取消)
                        if !existingTags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("快速选择:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FlowLayoutView(items: existingTags) { tag in
                                    TagSelectChip(
                                        title: tag,
                                        isSelected: item.tags.contains(tag)
                                    ) {
                                        toggleTag(tag)
                                    }
                                }
                            }
                        }
                    }
                    .padding(cardPadding)
                    .background(cardBackground)
                    .cornerRadius(cornerRadius)
                    .shadow(color: shadowColor, radius: 8, y: 4)
                    
                    // ✨ 卡片 C: 数据详情
                    VStack(alignment: .leading, spacing: 16) {
                        Label("数据统计", systemImage: "chart.bar.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        Grid(horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                InfoCell(title: "创建时间", value: item.createdDate.formatted(date: .numeric, time: .omitted))
                                InfoCell(title: "下次复习", value: item.nextReviewDate.formatted(date: .numeric, time: .omitted))
                            }
                            GridRow {
                                InfoCell(title: "复习次数", value: "\(item.repetition) 次")
                                InfoCell(title: "记忆间隔", value: "\(item.interval) 天")
                            }
                        }
                    }
                    .padding(cardPadding)
                    .background(cardBackground)
                    .cornerRadius(cornerRadius)
                    .shadow(color: shadowColor, radius: 8, y: 4)
                }
                .padding(24)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.type)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            // 3. 底部栏
            HStack {
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("保存") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .top)
        }
        .frame(width: 500, height: 650)
        .onAppear {
            // 初始化输入框
            tagString = item.tags.joined(separator: ", ")
        }
    }
    
    // MARK: - 逻辑处理
    
    // 输入框文字 -> tags 数组
    func updateTags(fromString string: String) {
        let newTags = string.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        item.tags = newTags
    }
    
    // 点击标签云 -> tags 数组 + 更新输入框
    func toggleTag(_ tag: String) {
        var currentTags = item.tags
        if currentTags.contains(tag) {
            currentTags.removeAll { $0 == tag }
        } else {
            currentTags.append(tag)
        }
        item.tags = currentTags
        tagString = currentTags.joined(separator: ", ")
    }
    
    // MARK: - 视觉属性
    var cardBackground: Color {
        colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.white
    }
    var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.05)
    }
}

// MARK: - 🧩 辅助组件

// 1. 简单的流式布局 (用于标签云)
struct FlowLayoutView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content
    
    var body: some View {
        // 使用 Layout 如果是 macOS 13+，这里为了兼容简单写个 wrap
        // 这里偷懒用一个简单的 ScrollView + HStack 组合，
        // 如果标签特别多想要自动换行，可以用 LazyVGrid
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
            .padding(.vertical, 4) // 给 shadow 留空间
        }
    }
}

// 2. 可点击的标签 Chip
struct TagSelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? .clear : .gray.opacity(0.2), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// 3. 复用之前的 TextEditor
// (如果之前没定义 EditStyledTextEditor，这里再贴一次，防止报错)
// struct EditStyledTextEditor: View { ... }
// 👆 刚才的代码里已经有了，就不重复贴了，如果报错找不到就告诉我~
// 🛠️ 辅助组件：美化版输入框
struct EditStyledTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("点击输入...")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }
            
            TextEditor(text: $text)
                .font(.body)
                .lineSpacing(4)
                .scrollContentBackground(.hidden) // 透明背景
                .background(.clear)
                .frame(minHeight: minHeight)
        }
        .padding(8)
        .background(Color.gray.opacity(0.05)) // 输入框内部底色
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// 🛠️ 辅助组件：信息单元格
struct InfoCell: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - 📝 简易 Markdown 渲染组件 (修复编译报错版)
struct SimpleMarkdownView: View {
    let content: String
    var alignment: HorizontalAlignment = .leading
    
    // 内容块定义
    enum Block: Identifiable {
        case text(String)
        case table(rows: [[String]])
        var id: UUID { UUID() }
    }
    
    // 解析逻辑
    var blocks: [Block] {
        var result: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var tableBuffer: [[String]] = []
        
        func flushTable() {
            if !tableBuffer.isEmpty {
                let validRows = tableBuffer.filter { row in
                    !row.allSatisfy { cell in
                        cell.trimmingCharacters(in: CharacterSet(charactersIn: "- ")).isEmpty
                    }
                }
                if !validRows.isEmpty { result.append(.table(rows: validRows)) }
                tableBuffer = []
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                let rowContent = trimmed.dropFirst().dropLast()
                let cells = rowContent.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                tableBuffer.append(cells)
            } else {
                flushTable()
                result.append(.text(line))
            }
        }
        flushTable()
        return result
    }
    
    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .text(let line):
                    renderTextLine(line)
                case .table(let rows):
                    renderTable(rows)
                }
            }
        }
    }
    
    // 🎨 渲染普通文本行
    @ViewBuilder
    func renderTextLine(_ line: String) -> some View {
        // 1. 计算缩进 (每2个空格算一级，约等于)
        let leadingSpacesCount = line.prefix(while: { $0 == " " }).count
        let indentPadding = CGFloat(leadingSpacesCount) * 7.0
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("###") {
            Text(LocalizedStringKey(trimmed.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.top, 12)
                .padding(.leading, indentPadding)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
        else if trimmed.hasPrefix("##") {
            Text(LocalizedStringKey(trimmed.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .padding(.top, 16)
                .padding(.leading, indentPadding)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
        else if trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                // 👇👇👇 修复点在这里 👇👇👇
                Text("•")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.secondary) // 统一用 secondary
                    .opacity(leadingSpacesCount > 0 ? 0.6 : 1.0) // 通过 opacity 修饰符来改变透明度，不再报错！
                
                Text(LocalizedStringKey(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)))
                    .font(.system(size: 19, design: .rounded))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 8 + indentPadding)
        }
        else if !trimmed.isEmpty {
            Text(LocalizedStringKey(trimmed))
                .font(.system(size: 19, design: .rounded))
                .lineSpacing(5)
                .padding(.leading, indentPadding)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
    }
    
    // 📊 渲染表格
    @ViewBuilder
    func renderTable(_ rows: [[String]]) -> some View {
        if let header = rows.first {
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    ForEach(0..<header.count, id: \.self) { i in
                        Text(LocalizedStringKey(header[i]))
                            .font(.system(.body, design: .rounded).bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                ForEach(rows.dropFirst().indices, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    GridRow {
                        ForEach(0..<header.count, id: \.self) { colIndex in
                            if colIndex < row.count {
                                Text(LocalizedStringKey(row[colIndex]))
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else { Text("") }
                        }
                    }
                    if rowIndex < rows.count - 1 { Divider().opacity(0.3) }
                }
            }
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            .padding(.vertical, 8)
        }
    }
}


extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


// MARK: - 🎨 美化版日历模式切换器 (复刻复习界面的胶囊风格)
struct ModernCalendarModePicker: View {
    @Binding var selection: CalendarViewMode
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = mode
                    }
                } label: {
                    ZStack {
                        // 1. 选中背景 (滑块)
                        if selection == mode {
                            Capsule()
                                .fill(Color(nsColor: .controlColor)) // 使用系统控件色，看起来像原生 macOS 控件
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1) // 微微的立体感
                                .matchedGeometryEffect(id: "CalTab", in: animation)
                        }
                        
                        // 2. 文字
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: selection == mode ? .medium : .regular))
                            .foregroundStyle(selection == mode ? .primary : .secondary)
                            .fixedSize() // 防止文字换行
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 26) // 高度锁定，小巧精致
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3) // 轨道内边距
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5)) // 轨道背景
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.05), lineWidth: 1) // 极细边框
        )
        .frame(width: 180) // 🌟 关键：锁死总宽度，防止它变得巨大！
    }
}
