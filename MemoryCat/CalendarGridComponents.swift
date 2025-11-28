// 📄 CalendarGridComponents.swift
import SwiftUI
import EventKit
import Combine
import SwiftData

// MARK: - 🧱 数据模型
struct PositionedEvent: Identifiable {
    let id = UUID()
    let event: EKEvent
    let frame: CGRect
    let zIndex: Int
}

// MARK: - 📦 状态管理
class EventEditState: ObservableObject {
    @Published var selectedEvent: EKEvent? = nil
    @Published var isNewEvent: Bool = false
    
    // ✋ 仅保留新建时的拖拽状态
    enum DragMode { case create }
    
    @Published var activeDragEvent: EKEvent? = nil
    @Published var dragMode: DragMode? = nil
    
    func close() {
        selectedEvent = nil
        isNewEvent = false
        activeDragEvent = nil
        dragMode = nil
    }
}

// MARK: - 🛡️ 基础扩展 (保持不变)
extension EKCalendar {
    var safeColor: Color {
        guard let cg = self.cgColor else { return .blue }
        return Color(nsColor: NSColor(cgColor: cg) ?? .blue)
    }
}

extension Array where Element: EKEvent {
    func deduped() -> [EKEvent] {
        var seen = Set<String>()
        return filter { seen.insert($0.eventIdentifier).inserted }
    }
}

extension Color {
    var darker: Color {
        let nsColor = NSColor(self)
        let darkened = nsColor.blended(withFraction: 0.4, of: .black) ?? nsColor
        return Color(nsColor: darkened)
    }
}

// MARK: - 🧮 布局算法核心 (保持不变)
struct LayoutHelper {
    static func calculateFrames(events: [EKEvent], in totalWidth: CGFloat, hourHeight: CGFloat) -> [PositionedEvent] {
        let dayEvents = events.filter { !$0.isAllDay }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.endDate > $1.endDate
        }
        if dayEvents.isEmpty { return [] }
        
        var columns: [[EKEvent]] = []
        var eventColMap: [String: Int] = [:]
        
        for event in dayEvents {
            var placed = false
            for i in 0..<columns.count {
                if !columns[i].contains(where: { intersects($0, event) }) {
                    columns[i].append(event)
                    eventColMap[event.eventIdentifier] = i
                    placed = true
                    break
                }
            }
            if !placed {
                columns.append([event])
                eventColMap[event.eventIdentifier] = columns.count - 1
            }
        }
        
        var positioned: [PositionedEvent] = []
        for event in dayEvents {
            guard let colIndex = eventColMap[event.eventIdentifier] else { continue }
            let concurrent = dayEvents.filter { $0 != event && intersects($0, event) }
            
            let neighborMax = concurrent.compactMap { eventColMap[$0.eventIdentifier] }.max() ?? 0
            let totalCols = max(neighborMax, colIndex) + 1
            
            let startY = calculateY(for: event.startDate, hourHeight: hourHeight)
            let endY = calculateY(for: event.endDate, hourHeight: hourHeight)
            let height = max(20, endY - startY)
            
            let spacing: CGFloat = 1.0
            let colWidth = (totalWidth - (CGFloat(totalCols) - 1) * spacing) / CGFloat(totalCols)
            let x = CGFloat(colIndex) * (colWidth + spacing)
            
            positioned.append(PositionedEvent(event: event, frame: CGRect(x: x, y: startY, width: colWidth, height: height), zIndex: colIndex + 10))
        }
        return positioned
    }
    
    static func intersects(_ a: EKEvent, _ b: EKEvent) -> Bool {
        return a.startDate < b.endDate && a.endDate > b.startDate
    }
    
    static func calculateY(for date: Date, hourHeight: CGFloat) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let min = cal.component(.minute, from: date)
        return CGFloat(hour) * hourHeight + CGFloat(min) / 60.0 * hourHeight
    }
    
    static func calculateTimeFromY(_ y: CGFloat, hourHeight: CGFloat) -> TimeInterval {
        let hour = floor(y / hourHeight)
        let minute = (y.truncatingRemainder(dividingBy: hourHeight) / hourHeight) * 60
        let roundedMinute = round(minute / 15) * 15
        return (hour * 60 + roundedMinute) * 60
    }
}

