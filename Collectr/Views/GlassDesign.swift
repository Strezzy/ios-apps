import SwiftUI

extension RGB { var color: Color { Color(red: r,green: g,blue: b) } }
extension Rarity {
    var color: Color { switch self { case .original: .white; case .rare: .cyan; case .epic: Color(red: 0.76,green: 0.61,blue: 1); case .legendary: Color(red: 1,green: 0.83,blue: 0.48) } }
}
struct AmbientBackground: View {
    var palette: [RGB]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.035,green: 0.04,blue: 0.055)
                ForEach(Array(palette.prefix(3).enumerated()),id: \.offset) { i,c in
                    Ellipse().fill(c.color.opacity(reduceTransparency ? 0.16 : 0.48))
                        .frame(width: geo.size.width*1.3,height: geo.size.height*0.75)
                        .blur(radius: 100)
                        .offset(x: i == 1 ? geo.size.width*0.4 : -geo.size.width*0.25,y: CGFloat(i-1)*geo.size.height*0.4)
                }
                LinearGradient(colors: [.black.opacity(0.05),.black.opacity(0.65)],startPoint: .top,endPoint: .bottom)
            }
        }.ignoresSafeArea().animation(.easeInOut(duration: 0.85),value: palette)
    }
}
struct EditionLabel: View {
    var rarity: Rarity
    var serial: Int
    var total: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rarity.symbol).foregroundStyle(rarity.color)
            Text(rarity.title.uppercased()).tracking(1.4).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(serial) OF \(total)").monospacedDigit().tracking(1.4).lineLimit(1).minimumScaleFactor(0.7)
        }.font(.system(size: 9,weight: .semibold,design: .monospaced)).foregroundStyle(.white.opacity(0.85))
    }
}
struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).glassEffect(.regular,in: .rect(cornerRadius: 24)) }
}
struct CardFace: View {
    var image: UIImage?
    var depth: UIImage? = nil
    var amount: Double = 0
    var tilt: SIMD2<Float> = .zero
    var rarity: Rarity = .original
    var serial = 1
    var total = 1
    var sleeved = true
    var live = false
    @State private var rendererFailed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = sleeved ? max(7,geo.size.width*0.026) : 0
            let radius = geo.size.width*0.026
            ZStack {
                if sleeved {
                    RoundedRectangle(cornerRadius: radius+inset).fill(.black.opacity(0.28)).offset(x: 3,y: 8).blur(radius: 4)
                    RoundedRectangle(cornerRadius: radius+inset).fill(LinearGradient(colors: [.white.opacity(0.42),.white.opacity(0.025),.white.opacity(0.12),.white.opacity(0.38)],startPoint: .topLeading,endPoint: .bottomTrailing)).offset(x: 2,y: 3)
                }
                ZStack(alignment: .bottom) {
                    if let image {
                        if live && !rendererFailed {
                            DepthPhoto(image: image,depth: depth,tilt: tilt,amount: amount,onFailure: { _ in rendererFailed = true })
                        } else { Image(uiImage: image).resizable().scaledToFill() }
                    } else { EmptyCardArt() }
                    LinearGradient(colors: [.clear,.black.opacity(0.65)],startPoint: .center,endPoint: .bottom)
                    EditionLabel(rarity: rarity,serial: serial,total: total).padding(.horizontal,12).padding(.bottom,13)
                }
                .frame(width: geo.size.width-inset*2,height: geo.size.height-inset*2)
                .clipShape(.rect(cornerRadius: radius))
                if sleeved {
                    RoundedRectangle(cornerRadius: radius+inset)
                        .fill(LinearGradient(stops: [.init(color: .white.opacity(0.02),location: 0),.init(color: .white.opacity(reduceTransparency ? 0.025 : 0.11),location: 0.34+Double(tilt.x)*0.08),.init(color: .clear,location: 0.48),.init(color: .white.opacity(0.025),location: 1)],startPoint: .topLeading,endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: radius+inset).strokeBorder(LinearGradient(colors: [.white.opacity(0.8),.white.opacity(0.12),.white.opacity(0.08),.white.opacity(0.5)],startPoint: .topLeading,endPoint: .bottomTrailing),lineWidth: 0.85)
                    RoundedRectangle(cornerRadius: radius+inset-3).strokeBorder(.white.opacity(0.15),lineWidth: 0.6).padding(3)
                    Capsule().fill(.white.opacity(0.5)).frame(width: geo.size.width*0.16,height: 1).offset(y: -geo.size.height/2+4)
                }
            }
        }.aspectRatio(5/7,contentMode: .fit).shadow(color: .black.opacity(0.4),radius: 22,x: 0,y: 18)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(rarity.title) collector card, \(serial) of \(total)\(amount > 0 ? ", with depth" : "")")
    }
}
struct EmptyCardArt: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.15,green: 0.2,blue: 0.28),Color(red: 0.07,green: 0.09,blue: 0.15)],startPoint: .topLeading,endPoint: .bottomTrailing)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.8),Color(red: 0.67,green: 0.76,blue: 0.83),Color(red: 0.22,green: 0.29,blue: 0.42)],center: .init(x: 0.3,y: 0.25),startRadius: 1,endRadius: geo.size.width*0.57))
                    .frame(width: geo.size.width*0.68,height: geo.size.width*0.68).shadow(color: .black.opacity(0.6),radius: 25,x: 14,y: 24).offset(y: -10)
                VStack { Text("COLLECTR").font(.system(size: 10,weight: .medium,design: .monospaced)).tracking(5).padding(.top,26); Spacer(); Text("A moment.\nMade rare.").font(.system(size: geo.size.width*0.11,weight: .light,design: .serif)).multilineTextAlignment(.center).padding(.bottom,50) }
            }
        }
    }
}
