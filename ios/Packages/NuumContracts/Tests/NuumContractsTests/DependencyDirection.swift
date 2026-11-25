import Foundation

enum DependencyDirection {
    static let allowedEdges: [String: Set<String>] = [
        "NuumFeatureShell": ["NuumContracts", "NuumProtocol"],
        "NuumFeatureConversation": ["NuumContracts", "NuumProtocol"],
        "NuumFeatureWork": ["NuumContracts", "NuumProtocol"],
        "NuumFeatureSettings": ["NuumContracts", "NuumProtocol"],
        "NuumAgent": ["NuumContracts", "NuumProtocol"],
        "NuumKernel": ["NuumContracts", "NuumProtocol"],
        "NuumModel": ["NuumContracts", "NuumProtocol"],
        "NuumTools": ["NuumContracts", "NuumProtocol"],
        "NuumStorage": ["NuumContracts", "NuumProtocol"],
        "NuumSecurity": ["NuumContracts"],
        "NuumProtocol": [],
        "NuumContracts": ["NuumProtocol"],
        "NuumAcceptance": [],
    ]

    static let appLinkedProducts: Set<String> = [
        "NuumContracts",
        "NuumProtocol",
        "NuumSecurity",
        "NuumStorage",
        "NuumModel",
        "NuumKernel",
        "NuumAgent",
        "NuumTools",
        "NuumFeatureShell",
        "NuumFeatureConversation",
        "NuumFeatureWork",
        "NuumFeatureSettings",
    ]

    static let thirdPartyModules: Set<String> = [
        "Datadog",
        "DatadogCore",
        "Sentry",
        "Firebase",
        "FirebaseCore",
        "Alamofire",
        "Swinject",
    ]

    static func violations(at iosRoot: URL) throws -> [String] {
        var violations = selfCheck()
        let packagesRoot = iosRoot.appendingPathComponent("Packages")
        let directories = try packageDirectories(packagesRoot)
        if Set(directories) != Set(allowedEdges.keys) {
            violations.append(
                "Packages directories \(directories.sorted()) do not match the allow-map \(allowedEdges.keys.sorted())"
            )
        }
        for name in directories.sorted() {
            let manifestURL = packagesRoot.appendingPathComponent(name).appendingPathComponent("Package.swift")
            let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            violations += manifestViolations(package: name, manifest: manifest).map { "\(name) \($0)" }
            let sources = packagesRoot.appendingPathComponent(name).appendingPathComponent("Sources")
            if FileManager.default.fileExists(atPath: sources.path) {
                for file in try swiftFiles(in: sources) {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    let relative = file.path.replacingOccurrences(of: iosRoot.path + "/", with: "")
                    violations += importViolations(package: name, source: text).map { "\(relative) \($0)" }
                }
            } else {
                violations.append("\(name) has no Sources directory")
            }
        }
        violations += try projectViolations(iosRoot)
        violations += try isolationViolations(iosRoot)
        return violations
    }

    static func edgeAllowed(_ from: String, _ to: String) -> Bool {
        allowedEdges[from]?.contains(to) == true
    }

    static func manifestViolations(package: String, manifest: String) -> [String] {
        var violations: [String] = []
        if manifest.range(of: #"\.package\(\s*url\s*:"#, options: .regularExpression) != nil {
            violations.append("has a remote package dependency")
        }
        if manifest.contains("github.com") || manifest.contains("http://") || manifest.contains("https://") {
            violations.append("mentions a remote URL")
        }
        let allowed = allowedEdges[package] ?? []
        for edge in declaredEdges(manifest) where !allowed.contains(edge) {
            violations.append("depends on \(edge)")
        }
        if package == "NuumProtocol" || package == "NuumContracts" {
            for word in ["UIKit", "SwiftUI", "Security", "URLSession", "Network"] where manifest.contains(word) {
                violations.append("Package.swift mentions \(word)")
            }
        }
        return violations
    }

