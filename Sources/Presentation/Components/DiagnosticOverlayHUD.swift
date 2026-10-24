//
//  DiagnosticOverlayHUD.swift
//  LineriOS
//
//  Screen S11 Component: Floating draggable Windows-less diagnostic HUD.
//  Monitors real-time FPS (CADisplayLink), resident RAM (mach task_info), IPC socket state,
//  and live network transaction latency.
//

import SwiftUI
import Combine

public struct DiagnosticOverlayHUD: View {
    @State private var offset: CGSize = CGSize(width: 16, height: 120)
    @State private var isExpanded: Bool = false
    @State private var currentFPS: Double = 120.0
    @State private var ramUsageMB: Double = 0.0
    @State private var recentLogs: [LogEntry] = []

    @StateObject private var fpsTracker = FPSTracker()

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let theme = ThemePreset.obsidian

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Drag Header & Primary Metrics
            HStack(spacing: 12) {
                // Drag handle dot
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 8, height: 8)

                // Live FPS
                HStack(spacing: 4) {
                    Text("\(Int(fpsTracker.fps))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(fpsTracker.fps >= 115 ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))
                    Text("FPS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.gray)
                }

                // Resident RAM
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", ramUsageMB))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textPrimary)
                    Text("MB")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.gray)
                }

                Spacer()

                // IPC Status Pill
                ipcStatusBadge

                // Expand / Collapse Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        if isExpanded {
                            recentLogs = RingBufferLogger.shared.getRecentLogs()
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.8))
                }
            }

            // Expanded Transaction Log Viewer
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().background(Color.white.opacity(0.2))

                    HStack {
                        Text("RECENT TRANSACTIONS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.gray)
                        Spacer()
                        Button("Clear") {
                            RingBufferLogger.shared.clear()
                            recentLogs = []
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#38BDF8"))
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(recentLogs.prefix(15)) { log in
                                logRow(log)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
        )
        .frame(maxWidth: isExpanded ? 340 : 280)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = CGSize(
                        width: offset.width + gesture.translation.width,
                        height: offset.height + gesture.translation.height
                    )
                }
        )
        .onReceive(timer) { _ in
            ramUsageMB = getResidentMemoryMB()
            if isExpanded {
                recentLogs = RingBufferLogger.shared.getRecentLogs()
            }
        }
        .onAppear {
            fpsTracker.start()
            ramUsageMB = getResidentMemoryMB()
        }
    }

    private var ipcStatusBadge: some View {
        let state = PlayerStore.shared.connectionState
        let title: String
        let color: Color
        switch state {
        case .connectedLocalIPC:
            title = "IPC <15ms"
            color = Color(hex: "#10B981")
        case .connectedCloudWebAPI:
            title = "Cloud"
            color = Color(hex: "#38BDF8")
        case .connecting:
            title = "Linking..."
            color = Color(hex: "#F59E0B")
        case .rateLimited:
            title = "429 Wait"
            color = Color(hex: "#F43F5E")
        case .disconnected, .error:
            title = "Offline"
            color = Color.gray
        }

        return Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func logRow(_ log: LogEntry) -> some View {
        HStack(spacing: 6) {
            Text(log.formattedTimestamp)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Color.gray)

            Text("[\(log.category)]")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#38BDF8"))

            Text(log.message)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            if let latency = log.latencyMs {
                Text(String(format: "%.0fms", latency))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(latency < 25 ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))
            }
        }
    }

    // MARK: - Mach RAM Query
    private func getResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
}

// MARK: - 120Hz ProMotion Frame Rate Tracker
private final class FPSTracker: ObservableObject {
    @Published var fps: Double = 120.0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0.0
    private var frameCount: Int = 0

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(onFrame(link:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func onFrame(link: CADisplayLink) {
        if lastTimestamp == 0.0 {
            lastTimestamp = link.timestamp
            return
        }

        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp

        if elapsed >= 0.5 {
            let calculated = Double(frameCount) / elapsed
            self.fps = min(max(calculated, 0.0), 120.0)
            self.frameCount = 0
            self.lastTimestamp = link.timestamp
        }
    }

    deinit {
        stop()
    }
}
