#!/usr/bin/env swift

import CryptoKit
import Foundation

enum CryptoError: Error, CustomStringConvertible {
    case invalidInput(String)

    var description: String {
        switch self {
        case .invalidInput(let message): return message
        }
    }
}

func decode(_ value: Any?, name: String) throws -> Data {
    guard let text = value as? String else {
        throw CryptoError.invalidInput("Missing \(name).")
    }
    var base64 = text.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64) else {
        throw CryptoError.invalidInput("Invalid Base64URL in \(name).")
    }
    return data
}

func encode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let object = try JSONSerialization.jsonObject(with: input) as? [String: Any],
          let action = object["action"] as? String else {
        throw CryptoError.invalidInput("Expected a JSON object with an action.")
    }

    let output: [String: Any]
    switch action {
    case "derive":
        let seed = try decode(object["privateKey"], name: "privateKey")
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        output = ["publicKey": encode(key.publicKey.rawRepresentation)]
    case "sign":
        let seed = try decode(object["privateKey"], name: "privateKey")
        let message = try decode(object["message"], name: "message")
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        output = ["signature": encode(try key.signature(for: message))]
    case "verify":
        let publicKey = try decode(object["publicKey"], name: "publicKey")
        let message = try decode(object["message"], name: "message")
        let signature = try decode(object["signature"], name: "signature")
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        output = ["valid": key.isValidSignature(signature, for: message)]
    default:
        throw CryptoError.invalidInput("Unsupported action: \(action)")
    }

    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
} catch {
    FileHandle.standardError.write(Data("fmo_crypto: \(error)\n".utf8))
    exit(1)
}
