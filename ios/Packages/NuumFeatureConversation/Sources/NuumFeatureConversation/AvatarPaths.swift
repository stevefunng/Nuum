import Foundation

struct VectorPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

enum VectorCommand: Equatable, Sendable {
    case move(VectorPoint)
    case curve(VectorPoint, VectorPoint, VectorPoint)
    case close
}

/// Absolute `M`, `C`, and `Z` only. These are the five nunu silhouettes.
func parseVectorPath(_ source: String) -> [VectorCommand] {
    var commands: [VectorCommand] = []
    var numbers: [Double] = []
    var command: Character?
    var digits = ""
    func flushNumber() {
        guard !digits.isEmpty, let value = Double(digits) else {
            digits = ""
            return
        }
        numbers.append(value)
        digits = ""
    }
    func emit() {
        guard let command else { return }
        switch command {
        case "M" where numbers.count >= 2:
            commands.append(.move(VectorPoint(x: numbers[0], y: numbers[1])))
        case "C" where numbers.count >= 6:
            commands.append(.curve(
                VectorPoint(x: numbers[0], y: numbers[1]),
                VectorPoint(x: numbers[2], y: numbers[3]),
                VectorPoint(x: numbers[4], y: numbers[5])
            ))
        case "Z":
            commands.append(.close)
        default:
            break
        }
        numbers = []
    }
    for character in source {
        if character == "M" || character == "C" || character == "Z" {
            flushNumber()
            emit()
            command = character
            if character == "Z" { emit() }
            continue
        }
        if character == "-" && !digits.isEmpty && !digits.hasSuffix("e") && !digits.hasSuffix("E") {
            flushNumber()
            digits = "-"
            continue
        }
        if character.isNumber || character == "." || character == "-" {
            digits.append(character)
        } else {
            flushNumber()
        }
    }
    flushNumber()
    emit()
    return commands
}

enum NunuSilhouette {
    static let bounds = (width: 220.0, height: 220.0)
    static let paths: [String: String] = [
        "blob": "M42 174C32 153 40 112 49 86C54 64 53 26 78 20C105 12 116 31 114 65C138 32 169 43 176 74C182 102 203 143 191 174C179 201 60 203 42 174Z",
        "circle": "M34 158C29 131 44 106 54 84C56 53 64 32 84 31C108 28 119 45 118 64C141 40 165 54 173 79C191 100 207 132 199 158C190 207 47 208 34 158Z",
        "droplet": "M43 169C38 144 55 108 64 78C65 48 64 18 85 15C110 10 122 34 116 65C139 41 158 53 164 80C173 111 198 147 188 174C174 203 58 204 43 169Z",
        "cloud": "M29 167C23 142 36 113 46 99C43 65 62 43 86 49C101 51 109 65 109 77C133 48 159 55 170 83C195 92 211 130 202 162C191 200 45 204 29 167Z",
        "tablet": "M32 171C26 150 31 119 38 96C39 61 54 36 80 38C105 37 112 57 111 74C137 43 168 54 178 83C190 109 203 148 195 174C184 194 46 198 32 171Z",
    ]

    static func path(for shape: String) -> [VectorCommand] {
        parseVectorPath(paths[shape] ?? paths["blob"]!)
    }
}
