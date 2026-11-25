import NuumContracts

/// Relative paths under Application Support/`nuum`, plus the session paths from
/// `StoragePaths` that are not on `NuumPaths`.
/// Work-session ids use `sha256(JSON.stringify([workId, taskId, agentId, membershipRevision]))`.
public enum StoragePaths {
    public static let migrationVersion = 3

    /// Same tail window as Mac `TAIL_WINDOW` in `agent-store.ts`.
    public static let tailWindowBytes = 64 * 1024

    /// UserDefaults suite. The values live outside the nuum tree.
    public static let uiPreferencesName = NuumUIPreferences.suiteName

    public static let topLevelDirectories: [String] = [
        "agents",
        "works",
        "work-sessions",
        "workspaces",
    ]

    public static func settingsPath() -> String { NuumPaths.settingsPath() }
    public static func migrationsPath() -> String { NuumPaths.migrationsPath() }
    public static func agentDir(_ agentId: String) -> String { NuumPaths.agentDir(agentId) }
    public static func profilePath(_ agentId: String) -> String { NuumPaths.profilePath(agentId) }
    public static func agentSettingsPath(_ agentId: String) -> String { NuumPaths.agentSettingsPath(agentId) }
    public static func transcriptPath(_ agentId: String) -> String { NuumPaths.transcriptPath(agentId) }
    public static func readCursorPath(_ agentId: String) -> String { NuumPaths.readCursorPath(agentId) }
    public static func toolApprovalsPath(_ agentId: String) -> String { NuumPaths.toolApprovalsPath(agentId) }
    public static func promptCachePath(_ agentId: String) -> String { NuumPaths.promptCachePath(agentId) }
    public static func memoryDir(_ agentId: String) -> String { NuumPaths.memoryDir(agentId) }
    public static func scratchDir(_ agentId: String) -> String { NuumPaths.scratchDir(agentId) }
    public static func terminalsDir(_ agentId: String) -> String { NuumPaths.terminalsDir(agentId) }
    public static func workDir(_ workId: String) -> String { NuumPaths.workDir(workId) }
    public static func workProfilePath(_ workId: String) -> String { NuumPaths.workProfilePath(workId) }
    public static func workCatalogPath(_ workId: String) -> String { NuumPaths.workCatalogPath(workId) }
    public static func workTimelinePath(_ workId: String) -> String { NuumPaths.workTimelinePath(workId) }
    public static func workspaceRecordPath(_ workspaceId: String) -> String { NuumPaths.workspaceRecordPath(workspaceId) }
    public static func managedWorkspaceDir(_ workspaceId: String) -> String { NuumPaths.managedWorkspaceDir(workspaceId) }
    public static func secretsFileName() -> String { NuumPaths.secretsFileName() }

    /// `sha256(owner)`, the Mac workspace record id.
    public static func workspaceIdForOwner(_ owner: String) -> String { sha256Hex(owner) }

    public static func workspaceRecordPathForOwner(_ owner: String) -> String {
        workspaceRecordPath(workspaceIdForOwner(owner))
    }

    /// `JSON.stringify([workId, taskId, agentId, membershipRevision])` as Node emits it.
    public static func cardSessionPayload(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        "[\(jsonString(workId)),\(jsonString(taskId)),\(jsonString(agentId)),\(membershipRevision)]"
    }

    public static func cardSessionId(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        sha256Hex(cardSessionPayload(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        ))
    }

    /// `sha256(workId)`, the first path component under `work-sessions/`.
    public static func workSessionRoom(_ workId: String) -> String { sha256Hex(workId) }

    public static func workSessionDir(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        let room = workSessionRoom(workId)
        let id = cardSessionId(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        )
        return "work-sessions/\(room)/\(id)"
    }

    public static func workSessionRecordPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        workSessionDir(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        ) + "/session.json"
    }

    public static func workSessionTranscriptPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        workSessionDir(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        ) + "/transcript.jsonl"
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hex(Array(text.utf8))
    }

    /// Node `JSON.stringify` for the strings that appear in a card-session payload.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                out += "\\\\"
            case 0x22:
                out += "\\\""
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case let code where code < 0x20:
                out += String(format: "\\u%04x", code)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}

enum SHA256 {
    static func hex(_ bytes: [UInt8]) -> String {
        let digest = hash(bytes)
        let alphabet = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(digest.count * 2)
        for byte in digest {
            out.append(alphabet[Int(byte >> 4)])
            out.append(alphabet[Int(byte & 0x0F)])
        }
        return out
    }

    private static let k: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]

    private static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
        ]
        var bytes = message
        let bitLength = UInt64(message.count) &* 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] =
                    (UInt32(bytes[start]) << 24)
                    | (UInt32(bytes[start + 1]) << 16)
                    | (UInt32(bytes[start + 2]) << 8)
                    | UInt32(bytes[start + 3])
            }
            for index in 16..<64 {
                let s0 = rotr(words[index - 15], 7) ^ rotr(words[index - 15], 18) ^ (words[index - 15] >> 3)
                let s1 = rotr(words[index - 2], 17) ^ rotr(words[index - 2], 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            for index in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ k[index] &+ words[index]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in state {
            out.append(UInt8((word >> 24) & 0xFF))
            out.append(UInt8((word >> 16) & 0xFF))
            out.append(UInt8((word >> 8) & 0xFF))
            out.append(UInt8(word & 0xFF))
        }
        return out
    }

    private static func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
