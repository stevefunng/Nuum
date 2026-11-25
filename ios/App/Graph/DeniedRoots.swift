import Foundation
import NuumContracts

/// Host children kept denied when a scratch or workspace path is carved out of `nuum/`.
/// Same lists as Android `DeniedRoots.kt`.
let nuumHostChildren: [String] = [
    "settings.json",
    "migrations.json",
    "agents",
    "works",
    "work-sessions",
    "workspaces",
]

let agentHostChildren: [String] = [
    "profile.json",
    "settings.json",
    "transcript.jsonl",
    "read-cursor.json",
    "tool-approvals.json",
    "prompt-cache.json",
    "memory",
    "terminals",
]

/// The whole `nuum/` tree, plus the four secret filenames under that tree and its parent.
/// Keychain holds the keys, so these filenames are not storage. They stay denied anyway.
func hostDeniedRoots(nuumRoot: String, dataParent: String) -> [String] {
    var roots = [normalizePath(nuumRoot)]
    roots.append(contentsOf: sealedSecretPaths(nuumRoot: nuumRoot, dataParent: dataParent))
    return roots
}

func sealedSecretPaths(nuumRoot: String, dataParent: String) -> [String] {
    let names = SealedSecretFilename.all.sorted()
    var paths: [String] = []
    for name in names {
        paths.append(joinPath(nuumRoot, name))
        if normalizePath(dataParent) != normalizePath(nuumRoot) {
            paths.append(joinPath(dataParent, name))
        }
    }
    return paths
}

/// Rewrites a denied directory into the host children around scratch, project, and read-only roots.
/// A sealed path, including every secret filename, stays denied even when it is passed as an exception.
func carveDeniedRoots(
    denied: [String],
    exceptions: [String],
    sealed: [String] = [],
    childrenOf: (String) -> [String] = directoryChildren
) -> [String] {
    let sealedNorm = sealed.map(normalizePath).filter { !$0.isEmpty }
    let usable = uniquePaths(exceptions.compactMap { raw -> String? in
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if raw.hasPrefix("content://") { return nil }
        let normalized = normalizePath(raw)
        if normalized.isEmpty || sealedPath(normalized, sealed: sealedNorm) { return nil }
        return normalized
    })
    var seen = Set<String>()
    var out: [String] = []
    for root in denied {
        if root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let normalized = normalizePath(root)
        if normalized.isEmpty { continue }
        let pieces: [String]
        if sealedPath(normalized, sealed: sealedNorm) {
            pieces = [normalized]
        } else {
            let hits = usable.filter { samePath(normalized, $0) || pathInside(normalized, $0) }
            pieces = expandDenied(normalized, hits, childrenOf, sealedNorm)
        }
        for piece in pieces where seen.insert(piece).inserted {
            out.append(piece)
        }
    }
    return out
}

func deniedCovers(_ denied: [String], _ path: String) -> Bool {
    let target = normalizePath(path)
    return denied.contains { root in
        let normalized = normalizePath(root)
        return samePath(normalized, target) || pathInside(normalized, target)
    }
}

func normalizePath(_ path: String) -> String {
    let slash = path.replacingOccurrences(of: "\\", with: "/")
    let leading = slash.hasPrefix("/")
    var parts: [String] = []
    for part in slash.split(separator: "/", omittingEmptySubsequences: false) {
        if part.isEmpty || part == "." { continue }
        if part == ".." {
            if !parts.isEmpty { parts.removeLast() }
            continue
        }
        parts.append(String(part))
    }
    if leading {
        return "/" + parts.joined(separator: "/")
    }
    return parts.joined(separator: "/")
}

func isSealedSecretFile(_ path: String) -> Bool {
    let trimmed = trimSlash(path)
    guard let name = trimmed.split(separator: "/").last else { return false }
    let folded = String(name).lowercased()
    return SealedSecretFilename.all.contains { $0.lowercased() == folded }
}

func joinPath(_ parent: String, _ name: String) -> String {
    if parent == "/" { return "/" + name }
    return trimSlash(parent) + "/" + name
}

private func expandDenied(
    _ root: String,
    _ exceptions: [String],
    _ childrenOf: (String) -> [String],
    _ sealed: [String]
) -> [String] {
    if exceptions.isEmpty { return [root] }
    if sealedPath(root, sealed: sealed) { return [root] }
    if exceptions.contains(where: { samePath($0, root) }) {
        return secretFilePaths(under: root)
    }
    let nested = exceptions.filter { pathInside(root, $0) }
    if nested.isEmpty { return [root] }
    var names = Set<String>()
    for child in childrenOf(root) {
        let name = trimSlash(child).split(separator: "/").last.map(String.init) ?? ""
        if !name.isEmpty { names.insert(name) }
    }
    for exception in nested {
        let name = nextSegment(root, exception)
        if !name.isEmpty { names.insert(name) }
    }
    if nested.contains(where: { nextSegment(root, $0) == "agents" || nextSegment(root, $0) == "workspaces" }) {
        names.formUnion(nuumHostChildren)
    }
    if nested.contains(where: { nextSegment(root, $0) == "scratch" }) {
        names.formUnion(agentHostChildren)
    }
    names.formUnion(SealedSecretFilename.all)
    var result: [String] = []
    for name in names.sorted() {
        let child = joinPath(root, name)
        if sealedPath(child, sealed: sealed) {
            result.append(child)
            continue
        }
        let under = nested.filter { samePath($0, child) || pathInside(child, $0) }
        result.append(contentsOf: expandDenied(child, under, childrenOf, sealed))
    }
    return result
}

private func secretFilePaths(under root: String) -> [String] {
    SealedSecretFilename.all.sorted().map { joinPath(root, $0) }
}

private func directoryChildren(_ path: String) -> [String] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return []
    }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    return names.map { normalizePath(joinPath(path, $0)) }.sorted()
}

private func nextSegment(_ root: String, _ descendant: String) -> String {
    let base = trimSlash(root)
    let prefix = base == "/" ? "/" : base + "/"
    guard descendant.hasPrefix(prefix) else { return "" }
    let rest = descendant.dropFirst(prefix.count)
    if let slash = rest.firstIndex(of: "/") {
        return String(rest[..<slash])
    }
    return String(rest)
}

private func sealedPath(_ path: String, sealed: [String]) -> Bool {
    if isSealedSecretFile(path) { return true }
    return sealed.contains { prefix in
        samePath(prefix, path) || pathInside(prefix, path)
    }
}

private func samePath(_ left: String, _ right: String) -> Bool {
    trimSlash(left) == trimSlash(right)
}

private func pathInside(_ root: String, _ path: String) -> Bool {
    let base = trimSlash(root)
    let target = trimSlash(path)
    return !base.isEmpty && target.count > base.count && target.hasPrefix(base + "/")
}

private func trimSlash(_ path: String) -> String {
    if path == "/" { return path }
    var value = path
    while value.count > 1 && value.hasSuffix("/") {
        value.removeLast()
    }
    return value
}

private func uniquePaths(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.filter { seen.insert($0).inserted }
}
