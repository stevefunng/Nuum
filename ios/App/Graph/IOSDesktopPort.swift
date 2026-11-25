import Combine
import Foundation
import NuumContracts
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Directory and file pickers for `DesktopPort`.
/// Cancel returns nil or an empty list and does not change a saved path.
/// A chosen directory is turned into a security-scoped bookmark, resolved back to a path,
/// and that path is what feature packages store. Bookmark bytes stay in this type.
@MainActor
final class DocumentPickerModel: ObservableObject {
    @Published var directoryPresented = false
    @Published var filesPresented = false

    private let bookmarks = BookmarkStore()
    private var directoryWait: CheckedContinuation<DirectoryOutcome, Never>?
    private var filesWait: CheckedContinuation<FilesOutcome, Never>?
    private var attached = false

    func attach() {
        attached = true
    }

    func restoreBookmarks() {
        bookmarks.restore()
    }

    func pickDirectory() async throws -> String? {
        guard attached, directoryWait == nil else { return nil }
        let outcome: DirectoryOutcome = await withCheckedContinuation { continuation in
            directoryWait = continuation
            directoryPresented = true
        }
        switch outcome {
        case .path(let path):
            return path
        case .cancelled:
            return nil
        case .failed:
            throw NuumError(code: DesktopErrorCode.folderPick, message: DesktopCopy.folderUnavailable)
        }
    }

    func pickFiles() async throws -> [PickedFile] {
        guard attached, filesWait == nil else { return [] }
        let outcome: FilesOutcome = await withCheckedContinuation { continuation in
            filesWait = continuation
            filesPresented = true
        }
        switch outcome {
        case .files(let files):
            return files
        case .cancelled:
            return []
        case .failed:
            throw NuumError(code: DesktopErrorCode.folderPick, message: DesktopCopy.fileUnavailable)
        }
    }

    func finishDirectory(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            resumeDirectory(isUserCancellation(error) ? .cancelled : .failed)
        case .success(let urls):
            guard let url = urls.first else {
                resumeDirectory(.cancelled)
                return
            }
            if let path = bookmarks.materializeDirectory(url) {
                resumeDirectory(.path(path))
            } else {
                resumeDirectory(.failed)
            }
        }
    }

    func finishFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            resumeFiles(isUserCancellation(error) ? .cancelled : .failed)
        case .success(let urls):
            if urls.isEmpty {
                resumeFiles(.cancelled)
                return
            }
            resumeFiles(.files(urls.compactMap(readPicked)))
        }
    }

    func openAttachment(path: String) async throws {
        guard let url = try preparedURL(path) else { return }
        #if canImport(UIKit)
        let opened = await openExternal(url)
        if !opened {
            presentShare(url)
        }
        #else
        _ = url
        #endif
    }

    func share(path: String) async throws {
        guard let url = try preparedURL(path) else { return }
        #if canImport(UIKit)
        presentShare(url)
        #else
        _ = url
        #endif
    }

    private func resumeDirectory(_ outcome: DirectoryOutcome) {
        directoryPresented = false
        let wait = directoryWait
        directoryWait = nil
        wait?.resume(returning: outcome)
    }

    private func resumeFiles(_ outcome: FilesOutcome) {
        filesPresented = false
        let wait = filesWait
        filesWait = nil
        wait?.resume(returning: outcome)
    }

    /// Blank and secret filenames are ignored. A revoked external bookmark throws 3002.
    private func preparedURL(_ path: String) throws -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isSealedSecretFile(trimmed) { return nil }
        if let retained = bookmarks.url(for: trimmed) {
            _ = retained.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: retained.path) {
                return retained
            }
            throw NuumError(code: DesktopErrorCode.folderPick, message: DesktopCopy.folderUnavailable)
        }
        if bookmarks.isInsideContainer(trimmed) {
            guard FileManager.default.fileExists(atPath: trimmed) else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        if FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }
        throw NuumError(code: DesktopErrorCode.folderPick, message: DesktopCopy.folderUnavailable)
    }

    private func readPicked(_ url: URL) -> PickedFile? {
        if isSealedSecretFile(url.path) { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        guard let bytes = readLimited(url, maxBytes: AttachmentLimits.maxBytes + 1) else { return nil }
        return PickedFile(name: name, mimeType: mimeType(for: url), bytes: bytes)
    }
}

final class IOSDesktopPort: DesktopPort, @unchecked Sendable {
    private let picker: DocumentPickerModel

    init(picker: DocumentPickerModel) {
        self.picker = picker
    }

    func pickDirectory() async throws -> String? {
        try await picker.pickDirectory()
    }

    func pickFiles() async throws -> [PickedFile] {
        try await picker.pickFiles()
    }

    func openAttachment(path: String) async throws {
        try await picker.openAttachment(path: path)
    }

    func share(path: String) async throws {
        try await picker.share(path: path)
    }
}

