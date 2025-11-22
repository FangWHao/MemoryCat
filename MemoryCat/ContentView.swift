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
                        .foregroundStyle(globalState.isTimerRunning ? .green : .primary)
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

// MARK: - 🧠 复习界面
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryItem.nextReviewDate) var allItems: [MemoryItem]
    
    enum SessionState {
        case idle       // 准备
        case active     // 进行中
        case completed  // 结算
    }
    
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
    
    var progressText: String {
        guard !sessionQueue.isEmpty else { return "0/0" }
        return "\(currentIndex + 1)/\(sessionQueue.count)"
    }
    
    var potentialItems: [MemoryItem] {
        switch reviewMode {
        case .dueToday:
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
            return allItems.filter { $0.nextReviewDate <= endOfDay }
        case .new24h:
            let yesterday = Date.now.addingTimeInterval(-86400)
            return allItems.filter { $0.createdDate >= yesterday }
        case .reviewAhead:
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
            return Array(allItems.filter { $0.nextReviewDate > endOfDay }.prefix(20))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $reviewMode) {
                ForEach(ReviewMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .frame(width: 400)
            .padding(.top, 20)
            .disabled(sessionState == .active)
            .opacity(sessionState == .active ? 0.5 : 1.0)
            
            Spacer()
            
            switch sessionState {
            case .idle: idleView
            case .active: activeReviewView
            case .completed: completedView
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: reviewMode) { _, _ in sessionState = .idle }
    }
    
    var idleView: some View {
        VStack(spacing: 30) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.opacity(0.8))
                .padding(.bottom, 10)
            
            Text(reviewMode.rawValue).font(.title.bold())
            
            if potentialItems.isEmpty {
                ContentUnavailableView("暂无条目", systemImage: "checkmark.circle", description: Text("当前模式下没有需要处理的内容"))
            } else {
                Text("本次待处理: \(potentialItems.count) 个")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Button(action: startSession) {
                    Text("开始学习")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.blue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
            }
        }
    }
    
    var activeReviewView: some View {
        VStack {
            HStack {
                Text("进度")
                ProgressView(value: Double(currentIndex), total: Double(sessionQueue.count))
                    .frame(width: 200)
                Text(progressText).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
            
            if currentIndex < sessionQueue.count {
                let item = sessionQueue[currentIndex]
                
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.08), radius: 15, y: 8)
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.5), lineWidth: 1))
                        
                        VStack(spacing: 20) {
                            if !item.tags.isEmpty {
                                HStack {
                                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                                        Text("#\(tag)").font(.caption).padding(6)
                                            .background(Color.blue.opacity(0.1)).foregroundStyle(.blue).clipShape(Capsule())
                                    }
                                }
                            }
                            Spacer()
                            
                            if item.type == .qa {
                                VStack(spacing: 16) {
                                    Text(item.content).font(.system(size: 28, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                                    if isFlipped {
                                        Divider().padding(.vertical)
                                        Text(item.answer).font(.system(size: 24, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center).transition(.opacity)
                                    }
                                }
                            } else {
                                Text(item.content).font(.system(size: 28, design: .rounded)).multilineTextAlignment(.center).padding()
                            }
                            Spacer()
                            if item.type == .qa && !isFlipped { Text("点击查看背面").font(.caption).foregroundStyle(.tertiary) }
                        }
                        .padding(40)
                    }
                    .frame(maxWidth: 600, maxHeight: 450)
                    .onTapGesture {
                        if item.type == .qa { withAnimation(.spring()) { isFlipped.toggle() } }
                    }
                    
                    Button(action: { deleteCurrentItem(item) }) {
                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.6)).padding(12).background(.ultraThinMaterial, in: Circle())
                    }.buttonStyle(.plain).padding(16)
                }
                
                HStack(spacing: 60) {
                    if item.type == .qa && !isFlipped {
                        Button(action: { withAnimation { isFlipped = true } }) {
                            Text("显示答案").font(.headline).padding(.horizontal, 30).padding(.vertical, 12).background(Capsule().fill(Color(nsColor: .controlColor)))
                        }.buttonStyle(.plain)
                    } else {
                        ActionBtn(icon: "xmark", label: "忘记", color: .red) { processAnswer(item, remembered: false) }
                        ActionBtn(icon: "checkmark", label: "记得", color: .green) { processAnswer(item, remembered: true) }
                    }
                }.padding(.top, 40).frame(height: 100)
            }
        }
    }
    
    var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom))
            
            Text("本轮学习完成！")
                .font(.title.bold())
            
            Text("共复习了 \(sessionQueue.count) 个知识点")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                Button(action: { sessionState = .idle }) {
                    Text("返回").font(.headline).padding(.horizontal, 30).padding(.vertical, 10).background(Capsule().fill(Color.gray.opacity(0.2)))
                }.buttonStyle(.plain)
                
                Button(action: {
                    if !potentialItems.isEmpty { startSession() } else { sessionState = .idle }
                }) {
                    Text("再来一轮").font(.headline).padding(.horizontal, 30).padding(.vertical, 10).background(Capsule().fill(Color.blue)).foregroundStyle(.white)
                }.buttonStyle(.plain).disabled(potentialItems.isEmpty)
            }
        }
    }
    
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
            sessionQueue.remove(at: currentIndex)
            isFlipped = false
            if sessionQueue.isEmpty || currentIndex >= sessionQueue.count { sessionState = .completed }
        }
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
    
    // ... (Enum 和 DateValue 结构体保持不变) ...
    enum ChartType: String, CaseIterable {
        case review = "复习量"
        case added = "新增量"
        case focus = "专注时长"
    }
    
    enum VisMode: String, CaseIterable {
        case trend = "趋势图 (Line)"
        case activity = "热力图 (Heat)"
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
                        if visualizationMode == .trend { ChartBlock(type: chartType, data: getData(for: chartType)) } else { HeatMapBlock(data: getData(for: chartType)) }
                    }.frame(height: 350)
                }.padding().background(Color(nsColor: .textBackgroundColor)).cornerRadius(16)
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

struct HeatMapBlock: View {
    let data: [StatsView.DateValue]; let rows = 7; let cellSize: CGFloat = 20; let spacing: CGFloat = 4
    var dataMap: [Date: Double] { Dictionary(uniqueKeysWithValues: data.map { (Calendar.current.startOfDay(for: $0.date), $0.value) }) }
    var calendarGrid: [[Date?]] {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date()); let weeks = 20
        var grid = Array(repeating: Array(repeating: nil as Date?, count: rows), count: weeks)
        for w in 0..<weeks { for d in 0..<rows { let offset = (-(weeks - 1 - w) * 7) - (6 - d); if let date = calendar.date(byAdding: .day, value: offset, to: today) { grid[w][d] = date } } }
        return grid
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("过去 20 周活跃度").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: spacing) { ForEach(0..<calendarGrid.count, id: \.self) { col in VStack(spacing: spacing) { ForEach(0..<rows, id: \.self) { row in if let date = calendarGrid[col][row] { let value = dataMap[date] ?? 0; Rectangle().fill(getColor(value: value)).frame(width: cellSize, height: cellSize).cornerRadius(3).help("\(date.formatted(date: .numeric, time: .omitted)): \(Int(value))") } else { Rectangle().fill(.clear).frame(width: cellSize, height: cellSize) } } } } } }.padding(.vertical, 4) }
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
