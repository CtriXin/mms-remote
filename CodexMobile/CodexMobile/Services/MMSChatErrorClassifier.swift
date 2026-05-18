// FILE: MMSChatErrorClassifier.swift
// Purpose: Classifies MMSChat failures into stable user-facing recovery messages.
// Layer: Service
// Exports: MMSChatErrorCategory, MMSChatErrorClassifier
// Depends on: Foundation, CodexServiceError, RPCError, LocalizationManager

import Foundation

enum MMSChatErrorCategory {
    case bridgeMismatch
    case disconnected
    case other
}

struct MMSChatErrorClassifier {
    static func classify(_ error: Error) -> MMSChatErrorCategory {
        if isBridgeMismatch(error) {
            return .bridgeMismatch
        }
        if isDisconnected(error) {
            return .disconnected
        }
        return .other
    }

    static func localizedMessage(for error: Error) -> String {
        switch classify(error) {
        case .bridgeMismatch:
            return LocalizationManager.shared.localized("mmschat.error_bridge_mismatch")
        case .disconnected:
            return LocalizationManager.shared.localized("mmschat.error_connection_lost")
        case .other:
            return LocalizationManager.shared.localized("mmschat.error_generic")
        }
    }
}

private extension MMSChatErrorClassifier {
    static func isBridgeMismatch(_ error: Error) -> Bool {
        if let rpcError = rpcError(from: error), rpcError.code == -32601 {
            return true
        }

        let fragments = normalizedTextFragments(for: error)
        if fragments.contains(where: isBridgeMismatchFragment) {
            return true
        }

        return hasCombinedBridgeMismatchHint(in: fragments)
    }

    static func isDisconnected(_ error: Error) -> Bool {
        if let serviceError = error as? CodexServiceError,
           case .disconnected = serviceError {
            return true
        }

        guard !isBridgeMismatch(error) else {
            return false
        }

        return normalizedTextFragments(for: error).contains(where: isDisconnectedFragment)
    }

    static func rpcError(from error: Error) -> RPCError? {
        if let rpcError = error as? RPCError {
            return rpcError
        }
        guard let serviceError = error as? CodexServiceError,
              case .rpcError(let rpcError) = serviceError else {
            return nil
        }
        return rpcError
    }

    static func normalizedTextFragments(for error: Error) -> [String] {
        var fragments: [String] = []

        if let rpcError = rpcError(from: error) {
            fragments.append(rpcError.message)
            if let data = rpcError.data {
                fragments.append(contentsOf: flattenJSONValue(data))
            }
        }

        if let serviceError = error as? CodexServiceError {
            switch serviceError {
            case .invalidServerURL(let value), .invalidInput(let value), .invalidResponse(let value):
                fragments.append(value)
            case .disconnected:
                fragments.append(serviceError.localizedDescription)
            case .rpcError, .encodingFailed, .noPendingApproval:
                break
            }
        }

        let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localizedDescription.isEmpty {
            fragments.append(localizedDescription)
        }

        return fragments
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    static func flattenJSONValue(_ value: JSONValue) -> [String] {
        switch value {
        case .string(let string):
            return [string]
        case .integer(let integer):
            return [String(integer)]
        case .double(let double):
            return [String(double)]
        case .bool(let bool):
            return [String(bool)]
        case .object(let object):
            return object.flatMap { key, nestedValue in
                [key] + flattenJSONValue(nestedValue)
            }
        case .array(let array):
            return array.flatMap(flattenJSONValue)
        case .null:
            return []
        }
    }

    static func isBridgeMismatchFragment(_ fragment: String) -> Bool {
        let hasUnsupportedMethodMarker = fragment.contains("unsupported_method")
            || fragment.contains("unsupported mmschat method")
            || fragment.contains("method not found")
            || fragment.contains("unsupported method")
        let hasMMSChatMethodMarker = fragment.contains("mmschat/")

        return hasUnsupportedMethodMarker || (hasMMSChatMethodMarker && hasBridgeMismatchHint(fragment))
    }

    static func hasCombinedBridgeMismatchHint(in fragments: [String]) -> Bool {
        let hasMMSChatMethodMarker = fragments.contains { $0.contains("mmschat/") }
        let hasHint = fragments.contains(where: hasBridgeMismatchHint)

        return hasMMSChatMethodMarker && hasHint
    }

    static func hasBridgeMismatchHint(_ fragment: String) -> Bool {
        fragment.contains("unsupported")
            || fragment.contains("missing")
            || fragment.contains("not found")
            || fragment.contains("not supported")
            || fragment.contains("unknown method")
            || fragment.contains("not implemented")
    }

    static func isDisconnectedFragment(_ fragment: String) -> Bool {
        fragment.contains("connection unavailable")
            || fragment.contains("connection lost")
            || fragment.contains("not connected")
            || fragment.contains("connection timed out")
            || fragment.contains("timed out")
            || fragment.contains("websocket not connected")
            || fragment.contains("session unavailable")
    }
}
