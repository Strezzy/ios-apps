#if DEBUG && targetEnvironment(simulator)
import UIKit
import SwiftUI

// Simulator-only visual QA data. Never compiled into the iPhone release.
@MainActor
enum PreviewFixtures {
    static var enabled: Bool { CommandLine.arguments.contains { $0.hasPrefix("--preview-") } }
    static func photo() -> UIImage {
        let size = CGSize(width: 700,height: 980)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let ctx = renderer.cgContext
            let colors = [UIColor(red: 0.22,green: 0.31,blue: 0.46,alpha: 1).cgColor,UIColor(red: 0.57,green: 0.62,blue: 0.68,alpha: 1).cgColor,UIColor(red: 0.93,green: 0.66,blue: 0.49,alpha: 1).cgColor] as CFArray
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: colors,locations: [0,0.5,1])!
            ctx.drawLinearGradient(sky,start: .zero,end: CGPoint(x: 0,y: 980),options: [])
            ctx.setFillColor(UIColor(red: 1,green: 0.91,blue: 0.72,alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: 430,y: 235,width: 110,height: 110))
            for layer in 0..<4 {
                let path = UIBezierPath(); let base = CGFloat(420+layer*115)
                path.move(to: CGPoint(x: -10,y: 1000)); path.addLine(to: CGPoint(x: -10,y: base))
                for x in stride(from: 0,through: 710,by: 5) {
                    let y = base + CGFloat(sin(Double(x)/130+Double(layer)*1.2)*80+cos(Double(x)/61)*24)
                    path.addLine(to: CGPoint(x: CGFloat(x),y: y))
                }
                path.addLine(to: CGPoint(x: 710,y: 1000)); path.close()
                UIColor(red: 0.25-Double(layer)*0.055,green: 0.34-Double(layer)*0.06,blue: 0.43-Double(layer)*0.065,alpha: 1).setFill(); path.fill()
            }
            // Fine, deterministic film grain keeps the fixture visibly photographic.
            for n in 0..<14000 {
                let x = (n*137+29)%700, y = (n*313+17)%980
                ctx.setFillColor(UIColor.white.withAlphaComponent(n%2 == 0 ? 0.025 : 0.06).cgColor)
                ctx.fill(CGRect(x: CGFloat(x),y: CGFloat(y),width: 1,height: 1))
            }
        }
    }
    static func depth() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 350,height: 490)).image { renderer in
            let ctx = renderer.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: [UIColor(white: 0.08,alpha: 1).cgColor,UIColor(white: 0.95,alpha: 1).cgColor] as CFArray,locations: [0,1])!
            ctx.drawLinearGradient(gradient,start: .zero,end: CGPoint(x: 0,y: 490),options: [])
        }
    }
    static func markReady() {
        let token = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-") }) ?? "normal"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let path = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("preview-ready.txt")
            try? Data(token.utf8).write(to: path,options: .atomic)
        }
    }
    static func prepare(_ store: CollectionStore) {
        guard store.cards.isEmpty else { return }
        let image = photo(), bytes = image.jpegData(compressionQuality: 0.94)!, map = depth().pngData()!
        do {
            try store.saveDraft(DraftRecord(editionID: UUID(),title: "First light",rarity: .rare,count: 3,depthAmount: 0.6,palette: PhotoPipeline.palette(image),imageHash: CollectionStore.hash(bytes),depthHash: CollectionStore.hash(map),sourceIdentifier: "simulator-fixture",deletionConfirmed: false),photo: bytes,depth: map)
            try store.confirmDeletion(); _ = try store.finalizeDraft()
        } catch { assertionFailure(error.localizedDescription) }
    }
}
#endif