// MARK: - ☀️ 主视图容器
struct InteractiveTimelineContainer: View {
    let mode: CalendarViewMode
    let currentDate: Date
    let events: [EKEvent]
    let todos: [TodoItem]
    @ObservedObject var editState: EventEditState
    @ObservedObject var manager: CalendarManager
    
    var datesToShow: [Date] {
        if mode == .day { return [currentDate] }
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: currentDate) else { return [currentDate] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }
    
    var body: some View {
        Group {
            if mode == .month {
                MonthCalendarContainer(currentDate: currentDate, events: events, editState: editState)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if mode == .week { WeekHeaderView(dates: datesToShow) }
                        AllDayEventsRow(dates: datesToShow, events: events, todos: todos)
                            .padding(.leading, 50).padding(.trailing, 14)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                            .fixedSize(horizontal: false, vertical: true)
                            .overlay(Divider(), alignment: .bottom)
                    }
                    .zIndex(10)
                    
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                // 层级 1: 基础网格
                                HStack(alignment: .top, spacing: 0) {
                                    TimeLabelsColumn()
                                        .padding(.top, 10)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                    
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(datesToShow, id: \.self) { date in
                                            let dayEvents = events
                                                .filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
                                                .deduped()
                                            
                                            DayTimelineColumn(date: date, events: dayEvents, editState: editState, manager: manager)
                                                .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.gray.opacity(0.1)), alignment: .trailing)
                                        }
                                    }
                                }
                                
                                // 层级 2: 全局红线 (🔴 修复：不透明)
                                GlobalTimeIndicator(timelineWidth: 50, isTodayFocused: false)
                                    .padding(.top, 10)
                                    .zIndex(90)
                                
                                // 层级 3: 拖拽新建时的临时层
                                if let dragEvent = editState.activeDragEvent {
                                    DragFeedbackLayer(dragEvent: dragEvent, dates: datesToShow)
                                        .zIndex(999)
                                }
                            }
                            .padding(.bottom, 50)
                            .onAppear { scrollProxy.scrollTo(8, anchor: .top) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 🤚 拖拽反馈层 (仅用于新建)
struct DragFeedbackLayer: View {
    let dragEvent: EKEvent
    let dates: [Date]
    let hourHeight: CGFloat = 60.0
    
    var body: some View {
        GeometryReader { geo in
            let dayWidth = (geo.size.width - 50) / CGFloat(dates.count)
            if let dayIndex = dates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: dragEvent.startDate) }) {
                let startY = LayoutHelper.calculateY(for: dragEvent.startDate, hourHeight: hourHeight)
                let endY = LayoutHelper.calculateY(for: dragEvent.endDate, hourHeight: hourHeight)
                let height = max(20, endY - startY)
                let x = 50 + CGFloat(dayIndex) * dayWidth
                
                EventBlock(event: dragEvent, rect: CGRect(x: 0, y: 0, width: dayWidth - 4, height: height), isDraft: true)
                    .offset(x: x, y: startY)
                    .allowsHitTesting(false)
                    .opacity(0.9)
                    .shadow(radius: 5)
            }
        }
    }
}

// MARK: - 📅 单日列 (只保留新建拖拽)
struct DayTimelineColumn: View {
    let date: Date
    let events: [EKEvent]
    @ObservedObject var editState: EventEditState
    @ObservedObject var manager: CalendarManager
    let hourHeight: CGFloat = 60.0
    
