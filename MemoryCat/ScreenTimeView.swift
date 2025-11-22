import SwiftUI
import SwiftData
import Charts

struct ScreenTimeView: View {
    @State private var viewMode: ViewMode = .daily
    @State private var selectedDate: Date = Date()
    @State private var weekOffset: Int = 0
    
    // 垃圾桶 + 手动 fetch 都需要 Context
    @Environment(\.modelContext) var context
    @State private var showDeleteAlert = false
    
    // 👇 新增：不再用 @Query，而是自己存结果快照
    @State private var dailyRecords: [AppUsageRecord] = []
    @State private var weeklyRecords: [AppUsageRecord] = []
    
    enum ViewMode: String, CaseIterable {
        case daily = "按日查询"
        case weekly = "按周趋势"
    }
    
    var body: some View {

        ScrollView {
            let _ = print("ScreenTimeView rendered at", Date())
            VStack(alignment: .leading, spacing: 24) {
                // 1. 顶部大标题、模式切换、垃圾桶
                HStack {
                    Text("屏幕时间")
                        .font(.largeTitle.bold())
                    
                    Spacer()
                    
                    Picker("模式", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    // 🗑️ 清空数据按钮
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("清空所有屏幕时间记录（解决卡顿问题）")
                }
                
                Divider()
                
                // 2. 根据模式加载不同视图（直接用状态数组）
                switch viewMode {
                case .daily:
                    DailyStatsView(
                        selectedDate: $selectedDate,
                        dailyRecords: dailyRecords
                    )
                case .weekly:
                    WeeklyStatsView(
                        weekOffset: $weekOffset,
                        weeklyRecords: weeklyRecords
                    )
                }
            }
            .padding(40)
        }
        .alert("清空屏幕时间数据？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("全部清空", role: .destructive) {
                do {
                    try context.delete(model: AppUsageRecord.self)
                    dailyRecords = []
                    weeklyRecords = []
                    print("已清空所有屏幕时间记录")
                } catch {
                    print("清空失败: \(error)")
                }
            }
        } message: {
            Text("如果感觉卡顿严重，建议清空一次。这不会影响您的记忆卡片数据。")
        }
        // 👇👇👇 关键：只在这些时机重新 fetch
        .onAppear {
            reloadForCurrentMode()
        }
        .onChange(of: viewMode) { _ in
            reloadForCurrentMode()
        }
        .onChange(of: selectedDate) { _ in
            if viewMode == .daily {
                reloadDaily()
            }
        }
        .onChange(of: weekOffset) { _ in
            if viewMode == .weekly {
                reloadWeekly()
            }
        }
    }
    
    // MARK: - 加载逻辑
    
    private func reloadForCurrentMode() {
        switch viewMode {
        case .daily:
            reloadDaily()
        case .weekly:
            reloadWeekly()
        }
    }
    
    private func reloadDaily() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: selectedDate) ?? selectedDate
        
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.date >= startOfDay && $0.date <= endOfDay
            },
            sortBy: [SortDescriptor(\.duration, order: .reverse)]
        )
        
        do {
            dailyRecords = try context.fetch(descriptor)
        } catch {
            print("加载当日记录失败: \(error)")
            dailyRecords = []
        }
    }
    
    private func reloadWeekly() {
        let calendar = Calendar.current
        let today = Date()
        let baseWeek = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today) ?? today
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: baseWeek)) ?? today
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? today
        
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.date >= startOfWeek && $0.date < endOfWeek
            },
            sortBy: [SortDescriptor(\.duration, order: .reverse)]
        )
        
        do {
            weeklyRecords = try context.fetch(descriptor)
        } catch {
            print("加载周记录失败: \(error)")
            weeklyRecords = []
        }
    }
}

// MARK: - 📅 日视图 UI
struct DailyStatsView: View {
    @Binding var selectedDate: Date
    let dailyRecords: [AppUsageRecord]
    
    @State private var showCalendarPopover = false
    
