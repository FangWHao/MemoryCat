// 📄 TodoItem.swift
import Foundation
import SwiftData
import SwiftUI

// MARK: - 📎 附件模型 (新增)
@Model
final class AttachmentItem {
    var id: UUID
    var fileName: String
    var fileType: String // 例如 "pdf", "png"
    var createdDate: Date
    
    // ✨ 关键：使用 externalStorage 让 SwiftData 把大文件存在磁盘，而不是塞爆数据库
    @Attribute(.externalStorage) var data: Data?
    
    init(fileName: String, data: Data?) {
        self.id = UUID()
        self.fileName = fileName
        self.fileType = (fileName as NSString).pathExtension.lowercased()
        self.data = data
        self.createdDate = Date()
    }
}

// MARK: - ✅ 待办事项模型 (修改)
@Model
final class TodoItem {
    var id: UUID
    var content: String
    var priorityRaw: Int
    var dueDate: Date?
    var isCompleted: Bool
    var createdDate: Date
    
    // ✨ 新增：一对多关联附件
    // deleteRule: .cascade 意思是删除任务时，附件也一起删掉
    @Relationship(deleteRule: .cascade) var attachments: [AttachmentItem] = []
    
    init(content: String, priority: TodoPriority = .medium, dueDate: Date? = nil) {
        self.id = UUID()
        self.content = content
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdDate = Date()
    }
    
    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}

// TodoPriority 枚举保持不变...
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
