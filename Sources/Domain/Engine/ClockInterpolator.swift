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

    public func updateAnchor(
        positionMs: Int,
        monotonicTime: CFTimeInterval,
        isPlaying: Bool,
        playbackSpeed: Double = 1.0
    ) {
        self.playbackRate = isPlaying ? playbackSpeed : 0.0

        if !isPlaying {
            // Paused: anchor directly locks to current static position
            self.anchorPositionMs = Double(positionMs)
            self.anchorMonotonicTime = monotonicTime
            self.targetPositionMs = nil
            self.slewingFramesRemaining = 0
            self.interpolatedTimeMs = positionMs + Int(userOffsetMs)
            onTick?(self.interpolatedTimeMs)
            stop()
            return
        }

        // Calculate expected local interpolated position right now
        let currentLocalMs = calculateRawPosition(at: monotonicTime)
        let drift = Double(positionMs) - currentLocalMs

        if abs(drift) > 150.0 {
            // Drift exceeds 150ms threshold: initiate 10-frame slewing filter
            self.targetPositionMs = Double(positionMs)
            self.slewingFramesRemaining = 10
            self.slewingStepMs = drift / 10.0
        } else {
            // Small jitter: soft-anchor update without visual jump
            self.anchorPositionMs = Double(positionMs)
            self.anchorMonotonicTime = monotonicTime
            self.targetPositionMs = nil
            self.slewingFramesRemaining = 0
        }

        start()
    }

    public func setUserOffset(ms: Int) {
        self.userOffsetMs = Double(ms)
    }

    // MARK: - CADisplayLink Render Loop (120Hz)

    public func start() {
        guard !isRunning else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
        // Target 120Hz ProMotion on iPhone 14 Pro
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60.0,
            maximum: 120.0,
            preferred: 120.0
        )
        link.add(to: .main, forMode: .common)
        self.displayLink = link
        self.isRunning = true
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    @objc private func handleDisplayLinkTick(_ link: CADisplayLink) {
        let currentTime = CACurrentMediaTime()
        var rawTime = calculateRawPosition(at: currentTime)

        // Apply slewing if mid-correction
        if slewingFramesRemaining > 0, let target = targetPositionMs {
            rawTime += slewingStepMs * Double(slewingFramesRemaining)
            slewingFramesRemaining -= 1
            if slewingFramesRemaining == 0 {
                self.anchorPositionMs = target
                self.anchorMonotonicTime = currentTime
                self.targetPositionMs = nil
            }
        }

        let finalTimeMs = max(0, Int(rawTime + userOffsetMs))
        self.interpolatedTimeMs = finalTimeMs
        onTick?(finalTimeMs)
    }

    // MARK: - Mathematical Formula

    private func calculateRawPosition(at time: CFTimeInterval) -> Double {
        let elapsedSeconds = time - anchorMonotonicTime
        let elapsedMs = elapsedSeconds * 1000.0 * playbackRate
        return anchorPositionMs + elapsedMs
    }

    // MARK: - Thermal & Background Throttling

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let link = self.displayLink else { return }
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                // Throttle to 60Hz under thermal distress to conserve battery
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 30.0,
                    maximum: 60.0,
                    preferred: 60.0
                )
            } else {
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 60.0,
                    maximum: 120.0,
                    preferred: 120.0
                )
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
        displayLink?.invalidate()
    }
}
