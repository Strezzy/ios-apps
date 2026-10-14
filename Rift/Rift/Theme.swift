import SwiftUI
import UIKit

enum RiftTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.43, blue: 0.48, alpha: 1)
            : UIColor(red: 0.73, green: 0.08, blue: 0.20, alpha: 1)
    })
    static let rose=Color(red:1,green:0.43,blue:0.48)
    static let wine=Color(red:0.30,green:0.035,blue:0.095)
}
struct RiftBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors:scheme == .dark ? [Color(red:0.07,green:0.035,blue:0.05),Color(red:0.13,green:0.035,blue:0.065),Color(red:0.23,green:0.045,blue:0.09)] : [Color(red:1,green:0.975,blue:0.975),Color(red:0.985,green:0.92,blue:0.935),Color(red:0.97,green:0.82,blue:0.85)],startPoint:.topLeading,endPoint:.bottomTrailing)
            .overlay(alignment:.topTrailing) { Circle().fill(RiftTheme.rose.opacity(scheme == .dark ? 0.09 : 0.15)).frame(width:280,height:280).blur(radius:65).offset(x:120,y:-120) }
            .ignoresSafeArea(.container)
    }
}
struct RiftWing: Shape {
    func path(in r: CGRect) -> Path {
        var p=Path()
        p.move(to:CGPoint(x:r.width*0.82,y:r.height*0.03))
        p.addCurve(to:CGPoint(x:r.width*0.13,y:r.height*0.62),control1:CGPoint(x:r.width*0.16,y:r.height*0.22),control2:CGPoint(x:r.width*0.1,y:r.height*0.35))
        p.addCurve(to:CGPoint(x:r.width*0.80,y:r.height*0.97),control1:CGPoint(x:r.width*0.15,y:r.height*0.80),control2:CGPoint(x:r.width*0.72,y:r.height*0.79))
        p.addCurve(to:CGPoint(x:r.width*0.69,y:r.height*0.55),control1:CGPoint(x:r.width*0.81,y:r.height*0.69),control2:CGPoint(x:r.width*0.49,y:r.height*0.57))
        p.addCurve(to:CGPoint(x:r.width*0.82,y:r.height*0.03),control1:CGPoint(x:r.width*0.84,y:r.height*0.45),control2:CGPoint(x:r.width*0.82,y:r.height*0.25))
        p.closeSubpath(); return p
    }
}
struct RiftMark: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HStack(spacing:0) {
                    RiftWing().fill(LinearGradient(colors:[RiftTheme.rose,RiftTheme.accent,RiftTheme.wine],startPoint:.topLeading,endPoint:.bottomTrailing))
                    RiftWing().fill(LinearGradient(colors:[RiftTheme.rose,RiftTheme.accent,RiftTheme.wine],startPoint:.topTrailing,endPoint:.bottomLeading)).scaleEffect(x:-1,y:1)
                }
                Image(systemName:"sparkle").resizable().scaledToFit().frame(width:proxy.size.width*0.16).foregroundStyle(RiftTheme.rose)
            }.shadow(color:RiftTheme.accent.opacity(0.2),radius:16)
        }.accessibilityHidden(true)
    }
}
struct BenefitBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.caption2,design:.rounded,weight:.semibold)).foregroundStyle(RiftTheme.accent)
            .padding(.horizontal,8).padding(.vertical,5)
            .background(RiftTheme.accent.opacity(0.09),in:Capsule())
            .overlay { Capsule().strokeBorder(RiftTheme.accent.opacity(0.13),lineWidth:0.5) }
            .fixedSize(horizontal:false,vertical:true).accessibilityLabel("Model benefit: \(text)")
    }
}
struct ErrorBanner: View {
    @EnvironmentObject var model: AppModel
    @State private var details = false
    var body: some View {
        if let error = model.error {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(RiftTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(error).font(.caption).lineLimit(2)
                    Button("Details") { details = true }.font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { model.dismissError() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .accessibilityLabel("Dismiss error")
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 12).padding(.top, 6)
                .alert("Rift", isPresented: $details) { Button("OK", role: .cancel) {} } message: { Text(error) }
        }
    }
}
