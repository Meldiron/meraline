import SwiftUI

/// The sparkle at the start of the input row, pulsing while an answer streams. In anonymous mode it goes
/// dark: the mascot's own sparkle from the app icon, whose fuller middle has room for a face, in graphite
/// with sunglasses cut out of it, like an incognito silhouette. Graphite follows the appearance, dark on
/// light glass and silver on dark, and the glass behind shows through the lenses.
struct SparkleIcon: View {
    let isStreaming: Bool
    let isAnonymous: Bool

    private static let graphite = LinearGradient(
        colors: [.primary.opacity(0.85), .primary.opacity(0.65)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            if isAnonymous {
                MascotInSunglasses()
                    .fill(Self.graphite)
                    .frame(width: 20.5, height: 20.9)
                    .modifier(Pulse(isActive: isStreaming))
                    .transition(.blurReplace)
            } else {
                Image(systemName: "sparkle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.meraline)
                    .symbolEffect(.pulse, isActive: isStreaming)
                    .transition(.blurReplace)
            }
        }
        .animation(.snappy(duration: 0.3), value: isAnonymous)
    }
}

/// The sparkle of `AppIcon.icon/Assets/sparkle.svg`, fitted to the frame, with sunglasses cut out where the
/// icon's eyes are. The SVG's sparkle spans x 140…884 and y 140…900 of its 1024-point canvas.
private nonisolated struct MascotInSunglasses: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 140) / 744 * rect.width, y: rect.minY + (y - 140) / 760 * rect.height)
        }
        var sparkle = Path()
        sparkle.move(to: point(512, 140))
        sparkle.addCurve(to: point(628, 424), control1: point(546, 140), control2: point(560, 360))
        sparkle.addCurve(to: point(884, 520), control1: point(694, 488), control2: point(884, 486))
        sparkle.addCurve(to: point(628, 616), control1: point(884, 554), control2: point(694, 552))
        sparkle.addCurve(to: point(512, 900), control1: point(560, 680), control2: point(546, 900))
        sparkle.addCurve(to: point(396, 616), control1: point(478, 900), control2: point(464, 680))
        sparkle.addCurve(to: point(140, 520), control1: point(330, 552), control2: point(140, 554))
        sparkle.addCurve(to: point(396, 424), control1: point(140, 486), control2: point(330, 488))
        sparkle.addCurve(to: point(512, 140), control1: point(464, 360), control2: point(478, 140))
        sparkle.closeSubpath()

        let size = CGSize(width: rect.width * 0.51, height: rect.height * 0.19)
        let glasses = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * 0.035, width: size.width, height: size.height)
        return sparkle.subtracting(Self.sunglasses(in: glasses))
    }

    /// Two lenses, flat on top and round below, joined by a thin bridge along their tops.
    private static func sunglasses(in rect: CGRect) -> Path {
        let gap = rect.width * 0.12
        let lensWidth = (rect.width - gap) / 2
        let lens = UnevenRoundedRectangle(
            topLeadingRadius: rect.height * 0.2,
            bottomLeadingRadius: rect.height * 0.5,
            bottomTrailingRadius: rect.height * 0.5,
            topTrailingRadius: rect.height * 0.2
        )
        var path = Path()
        for x in [rect.minX, rect.minX + lensWidth + gap] {
            path.addPath(lens.path(in: CGRect(x: x, y: rect.minY, width: lensWidth, height: rect.height)))
        }
        path.addRect(CGRect(x: rect.minX + lensWidth - 0.5, y: rect.minY + rect.height * 0.08, width: gap + 1, height: max(0.8, rect.height * 0.2)))
        return path
    }
}

/// What `.symbolEffect(.pulse)` does for the SF sparkle, for a shape: the opacity breathes while active.
private struct Pulse: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([1, 0.4]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            content
        }
    }
}
