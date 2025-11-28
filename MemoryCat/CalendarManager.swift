// 📄 CalendarManager.swift
import Foundation
import EventKit
import SwiftUI
import Combine

struct CalendarGroup: Identifiable {
    let id: String
    let sourceTitle: String
    var calendars: [EKCalendar]
}

@MainActor
class CalendarManager: ObservableObject {
    let store = EKEventStore()
    
    @Published var displayEvents: [EKEvent] = []
    @Published var calendarGroups: [CalendarGroup] = []
    @Published var visibleCalendarIDs: Set<String> = []
    @Published var isAccessGranted = false
    
    init() {
        // 1. 加载保存的可见日历设置
        if let saved = UserDefaults.standard.array(forKey: "VisibleCalendars") as? [String] {
            visibleCalendarIDs = Set(saved)
        }
        
        // 2. 检查权限
        checkPermission()
        
        // 🌟 3. 核心修复：监听系统日历变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
    }
    
    // 🌟 当系统日历发生变化时，自动刷新
    @objc func storeChanged() {
        print("检测到外部日历变化，正在刷新...")
        Task { @MainActor in
            self.fetchEvents()
        }
    }
    
    func checkPermission() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            isAccessGranted = true
            loadCalendarsAndEvents()
        case .notDetermined:
            requestAccess()
        default:
            isAccessGranted = false
        }
    }
    
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                self?.isAccessGranted = granted
                if granted { self?.loadCalendarsAndEvents() }
            }
        }
    }
    
    func loadCalendarsAndEvents() {
        guard isAccessGranted else { return }
        let calendars = store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars) { $0.source.title }
        self.calendarGroups = grouped.map { (source, cals) in
            CalendarGroup(id: source, sourceTitle: source, calendars: cals.sorted { $0.title < $1.title })
        }.sorted { $0.sourceTitle < $1.sourceTitle }
        
        if UserDefaults.standard.array(forKey: "VisibleCalendars") == nil {
            self.visibleCalendarIDs = Set(calendars.map { $0.calendarIdentifier })
        }
        fetchEvents()
    }
    
    func toggleCalendar(_ calendarID: String) {
        if visibleCalendarIDs.contains(calendarID) {
            visibleCalendarIDs.remove(calendarID)
        } else {
            visibleCalendarIDs.insert(calendarID)
        }
        UserDefaults.standard.set(Array(visibleCalendarIDs), forKey: "VisibleCalendars")
        filterEvents()
    }
    
    func fetchEvents() {
        let now = Date()
        // 拉取前后一年的数据
        guard let start = Calendar.current.date(byAdding: .year, value: -1, to: now),
              let end = Calendar.current.date(byAdding: .year, value: 1, to: now) else { return }
        
        // 必须指定 Calendars 否则可能拉不到数据
        let calsToFetch = store.calendars(for: .event) // 这里先拉取全部，然后在内存里 filter，防止谓词失效
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calsToFetch.isEmpty ? nil : calsToFetch)
        
        self.allSystemEvents = store.events(matching: predicate)
        filterEvents()
    }
    
    private var allSystemEvents: [EKEvent] = []
    
    private func filterEvents() {
        self.displayEvents = allSystemEvents.filter { event in
            visibleCalendarIDs.contains(event.calendar.calendarIdentifier)
        }
    }
    
    func saveEvent(_ event: EKEvent) {
        do {
            try store.save(event, span: .thisEvent)
            // fetchEvents() // 不需要手动调用了，因为 Notification 会触发
            print("Event saved!")
        } catch {
            print("Failed to save event: \(error)")
        }
    }
    
    func getDefaultCalendar() -> EKCalendar? {
        return store.defaultCalendarForNewEvents
    }
}
