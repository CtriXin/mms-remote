// FILE: MMSChatErrorClassifierTests.swift
// Purpose: Verifies MMSChat bridge-mismatch and disconnect classification stays stable.
// Layer: Unit Test
// Exports: MMSChatErrorClassifierTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

final class MMSChatErrorClassifierTests: XCTestCase {
    func testRPCMethodNotFoundIsBridgeMismatch() {
        let error = CodexServiceError.rpcError(
            RPCError(code: -32601, message: "Method not found")
        )

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .bridgeMismatch)
        XCTAssertEqual(
            MMSChatErrorClassifier.localizedMessage(for: error),
            LocalizationManager.shared.localized("mmschat.error_bridge_mismatch")
        )
    }

    func testUnsupportedMMSChatDataIsBridgeMismatch() {
        let error = RPCError(
            code: -32000,
            message: "Unsupported MMSChat method",
            data: .object([
                "errorCode": .string("unsupported_method"),
                "method": .string("mmschat/send"),
            ])
        )

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .bridgeMismatch)
    }


    func testSplitMethodAndReasonDataIsBridgeMismatch() {
        let error = RPCError(
            code: -32000,
            message: "Bridge rejected request",
            data: .object([
                "method": .string("mmschat/list"),
                "reason": .string("not supported"),
            ])
        )

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .bridgeMismatch)
    }

    func testSplitUnsupportedMMSChatDoesNotClassifyAsDisconnected() {
        let error = CodexServiceError.rpcError(
            RPCError(
                code: -32000,
                message: "Bridge rejected request",
                data: .object([
                    "method": .string("mmschat/list"),
                    "reason": .string("not supported"),
                ])
            )
        )

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .bridgeMismatch)
    }

    func testDisconnectedServiceErrorIsDisconnected() {
        XCTAssertEqual(MMSChatErrorClassifier.classify(CodexServiceError.disconnected), .disconnected)
    }

    func testTimeoutMessageIsDisconnected() {
        let error = CodexServiceError.invalidInput("MMSChat detail timed out while contacting the Mac bridge.")

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .disconnected)
        XCTAssertEqual(
            MMSChatErrorClassifier.localizedMessage(for: error),
            LocalizationManager.shared.localized("mmschat.error_connection_lost")
        )
    }

    func testOtherErrorsUseGenericMessage() {
        let error = CodexServiceError.invalidResponse("Unexpected payload")

        XCTAssertEqual(MMSChatErrorClassifier.classify(error), .other)
        XCTAssertEqual(
            MMSChatErrorClassifier.localizedMessage(for: error),
            LocalizationManager.shared.localized("mmschat.error_generic")
        )
    }
}
