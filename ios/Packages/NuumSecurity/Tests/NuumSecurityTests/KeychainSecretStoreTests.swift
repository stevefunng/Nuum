#if os(iOS)
import Foundation
import NuumContracts
import Security
import Testing

@testable import NuumSecurity

/// Runs on an iOS simulator or device, where Keychain and the app container exist.
/// Missing item reads as empty `Secrets`. After a write, read-back matches, and
/// Application Support and Documents contain no `secrets.bin` (or any other sealed name)
/// and none of the test key bytes.
@Test func simulatorKeychainRoundTripLeavesContainerFilesUntouched() async throws {
    let store = KeychainSecretStore()
    try store.removeItem()
    defer { try? store.removeItem() }

    #expect(try store.currentItem() == nil)
    #expect(try await store.read() == Secrets())

    let openai = "nuum-test-openai-key-7f3c1a"
    let anthropic = "nuum-test-anthropic-key-91ab"
    let deepseek = "nuum-test-deepseek-key-e04d"
    let written = Secrets(
        openaiApiKey: openai,
        anthropicApiKey: anthropic,
        deepseekApiKey: deepseek
    )
    try await store.write(written)
    #expect(try await store.read() == written)
    #expect(try await KeychainSecretStore().read() == written)
    try expectItemShape()
    try expectContainerHasNoSecretMaterial([openai, anthropic, deepseek])
    expectStoreDescriptionOmits(store, openai, anthropic, deepseek)

    let tricky = "a\"b\\c\n\u{0001}尾"
    let replacedKey = "nuum-test-openai-key-replaced"
    let replaced = Secrets(openaiApiKey: tricky, anthropicApiKey: "", deepseekApiKey: nil)
    try await store.write(replaced)
    #expect(try await store.read() == replaced)
    try await store.write(Secrets(openaiApiKey: replacedKey))
    #expect(try await store.read() == Secrets(openaiApiKey: replacedKey))
    try expectItemShape()
    try expectContainerHasNoSecretMaterial([openai, anthropic, deepseek, tricky, replacedKey])

    let plantedKey = "nuum-test-openai-key-planted"
    try store.replaceData(Data("{\"openaiApiKey\":\"\(plantedKey)\"".utf8))
    do {
        _ = try await store.read()
        Issue.record("malformed item should fail closed")
    } catch {
        expectFixedReadFailure(error, omits: [plantedKey, openai, replacedKey, tricky])
    }

    try store.replaceData(Data())
    do {
        _ = try await store.read()
        Issue.record("empty item should fail closed")
    } catch {
        expectFixedReadFailure(error, omits: [plantedKey, replacedKey])
    }

    try store.removeItem()
    #expect(try store.currentItem() == nil)
    #expect(try await store.read() == Secrets())
    try expectContainerHasNoSecretMaterial([openai, anthropic, deepseek, plantedKey, replacedKey, tricky])
}

private func expectItemShape() throws {
    let item = try KeychainSecretStore().currentItem()
    #expect(item?.service == KeychainSecretItem.service)
    #expect(item?.account == KeychainSecretItem.account)
    #expect(item?.accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    #expect(item?.synchronizable == false)
    #expect(item?.hasAccessControl == false)
    #expect(item?.isGenericPassword == true)
    #expect(item?.matchingItemCount == 1)
    let probes = [
        "nuum-test-openai-key-7f3c1a",
        "nuum-test-anthropic-key-91ab",
        "nuum-test-deepseek-key-e04d",
        "nuum-test-openai-key-replaced",
        "nuum-test-openai-key-planted",
    ]
    if let item {
        let visible = [item.service, item.account, item.accessible].joined(separator: "\n")
        for probe in probes {
            #expect(!visible.contains(probe))
        }
    }
}

private func expectStoreDescriptionOmits(_ store: KeychainSecretStore, _ keys: String...) {
    let rendered = String(describing: store) + "\n" + String(reflecting: store)
    #expect(rendered == "KeychainSecretStore\nKeychainSecretStore")
    for key in keys {
        #expect(!rendered.contains(key))
    }
}

private func expectFixedReadFailure(_ error: Error, omits keys: [String]) {
    #expect(error as? NuumError == NuumError.secretReadFailed)
    let rendered = renderedError(error)
    #expect(rendered.contains("Couldn't read secrets because decryption failed."))
    #expect(rendered.contains("3001"))
    #expect(!rendered.contains("OSStatus"))
    #expect(!rendered.contains("errSec"))
    for key in keys where !key.isEmpty {
        #expect(!rendered.contains(key))
    }
}

private func expectContainerHasNoSecretMaterial(_ keys: [String]) throws {
    let keyData = keys.filter { !$0.isEmpty }.map { Data($0.utf8) }
    for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory] {
        for root in FileManager.default.urls(for: directory, in: .userDomainMask) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: []
                )
            else { continue }
            for case let url as URL in enumerator {
                if SealedSecretFilename.all.contains(url.lastPathComponent) {
                    Issue.record("sealed secret filename \(url.lastPathComponent) is in the container")
                }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let bytes = try Data(contentsOf: url)
                for key in keyData where bytes.range(of: key) != nil {
                    Issue.record("container file contains key material")
                }
            }
        }
    }
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
#endif
