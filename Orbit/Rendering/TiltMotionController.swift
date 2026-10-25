import Combine
import CoreMotion
import QuartzCore
import UIKit
import simd

/// The Metal display loop reads motion directly, avoiding sixty SwiftUI updates per second.
@MainActor
final class TiltMotionController: ObservableObject {
    @Published private(set) var available: Bool
    private let manager = CMMotionManager()
    private var reference: CMAttitude?
    private var filtered = SIMD2<Double>.zero
    private var manual = SIMD2<Double>.zero
    private var manualReleasedAt: CFTimeInterval?
    private var lastTimestamp: TimeInterval = 0
    private var lastOrientation: UIInterfaceOrientation = .unknown

    init() {
        available = manager.isDeviceMotionAvailable
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        guard available, !manager.isDeviceMotionActive else { return }
        reference = nil
        lastTimestamp = 0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard let motion else {
                if error != nil { self.available = false; self.manager.stopDeviceMotionUpdates() }
                return
            }
            if self.reference == nil {
                self.reference = motion.attitude.copy() as? CMAttitude
                self.filtered = .zero
            }
            guard let reference = self.reference,
                  let relative = motion.attitude.copy() as? CMAttitude else { return }
            relative.multiply(byInverseOf: reference)
            let matrix = relative.rotationMatrix
            let limit = 0.30 // About seventeen degrees to either side of the neutral position.
            let raw = OrbitGeometry.boundedTilt(SIMD2(atan2(matrix.m13, matrix.m33) / limit,
                                                       -atan2(matrix.m23, matrix.m33) / limit))
            let dt = self.lastTimestamp > 0 ? min(0.1, max(0, motion.timestamp - self.lastTimestamp)) : 1.0 / 60
            self.lastTimestamp = motion.timestamp
            let alpha = 1 - exp(-dt / 0.055)
            self.filtered += (raw - self.filtered) * alpha
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        filtered = .zero
        lastTimestamp = 0
    }

    func recenter() {
        reference = manager.deviceMotion?.attitude.copy() as? CMAttitude
        filtered = .zero
        manual = .zero
        manualReleasedAt = nil
    }

    func setManualOffset(_ offset: CGSize) {
        manual = OrbitGeometry.boundedTilt(SIMD2(Double(offset.width), Double(offset.height)))
        manualReleasedAt = nil
    }

    func clearManualOffset() { manualReleasedAt = CACurrentMediaTime() }

    func sample(orientation: UIInterfaceOrientation, includeDeviceMotion: Bool = true) -> SIMD2<Float> {
        if orientation != lastOrientation && orientation != .unknown {
            lastOrientation = orientation
            recenter()
        }
        var touch = manual
        if let released = manualReleasedAt {
            let decay = exp(-(CACurrentMediaTime() - released) / 0.18)
            touch *= decay
            if decay < 0.002 { manual = .zero; manualReleasedAt = nil }
        }
        let deviceTilt = includeDeviceMotion ? OrbitGeometry.screenTilt(filtered, orientation: orientation) : .zero
        let value = OrbitGeometry.boundedTilt(deviceTilt + touch)
        return SIMD2(Float(value.x), Float(value.y))
    }
}
