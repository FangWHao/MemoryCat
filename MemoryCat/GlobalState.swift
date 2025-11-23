import SwiftUI
import UserNotifications
import SwiftData
import Combine
import AppKit

@MainActor
class GlobalState: ObservableObject {
    @Published var timerDuration: Double = 25 * 60
    @Published var timeRemaining: Double = 25 * 60
    @Published var isTimerRunning = false
    @Published var timerProgress: Double = 1.0
    @Published var lastUsedTags: [String] = []
    
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 30.0
    
    var sharedContext: ModelContext?
    private var timer: Timer?
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startScreenMonitoring(context: ModelContext) {
        self.sharedContext = context
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordCurrentApp()
            }
        }
    }
    
    private func recordCurrentApp() {
        guard let context = sharedContext else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleID = frontApp.bundleIdentifier ?? "unknown"
        
        // 👇👇👇 新增：系统进程黑名单 👇👇👇
        let ignoredBundleIDs: Set<String> = [
            "com.apple.loginwindow",            // 登录窗口
            "com.apple.systemuiserver",         // 系统UI服务 (顶部菜单栏图标等)
            "com.apple.dock",                   // 底部 Dock 栏
            "com.apple.controlcenter",          // 控制中心
            "com.apple.notificationcenterui",   // 通知中心
            "com.apple.WindowManager",          // 窗口管理
            "com.apple.screencaptureui"         // 截图工具 (看个人喜好，通常也不算专注)
        ]
        
        // 如果是黑名单里的应用，直接忽略，不记录！
        if ignoredBundleIDs.contains(bundleID) {
            return
        }
        
        
        let appName = frontApp.localizedName ?? "未知应用"
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleID == bundleID &&
                $0.date >= startOfDay &&
                $0.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date)]
        )
        
        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                existing.duration += monitorInterval
                existing.appName = appName
                if existing.icon == nil {
                    existing.icon = frontApp.icon?.resize(to: CGSize(width: 64, height: 64))?.pngData
                }
            } else {
                let iconData = frontApp.icon?.resize(to: CGSize(width: 64, height: 64))?.pngData
                let newRecord = AppUsageRecord(
                    bundleID: bundleID,
                    appName: appName,
                    date: startOfDay,
                    duration: monitorInterval,
                    icon: iconData
                )
                context.insert(newRecord)
            }
        } catch {
            print("监控出错: \(error)")
        }
    }
    
    func startTimer(context: ModelContext? = nil) {
        if let context = context { self.sharedContext = context }
        guard !isTimerRunning else { return }
        if timeRemaining <= 0 { resetTimer() }
        isTimerRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    self.timerProgress = self.timeRemaining / self.timerDuration
                } else {
                    self.stopTimer(finished: true)
                }
            }
        }
    }
    
    func pauseTimer() {
        isTimerRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func stopTimer(finished: Bool, modelContext: ModelContext? = nil) {
        pauseTimer()
        if finished {
            let ctx = modelContext ?? self.sharedContext
            if let context = ctx {
                let record = PomodoroRecord(duration: timerDuration)
                context.insert(record)
                try? context.save()
                print("番茄钟记录已保存: \(timerDuration)s")
            }
            let content = UNMutableNotificationContent()
            content.title = "专注完成！"
            content.body = "休息一下吧！"
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            resetTimer()
        }
    }
    
    func resetTimer() {
        pauseTimer()
        timeRemaining = timerDuration
        timerProgress = 1.0
    }
    
    func setDuration(_ minutes: Double) {
        timerDuration = minutes * 60
        resetTimer()
    }
    
    func updateLastUsedTags(_ tagString: String) {
        let tags = tagString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.lastUsedTags = tags
    }
}

extension NSImage {
    func resize(to targetSize: CGSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: self.size), operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    var pngData: Data? {
        guard let tiff = self.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
