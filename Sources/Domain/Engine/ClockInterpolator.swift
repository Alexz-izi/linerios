//
//  ClockInterpolator.swift
//  LineriOS
//
//  120Hz ProMotion monotonic clock interpolation engine driven by CADisplayLink.
//  Implements t_now = P_anchor + ((CACurrentMediaTime() - T_anchor) * 1000 * R) + Delta_user
//  with 10-frame slewing for resync drifts > 150ms.
//

import Foundation
import QuartzCore
import UIKit

@MainActor
public final class ClockInterpolator: ObservableObject {
    public static let shared = ClockInterpolator()

    // MARK: - Core Mathematical Anchor State
    private var anchorPositionMs: Double = 0.0
    private var anchorMonotonicTime: CFTimeInterval = 0.0
    private var playbackRate: Double = 0.0 // 1.0 when playing, 0.0 when paused
    private var userOffsetMs: Double = 0.0

    // MARK: - Slewing Smoothing State
    private var targetPositionMs: Double?
    private var slewingFramesRemaining: Int = 0
    private var slewingStepMs: Double = 0.0

    // MARK: - Output State & Observers
    @Published public private(set) var interpolatedTimeMs: Int = 0
    public var onTick: ((Int) -> Void)?

    private var displayLink: CADisplayLink?
    private var isRunning: Bool = false

    public init() {
        setupLifecycleObservers()
    }

    // MARK: - Anchor Update Flow

    public func setAnchor(
        positionMs: Int,
        monotonicTime: CFTimeInterval,
        isPlaying: Bool,
        userOffsetMs: Int = 0
    ) {
        let newRate = isPlaying ? 1.0 : 0.0
        self.userOffsetMs = Double(userOffsetMs)

        // Calculate expected time based on previous anchor to detect drift
        if isRunning && anchorMonotonicTime > 0.0 && playbackRate > 0.0 {
            let expectedCurrent = anchorPositionMs + ((monotonicTime - anchorMonotonicTime) * 1000.0 * playbackRate)
            let drift = Double(positionMs) - expectedCurrent

            if abs(drift) > 150.0 {
                // Large drift detected: Initiate 10-frame progressive slewing (~83ms at 120Hz)
                self.targetPositionMs = Double(positionMs)
                self.slewingFramesRemaining = 10
                self.slewingStepMs = drift / 10.0
                RingBufferLogger.shared.log(
                    level: .debug,
                    category: "Clock",
                    message: "Drift \(Int(drift))ms > 150ms. Slewing over 10 frames."
                )
            } else {
                // Negligible drift: snap cleanly without visual jitter
                self.anchorPositionMs = Double(positionMs)
                self.anchorMonotonicTime = monotonicTime
            }
        } else {
            self.anchorPositionMs = Double(positionMs)
            self.anchorMonotonicTime = monotonicTime
        }

        self.playbackRate = newRate

        if isPlaying {
            start()
        } else {
            // Freeze clock at exact anchor position
            interpolatedTimeMs = max(0, Int(anchorPositionMs + self.userOffsetMs))
            onTick?(interpolatedTimeMs)
        }
    }

    public func setUserOffset(ms: Int) {
        self.userOffsetMs = Double(ms)
    }

    // MARK: - DisplayLink Engine

    public func start() {
        guard !isRunning else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(link:)))
        if #available(iOS 15.0, *) {
            // Unlock 120Hz ProMotion refresh rate for iPhone 14 Pro
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
        self.isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    @objc private func handleFrame(link: CADisplayLink) {
        let now = CACurrentMediaTime()

        var calculatedPosition: Double
        if playbackRate > 0.0 {
            calculatedPosition = anchorPositionMs + ((now - anchorMonotonicTime) * 1000.0 * playbackRate)
        } else {
            calculatedPosition = anchorPositionMs
        }

        // Apply progressive slewing if active
        if slewingFramesRemaining > 0, let target = targetPositionMs {
            let offsetApplied = slewingStepMs * Double(10 - slewingFramesRemaining + 1)
            calculatedPosition += offsetApplied
            slewingFramesRemaining -= 1
            if slewingFramesRemaining == 0 {
                self.anchorPositionMs = target
                self.anchorMonotonicTime = now
                self.targetPositionMs = nil
            }
        }

        let finalMs = max(0, Int(calculatedPosition + userOffsetMs))
        self.interpolatedTimeMs = finalMs
        self.onTick?(finalMs)
    }

    // MARK: - Thermal & Background Throttling

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // When user locks phone, freeze display link immediately (0% GPU/CPU draw)
            self?.stop()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.playbackRate > 0.0 {
                self.anchorMonotonicTime = CACurrentMediaTime()
                self.start()
            }
        }
    }

    deinit {
        stop()
    }
}
