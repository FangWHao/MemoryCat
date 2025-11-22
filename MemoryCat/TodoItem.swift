// 📄 TodoItem.swift
import Foundation
import SwiftData
import SwiftUI

enum TodoPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .low: return "不急"
        case .medium: return "一般"
        case .high: return "重要"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "cup.and.saucer"
        case .medium: return "exclamationmark.circle"
        case .high: return "flame.fill"
        }
    }
}

@Model
final class TodoItem {
    var id: UUID
    var content: String
    var priorityRaw: Int // 存储 Enum 的原始值
    var dueDate: Date?   // 可选的截止时间
    var isCompleted: Bool
    var createdDate: Date
    
    init(content: String, priority: TodoPriority = .medium, dueDate: Date? = nil) {
        self.id = UUID()
        self.content = content
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdDate = Date()
    }
    
    // 方便使用的计算属性
    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}
