# MemoryCat 🐱

> **A native macOS productivity assistant combining Focus Timer, Spaced Repetition Memory, and Screen Time Tracking.**
> *打造你的第二大脑：集番茄钟、记忆卡片与屏幕统计于一体的 macOS 原生应用。*

![Swift](https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-macOS_14.0+-lightgrey?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

## 📖 Introduction (简介)

**MemoryCat** 是一个专为 macOS 设计的生产力工具，旨在帮助用户提升专注力并高效管理知识。它不仅仅是一个番茄钟，更是一个基于**艾宾浩斯遗忘曲线**的记忆辅助工具，同时还能自动记录你的应用使用时长，让你对自己的时间去向了如指掌。

完全采用 **SwiftUI** + **SwiftData** 构建，拥有原生的 macOS 体验。

## ✨ Key Features (核心功能)
### 📌 Menu Bar Companion (状态栏助手)
- **Always Ready**：MemoryCat 常驻 macOS 顶部菜单栏，点击图标即可唤出迷你窗口，随时待命。
- **Mini Timer**：提供极简版的番茄钟界面，不占用桌面空间也能随时查看剩余时间、控制暂停/开始。
- **Quick Capture (闪念胶囊)**：突然有了灵感？无需打开主程序，在菜单栏窗口即可**快速录入**新的记忆卡片（支持文本/问答模式及标签），不错过任何稍纵即逝的想法。
- **Seamless Sync**：利用 SwiftData 共享容器，状态栏与主窗口数据完全实时互通，无缝切换工作流。
<img width="300" alt="截屏2025-11-22 08 40 31" src="https://github.com/user-attachments/assets/f949cedb-2d30-4f69-94f4-89d3fbcd7f6f" />


### 🍅 Focus Timer (专注番茄钟)
- **沉浸式体验**：支持主窗口和 **菜单栏 (Menu Bar)** 悬浮窗两种模式。
- **双端同步**：利用 `GlobalState` 实现主窗口与菜单栏状态实时同步，随时随地管理时间。
- **专注统计**：自动记录专注时长，生成热力图与趋势图。
<img width="400" alt="截屏2025-11-22 08 33 32" src="https://github.com/user-attachments/assets/bf2c94f9-546f-45d6-bc19-b2721b4b2391" />

### 🧠 Smart Memory (智能记忆库)
- **科学复习**：内置 **Spaced Repetition (间隔重复)** 算法，根据你的反馈（记得/忘记）自动计算下次复习时间。
- **多种题型**：支持 **纯文本** 和 **Q&A (翻转卡片)** 两种模式。
- **知识库管理**：支持标签 (Tag) 系统、搜索、排序，轻松管理成千上万条知识点。
<img width="400" alt="截屏2025-11-22 08 34 07" src="https://github.com/user-attachments/assets/5680747e-aa48-4572-919c-70d9b167ca66" />

### 📊 Screen Time (屏幕时间追踪)
- **自动记录**：后台静默监控当前活跃窗口 (`NSWorkspace`)，精准统计每个 App 的使用时长。
- **隐私安全**：所有数据仅存储在本地 SwiftData 数据库中，绝不上传。
- **可视化报表**：提供**按日**和**按周**的图表分析，支持饼图、折线图展示。
- **性能优化**：针对大量日志数据进行了缓存优化，支持一键清理历史记录。
<img width="400" alt="截屏2025-11-22 08 34 18" src="https://github.com/user-attachments/assets/86d9f554-edac-4101-8e1c-9a46dabdbff9" />

### ✅ Todo List (待办清单)
- **优先级管理**：支持高、中、低优先级标记。
- **截止日期**：支持设置 Due Date，即将到期的任务会高亮提醒。
- **智能排序**：可按重要性、时间或创建顺序动态排序。
<img width="400" alt="截屏2025-11-22 08 34 32" src="https://github.com/user-attachments/assets/4d6d211e-8029-441e-a097-bcb5d58abc96" />

## 🛠️ Tech Stack (技术栈)

- **UI Framework**: SwiftUI (macOS)
- **Database**: SwiftData (Schema: `MemoryItem`, `PomodoroRecord`, `AppUsageRecord` etc.)
- **Concurrency**: Swift Concurrency (Task, MainActor)
- **Charts**: Swift Charts (用于统计视图)
- **System Integration**:
  - `MenuBarExtra` (菜单栏驻留)
  - `UserNotifications` (通知推送)
  - `AppKit` / `NSWorkspace` (屏幕监控)

## 📂 Project Structure (项目结构)

```text
MemoryCat
├── App
│   ├── MemoryCatApp.swift    // 入口：配置 SwiftData Container
│   └── GlobalState.swift     // 核心状态管理：定时器、屏幕监控逻辑
├── Models (SwiftData)
│   ├── MemoryItem.swift      // 记忆条目 + 遗忘曲线算法
│   ├── TodoItem.swift        // 待办事项
│   ├── PomodoroRecord.swift  // 专注记录
│   ├── ReviewLog.swift       // 复习日志
│   └── AppUsageRecord.swift  // 屏幕时间记录
├── Views
│   ├── Sidebar              // 侧边栏与导航
│   ├── Focus                // 番茄钟视图 (PomodoroView, MiniTimerView)
│   ├── Memory               // 记忆库与复习卡片 (AllItemsListView, ReviewSessionView)
│   ├── Todo                 // 待办列表 (TodoListView)
│   └── Stats                // 数据统计 (StatsView, ScreenTimeView)
└── Resources
    └── Assets.xcassets
