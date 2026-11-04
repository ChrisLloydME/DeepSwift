//
//  AppErrorPresentationTests.swift
//  DeepSwiftTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DeepSwift

@Suite("Error presentation")
@MainActor
struct AppErrorPresentationTests {
    @Test("A raw configuration document never reaches the alert")
    func rawConfigurationIsSuppressed() throws {
        let model = AppModel(bridge: MockBridgeService())
        let payload = """
        {"type":"configuration","meta":{"schemaVersion":3},"refs":[],"providers":{"opencode-go":{"apiKeyEnv":"DEEPSEEK_API_KEY","models":[{"contextWindow":128000}]}}}
        """
        model.errorMessage = payload

        let presentation = try #require(model.errorPresentation)
        #expect(!presentation.title.contains("{"))
        #expect(!presentation.message.contains("{"))
        #expect(!presentation.alertMessage.contains("apiKeyEnv"))
        #expect(!presentation.diagnosticText.contains("contextWindow"))
        #expect(presentation.message.count <= 322)
        #expect(presentation.technicalDetails?.count ?? 0 <= 8_000)
        #expect(model.errorMessage == presentation.message)
    }

    @Test("Serialized payloads are removed from technical details")
    func detailsPayloadRemoved() throws {
        let payload = #"{"type":"configuration","apiKeyEnv":"DEEPSEEK_API_KEY","models":[{"contextWindow":128000}]}"#
        let presentation = AppErrorPresentationFactory.make(
            title: "Runtime response error",
            message: "The response could not be read.",
            code: "bridge/frame-decode",
            action: "read a response",
            details: "Decoder: unexpected type\n" + payload
        )
        #expect(presentation.technicalDetails?.contains("apiKeyEnv") == false)
        #expect(presentation.technicalDetails?.contains("contextWindow") == false)
        #expect(presentation.technicalDetails?.contains("Decoder: unexpected type") == true)
    }

    @Test("Very long explanations are bounded without losing a short prefix")
    func longExplanationBounded() throws {
        let model = AppModel(bridge: MockBridgeService())
        model.errorMessage = "The request failed: " + String(repeating: "detail ", count: 2_000)
        let presentation = try #require(model.errorPresentation)
        #expect(presentation.message.count <= 322)
        #expect(presentation.alertMessage.count < 700)
    }

    @Test("The details sheet has a bounded native layout")
    func detailsSheetBounds() {
        let error = AppErrorPresentationFactory.make(
            title: "A bounded diagnostic",
            message: "A short explanation.",
            recovery: "Try again.",
            code: "test/error",
            action: "verify layout",
            details: "A short diagnostic block."
        )
        let hostingView = NSHostingView(rootView: ErrorDetailsView(error: error))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 1_200)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        #expect(size.width <= 681)
        #expect(size.height <= 561)
        #expect(size.width >= 420)
        #expect(size.height >= 280)
    }

    @Test("Short server explanations are preserved")
    func shortExplanation() throws {
        let model = AppModel(bridge: MockBridgeService())
        model.errorMessage = "The selected model is not available in this session."

        let presentation = try #require(model.errorPresentation)
        #expect(presentation.message == "The selected model is not available in this session.")
        #expect(presentation.title == "DeepSwift couldn’t complete that action")
    }

    @Test("Credential-shaped values are redacted from every diagnostic surface")
    func secretRedaction() throws {
        let model = AppModel(bridge: MockBridgeService())
        let secret = "sk-test-supersecret-123456"
        model.errorMessage = "The provider rejected \(secret) while saving the model."

        let presentation = try #require(model.errorPresentation)
        #expect(!presentation.alertMessage.contains(secret))
        #expect(!presentation.diagnosticText.contains(secret))
        #expect(presentation.alertMessage.contains("••••"))
    }

    @Test("Protocol failures use a concise title and bounded details")
    func protocolFailure() throws {
        let model = AppModel(bridge: MockBridgeService())
        model.present(
            error: BridgeClientError.protocolViolation(String(repeating: "x", count: 20_000)),
            action: "read a response from the local runtime"
        )

        let presentation = try #require(model.errorPresentation)
        #expect(presentation.title.contains("couldn’t read"))
        #expect(presentation.message.count < 400)
        #expect(presentation.technicalDetails?.count ?? 0 < 8_100)
        #expect(presentation.code == "bridge/protocol")
        #expect(presentation.recovery?.isEmpty == false)
    }

    @Test("Repeated identical failures are coalesced until the window expires")
    func repeatedFailureCoalescing() {
        let model = AppModel(bridge: MockBridgeService())
        model.errorMessage = "The runtime did not answer."
        #expect(model.errorPresentation != nil)

        model.clearError()
        model.errorMessage = "The runtime did not answer."
        #expect(model.errorPresentation == nil)

        model.errorMessage = "A different runtime failure."
        #expect(model.errorPresentation != nil)
    }

    @Test("Diagnostic copy contains only sanitized fields")
    func diagnosticCopy() throws {
        let model = AppModel(bridge: MockBridgeService())
        let secret = "Bearer abcdefghijklmnopqrstuvwxyz"
        model.errorMessage = "Authorization failed. \(secret) {\"apiKeyEnv\":\"DEEPSEEK_API_KEY\"}"
        let presentation = try #require(model.errorPresentation)

        #expect(!presentation.diagnosticText.contains(secret))
        #expect(!presentation.diagnosticText.contains("apiKeyEnv"))
        #expect(presentation.diagnosticText.contains(presentation.diagnosticID))
    }
}
