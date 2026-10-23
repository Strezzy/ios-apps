import UIKit

/// Camera chrome keeps its portrait geometry. Physical capture orientation is
/// tracked independently by CameraController; viewing photos can still rotate.
@MainActor
final class VelvetAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        InterfaceOrientation.allowed
    }
}

@MainActor
enum InterfaceOrientation {
    private(set) static var allowed: UIInterfaceOrientationMask = .portrait

    static func update(cameraIsVisible: Bool) {
        let mask: UIInterfaceOrientationMask = cameraIsVisible ? .portrait : .allButUpsideDown
        allowed = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            guard scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive else { continue }
            UIView.performWithoutAnimation {
                for window in scene.windows where !window.isHidden {
                    updateControllers(window.rootViewController)
                }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
        }
    }

    private static func updateControllers(_ controller: UIViewController?) {
        guard let controller else { return }
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        for child in controller.children { updateControllers(child) }
        updateControllers(controller.presentedViewController)
    }
}