    var body: some View {
        GeometryReader { geo in
            let positionedEvents = LayoutHelper.calculateFrames(
                events: events,
                in: geo.size.width,
                hourHeight: hourHeight
            )
            
            ZStack(alignment: .topLeading) {
                // 1. 背景网格 & 新建交互 (✅ 保留)
                VStack(spacing: 0) {
                    ForEach(0..<24) { _ in
                        Divider().opacity(0.3)
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .frame(height: hourHeight - 1)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in handleCreateDrag(value) }
                        .onEnded { _ in handleCreateEnd() }
                )
                
                // 3. 事件渲染层
                ForEach(positionedEvents) { item in
                    EventBlockContainer(
                        event: item.event,
                        editState: editState,
                        manager: manager,
                        dayWidth: geo.size.width
                    )
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
                    .zIndex(Double(item.zIndex))
                }
            }
        }
        .frame(height: 24 * hourHeight)
        .contentShape(Rectangle())
    }
    
    // --- 新建拖拽逻辑 (✅ 保留) ---
    func handleCreateDrag(_ value: DragGesture.Value) {
        // 如果正在进行其他模式的操作，禁止新建
        if editState.dragMode != nil && editState.dragMode != .create { return }
        
        let startY = value.startLocation.y
        let currentY = value.location.y
        let startSeconds = LayoutHelper.calculateTimeFromY(startY, hourHeight: hourHeight)
        let durationMinutes = max(15, abs(currentY - startY) / hourHeight * 60)
        let snappedDuration = ceil(durationMinutes / 15) * 15
        
        let draft = EKEvent(eventStore: manager.store)
        let startOfDay = Calendar.current.startOfDay(for: date)
        draft.startDate = startOfDay.addingTimeInterval(startSeconds)
        draft.endDate = draft.startDate.addingTimeInterval(snappedDuration * 60)
        draft.title = "新建日程"
        draft.calendar = manager.getDefaultCalendar()
        
        editState.activeDragEvent = draft
        editState.dragMode = .create
    }
    
    func handleCreateEnd() {
        if let draft = editState.activeDragEvent, editState.dragMode == .create {
            editState.selectedEvent = draft
            editState.isNewEvent = true
        }
        editState.dragMode = nil
    }
}


// MARK: - 🧩 事件容器 (❌ 删除了移动和缩放手势)
struct EventBlockContainer: View {
    let event: EKEvent
    @ObservedObject var editState: EventEditState
    @ObservedObject var manager: CalendarManager
    let dayWidth: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let localRect = CGRect(origin: .zero, size: geo.size)
            
            // 1. 事件本体
            EventBlock(event: event, rect: localRect)
                .opacity(editState.activeDragEvent?.eventIdentifier == event.eventIdentifier ? 0 : 1)
                // ✋ 仅保留点击查看详情
                .onTapGesture {
                    editState.selectedEvent = event
                    editState.isNewEvent = false
                    editState.activeDragEvent = nil
                }
        }
    }
}

// MARK: - ✨ 全局指示器 (🔴 瘦身长胶囊版)
struct GlobalTimeIndicator: View {
    let timelineWidth: CGFloat
    let isTodayFocused: Bool
    
    @State private var offset: CGFloat = 0
    @State private var timeString: String = ""
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. 左侧时间胶囊
            ZStack(alignment: .trailing) {
                Text(timeString)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 6) // ✨ 左右变窄 (10 -> 6)
                    .padding(.vertical, 3)   // ✨ 上下变窄 (5 -> 3)
                    .background(Capsule().fill(Color.red))
                    .fixedSize()
            }
            .frame(width: timelineWidth, alignment: .trailing)
            .zIndex(10)
            
            // 2. 连接小圆点
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
                .offset(x: -2.5)
                .zIndex(5)
            
            // 3. 贯穿线
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
                .offset(x: -2.5)
        }
        .offset(y: offset - 10) // ✨ 微调垂直对齐
        .onAppear { update() }
        .onReceive(timer) { _ in update() }
        .allowsHitTesting(false)
    }
    
    func update() {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let min = cal.component(.minute, from: now)
        offset = CGFloat(hour) * 60.0 + CGFloat(min)
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        timeString = formatter.string(from: now)
    }
}

// MARK: - 🎨 事件块 (样式保持不变)
struct EventBlock: View {
    let event: EKEvent
    let rect: CGRect
    var isDraft: Bool = false
    