extension View {
    /// The importer callback has to resolve the security scope before it returns.
    /// `assumeIsolated` keeps that work on the main actor without hopping to a later turn.
    func nuumDocumentPickers(_ picker: DocumentPickerModel) -> some View {
        fileImporter(
            isPresented: Binding(
                get: { MainActor.assumeIsolated { picker.directoryPresented } },
                set: { newValue in MainActor.assumeIsolated { picker.directoryPresented = newValue } }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: { result in
                MainActor.assumeIsolated { picker.finishDirectory(result) }
            }
        )
        .fileImporter(
            isPresented: Binding(
                get: { MainActor.assumeIsolated { picker.filesPresented } },
                set: { newValue in MainActor.assumeIsolated { picker.filesPresented = newValue } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: { result in
                MainActor.assumeIsolated { picker.finishFiles(result) }
            }
        )
    }
}

private enum DirectoryOutcome: Sendable {
    case path(String)
    case cancelled
    case failed
}

private enum FilesOutcome: Sendable {
    case files([PickedFile])
    case cancelled
    case failed
}

private enum DesktopCopy {
    static let folderUnavailable = "Couldn't open that folder."
    static let fileUnavailable = "Couldn't read that file."
}

@MainActor
private final class BookmarkStore {
    private var urls: [URL] = []
    private var byPath: [String: URL] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("nuum-access", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = directory
        try? copy.setResourceValues(values)
        fileURL = directory.appendingPathComponent("bookmarks.json")
    }

    func restore() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let file = try? JSONDecoder().decode(BookmarkFile.self, from: data) else { return }
        for entry in file.entries {
            guard let blob = Data(base64Encoded: entry.bookmark) else { continue }
            guard let resolved = resolve(blob) else { continue }
            _ = resolved.startAccessingSecurityScopedResource()
            var payload = blob
            if let refreshed = try? resolved.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                payload = refreshed
            }
            retain(paths: [entry.path, resolved.path], url: resolved, bookmark: payload)
        }
        if !saved.isEmpty { persist() }
    }

    func materializeDirectory(_ url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        let bookmark = makeBookmark(url)
        if let bookmark, let resolved = resolve(bookmark) {
            if accessed { url.stopAccessingSecurityScopedResource() }
            let resolvedAccess = resolved.startAccessingSecurityScopedResource()
            let path = resolved.standardizedFileURL.path
            if resolvedAccess || isInsideContainer(path) || FileManager.default.fileExists(atPath: path) {
                retain(paths: [path, url.path, resolved.path], url: resolved, bookmark: bookmark)
                persist()
                return path
            }
            return nil
        }
        let path = url.standardizedFileURL.path
        if accessed || isInsideContainer(path) {
            retain(paths: [path, url.path], url: url, bookmark: bookmark)
            if bookmark != nil { persist() }
            return path
        }
        if accessed { url.stopAccessingSecurityScopedResource() }
        return nil
    }

    func url(for path: String) -> URL? {
        byPath[path] ?? byPath[normalizePath(path)]
    }

    func isInsideContainer(_ path: String) -> Bool {
        let home = normalizePath(NSHomeDirectory())
        let target = normalizePath(path)
        return target == home || target.hasPrefix(home + "/")
    }

    private func retain(paths: [String], url: URL, bookmark: Data?) {
        urls.append(url)
        for path in paths {
            byPath[path] = url
            byPath[normalizePath(path)] = url
        }
        if let bookmark {
            saved[normalizePath(url.standardizedFileURL.path)] = bookmark.base64EncodedString()
            for path in paths {
                saved[normalizePath(path)] = bookmark.base64EncodedString()
            }
        }
    }

    private var saved: [String: String] = [:]

    private func persist() {
        let entries = saved.map { BookmarkEntry(path: $0.key, bookmark: $0.value) }.sorted { $0.path < $1.path }
        guard let data = try? JSONEncoder().encode(BookmarkFile(entries: entries)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func makeBookmark(_ url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}

private struct BookmarkFile: Codable {
    var entries: [BookmarkEntry]
}

private struct BookmarkEntry: Codable {
    var path: String
    var bookmark: String
}

private func isUserCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let ns = error as NSError
    return ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.userCancelled.rawValue
}

private func readLimited(_ url: URL, maxBytes: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: maxBytes)
}

private func mimeType(for url: URL) -> String {
    let ext = url.pathExtension
    if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
        return mime
    }
    return "application/octet-stream"
}

#if canImport(UIKit)
@MainActor
private func openExternal(_ url: URL) async -> Bool {
    await withCheckedContinuation { continuation in
        UIApplication.shared.open(url, options: [:]) { accepted in
            continuation.resume(returning: accepted)
        }
    }
}

@MainActor
private func presentShare(_ url: URL) {
    guard let presenter = topViewController() else { return }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
}

@MainActor
private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
    return deepest(root)
}

@MainActor
private func deepest(_ controller: UIViewController?) -> UIViewController? {
    if let presented = controller?.presentedViewController {
        return deepest(presented)
    }
    if let navigation = controller as? UINavigationController {
        return deepest(navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
        return deepest(tab.selectedViewController)
    }
    return controller
}
#endif
