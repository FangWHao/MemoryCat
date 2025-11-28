import SwiftUI
import UserNotifications
import SwiftData
import Combine
import AppKit

@MainActor
class GlobalState: ObservableObject {
    // MARK: - ⏱️ 计时器状态
    @Published var timerDuration: Double = 25 * 60
    @Published var timeRemaining: Double = 25 * 60
    @Published var isTimerRunning = false
    @Published var isTimerPaused = false // ✨ 新增：暂停状态
    @Published var timerProgress: Double = 1.0
    
    // MARK: - 🏷️ 其他状态
    @Published var lastUsedTags: [String] = []
    
    // MARK: - 🔧 内部变量
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 30.0
    
    var sharedContext: ModelContext?
    private var timer: Timer?
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    // MARK: - 🖥️ 屏幕监控逻辑 (保持不变)
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
        
        // 👇👇👇 系统进程黑名单 (保留你的逻辑) 👇👇👇
        let ignoredBundleIDs: Set<String> = [
            "com.apple.loginwindow",            // 登录窗口
            "com.apple.systemuiserver",         // 系统UI服务
            "com.apple.dock",                   // Dock
            "com.apple.controlcenter",          // 控制中心
            "com.apple.notificationcenterui",   // 通知中心
            "com.apple.WindowManager",          // 窗口管理
            "com.apple.screencaptureui"         // 截图工具
        ]
        
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
    
    // MARK: - ⏳ 番茄钟逻辑 (已增强)
    
    // ▶️ 开始计时
    func startTimer(context: ModelContext? = nil) {
        if let context = context { self.sharedContext = context }
        
        // 如果已经在运行，就不重复启动
        guard !isTimerRunning else { return }
        
        // 状态更新
        isTimerRunning = true
        isTimerPaused = false // ✨ 确保暂停状态被清除
        
        // 如果时间已耗尽，重置
        if timeRemaining <= 0 { resetTimer() }
        
        // 启动计时器
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    // 重新计算进度 (0.0 - 1.0)
                    if self.timerDuration > 0 {
                        self.timerProgress = self.timeRemaining / self.timerDuration
                    }
                } else {
                    self.stopTimer(finished: true)
                }
            }
        }
    }
    
    // ⏸️ 暂停 (新逻辑)
    func pauseTimer() {
        guard isTimerRunning else { return } // 只有在运行时才能暂停
        isTimerRunning = false
        isTimerPaused = true // ✨ 设置为暂停态
        
        timer?.invalidate()
        timer = nil
    }
    
    // ▶️ 继续 (供新 UI 调用)
    func resumeTimer() {
        guard isTimerPaused else { return }
        // 继续其实就是带着当前的 timeRemaining 重新 start
        startTimer()
    }
    
    // ⏹️ 停止/完成
    func stopTimer(finished: Bool, modelContext: ModelContext? = nil) {
        // 先彻底停掉计时器
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        isTimerPaused = false // ✨ 重置暂停态
        
        if finished {
            let ctx = modelContext ?? self.sharedContext
            if let context = ctx {
                let record = PomodoroRecord(duration: timerDuration)
                context.insert(record)
                try? context.save()
                print("番茄钟记录已保存: \(timerDuration)s")
            }
            sendNotification()
            resetTimer() // 完成后重置回初始状态
        } else {
            // 如果是放弃，仅仅重置 UI，不保存
            resetTimer()
        }
    }
    
    // 🔄 重置
    func resetTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        isTimerPaused = false
        timeRemaining = timerDuration
        timerProgress = 1.0
    }
    
    // ⚙️ 设置时长
    func setDuration(_ minutes: Double) {
        // 只有未开始时才允许设置
        guard !isTimerRunning else { return }
        timerDuration = minutes * 60
        resetTimer()
    }
    
    // 🏷️ 标签逻辑
    func updateLastUsedTags(_ tagString: String) {
        let tags = tagString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.lastUsedTags = tags
    }
    
    // 🔔 发送通知辅助方法
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "专注完成！"
        content.body = "休息一下吧，你真棒！🐱"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 🖼️ 图片扩展 (保持不变)
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
