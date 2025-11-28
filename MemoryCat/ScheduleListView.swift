import SwiftUI
import EventKit

// MARK: - 📅 仿截图风格的日程列表组件
struct UpcomingScheduleCard: View {
    @ObservedObject var manager: CalendarManager
    
    // ✨ 修改点 1：使用本地 State 存储未来日程，不依赖 manager 的属性
    @State private var upcomingEvents: [EKEvent] = []
    
    // 计算属性：按天分组
    var groupedEvents: [(date: Date, events: [EKEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcomingEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return grouped.map { key, value in
            (date: key, events: value.sorted { $0.startDate < $1.startDate })
        }.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        HomeCardBase {
            VStack(spacing: 0) {
                // 顶部标题
                HStack {
                    Label("接下来的日程", systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    // 刷新按钮 (可选)
                    Button {
                        fetchUpcomingEvents()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if upcomingEvents.isEmpty {
                            ContentUnavailableView("暂无日程", systemImage: "calendar.badge.checkmark", description: Text("未来7天没有安排，去休息吧~"))
                                .padding(.top, 20)
                        } else {
                            ForEach(groupedEvents, id: \.date) { group in
                                ScheduleDaySection(date: group.date, events: group.events)
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(height: 350)
            }
        }
        // ✨ 修改点 2：视图出现时主动拉取数据
        .onAppear {
            fetchUpcomingEvents()
        }
        // 监听 store 变化（比如你在日历页加了新事件，这里也要刷新）
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            fetchUpcomingEvents()
        }
    }
    
    // ✨ 修改点 3：主动拉取未来7天数据的函数
    func fetchUpcomingEvents() {
        // 确保获得了权限
        guard EKEventStore.authorizationStatus(for: .event) == .authorized else { return }
        
        let store = manager.store // 这里的 store 是 CalendarManager 里的底层 EKEventStore
        let calendar = Calendar.current
        
        // 设定范围：从现在开始，往后推 7 天
        let startDate = Date()
        guard let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) else { return }
        
        // 创建查询谓词 (Predicate)
        // calendars: nil 表示查询所有日历
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        
        // 放到后台队列去查，防止卡顿 UI，然后再回主线程更新
        DispatchQueue.global(qos: .userInitiated).async {
            let events = store.events(matching: predicate)
            
            DispatchQueue.main.async {
                // 过滤掉全天事件里已经过去的 (可选逻辑，看你需要)
                self.upcomingEvents = events.filter { event in
                    // 简单的过滤逻辑：结束时间还没到的
                    return event.endDate >= Date()
                }
            }
        }
    }
}

// MARK: - 📆 单日分组视图 (保持不变，但为了防止找不到，完整贴在下面)
struct ScheduleDaySection: View {
    let date: Date
    let events: [EKEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. 日期头
            HStack(spacing: 8) {
                Text(date.formatted(.dateTime.month().day()))
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? .red : .primary)
                
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? .red : .primary)
                
                Text("|")
                    .foregroundStyle(.secondary.opacity(0.5))
                
                Text(getLunarDate(date: date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            // 2. 事件列表
            VStack(spacing: 8) {
                ForEach(events.prefix(3), id: \.eventIdentifier) { event in
                    ScheduleEventRow(event: event)
                }
                
                if events.count > 3 {
                    HStack {
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: 4, height: 16)
                        Text("其他 \(events.count - 3) 个日程")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
    
    func getLunarDate(date: Date) -> String {
        let chinese = Calendar(identifier: .chinese)
        let month = chinese.component(.month, from: date)
        let day = chinese.component(.day, from: date)
        return "\(visualLunarMonth(month))\(visualLunarDay(day))"
    }
    
    func visualLunarMonth(_ m: Int) -> String {
        let map = ["正月","二月","三月","四月","五月","六月","七月","八月","九月","十月","冬月","腊月"]
        if m > 0 && m <= map.count { return map[m-1] }
        return ""
    }
    func visualLunarDay(_ d: Int) -> String {
        let map = ["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
                   "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
                   "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]
        if d > 0 && d <= map.count { return map[d-1] }
        return ""
    }
}

// MARK: - 🎟️ 单个日程条目
struct ScheduleEventRow: View {
    let event: EKEvent
    
    var calendarColor: Color {
        // 安全获取颜色，防止崩溃
        if let cg = event.calendar.cgColor {
            return Color(nsColor: NSColor(cgColor: cg) ?? .blue)
        }
        return .blue
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧色条
            Rectangle()
                .fill(calendarColor)
                .frame(width: 4)
                // 兼容旧系统的圆角写法
                .cornerRadius(4)
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(.subheadline, design: .default).bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location")
                                .font(.caption2)
                            Text(location)
                                .font(.caption)
                        }
                        .foregroundStyle(calendarColor.opacity(0.8))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if event.isAllDay {
                        Text("全天")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.8))
                        
                        Text(event.endDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(calendarColor.opacity(0.1))
        .cornerRadius(6)
    }
}
