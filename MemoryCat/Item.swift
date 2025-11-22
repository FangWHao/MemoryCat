import Foundation
import SwiftData

// 条目类型
enum ItemType: String, Codable {
    case textOnly
    case qa
}

// 1. 专注记录 (用于专注统计)
@Model
final class PomodoroRecord {
    var id: UUID
    var date: Date
    var duration: Double
    
    init(duration: Double) {
        self.id = UUID()
        self.date = Date()
        self.duration = duration
    }
}

// 2. 复习日志 (新增！用于统计复习量和遗忘率)
@Model
final class ReviewLog {
    var date: Date
    var itemId: UUID
    var remembered: Bool // true = 记得, false = 忘了
    
    init(itemId: UUID, remembered: Bool) {
        self.date = Date()
        self.itemId = itemId
        self.remembered = remembered
    }
}

// 3. 记忆条目
@Model
final class MemoryItem {
    var id: UUID
    var type: ItemType
    var content: String
    var answer: String
    var createdDate: Date
    var tags: [String] = []
    
    // --- 遗忘曲线核心数据 ---
    var nextReviewDate: Date
    var interval: Int
    var repetition: Int
    var easeFactor: Double

    init(type: ItemType, content: String, answer: String = "", tags: [String] = []) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.answer = answer
        self.tags = tags
        self.createdDate = Date()
        
        // 初始状态
        self.nextReviewDate = Date()
        self.interval = 0
        self.repetition = 0
        self.easeFactor = 2.5
    }
    
    // 核心算法更新：传入 Context 以便保存日志
    func processReview(remembered: Bool, context: ModelContext) {
        // 1. 记录日志
        let log = ReviewLog(itemId: self.id, remembered: remembered)
        context.insert(log)
        
        // 2. 调整算法
        if !remembered {
            repetition = 0
            interval = 1
        } else {
            repetition += 1
            if repetition == 1 { interval = 1 }
            else if repetition == 2 { interval = 6 }
            else { interval = Int(ceil(Double(interval) * easeFactor)) }
        }
        nextReviewDate = Date().addingTimeInterval(TimeInterval(interval * 86400))
    }
}
