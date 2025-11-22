// 📄 MemoryCatApp.swift
// ⚠️ 请完全替换这个文件，这是修复数据丢失的关键！

import SwiftUI
import SwiftData

@main
struct MemoryCatApp: App {
    @StateObject private var globalState = GlobalState()
    
    // 👇 1. 创建一个共享的数据库容器 (这就好比家里唯一的账本)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MemoryItem.self,
            PomodoroRecord.self,
            ReviewLog.self, // 👈 重点：必须包含 ReviewLog，否则重启后“已做”数据会丢！
            TodoItem.self,
            AppUsageRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        // 2. 主窗口
        WindowGroup {
            ContentView()
                .environmentObject(globalState)
        }
        // 👇 使用同一个容器
        .modelContainer(sharedModelContainer)
        
        // 3. 悬浮任务栏窗口
        MenuBarExtra {
            MiniTimerView()
                .environmentObject(globalState)
                // 👇 必须也用同一个容器，否则数据不互通！
                .modelContainer(sharedModelContainer)
        } label: {
            let imageName = globalState.isTimerRunning ? "timer.circle.fill" : "timer"
            Image(systemName: imageName)
        }
        .menuBarExtraStyle(.window)
    }
}
