import Foundation
import Testing

@testable import ShortcutCore

@Test func structuralDiffPreservesTypesAndEscapesPaths() throws {
    let before = WorkflowProject(
        name: "Before",
        workflow: .dictionary([
            "WFWorkflowActions": .array([]), "a/b~c": .real(-0.0), "removed": .data(Data([1])),
        ]))
    let after = WorkflowProject(
        name: "After",
        workflow: .dictionary([
            "WFWorkflowActions": .array([]), "a/b~c": .real(0.0), "added": .bool(true),
        ]))
    let result = try WorkflowDiffer.compare(before, after)
    #expect(!result.equal)
    #expect(result.changes.map(\.path) == ["/name", "/workflow/a~1b~0c", "/workflow/added", "/workflow/removed"])
    #expect(result.changes[1].before == .real(-0.0))
    #expect(result.changes[2].kind == "added")
    #expect(result.changes[3].kind == "removed")
    #expect(try WorkflowDiffer.compare(before, before).equal)
    #expect(
        try WorkflowDiffer.compare(
            before, WorkflowProject(name: "Other", workflow: before.workflow), workflowOnly: true
        ).equal)
}

@Test func structuralDiffDoesNotNormalizeDictionaryKeys() throws {
    let before = WorkflowProject(
        name: "Unicode", workflow: .dictionary(["WFWorkflowActions": .array([]), "é": .string("same")]))
    let after = WorkflowProject(
        name: "Unicode", workflow: .dictionary(["WFWorkflowActions": .array([]), "e\u{0301}": .string("same")]))
    let result = try WorkflowDiffer.compare(before, after)
    #expect(!result.equal)
    #expect(result.changes.count == 2)
    #expect(Set(result.changes.map(\.kind)) == ["added", "removed"])
}

@Test func structuralDiffIncludesTestsAndOrderedActions() throws {
    let before = try ProjectTemplates.make(name: "Example", template: "text")
    var after = before
    after.tests[0].expectedOutput = "different"
    #expect(try WorkflowDiffer.compare(before, after).changes.contains { $0.path == "/tests/0/expectedOutput" })
    after = before
    after.workflow = .dictionary(["WFWorkflowActions": .array([])])
    #expect(try WorkflowDiffer.compare(before, after).changes.contains { $0.kind == "removed" })
}

@Test func discoveryDistinguishesCatalogMetadataAndObservedActions() throws {
    let catalog = ActionDiscovery.catalog(query: "gettext")
    #expect(catalog.count == 1)
    #expect(catalog[0].kind == "compatibility")
    let data = Data(
        """
        {"actions":{"Example":{"identifier":"Example","title":{"key":"Example Title"},"parameters":[{"name":"input"}],"isDiscoverable":false,"future":null}}}
        """.utf8)
    let metadata = try ActionDiscovery.metadata(data, source: "synthetic")
    #expect(metadata.count == 1)
    #expect(metadata[0].kind == "app-intent")
    #expect(metadata[0].title == "Example Title")
    #expect(metadata[0].parameters == ["input"])
    #expect(metadata[0].metadataJSON?.contains("future") == true)
    #expect(throws: ToolFailure.self) { try ActionDiscovery.metadata(Data("{}".utf8), source: "bad") }
    let project = WorkflowProject(
        name: "Observed",
        workflow: .dictionary([
            "WFWorkflowActions": .array([
                .dictionary([
                    "WFWorkflowActionIdentifier": .string("example.future"),
                    "WFWorkflowActionParameters": .dictionary(["x": .integer(1)]),
                ])
            ])
        ]))
    #expect(ActionDiscovery.observed(project, source: "fixture")[0].parameters == ["x"])
}

@Test func installedListingRetainsNamesAndRejectsAmbiguity() throws {
    let identifier = "00000000-0000-4000-8000-000000000001"
    let rows = try ShortcutListing.parse(Data("Name (with parentheses) (\(identifier))\n中文 (\(identifier))\n".utf8))
    #expect(rows.map(\.name) == ["Name (with parentheses)", "中文"])
    #expect(rows[0].identifier == identifier)
    #expect(try ShortcutListing.parse(Data()).isEmpty)
    #expect(throws: ToolFailure.self) { try ShortcutListing.parse(Data("Unrecognized output\n".utf8)) }
}

@Test func watchDebouncesContentAndRetriesAfterFailure() {
    var state = WatchState(debounce: 0.5)
    let observed1 = state.observe(Data("a".utf8), at: 0)
    #expect(observed1)
    let observed2 = !state.observe(Data("a".utf8), at: 1)
    #expect(observed2)
    let observed3 = !state.observe(Data("b".utf8), at: 2)
    #expect(observed3)
    let observed4 = !state.observe(Data("c".utf8), at: 2.2)
    #expect(observed4)
    let observed5 = !state.observe(Data("c".utf8), at: 2.5)
    #expect(observed5)
    let observed6 = state.observe(Data("c".utf8), at: 2.8)
    #expect(observed6)
    let observed7 = !state.observe(Data("c".utf8), at: 3)
    #expect(observed7)
    state.invalidate()
    let observed8 = !state.observe(Data("c".utf8), at: 4)
    #expect(observed8)
    let observed9 = state.observe(Data("c".utf8), at: 4.6)
    #expect(observed9)
}
