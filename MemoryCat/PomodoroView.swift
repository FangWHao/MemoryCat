import SwiftUI
import SwiftData

struct PomodoroView: View {
    @EnvironmentObject var globalState: GlobalState
    @Environment(\.modelContext) var modelContext
    @Query(sort: \PomodoroRecord.date) var records: [PomodoroRecord]
    
    // 交互状态
    @State private var dragAngle: Double = (25.0 / 120.0) * 360.0
    @State private var inputMinutes: Int = 25
    @State private var showStopAlert = false
    
    // 视觉状态
    @State private var breathingScale: CGFloat = 1.0
    
    // 常量配置
    private let maxDragDuration: Double = 120
    private let circleSize: CGFloat = 340
    
    // 计算属性
    var todayMinutes: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todayRecords = records.filter { $0.date >= startOfToday }
        return Int(todayRecords.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var progress: Double {
        // ✨ 修复逻辑：只要还在专注会话中（无论是跑着还是暂停），都算 active
        if isSessionActive {
            return globalState.timerProgress
        } else {
            return min(Double(inputMinutes) / maxDragDuration, 1.0)
        }
    }
    
    // ✨ 核心修复：定义什么叫“专注会话中”
    // 只要是 Running 或者 Paused，都算是在干活，不能切回开始界面！
    var isSessionActive: Bool {
        return globalState.isTimerRunning || globalState.isTimerPaused
    }
    
    var body: some View {
        ZStack {
            // 背景氛围光
            if isSessionActive {
                AmbientBackground()
                    .transition(.opacity.animation(.easeInOut(duration: 1.0)))
            }
            
            VStack(spacing: 40) {
                // 1. 核心时钟区域
                ZStack {
                    // 外层刻度圈
                    Circle()
                        .stroke(Color.primary.opacity(0.05), style: StrokeStyle(lineWidth: 20, lineCap: .butt, dash: [2, 10]))
                        .frame(width: circleSize + 50)
                    
                    // 背景轨道
                    Circle()
                        .stroke(Color.gray.opacity(0.1), lineWidth: 24)
                        .frame(width: circleSize)
                    
                    // ✨ 动态进度条 (视觉 Bug 修复版)
                    // 不再动态改变渐变的角度，而是用 trim 来遮罩一个完整的渐变圆
                    Circle()
                        .trim(from: 0, to: max(progress, 0.001))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple, .pink, .cyan]), // 首尾颜色一致闭环
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 24, lineCap: .round)
                        )
                        .frame(width: circleSize)
                        .rotationEffect(.degrees(-90)) // 从 12 点方向开始
                        .shadow(color: .blue.opacity(isSessionActive ? 0.3 : 0.1), radius: 10)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                    
                    // ✨ 交互旋钮
                    // 只有在“非”专注状态下才显示旋钮
                    if !isSessionActive {
                        KnobView(angle: $dragAngle, circleSize: circleSize) {
                            let mins = max(1, Int((dragAngle / 360.0) * maxDragDuration))
                            self.inputMinutes = mins
                            globalState.setDuration(Double(mins))
                        }
                        .opacity(inputMinutes > Int(maxDragDuration) ? 0 : 1)
                    }
                    
                    // ✨ 中间数字
                    VStack(spacing: 4) {
                        if isSessionActive {
                            // 倒计时模式
                            Text(formatTime(globalState.timeRemaining))
                                .font(.system(size: 64, weight: .thin, design: .monospaced))
                                .contentTransition(.numericText())
                                .foregroundStyle(.primary)
                                .shadow(color: .white.opacity(0.5), radius: 10)
                        } else {
                            // 设定模式 (可输入)
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                TextField("25", value: $inputMinutes, format: .number)
                                    .font(.system(size: 64, weight: .thin, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.plain)
                                    .frame(width: 140)
                                    .foregroundStyle(.primary)
                                    .onSubmit { syncInputToState() }
                                    .onChange(of: inputMinutes) { _, _ in syncInputToState() }
                                
                                Text("min")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .offset(x: -10)
                            }
                        }
                        
                        // 状态文字
                        if isSessionActive {
                            Text(globalState.isTimerPaused ? "PAUSED" : "FOCUSING") // 显示暂停状态
                                .font(.caption.bold())
                                .tracking(4)
                                .foregroundStyle(globalState.isTimerPaused ? .yellow : .secondary)
                                .opacity(0.8)
                                .padding(4)
                                .background(globalState.isTimerPaused ? Color.yellow.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                        } else {
                            Text("DRAG OR TYPE")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                }
                .scaleEffect(globalState.isTimerRunning ? breathingScale : 1.0)
                
                // 2. 底部控制台 (逻辑修复版)
                HStack(spacing: 0) {
                    // 只要在会话中（运行 OR 暂停），都显示控制条
                    if isSessionActive {
                        ControlCapsuleButton(icon: globalState.isTimerPaused ? "play.fill" : "pause.fill", color: .orange) {
                            if globalState.isTimerPaused {
                                globalState.resumeTimer()
                            } else {
                                globalState.pauseTimer()
                            }
                        }
                        
                        Divider().frame(height: 20).padding(.horizontal, 10)
                        
                        ControlCapsuleButton(icon: "xmark", color: .red) {
                            showStopAlert = true
                        }
                    } else {
                        // 未开始状态
                        Button {
                            startFocus()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("开始专注")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                .animation(.spring(), value: isSessionActive) // 动画绑定到新变量
                
                if !isSessionActive {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("今日能量: \(todayMinutes) min")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, -10)
                }
            }
        }
        .onAppear {
            let currentMins = Int(globalState.timerDuration / 60)
            self.inputMinutes = currentMins
            let ratio = min(Double(currentMins) / maxDragDuration, 1.0)
            self.dragAngle = ratio * 360.0
            startBreathingAnimation()
        }
        .onChange(of: globalState.isTimerRunning) { _, isRunning in
            if isRunning { startBreathingAnimation() }
        }
        .alert("放弃本次专注？", isPresented: $showStopAlert) {
            Button("继续", role: .cancel) { }
            Button("放弃", role: .destructive) {
                withAnimation { globalState.stopTimer(finished: false) }
            }
        } message: { Text("放弃的话，刚才的努力就不会被记录咯😿") }
    }
    
    // 逻辑函数保持不变...
    func syncInputToState() {
        globalState.setDuration(Double(inputMinutes))
        let ratio = Double(inputMinutes) / maxDragDuration
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragAngle = min(ratio, 1.0) * 360.0
        }
    }
    
    func startFocus() {
        globalState.setDuration(Double(inputMinutes))
        withAnimation(.spring()) {
            globalState.startTimer(context: modelContext)
        }
    }
    
    func startBreathingAnimation() {
        if globalState.isTimerRunning {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathingScale = 1.03
            }
        } else {
            withAnimation { breathingScale = 1.0 }
        }
    }
    
    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// KnobView 保持之前的修复版
struct KnobView: View {
    @Binding var angle: Double
    let circleSize: CGFloat
    let onDragChange: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = circleSize / 2
            let x = center.x + radius * cos(Angle(degrees: angle - 90).radians)
            let y = center.y + radius * sin(Angle(degrees: angle - 90).radians)
            
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                    .overlay(Circle().stroke(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                    .scaleEffect(isHovering ? 1.3 : 1.0)
                    .position(x: x, y: y)
            }
            .gesture(
                DragGesture().onChanged { value in
                    calculateAngle(center: center, location: value.location)
                    onDragChange()
                }
            )
            .onHover { isHovering = $0 }
        }
        .frame(width: circleSize + 40, height: circleSize + 40)
    }
    
    private func calculateAngle(center: CGPoint, location: CGPoint) {
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        var radians = atan2(vector.dy, vector.dx)
        let degrees = radians * 180 / .pi + 90
        let positiveDegrees = degrees >= 0 ? degrees : degrees + 360
        
        if positiveDegrees < 5 { self.angle = 0 }
        else if positiveDegrees > 355 { self.angle = 360 }
        else { self.angle = positiveDegrees }
    }
}

// 辅助组件：背景氛围和按钮
struct AmbientBackground: View {
    @State private var rotate = false
    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.1)).frame(width: 600, height: 600).blur(radius: 100).offset(x: -150, y: -150)
            Circle().fill(Color.purple.opacity(0.1)).frame(width: 500, height: 500).blur(radius: 100).offset(x: 150, y: 150)
        }
        .rotationEffect(.degrees(rotate ? 360 : 0))
        .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotate)
        .onAppear { rotate = true }
    }
}

struct ControlCapsuleButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(isHovering ? 0.15 : 0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.spring(), value: isHovering)
    }
}
