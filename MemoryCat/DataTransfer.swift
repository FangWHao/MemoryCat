// 📄 DataTransfer.swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 1. 定义一个用于备份的纯结构体 (DTO)
// 它可以直接自动转成 JSON，不需要我们要死要活地去拼字符串
struct MemoryItemBackup: Codable, Identifiable {
    var id: UUID = UUID()
    let type: ItemType
    let content: String
    let answer: String
    let tags: [String]
    let createdDate: Date
    
    // 复习进度数据
    let nextReviewDate: Date
    let repetition: Int
    let interval: Int
    let easeFactor: Double
    
    // 👇 这是一个“初始化器”，负责把数据库里的 MemoryItem 变成这个备份小盒子
    init(from item: MemoryItem) {
        self.type = item.type
        self.content = item.content
        self.answer = item.answer
        self.tags = item.tags
        self.createdDate = item.createdDate
        self.nextReviewDate = item.nextReviewDate
        self.repetition = item.repetition
        self.interval = item.interval
        self.easeFactor = item.easeFactor
    }
}

// 2. 定义 JSON 文档格式 (用于导出/导入)
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var items: [MemoryItemBackup] = []
    
    init(items: [MemoryItemBackup] = []) {
        self.items = items
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // 自动把 JSON Data 变成对象数组，超方便！
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // 标准日期格式
        self.items = try decoder.decode([MemoryItemBackup].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // 生成漂亮的格式化 JSON
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        return FileWrapper(regularFileWithContents: data)
    }
}
