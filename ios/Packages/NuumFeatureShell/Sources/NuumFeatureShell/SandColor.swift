import Foundation

/// CSS color. Eight-digit form is `#RRGGBBAA`, matching the sand tokens.
public struct SandColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(css: String) {
        var hex = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        switch hex.count {
        case 6:
            red = Self.channel(value >> 16)
            green = Self.channel(value >> 8)
            blue = Self.channel(value)
            alpha = 1
        case 8:
            red = Self.channel(value >> 24)
            green = Self.channel(value >> 16)
            blue = Self.channel(value >> 8)
            alpha = Self.channel(value)
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1
        }
    }

    private static func channel(_ value: UInt64) -> Double {
        Double(value & 0xff) / 255
    }
}

func mix(_ foreground: SandColor, onto background: SandColor, amount: Double) -> SandColor {
    let ratio = min(1, max(0, amount))
    func blend(_ front: Double, _ back: Double) -> Double {
        front * ratio + back * (1 - ratio)
    }
    return SandColor(
        red: blend(foreground.red, background.red),
        green: blend(foreground.green, background.green),
        blue: blend(foreground.blue, background.blue),
        alpha: 1
    )
}
