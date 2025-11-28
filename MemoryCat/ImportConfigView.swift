import SwiftUI

struct ImportConfigView: View {
    @Environment(\.dismiss) var dismiss
    
    let fileName: String
    let items: [MemoryItemBackup]
    let onConfirm: (ImportStrategy) -> Void
    
    @State private var globalTags: String = ""
    @State private var mode: TagMode = .append
    
    enum TagMode: String, CaseIterable {
        case append = "追加 (保留原标签)"
        case override = "覆盖 (丢弃原标签)"
        case ignore = "忽略 (仅使用原标签)"
    }
    
    struct ImportStrategy {
        var tags: [String]
        var mode: TagMode
    }
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                // 图标换成 JSON 风格的括号
                Image(systemName: "curlybraces")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("导入 JSON 备份")
                    .font(.title2.bold())
                
                Text("从文件 \"\(fileName)\" 准备导入 \(items.count) 条记忆")
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            Form {
                Section("标签处理") {
                    TextField("额外标签 (逗号分隔，可选)", text: $globalTags)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("模式", selection: $mode) {
                        ForEach(TagMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .frame(height: 150)
            
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("开始导入") {
                    let tags = globalTags.split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    
                    onConfirm(ImportStrategy(tags: tags, mode: mode))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(30)
        .frame(width: 450)
    }
}
