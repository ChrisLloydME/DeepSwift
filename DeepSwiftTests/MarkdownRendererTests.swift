//
//  MarkdownRendererTests.swift
//  DeepSwiftTests
//

import Foundation
import MarkdownView
import Testing
@testable import DeepSwift

@MainActor
struct MarkdownRendererTests {
    @Test("The streaming source is stable for one assistant attempt")
    func stableSource() throws {
        let coordinator = MarkdownStreamCoordinator()
        coordinator.synchronize(attemptID: "attempt-1", text: "Hello")
        let first = try #require(coordinator.source(for: "attempt-1"))
        #expect(first.text == "Hello")

        coordinator.synchronize(attemptID: "attempt-1", text: "Hello **world**")
        let second = try #require(coordinator.source(for: "attempt-1"))
        #expect(first === second)
        #expect(second.text == "Hello **world**")
    }

    @Test("Finishing releases the active source")
    func finishReleasesSource() throws {
        let coordinator = MarkdownStreamCoordinator()
        coordinator.synchronize(attemptID: "attempt-1", text: "Partial")
        let source = try #require(coordinator.source(for: "attempt-1"))

        coordinator.synchronize(attemptID: nil, text: "")

        #expect(coordinator.source(for: "attempt-1") == nil)
        #expect(source.text == "Partial")
    }

    @Test("Relative Markdown links become Host-scoped workspace paths")
    func relativeLinkPath() throws {
        let url = try #require(URL(string: "Sources/App.swift#L10", relativeTo: MarkdownRouting.baseURL))
        #expect(url.scheme == "dsh-file")
        #expect(MarkdownRouting.workspacePath(from: url) == "Sources/App.swift")
    }

    @Test("A new attempt replaces the previous source")
    func attemptSwitch() throws {
        let coordinator = MarkdownStreamCoordinator()
        coordinator.synchronize(attemptID: "attempt-1", text: "First")
        let first = try #require(coordinator.source(for: "attempt-1"))

        coordinator.synchronize(attemptID: "attempt-2", text: "Second")

        #expect(coordinator.source(for: "attempt-1") == nil)
        let second = try #require(coordinator.source(for: "attempt-2"))
        #expect(first !== second)
        #expect(second.text == "Second")
    }
}