    var body: some View {
        let baseColor = isDraft ? Color.blue : event.calendar?.safeColor ?? .blue
        let isVeryShort = rect.height < 25
        
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(baseColor.opacity(isDraft ? 0.3 : 0.12))
            
            HStack {
                Capsule().fill(baseColor).frame(width: 3).padding(.vertical, 4)
                Spacer()
            }
            .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(baseColor.darker)
                    .lineLimit(isVeryShort ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !isVeryShort && rect.height > 40 {
                    HStack(spacing: 0) {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        Text(" - ")
                        Text(event.endDate.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(baseColor.darker.opacity(0.85))
                    .padding(.top, 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                }
            }
            .padding(.leading, 12).padding(.top, 4).padding(.trailing, 4)
        }
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
        )
        .overlay(
            isDraft ? RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 2, dash: [5])).foregroundStyle(.white.opacity(0.5)) : nil
        )
    }
}

// MARK: - 静态组件 (WeekHeaderView 等，保持不变)
struct WeekHeaderView: View {
    let dates: [Date]
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 65)
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    VStack(spacing: 0) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.bottom, 1)
                        ZStack {
                            if Calendar.current.isDateInToday(date) {
                                Circle().fill(Color.red).frame(width: 20, height: 20)
                                Text(date.formatted(.dateTime.day())).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            } else {
                                Text(date.formatted(.dateTime.day())).font(.system(size: 11)).foregroundStyle(.primary).frame(height: 20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.gray.opacity(0.1)), alignment: .trailing)
                }
            }
        }.frame(height: 50).padding(.trailing, 14).background(Color(nsColor: .windowBackgroundColor)).overlay(Divider(), alignment: .bottom)
    }
}

struct TimeLabelsColumn: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<24) { hour in
                Text(String(format: "%d:00", hour))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 60, alignment: .topTrailing)
                    .padding(.trailing, 8)
                    .offset(y: -6)
                    .id(hour)
            }
        }
        .frame(width: 65)
    }
}

struct AllDayEventsRow: View {
    let dates: [Date]; let events: [EKEvent]; let todos: [TodoItem]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let dayEvents = events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) && $0.isAllDay }.deduped()
                let dayTodos = todos.filter { guard let due = $0.dueDate else { return false }; return Calendar.current.isDate(due, inSameDayAs: date) && !$0.isCompleted }
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(dayEvents, id: \.eventIdentifier) { event in
                        Text(event.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 4).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .blue).opacity(0.2)).foregroundStyle(Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .blue)).cornerRadius(2)
                    }
                    ForEach(dayTodos) { todo in
                        HStack(spacing: 2) { Image(systemName: "circle").font(.system(size: 8)); Text(todo.content).font(.system(size: 10, weight: .medium)).lineLimit(1) }.padding(.horizontal, 4).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1)).foregroundStyle(.orange).cornerRadius(2)
                    }
                    if dayEvents.isEmpty && dayTodos.isEmpty { Color.clear.frame(height: 1) }
                }.padding(.vertical, 2).padding(.horizontal, 1).frame(maxWidth: .infinity).overlay(Rectangle().frame(width: 1).foregroundStyle(Color.gray.opacity(0.1)), alignment: .trailing)
            }
        }
    }
}

struct MonthCalendarContainer: View {
    let currentDate: Date; let events: [EKEvent]; @ObservedObject var editState: EventEditState
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    var days: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else { return [] }
        let monthStart = monthInterval.start; let weekday = calendar.component(.weekday, from: monthStart); let offset = weekday - 1
        guard let startDisplay = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: startDisplay) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in Text(day).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8).background(.ultraThinMaterial) } }
            Divider()
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(days, id: \.self) { date in
                    let isCurrentMonth = calendar.isDate(date, equalTo: currentDate, toGranularity: .month)
                    let dayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }.deduped()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text("\(calendar.component(.day, from: date))").font(.system(size: 14, weight: isCurrentMonth ? .bold : .regular)).foregroundStyle(calendar.isDateInToday(date) ? .red : (isCurrentMonth ? .primary : .secondary.opacity(0.5))).padding(4).background(calendar.isDateInToday(date) ? Circle().fill(Color.red.opacity(0.1)) : nil); Spacer() }
                        ForEach(dayEvents.prefix(4), id: \.eventIdentifier) { event in
                            HStack(spacing: 2) { Circle().fill(event.calendar.safeColor).frame(width: 4, height: 4); Text(event.title).font(.caption2).lineLimit(1).foregroundStyle(.primary) }.padding(.horizontal, 2).onTapGesture { editState.selectedEvent = event; editState.isNewEvent = false }
                        }
                        Spacer()
                    }.frame(height: 100, alignment: .top).background(Color(nsColor: .textBackgroundColor)).border(Color.gray.opacity(0.1), width: 0.5)
                }
            }
        }.padding(10)
    }
}

