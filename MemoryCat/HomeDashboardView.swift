import SwiftUI
import SwiftData
import Charts

// MARK: - 🏠 主页仪表盘 (Pro 版)
struct HomeDashboardView: View {
    // 👇 1. 接收跳转控制权
    @Binding var tabSelection: ContentView.SidebarItem?
    
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) var context
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject private var calendarManager = CalendarManager()
    
    // 数据查询
    // 按优先级和创建时间排序，只取未完成的
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted },
           sort: [SortDescriptor(\.priorityRaw, order: .reverse), SortDescriptor(\.createdDate, order: .reverse)])
    var pendingTodos: [TodoItem]
    
    @Query var memoryItems: [MemoryItem]
    @Query var reviewLogs: [ReviewLog]
    @Query var pomoRecords: [PomodoroRecord]
    
    @State private var animateGradient = false
    @State private var showAddTaskSheet = false // 快速新建任务
    
    // 问候语
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "夜深了，注意休息喵 🌙"
        case 6..<12: return "早安，今天也要元气满满！☀️"
        case 12..<18: return "下午好，保持专注哦 ☕️"
        default: return "晚上好，今天过得怎么样？✨"
        }
    }
    
    var todayFocusMinutes: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return Int(pomoRecords.filter { $0.date >= startOfToday }.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var body: some View {
        ScrollView {
            ZStack {
                // 动态背景
                BackgroundBlobs(animate: $animateGradient)
                
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 1. 顶部：问候 + 统计摘要
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greeting)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("这里是你的记忆指挥中心")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // 快速跳转按钮组
                        HStack(spacing: 12) {
                            QuickNavBtn(icon: "chart.bar.fill", color: .purple) { tabSelection = .stats }
                                .help("查看统计")
                            QuickNavBtn(icon: "laptopcomputer", color: .blue) { tabSelection = .screenTime }
                                .help("屏幕时间")
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // 2. Bento Grid 核心布局
                    HStack(alignment: .top, spacing: 20) {
                        
                        // === 左侧列 (专注 + 日历) ===
                        VStack(spacing: 20) {
                            // 2.1 专注卡片 (可交互)
                            InteractiveFocusCard(
                                minutes: todayFocusMinutes,
                                isRunning: globalState.isTimerRunning,
                                onToggle: toggleTimer,
                                onTap: { tabSelection = .focus }
                            )
                            .frame(height: 240)
                            
                            // 2.2 小日历 (点击跳转)
                            UpcomingScheduleCard(manager: calendarManager)
                                             .frame(height: 400) 
                        }
                        .frame(width: 320) // 固定左侧宽度
                        
                        // === 右侧列 (任务列表 + 复习状态) ===
                        VStack(spacing: 20) {
                            
                            // 2.3 任务清单 (长列表，可勾选)
                            TaskListCard(
                                todos: Array(pendingTodos.prefix(6)), // 只显示前6个
                                onComplete: completeTodo,
                                onAdd: { showAddTaskSheet = true },
                                onTapHeader: { tabSelection = .todo }
                            )
                            .frame(minHeight: 300) // 让它尽可能长
                            
                            // 2.4 复习概览
                            ReviewStatusCard(
                                dueCount: memoryItems.filter { $0.nextReviewDate <= Date() }.count,
                                totalCount: memoryItems.count,
                                onTap: { tabSelection = .review }
                            )
                            .frame(height: 160)
                        }
                    }
                }
                .padding(40)
            }
        }
        .onAppear { animateGradient = true }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTodoSheet() // 复用你之前的 sheet
        }
    }
    
    // MARK: - 逻辑处理
    
    func toggleTimer() {
        if globalState.isTimerRunning {
            globalState.pauseTimer()
        } else {
            // 默认 25 分钟开始
            if globalState.timeRemaining <= 0 { globalState.timeRemaining = 25 * 60 }
            globalState.startTimer(context: context)
        }
    }
    
    func completeTodo(_ item: TodoItem) {
        withAnimation {
            item.isCompleted = true
            // 稍微延迟保存，让动画飞一会儿
            try? context.save()
        }
    }
    
    // 临时 helper，如果 Calendar 在 AppMode 里，这里可能需要发通知或者用 Binding 切换 AppMode
    // 这里简单示意跳转
    func appModeSwitch() {
        // 如果你有 appMode 的 Binding 也可以传进来切换
        print("Jump to calendar")
    }
}

// MARK: - 🧩 组件库 (Interactive & Fancy)

// 1. 专注卡片 (带播放按钮)
struct InteractiveFocusCard: View {
    let minutes: Int
    let isRunning: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    
    @State private var breathing = false
    
