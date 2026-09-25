import SwiftUI

extension Color {
    static let meralinePink = Color("AccentColor")
    static let meralineLavender = Color("Lavender")
}

extension ShapeStyle where Self == LinearGradient {
    static var meraline: LinearGradient {
        LinearGradient(colors: [.meralinePink, .meralineLavender], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