    static func bannedImports(_ package: String) -> Set<String> {
        let featureImpl: Set<String> = [
            "NuumKernel", "NuumAgent", "NuumModel", "NuumStorage", "NuumSecurity", "NuumTools",
        ]
        let features: Set<String> = [
            "NuumFeatureShell", "NuumFeatureConversation", "NuumFeatureWork", "NuumFeatureSettings",
        ]
        let ui: Set<String> = ["UIKit", "SwiftUI"]
        let secret: Set<String> = ["Security"]
        let net: Set<String> = ["Network", "URLSession"]
        switch package {
        case "NuumProtocol", "NuumContracts":
            return ui.union(secret).union(net)
        case "NuumKernel":
            return ui.union(net).union(featureImpl.subtracting(["NuumKernel"])).union(features)
        case "NuumAgent":
            return ui.union(net).union(featureImpl.subtracting(["NuumAgent"])).union(features)
        case "NuumTools":
            return ui.union(secret).union(net).union(featureImpl.subtracting(["NuumTools"]))
        case "NuumSecurity":
            return ui.union(net).union(featureImpl.subtracting(["NuumSecurity"]))
        case "NuumModel":
            return ui.union(featureImpl.subtracting(["NuumModel"]))
        case "NuumStorage":
            return ui.union(secret).union(net).union(featureImpl.subtracting(["NuumStorage"]))
        case let name where name.hasPrefix("NuumFeature"):
            return featureImpl.union(net)
        case "NuumAcceptance":
            return featureImpl.union(net)
        default:
            return featureImpl.union(ui).union(secret).union(net)
        }
    }

    static func importViolations(package: String, source: String) -> [String] {
        var violations: [String] = []
        let banned = bannedImports(package)
        let allowed = allowedEdges[package] ?? []
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let code = codePortion(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if code.isEmpty { continue }
            if let module = importedModule(code) {
                if banned.contains(module) || thirdPartyModules.contains(module) {
                    violations.append("line \(index + 1) imports \(module)")
                } else if module.hasPrefix("Nuum"), module != package, !allowed.contains(module) {
                    violations.append("line \(index + 1) imports \(module)")
                }
            }
            for token in banned where token == "URLSession" || token == "Network" || token == "UIKit" || token == "SwiftUI" || token == "Security" {
                if containsToken(token, in: code) {
                    violations.append("line \(index + 1) uses \(token)")
                }
            }
        }
        return violations
    }

    static func selfCheck() -> [String] {
        var failures: [String] = []
        func expectViolation(_ label: String, _ found: [String]) {
            if found.isEmpty { failures.append("self-check allowed \(label)") }
        }
        func expectClean(_ label: String, _ found: [String]) {
            if !found.isEmpty { failures.append("self-check rejected \(label): \(found.joined(separator: "; "))") }
        }

        expectViolation(
            "feature -> kernel import",
            importViolations(package: "NuumFeatureShell", source: "import NuumKernel\n")
        )
        expectClean(
            "feature -> contracts import",
            importViolations(package: "NuumFeatureShell", source: "import NuumContracts\n")
        )
        expectViolation(
            "protocol SwiftUI",
            importViolations(package: "NuumProtocol", source: "import SwiftUI\n")
        )
        expectClean(
            "protocol Foundation",
            importViolations(package: "NuumProtocol", source: "import Foundation\n")
        )
        expectViolation(
            "kernel URLSession",
            importViolations(package: "NuumKernel", source: "let session = URLSession.shared\n")
        )
        expectViolation(
            "agent URLSession",
            importViolations(package: "NuumAgent", source: "URLSession.shared.dataTask(with: url)\n")
        )
        expectViolation(
            "contracts Security",
            importViolations(package: "NuumContracts", source: "import Security\n")
        )
        expectClean(
            "security may import Security",
            importViolations(package: "NuumSecurity", source: "import Security\nimport NuumContracts\n")
        )
        expectViolation(
            "security -> kernel",
            importViolations(package: "NuumSecurity", source: "import NuumKernel\n")
        )
        expectViolation(
            "tools Security",
            importViolations(package: "NuumTools", source: "import Security\n")
        )
        expectClean(
            "model may use URLSession",
            importViolations(package: "NuumModel", source: "import Foundation\nlet session = URLSession.shared\n")
        )
        expectViolation(
            "remote package",
            manifestViolations(
                package: "NuumProtocol",
                manifest: ".package(url: \"https://github.com/example/sdk.git\", from: \"1.0.0\")\n"
            )
        )
        expectViolation(
            "protocol depends on contracts",
            manifestViolations(package: "NuumProtocol", manifest: ".package(path: \"../NuumContracts\")\n")
        )
        expectClean(
            "contracts depends on protocol",
            manifestViolations(package: "NuumContracts", manifest: ".package(path: \"../NuumProtocol\")\n")
        )
        expectViolation(
            "feature depends on kernel",
            manifestViolations(package: "NuumFeatureShell", manifest: ".package(path: \"../NuumKernel\")\n")
        )
        expectViolation(
            "acceptance depends on a package",
            manifestViolations(package: "NuumAcceptance", manifest: ".package(path: \"../NuumContracts\")\n")
        )
        expectViolation(
            "datadog import",
            importViolations(package: "NuumFeatureSettings", source: "import Datadog\n")
        )
        if edgeAllowed("NuumFeatureShell", "NuumKernel") {
            failures.append("self-check allowed feature -> kernel edge")
        }
        if !edgeAllowed("NuumContracts", "NuumProtocol") || !edgeAllowed("NuumSecurity", "NuumContracts") {
            failures.append("self-check rejected a legal edge")
        }
        if edgeAllowed("NuumProtocol", "NuumContracts") || edgeAllowed("NuumAcceptance", "NuumKernel") {
            failures.append("self-check allowed an illegal edge")
        }
        return failures
    }