struct EventInspectorView: View {
    @ObservedObject var editState: EventEditState; @ObservedObject var manager: CalendarManager
    @State private var title = ""; @State private var startDate = Date(); @State private var endDate = Date(); @State private var selectedCalendar: EKCalendar?; @State private var notes = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { Button("取消") { editState.close() }.buttonStyle(.plain).foregroundStyle(.red); Spacer(); Text(editState.isNewEvent ? "新建" : "详情").font(.headline); Spacer(); Button("完成") { saveEvent() }.buttonStyle(.plain).fontWeight(.bold).foregroundStyle(.blue) }.padding().background(.ultraThinMaterial).overlay(Divider(), alignment: .bottom)
            ScrollView {
                VStack(spacing: 0) {
                    TextField("日程标题", text: $title).font(.title2.bold()).textFieldStyle(.plain).padding(20); Divider().padding(.leading, 20)
                    VStack(spacing: 16) { HStack { Text("开始").foregroundStyle(.secondary).frame(width: 40, alignment: .leading); DatePicker("", selection: $startDate).labelsHidden().datePickerStyle(.compact); Spacer() }; HStack { Text("结束").foregroundStyle(.secondary).frame(width: 40, alignment: .leading); DatePicker("", selection: $endDate).labelsHidden().datePickerStyle(.compact); Spacer() } }.padding(20); Divider().padding(.leading, 20)
                    HStack { if let cal = selectedCalendar { Circle().fill(cal.safeColor).frame(width: 8, height: 8) }; if let _ = selectedCalendar { Picker("", selection: $selectedCalendar) { ForEach(manager.calendarGroups.flatMap { $0.calendars }, id: \.self) { cal in Text(cal.title).tag(cal as EKCalendar?) } }.labelsHidden() }; Spacer() }.padding(20); Divider().padding(.leading, 20)
                    ZStack(alignment: .topLeading) { if notes.isEmpty { Text("备注...").foregroundStyle(.tertiary).padding(.top, 4) }; TextEditor(text: $notes).font(.body).scrollContentBackground(.hidden).background(.clear).frame(minHeight: 100) }.padding(20)
                    if !editState.isNewEvent { Divider(); Button(role: .destructive) { deleteEvent() } label: { Text("删除日程").frame(maxWidth: .infinity).padding() }.buttonStyle(.plain).foregroundStyle(.red) }
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor)).overlay(Divider(), alignment: .leading).onAppear(perform: setupData).onChange(of: editState.selectedEvent) { _, _ in setupData() }
    }
    func setupData() { if let event = editState.selectedEvent { title = event.title; startDate = event.startDate; endDate = event.endDate; selectedCalendar = event.calendar ?? manager.getDefaultCalendar(); notes = event.notes ?? "" } else { selectedCalendar = manager.getDefaultCalendar() } }
    func saveEvent() { guard let editing = editState.selectedEvent else { return }; let event = editState.isNewEvent ? EKEvent(eventStore: manager.store) : editing; event.title = title.isEmpty ? "日程" : title; event.startDate = startDate; event.endDate = endDate; event.calendar = selectedCalendar ?? manager.getDefaultCalendar(); event.notes = notes; manager.saveEvent(event); editState.close() }
    func deleteEvent() { if let event = editState.selectedEvent { try? manager.store.remove(event, span: .thisEvent); manager.fetchEvents(); editState.close() } }
}
