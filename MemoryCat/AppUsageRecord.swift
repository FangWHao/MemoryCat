// 📄 AppUsageRecord.swift
import Foundation
import SwiftData

@Model
final class AppUsageRecord {
    var id: UUID
    var bundleID: String    // App 的唯一标识
    var appName: String     // App 名字
    var date: Date          // 记录日期
    var duration: Double    // 时长 (秒)
    
    // 👇 这里只能有一行定义！请确保只有这一行，不要保留旧的 "var icon: Data?"
    @Attribute(.externalStorage) var icon: Data?
    
    init(bundleID: String, appName: String, date: Date, duration: Double = 0, icon: Data? = nil) {
        self.id = UUID()
        self.bundleID = bundleID
        self.appName = appName
        self.date = date
        self.duration = duration
        self.icon = icon
    }
}
