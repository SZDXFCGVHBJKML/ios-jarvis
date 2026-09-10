import SwiftUI

enum Hud {
    static let bg = Color(red: 0.024, green: 0.020, blue: 0.016)
    static let acc = Color(red: 1.0, green: 0.69, blue: 0.18)      // amber
    static let hot = Color(red: 1.0, green: 0.90, blue: 0.66)
    static let dim = Color.white.opacity(0.45)
    static let ink = Color.white.opacity(0.88)
    static let line = Color(red: 1.0, green: 0.69, blue: 0.18).opacity(0.25)
    static let bad = Color(red: 1.0, green: 0.37, blue: 0.24)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