    var body: some View {
        HomeCardBase {
            VStack(alignment: .leading) {
                // 标题栏 (可点击跳转)
                Button(action: onTap) {
                    HStack {
                        Label("专注时刻", systemImage: "timer")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // 核心交互区
                HStack(alignment: .center, spacing: 20) {
                    // 左侧：时间显示
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isRunning ? "专注中..." : "今日累计")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(minutes)")
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text("min")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 右侧：巨大的播放按钮
                    Button(action: onToggle) {
                        ZStack {
                            // 呼吸光圈
                            if isRunning {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(breathing ? 1.2 : 1.0)
                                    .opacity(breathing ? 0.0 : 1.0)
                                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: breathing)
                            }
                            
                            Circle()
                                .fill(LinearGradient(colors: isRunning ? [.orange, .red] : [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 70, height: 70)
                                .shadow(color: isRunning ? .red.opacity(0.4) : .blue.opacity(0.4), radius: 10, y: 5)
                            
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear { breathing = true }
                }
            }
            .padding(24)
        }
    }
}

// 2. 任务清单卡片 (核心升级)
struct TaskListCard: View {
    let todos: [TodoItem]
    let onComplete: (TodoItem) -> Void
    let onAdd: () -> Void
    let onTapHeader: () -> Void
    
    var body: some View {
        HomeCardBase {
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Button(action: onTapHeader) {
                        Label("待办事项", systemImage: "checklist")
                            .font(.headline)
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // 新建按钮
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.purple))
                    }
                    .buttonStyle(.plain)
                    .help("快速添加任务")
                }
                .padding(20)
                
                Divider()
                
                // 列表区
                if todos.isEmpty {
                    ContentUnavailableView("无任务", systemImage: "balloon.fill", description: Text("太棒了，去休息吧！"))
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(todos) { todo in
                                DashboardTaskRow(todo: todo, onComplete: { onComplete(todo) })
                                Divider().padding(.leading, 40)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

// 单行任务组件
struct DashboardTaskRow: View {
    let todo: TodoItem
    let onComplete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 勾选圈
            Button(action: onComplete) {
                Circle()
                    .stroke(todo.priority.color, lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay(
                        isHovering ? Circle().fill(todo.priority.color.opacity(0.3)) : nil
                    )
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let due = todo.dueDate {
                    Text(due.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(due < Date() ? .red : .secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovering = $0 }
    }
}

// 3. 迷你日历卡片 (纯展示 + 装饰)
struct DashboardCalendarCard: View {
    let calendar = Calendar.current
    let today = Date()
    
    // 生成当前周的日期
    var currentWeek: [Date] {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
    
    var body: some View {
        HomeCardBase {
            VStack(spacing: 0) {
                // 红色顶部装饰
                Rectangle()
                    .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 6)
                
                VStack(alignment: .leading, spacing: 16) {
                    // 月份大标题
                    HStack {
                        Text(today.formatted(.dateTime.month(.wide)))
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                        Spacer()
                        Text(today.formatted(.dateTime.year()))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 大大的"今天"
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(today.formatted(.dateTime.day()))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(today.formatted(.dateTime.weekday(.wide)))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // 底部：本周小圆点
                    HStack(spacing: 0) {
                        ForEach(currentWeek, id: \.self) { date in
                            VStack(spacing: 4) {
                                Text(date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                ZStack {
                                    if calendar.isDateInToday(date) {
                                        Circle().fill(Color.red)
                                    } else {
                                        Circle().fill(Color.gray.opacity(0.1))
                                    }
                                }
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(date.formatted(.dateTime.day()))
                                        .font(.caption2.bold())
                                        .foregroundStyle(calendar.isDateInToday(date) ? .white : .primary)
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(24)
            }
        }
    }
}

// 4. 复习状态卡片
struct ReviewStatusCard: View {
    let dueCount: Int
    let totalCount: Int
    let onTap: () -> Void
    
    var body: some View {
        HomeCardBase {
            Button(action: onTap) {
                HStack(spacing: 20) {
                    // 左侧环形进度
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.1), lineWidth: 8)
                        
                        // 进度条：已复习占比 (简化逻辑：假设 total-due = 已复习)
                        let progress = totalCount > 0 ? Double(totalCount - dueCount) / Double(totalCount) : 0
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(colors: [.green, .mint], center: .center),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text("\(dueCount)")
                                .font(.title.bold())
                                .foregroundStyle(dueCount > 0 ? .orange : .green)
                            Text("待复习")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 80, height: 80)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("记忆库状态")
                            .font(.headline)
                        
                        if dueCount > 0 {
                            Text("有 \(dueCount) 个知识点需要巩固")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("所有卡片已完成，太强了！")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 统计小标签
                        HStack {
                            Label("\(totalCount)", systemImage: "doc.on.doc")
                                .font(.caption2)
                                .padding(4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .buttonStyle(.plain)
        }
    }
}

// 小小的导航按钮
struct QuickNavBtn: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// ⚠️ 别忘了保留 BackgroundBlobs 和 HomeCardBase
// (如果之前文件里有，这里可以不重复写；如果没有，请保留之前的代码)

// MARK: - 🎨 基础样式封装 (Glassmorphism)
struct HomeCardBase<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder var content: Content
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // 背景层：根据日夜模式调整
            RoundedRectangle(cornerRadius: 24)
                .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                .opacity(colorScheme == .dark ? 0.8 : 0.6)
            
            // 纯白模式下的底色增强
            if colorScheme == .light {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.5))
            }
            
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // 阴影和悬浮效果
        .shadow(color: Color.black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 20 : 10, y: isHovering ? 10 : 5)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// 背景光斑组件
struct BackgroundBlobs: View {
    @Binding var animate: Bool
    
    var body: some View {
        ZStack {
            // 基础底色
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            
            // 光斑1: 蓝色
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(x: animate ? -200 : 0, y: animate ? -200 : -100)
            
            // 光斑2: 紫色
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: animate ? 200 : 100, y: animate ? 100 : 200)
            
            // 光斑3: 橙色 (活跃感)
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animate ? 0 : 200, y: animate ? 200 : 0)
        }
        .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animate)
    }
}
