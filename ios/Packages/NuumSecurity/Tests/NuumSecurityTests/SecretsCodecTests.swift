import Foundation
import NuumContracts
import Testing

@testable import NuumSecurity

@Test func emptySecretsEncodeAsAnEmptyObject() throws {
    let data = SecretsCodec.encode(.empty)
    #expect(String(decoding: data, as: UTF8.self) == "{}")
    #expect(try SecretsCodec.decode(data) == .empty)
}

@Test func jsonFieldOrderOmitsNilAndKeepsEmptyStrings() throws {
    let partial = Secrets(openaiApiKey: "o", anthropicApiKey: nil, deepseekApiKey: "d")
    #expect(text(SecretsCodec.encode(partial)) == "{\"openaiApiKey\":\"o\",\"deepseekApiKey\":\"d\"}")

    let onlyDeepseek = Secrets(deepseekApiKey: "d")
    #expect(text(SecretsCodec.encode(onlyDeepseek)) == "{\"deepseekApiKey\":\"d\"}")

    let blanks = Secrets(openaiApiKey: "", anthropicApiKey: "", deepseekApiKey: "")
    #expect(
        text(SecretsCodec.encode(blanks))
            == "{\"openaiApiKey\":\"\",\"anthropicApiKey\":\"\",\"deepseekApiKey\":\"\"}"
    )
    #expect(try SecretsCodec.decode(SecretsCodec.encode(blanks)) == blanks)

    let androidVector = Secrets(
        openaiApiKey: "a\"b\\c\n\u{0001}尾",
        anthropicApiKey: "",
        deepseekApiKey: nil
    )
    let encoded = text(SecretsCodec.encode(androidVector))
    #expect(encoded == "{\"openaiApiKey\":\"a\\\"b\\\\c\\n\\u0001尾\",\"anthropicApiKey\":\"\"}")
    #expect(encoded.contains("\"openaiApiKey\""))
    #expect(encoded.contains("\"anthropicApiKey\":\"\""))
    #expect(!encoded.contains("deepseekApiKey"))
    #expect(try SecretsCodec.decode(Data(encoded.utf8)) == androidVector)
}

@Test func jsonEscapesControlsAndKeepsSlashAndNonASCII() throws {
    let value = "https://api.example/v1 \t\r\u{0008}\u{000C}\u{001F}\u{2028}\u{2029}🔐"
    let secrets = Secrets(anthropicApiKey: value)
    let encoded = text(SecretsCodec.encode(secrets))
    #expect(encoded == "{\"anthropicApiKey\":\"https://api.example/v1 \\t\\r\\b\\f\\u001f\\u2028\\u2029🔐\"}")
    #expect(!encoded.contains("\\/"))
    #expect(try SecretsCodec.decode(Data(encoded.utf8)) == secrets)
    let parsed = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: String]
    #expect(parsed?["anthropicApiKey"] == value)
    #expect(parsed?["openaiApiKey"] == nil)
}

@Test func decoderAcceptsWhitespaceNullsAndDropsUnknownFields() throws {
    let key = "sk-test-openai-9f3c2b"
    let extra = "sk-test-extra-should-drop"
    let json = """
    {
      "unused" : "\(extra)",
      "openaiApiKey" : "\(key)",
      "anthropicApiKey" : null,
      "nope" : true
    }
    """
    let decoded = try SecretsCodec.decode(Data(json.utf8))
    #expect(decoded == Secrets(openaiApiKey: key))
    #expect(!String(describing: decoded).contains(key))
    #expect(!String(reflecting: decoded).contains(key))
    #expect(!String(describing: decoded).contains(extra))
    #expect(!String(reflecting: decoded).contains(extra))
}

@Test func malformedPayloadDoesNotEchoTheKey() {
    let key = "sk-test-openai-9f3c2b"
    let samples = [
        Data("{\"openaiApiKey\":\"\(key)\"".utf8),
        Data(),
        Data("   ".utf8),
        Data("\"\(key)\"".utf8),
        Data("[\(key)]".utf8),
        Data("{\"openaiApiKey\":{\"raw\":\"\(key)\"}}".utf8),
        Data("{\"deepseekApiKey\":[\"\(key)\"]}".utf8),
        Data("{\"anthropicApiKey\":1,\"note\":\"\(key)\"}".utf8),
        Data("null".utf8),
    ]
    for sample in samples {
        do {
            _ = try SecretsCodec.decode(sample)
            Issue.record("decode should fail")
        } catch {
            #expect(error is SecretsCodecError)
            let rendered = renderedError(error)
            #expect(!rendered.contains(key))
            #expect(!rendered.contains("openaiApiKey"))
            #expect(!rendered.contains("OSStatus"))
            #expect(!rendered.contains("errSec"))
        }
    }
}

@Test func surfacedSentencesStayFixedAndOmitAProbeKey() {
    let key = "sk-test-openai-9f3c2b"
    #expect(DesktopErrorCode.secretStore == 3001)
    #expect(
        NuumError.secretReadFailed
            == NuumError(code: 3001, message: "Couldn't read secrets because decryption failed.")
    )
    #expect(
        NuumError.secretWriteFailed
            == NuumError(code: 3001, message: "Couldn't store secrets because encryption failed.")
    )
    for error in [NuumError.secretReadFailed, NuumError.secretWriteFailed] {
        let rendered = renderedError(error)
        #expect(!rendered.contains(key))
        #expect(!rendered.contains("OSStatus"))
        #expect(!rendered.contains("errSec"))
    }
}

@Test func keychainSourceDeclaresOneGenericPasswordItem() throws {
    let source = try sourceText("KeychainSecretStore.swift")
    #expect(source.contains("import Security"))
    #expect(source.contains("kSecClassGenericPassword"))
    #expect(source.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
    #expect(source.contains("kSecAttrSynchronizable"))
    #expect(source.contains("kSecUseDataProtectionKeychain"))
    #expect(source.contains("KeychainSecretItem.service"))
    #expect(source.contains("KeychainSecretItem.account"))
    #expect(source.contains("NuumError.secretReadFailed"))
    #expect(source.contains("NuumError.secretWriteFailed"))
    #expect(!source.contains("SecAccessControlCreateWithFlags"))
    #expect(!source.contains("kSecAttrAccessControl:"))
}

@Test func securitySourcesDoNotWriteFilesOrLog() throws {
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/NuumSecurity", isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(
        at: sources,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    #expect(files.count >= 2)
    let banned = [
        "FileManager",
        "UserDefaults",
        "secrets.bin",
        "noBackupFilesDir",
        "safeStorage",
        "CryptoKit",
        "LocalAuthentication",
        "print(",
        "NSLog",
        "os_log",
        "Logger",
        "debugPrint",
        "dump(",
        "write(to:",
        "createFile",
        "URLSession",
        "UIKit",
        "SwiftUI",
    ]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in banned {
            #expect(!text.contains(token), "\(file.lastPathComponent) contains \(token)")
        }
    }
}

private func sourceText(_ name: String) throws -> String {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/NuumSecurity", isDirectory: true)
        .appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
}

private func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
}

private func renderedError(_ error: Error) -> String {
    let bridged = error as NSError
    var parts = [
        String(describing: error),
        String(reflecting: error),
        error.localizedDescription,
        bridged.domain,
        String(bridged.code),
        bridged.localizedDescription,
        bridged.localizedFailureReason ?? "",
        bridged.localizedRecoverySuggestion ?? "",
    ]
    for value in bridged.userInfo.values {
        parts.append(String(describing: value))
        parts.append(String(reflecting: value))
    }
    return parts.joined(separator: "\n")
}
