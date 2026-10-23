import SwiftUI
import UIKit

/// Synchronous UIKit cover for snapshots; independent of SwiftUI's next render pass.
struct SystemPrivacyShield: UIViewRepresentable {
    func makeUIView(context: Context) -> SnapshotShieldView { SnapshotShieldView() }
    func updateUIView(_ uiView: SnapshotShieldView, context: Context) {}
}

final class SnapshotShieldView: UIView {
    private var cover: UIView?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(conceal), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(conceal), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(conceal), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(captureChanged), name: UIScreen.capturedDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cover?.removeFromSuperview(); cover = nil }
        else if UIApplication.shared.applicationState != .active || UIScreen.main.isCaptured { conceal() }
    }
    @objc private func conceal() {
        guard let window else { return }
        if let cover { window.bringSubviewToFront(cover); return }
        let shield = UIView(frame: window.bounds)
        shield.backgroundColor = .black
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shield.isAccessibilityElement = true
        shield.accessibilityLabel = "Velvet. Private content concealed."
        let label = UILabel()
        label.text = "Velvet"
        label.textColor = UIColor(white: 0.85, alpha: 1)
        label.font = .systemFont(ofSize: 30, weight: .light)
        label.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: shield.centerXAnchor), label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)])
        window.addSubview(shield)
        shield.layoutIfNeeded()
        cover = shield
    }
    @objc private func active() {
        guard !UIScreen.main.isCaptured else { conceal(); return }
        cover?.removeFromSuperview(); cover = nil
    }
    @objc private func captureChanged() { if UIScreen.main.isCaptured { conceal() } else if UIApplication.shared.applicationState == .active { active() } }
}