    var totalDuration: Double {
        dailyRecords.reduce(0) { $0 + $1.duration }
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // 日期导航栏
            HStack(spacing: 16) {
                Button(action: { moveDay(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                
                Button(action: { showCalendarPopover = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
                        
                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 220, alignment: .center)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCalendarPopover) {
                    DatePicker(
                        "选择日期",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .frame(width: 280)
                    .padding()
                }
                
                Button(action: { moveDay(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.body.bold())
                        .foregroundStyle(isToday ? .gray.opacity(0.2) : .secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(isToday ? 0 : 0.05), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(isToday)
            }
            .padding(.bottom, 10)
            
            if dailyRecords.isEmpty {
                ContentUnavailableView("这天没有记录", systemImage: "zzz", description: Text("这天好像没有打开电脑，或者我在偷懒..."))
                    .frame(height: 300)
            } else {
                // 核心数据卡片
                HStack(spacing: 20) {
                    STStatCard(title: "当日总计", value: formatDuration(totalDuration), icon: "clock.fill", color: .blue)
                    STStatCard(title: "最常使用", value: dailyRecords.first?.appName ?? "-", icon: "crown.fill", color: .orange)
                }
                
                // 饼图 (只显示前8个)
                VStack(alignment: .leading) {
                    Text("时间分布").font(.headline).padding(.bottom, 5)
                    Chart(dailyRecords.prefix(8)) { item in
                        SectorMark(
                            angle: .value("时长", item.duration),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .cornerRadius(5)
                        .foregroundStyle(by: .value("App", item.appName))
                    }
                    .frame(height: 300)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 列表 (只显示前20个，防止卡顿！)
                let topRecords = dailyRecords.prefix(20)
                AppUsageListView(
                    items: topRecords.map {
                        AppUsageDisplay(
                            id: $0.bundleID,              // ✅ 稳定 ID
                            name: $0.appName,
                            duration: $0.duration,
                            icon: $0.icon
                        )
                    },
                    total: totalDuration
                )

                
                if dailyRecords.count > 20 {
                    Text("还有 \(dailyRecords.count - 20) 个应用未显示...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading)
                }
            }
        }
    }
    
    func moveDay(by offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            if newDate <= Date() {
                withAnimation {
                    selectedDate = newDate
                }
            }
        }
    }
}

// MARK: - 🗓️ 周视图 UI
struct WeeklyStatsView: View {
    @Binding var weekOffset: Int
    let weeklyRecords: [AppUsageRecord]
    
    var weekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = Date()
        guard let baseWeek = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today),
              let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: baseWeek))
        else { return (today, today) }
        
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? startOfWeek
        return (startOfWeek, endOfWeek)
    }
    
    // 聚合逻辑：按 App 合并并排序
    var aggregatedApps: [AppUsageDisplay] {
        // 按 bundleID 分组，保证同一个 app 归在一起
        let grouped = Dictionary(grouping: weeklyRecords) { $0.bundleID }
        
        let sorted = grouped.map { (bundleID, records) in
            let total = records.reduce(0) { $0 + $1.duration }
            let name = records.first?.appName ?? bundleID
            return AppUsageDisplay(
                id: bundleID,          // ✅ 稳定 ID
                name: name,
                duration: total,
                icon: records.first?.icon
            )
        }
        .sorted { $0.duration > $1.duration }
        
        return Array(sorted.prefix(20))
    }

    
    // 每日趋势数据
    struct DailyTotal: Identifiable {
        let id = UUID()
        let date: Date
        let duration: Double // 小时
    }
    
    var dailyTrend: [DailyTotal] {
        let calendar = Calendar.current
        let range = weekRange
        var result: [DailyTotal] = []
        
        for i in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: i, to: range.start) {
                let dayRecords = weeklyRecords.filter { calendar.isDate($0.date, inSameDayAs: dayDate) }
                let totalSeconds = dayRecords.reduce(0) { $0 + $1.duration }
                result.append(DailyTotal(date: dayDate, duration: totalSeconds / 3600.0))
            }
        }
        return result
    }
    
    var totalDuration: Double {
        weeklyRecords.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 周导航栏
            HStack {
                Button(action: { withAnimation { weekOffset -= 1 } }) {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(weekOffset == 0 ? "本周" : (weekOffset == -1 ? "上周" : "\(abs(weekOffset))周前"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("\(weekRange.start.formatted(.dateTime.month().day())) - \(weekRange.end.formatted(.dateTime.month().day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { withAnimation { weekOffset += 1 } }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(weekOffset >= 0 ? .gray.opacity(0.3) : .primary)
                }
                .buttonStyle(.plain)
                .disabled(weekOffset >= 0)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            if weeklyRecords.isEmpty {
                ContentUnavailableView("本周无数据", systemImage: "calendar.badge.exclamationmark", description: Text("这段时间看起来很清闲呢~"))
                    .frame(height: 300)
            } else {
                STStatCard(title: "周累计时长", value: formatDuration(totalDuration), icon: "chart.bar.fill", color: .purple)
                
                // 每日趋势折线图
                VStack(alignment: .leading) {
                    Text("每日趋势 (小时)").font(.headline).padding(.bottom, 10)
                    
                    Chart(dailyTrend) { item in
                        LineMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("时长", item.duration)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.blue)
                        .symbol(Circle())
                        
                        AreaMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("时长", item.duration)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisValueLabel(format: .dateTime.weekday(), centered: true)
                        }
                    }
                    .frame(height: 250)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 周排行列表
                VStack(alignment: .leading) {
                    Text("周排行 (Top 20)").font(.headline).padding(.bottom, 10)
                    AppUsageListView(items: aggregatedApps, total: totalDuration)
                }
            }
        }
    }
}

// MARK: - 🛠️ 辅助组件

struct AppUsageDisplay: Identifiable, Hashable {
    /// 用 bundleID 做稳定 ID，避免每次都是新的 UUID
    let id: String       // bundleID
    let name: String     // appName
    let duration: Double // 秒
    let icon: Data?
}


struct AppUsageListView: View {
    let items: [AppUsageDisplay]
    let total: Double
    
    var body: some View {
        ForEach(items) { item in
            HStack {
                // 使用缓存：同一个 bundleID 只解码一次
                if let image = AppIconCache.shared.image(for: item.id, data: item.icon) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                        .frame(width: 32, height: 32)
                }
                
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.body.bold())
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.1))
                            if total > 0 {
                                Capsule().fill(Color.blue.opacity(0.6))
                                    .frame(width: geo.size.width * (item.duration / total))
                            }
                        }
                    }
                    .frame(height: 4)
                }
                
                Spacer()
                
                Text(formatDuration(item.duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// 为了不和 StatsView 的冲突，这里改个名，或者你可以确认 StatsView 的那个是 public 的直接复用
struct STStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title.bold()).foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .padding(10)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    let h = m / 60
    if h > 0 { return "\(h)h \(m % 60)m" }
    else { return "\(m)m" }
}
// MARK: - 简单图标缓存，避免重复解码 PNG

final class AppIconCache {
    static let shared = AppIconCache()
    
    private let cache = NSCache<NSString, NSImage>()
    
    func image(for id: String, data: Data?) -> NSImage? {
        // 先看缓存里有没
        if let cached = cache.object(forKey: id as NSString) {
            return cached
        }
        // 没有的话，尝试解码一次，并存进去
        guard let data,
              let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: id as NSString)
        return image
    }
}
