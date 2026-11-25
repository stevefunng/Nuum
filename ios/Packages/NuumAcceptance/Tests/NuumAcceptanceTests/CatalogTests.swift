import Foundation
import Testing

@testable import NuumAcceptance

@Test func catalogListsScenariosOneThroughTwelveAsNotExecuted() {
    let scenarios = AcceptanceScenarios.all
    #expect(scenarios.map(\.number) == Array(1...12))
    #expect(Set(scenarios.map(\.title)).count == 12)
    #expect(scenarios.allSatisfy { $0.execution == .notExecutedOnMac })
    #expect(NuumAcceptanceModule.baselineCommit == "061033920588ca502d5874e3451f2e9c5878cc54")
    #expect(NuumAcceptanceModule.xcodeVersion == "27.2")
    #expect(NuumAcceptanceModule.xcodeBuild == "27B52")
}

@Test func checklistMatchesTheCatalogAndStaysUnrun() throws {
    let root = try RepositoryLayout.root()
    let checklist = try RepositoryLayout.text(root, "ios/docs/acceptance/SCENARIOS.md")
    let readme = try RepositoryLayout.text(root, "ios/docs/acceptance/README.md")
    for scenario in AcceptanceScenarios.all {
        let heading = "## \(scenario.number). \(scenario.title)"
        #expect(checklist.contains(heading), "missing \(heading)")
    }
    let sections = scenarioSections(checklist)
    #expect(sections.count == 12)
    for number in 1...12 {
        let section = try #require(sections[number])
        #expect(section.contains("**Simulator.** Not executed on a Mac."))
    }
    #expect(checklist.contains("## Known leftovers"))
    for phrase in leftoverPhrases {
        #expect(checklist.contains(phrase), "leftovers missing \(phrase)")
    }
    #expect(readme.contains("Xcode 27.2"))
    #expect(readme.contains(AcceptanceFixture.fakeModelArgument))
    #expect(readme.contains("Not executed on a Mac"))
    #expect(readme.contains("does not complete WP-13"))
}

@Test func fixturesMatchTheDebugRouterContract() {
    #expect(AcceptanceFixture.plantedKey == "sk-acceptance-not-a-real-key")
    #expect(AcceptanceFixture.plantedKey.hasPrefix("sk-acceptance-"))
    #expect(AcceptanceFixture.visibleReply == "Visible from SendMessage")
    #expect(AcceptanceFixture.scratchpad == "scratchpad-not-the-body")
    #expect(AcceptanceFixture.noteText == "accepted-note")
    #expect(AcceptanceFixture.laneCard == "Lane card")
    #expect(AcceptanceFixture.writeCue == "acceptance-write")
    #expect(AcceptanceFixture.sealedCue == "acceptance-secrets")
    #expect(AcceptanceFixture.sealedJSONName == "secrets.json")
    #expect(AcceptanceFixture.fakeModelArgument == "nuum.fakeModel=router")
    #expect(AcceptanceFixture.fakeModelEnvironment == "NUUM_FAKE_MODEL")
    #expect(AcceptanceFixture.missingKeyCode == 2004)
    #expect(AcceptanceFixture.attachmentCode == 1007)
    #expect(AcceptanceFixture.maxAttachments == 5)
    #expect(AcceptanceFixture.maxAttachmentBytes == 10 * 1024 * 1024)
    #expect(AcceptanceFixture.maxAttachmentTotalBytes == 20 * 1024 * 1024)
    #expect(AcceptanceFixture.bundleID == "com.nuum")
    #expect(!AcceptanceFixture.manualTaskLabels.isEmpty)
}

private let leftoverPhrases = [
    "NuumSecurityTests",
    "workId",
    "activeRequest",
    "roomInputs",
    "executionId",
    "externalGrants",
    "ShellSelection",
]

private func scenarioSections(_ markdown: String) -> [Int: String] {
    var sections: [Int: String] = [:]
    for part in markdown.components(separatedBy: "\n## ") {
        let header = part.prefix(while: { $0 != "\n" })
        guard let dot = header.firstIndex(of: ".") else { continue }
        let numberText = header[..<dot].trimmingCharacters(in: .whitespaces)
        guard let number = Int(numberText), (1...12).contains(number) else { continue }
        sections[number] = String(part)
    }
    return sections
}
