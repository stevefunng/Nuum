import Foundation

enum PathVerb: Equatable, Sendable {
    case move(Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
    case close
}

func parseSVGPath(_ data: String) -> [PathVerb] {
    var verbs: [PathVerb] = []
    var numbers: [Double] = []
    var command: Character?
    var token = ""

    func pushToken() {
        if let value = Double(token) { numbers.append(value) }
        token = ""
    }

    func flush() {
        guard let command else { return }
        switch command {
        case "M", "m":
            if numbers.count >= 2 { verbs.append(.move(numbers[0], numbers[1])) }
        case "C", "c":
            var index = 0
            while index + 6 <= numbers.count {
                verbs.append(.curve(
                    numbers[index], numbers[index + 1],
                    numbers[index + 2], numbers[index + 3],
                    numbers[index + 4], numbers[index + 5]
                ))
                index += 6
            }
        case "Z", "z":
            verbs.append(.close)
        default:
            break
        }
        numbers = []
    }

    for character in data {
        if character.isLetter {
            pushToken()
            flush()
            command = character
        } else if character == "-" && !token.isEmpty && !token.hasSuffix("e") && !token.hasSuffix("E") {
            pushToken()
            token = "-"
        } else if character == "," || character.isWhitespace {
            pushToken()
        } else {
            token.append(character)
        }
    }
    pushToken()
    flush()
    return verbs
}

enum NunuViewBox {
    static let avatarX = 18.0
    static let avatarY = 8.0
    static let avatarSide = 196.0
    static let bodySide = 232.0
}

enum NunuPaths {
    static let blob = "M42 174C32 153 40 112 49 86C54 64 53 26 78 20C105 12 116 31 114 65C138 32 169 43 176 74C182 102 203 143 191 174C179 201 60 203 42 174Z"
    static let circle = "M34 158C29 131 44 106 54 84C56 53 64 32 84 31C108 28 119 45 118 64C141 40 165 54 173 79C191 100 207 132 199 158C190 207 47 208 34 158Z"
    static let droplet = "M43 169C38 144 55 108 64 78C65 48 64 18 85 15C110 10 122 34 116 65C139 41 158 53 164 80C173 111 198 147 188 174C174 203 58 204 43 169Z"
    static let cloud = "M29 167C23 142 36 113 46 99C43 65 62 43 86 49C101 51 109 65 109 77C133 48 159 55 170 83C195 92 211 130 202 162C191 200 45 204 29 167Z"
    static let tablet = "M32 171C26 150 31 119 38 96C39 61 54 36 80 38C105 37 112 57 111 74C137 43 168 54 178 83C190 109 203 148 195 174C184 194 46 198 32 171Z"

    static func data(for shape: String) -> String {
        switch shape {
        case "circle": circle
        case "droplet": droplet
        case "cloud": cloud
        case "tablet": tablet
        default: blob
        }
    }
}

struct NunuAppearance: Equatable, Sendable {
    var agentID: String
    var colorID: String
    var shape: String
    var material: String
    var valueHex: String
    var darkHex: String
    var chatHex: String

    static func resolve(agentID: String, color: String?, shape: String?, material: String?) -> NunuAppearance {
        let pigment = resolvedPigment(agentId: agentID, requested: color)
        return NunuAppearance(
            agentID: agentID,
            colorID: pigment.id,
            shape: resolvedShape(agentId: agentID, requested: shape),
            material: resolvedMaterial(requested: material),
            valueHex: pigment.value,
            darkHex: pigment.dark,
            chatHex: pigment.chat
        )
    }
}

enum NunuMaterialStyle: Equatable, Sendable {
    case matte(SandColor)
    case felt(SandColor)
    case plush(SandColor, SandColor)
    case glass(SandColor)
    case aurora(SandColor)
}

func glassPigment(valueHex: String) -> SandColor {
    if valueHex.lowercased() == "#f3e8d4" {
        return SandColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    let base = SandColor(css: valueHex)
    let strength = 0.38
    func channel(_ value: Double) -> Double { 1 + (value - 1) * strength }
    return SandColor(red: channel(base.red), green: channel(base.green), blue: channel(base.blue), alpha: 1)
}

func materialStyle(_ appearance: NunuAppearance) -> NunuMaterialStyle {
    let value = SandColor(css: appearance.valueHex)
    switch appearance.material {
    case "felt":
        return .felt(value)
    case "plush":
        return .plush(value, SandColor(css: appearance.darkHex))
    case "glass":
        return .glass(glassPigment(valueHex: appearance.valueHex))
    case "aurora":
        return .aurora(glassPigment(valueHex: appearance.valueHex))
    default:
        return .matte(value)
    }
}