    private static func projectViolations(_ iosRoot: URL) throws -> [String] {
        var violations: [String] = []
        let project = try String(
            contentsOf: iosRoot.appendingPathComponent("Nuum.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let required = [
            "PRODUCT_BUNDLE_IDENTIFIER = com.nuum;",
            "IPHONEOS_DEPLOYMENT_TARGET = 26.0;",
            "SWIFT_VERSION = 6.0;",
            "SWIFT_STRICT_CONCURRENCY = complete;",
            "SDKROOT = iphoneos;",
            "SUPPORTS_MACCATALYST = NO;",
            "GENERATE_INFOPLIST_FILE = NO;",
            "INFOPLIST_FILE = App/Info.plist;",
            "CODE_SIGN_ENTITLEMENTS = App/Nuum.entitlements;",
            "TARGETED_DEVICE_FAMILY = \"1,2\";",
        ]
        for snippet in required where !project.contains(snippet) {
            violations.append("project is missing \(snippet)")
        }
        if project.contains("SUPPORTS_MACCATALYST = YES") || project.contains("SDKROOT = macosx") {
            violations.append("project builds a Mac target")
        }
        let bundleIDs = captures(#"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);"#, in: project)
        if bundleIDs.isEmpty || bundleIDs.contains(where: { $0 != "com.nuum" }) {
            violations.append("bundle identifier must be com.nuum, found \(bundleIDs)")
        }
        let linkedNames = Set(
            captures(#"productName = ([A-Za-z0-9]+);"#, in: section(project, "XCSwiftPackageProductDependency"))
        )
        if linkedNames != appLinkedProducts {
            violations.append("app links \(linkedNames.sorted()), expected \(appLinkedProducts.sorted())")
        }
        for package in allowedEdges.keys where !project.contains("relativePath = Packages/\(package);") {
            violations.append("project is missing local package \(package)")
        }
        if project.contains("productName = NuumAcceptance") {
            violations.append("app target links NuumAcceptance")
        }

        let info = try String(contentsOf: iosRoot.appendingPathComponent("App/Info.plist"), encoding: .utf8)
        let forbiddenInfo = [
            "UIBackgroundModes",
            "UIFileSharingEnabled",
            "LSSupportsOpeningDocumentsInPlace",
            "NSAllowsArbitraryLoads",
            "NSAllowsLocalNetworking",
            "NSExceptionDomains",
            "NSAppTransportSecurity",
            "NSUserTrackingUsageDescription",
            "remote-notification",
            "aps-environment",
        ]
        for key in forbiddenInfo where info.contains(key) {
            violations.append("Info.plist contains \(key)")
        }
        if !info.contains("<string>Nuum</string>") {
            violations.append("Info.plist must name the app Nuum")
        }

        let privacy = try String(
            contentsOf: iosRoot.appendingPathComponent("App/PrivacyInfo.xcprivacy"),
            encoding: .utf8
        )
        if !privacy.contains("<key>NSPrivacyTracking</key>") || !privacy.contains("<false/>") {
            violations.append("Privacy manifest must declare tracking false")
        }
        if privacy.contains("NSPrivacyTrackingDomain") {
            violations.append("Privacy manifest declares tracking domains")
        }

        let entitlements = try String(
            contentsOf: iosRoot.appendingPathComponent("App/Nuum.entitlements"),
            encoding: .utf8
        )
        if entitlements.contains("<key>") {
            violations.append("entitlements must stay empty")
        }
        for key in ["icloud", "application-groups", "aps-environment", "keychain-access-groups"]
            where entitlements.lowercased().contains(key) {
            violations.append("entitlements contain \(key)")
        }

        let rootView = try String(contentsOf: iosRoot.appendingPathComponent("App/RootView.swift"), encoding: .utf8)
        if !rootView.hasPrefix("// OWNED BY WP-12 AFTER SCAFFOLD\n") {
            violations.append("RootView.swift must start with OWNED BY WP-12 AFTER SCAFFOLD")
        }
        if !rootView.contains("Text(\"Nuum\")") {
            violations.append("RootView must show the name Nuum")
        }
        return violations
    }

    private static func isolationViolations(_ iosRoot: URL) throws -> [String] {
        var violations: [String] = []
        let workspaceURL = iosRoot.deletingLastPathComponent().appendingPathComponent("pnpm-workspace.yaml")
        let workspace = try String(contentsOf: workspaceURL, encoding: .utf8)
        if workspace.contains("ios") {
            violations.append("pnpm-workspace.yaml must not list the iOS tree")
        }
        let forbiddenText = ["secrets.bin", "noBackupFilesDir", "safeStorage"]
        let packagesRoot = iosRoot.appendingPathComponent("Packages")
        for name in try packageDirectories(packagesRoot) where name != "NuumContracts" {
            let sources = packagesRoot.appendingPathComponent(name).appendingPathComponent("Sources")
            for file in try swiftFiles(in: sources) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for token in forbiddenText where text.contains(token) {
                    violations.append("\(name) mentions \(token)")
                }
            }
        }
        let app = iosRoot.appendingPathComponent("App")
        if FileManager.default.fileExists(atPath: app.path) {
            for file in try swiftFiles(in: app) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for token in forbiddenText where text.contains(token) {
                    violations.append("App mentions \(token)")
                }
                violations += appImportViolations(text).map { "App \($0)" }
            }
        }
        let enumerator = FileManager.default.enumerator(
            at: iosRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        while let item = enumerator?.nextObject() as? URL {
            let filename = item.lastPathComponent
            if filename == ".build" || filename == ".swiftpm" || filename == "DerivedData" || filename == "xcuserdata" {
                enumerator?.skipDescendants()
                continue
            }
            if filename == "secrets.bin" || filename == ".env" || filename.hasPrefix(".env.") {
                violations.append("unexpected file \(filename)")
            }
        }
        return violations
    }

    private static func appImportViolations(_ source: String) -> [String] {
        var violations: [String] = []
        let banned: Set<String> = thirdPartyModules.union(["Security", "URLSession", "UIKit", "Network", "NuumAcceptance"])
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let code = codePortion(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if code.isEmpty { continue }
            if let module = importedModule(code), banned.contains(module) {
                violations.append("line \(index + 1) imports \(module)")
            }
            for token in ["URLSession", "UIKit", "Security"] where containsToken(token, in: code) {
                violations.append("line \(index + 1) uses \(token)")
            }
        }
        return violations
    }

    private static func packageDirectories(_ packagesRoot: URL) throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: packagesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        return contents.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let manifest = url.appendingPathComponent("Package.swift")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            return url.lastPathComponent
        }
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if item.pathExtension == "swift" {
                files.append(item)
            }
        }
        return files
    }

    private static func declaredEdges(_ manifest: String) -> [String] {
        captures(#"\.package\(\s*path:\s*"([^"]+)""#, in: manifest).map { path in
            (path as NSString).lastPathComponent
        }
    }

    private static func section(_ text: String, _ name: String) -> String {
        guard let start = text.range(of: "/* Begin \(name) section */"),
              let end = text.range(of: "/* End \(name) section */"),
              start.upperBound <= end.lowerBound
        else { return "" }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let slice = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[slice])
        }
    }

    private static func importedModule(_ code: String) -> String? {
        var rest = code
        if rest.hasPrefix("@testable") {
            rest = String(rest.dropFirst("@testable".count)).trimmingCharacters(in: .whitespaces)
        }
        guard rest.hasPrefix("import ") else { return nil }
        rest = String(rest.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
        for kind in ["struct ", "class ", "enum ", "protocol ", "typealias ", "func ", "let ", "var "]
            where rest.hasPrefix(kind) {
            rest = String(rest.dropFirst(kind.count))
        }
        let module = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return module.isEmpty ? nil : String(module)
    }

    private static func containsToken(_ token: String, in code: String) -> Bool {
        code.range(of: "\\b\(token)\\b", options: .regularExpression) != nil
    }

    private static func codePortion(_ line: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
                result.append(character)
            } else if character == "/" {
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "/" {
                    break
                }
                result.append(character)
            } else {
                result.append(character)
            }
            index = line.index(after: index)
        }
        return result
    }
}
