import CryptoKit
import Foundation
import Security

enum OpenNoteError: LocalizedError {
    case missingClientID
    case invalidCallback
    case authStateMismatch
    case tokenUnavailable
    case graph(String)
    case unsupported(String)
    case selectionRequired(String)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Add your Microsoft client ID in Settings before signing in."
        case .invalidCallback:
            "The Microsoft sign-in callback was invalid."
        case .authStateMismatch:
            "The sign-in response did not match the current login session."
        case .tokenUnavailable:
            "No valid Microsoft token is available. Sign in again."
        case .graph(let message):
            message
        case .unsupported(let message):
            message
        case .selectionRequired(let message):
            message
        case .fileSystem(let message):
            message
        }
    }
}

enum PKCE {
    static func verifier(byteCount: Int = 32) -> String {
        var data = Data(count: byteCount)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, byteCount, $0.baseAddress!) }
        return base64URLEncoded(data)
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum Filename {
    private static let invalid = CharacterSet(charactersIn: #"/\?%*|"<>"#)
        .union(.controlCharacters)
        .union(.newlines)

    static func safe(_ raw: String, fallback: String = "Untitled") -> String {
        let replaced = raw.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        let cleaned = String(replaced).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func unique(in directory: URL, name: String) -> URL {
        let safeName = safe(name, fallback: "Attachment")
        var candidate = directory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        var index = 2
        repeat {
            candidate = numbered(in: directory, name: safeName, occurrence: index)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    static func numbered(in directory: URL, name: String, occurrence: Int) -> URL {
        let safeName = safe(name, fallback: "Attachment")
        guard occurrence > 1 else {
            return directory.appendingPathComponent(safeName)
        }

        let base = directory.appendingPathComponent(safeName)
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        let numberedName = ext.isEmpty
            ? "\(stem) (\(occurrence))"
            : "\(stem) (\(occurrence)).\(ext)"
        return directory.appendingPathComponent(numberedName)
    }
}

struct ExportFileNamer {
    private var occurrences: [String: Int] = [:]

    mutating func next(in directory: URL, name: String) -> URL {
        let safeName = Filename.safe(name, fallback: "Attachment")
        let key = "\(directory.standardizedFileURL.path)\u{0}\(safeName)"
        let occurrence = occurrences[key, default: 0] + 1
        occurrences[key] = occurrence
        return Filename.numbered(in: directory, name: safeName, occurrence: occurrence)
    }
}

final class KeychainStore {
    private let service = "com.openbatch.opennotebatch"

    func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpenNoteError.fileSystem("Keychain save failed with status \(status).")
        }
    }

    func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OpenNoteError.fileSystem("Keychain load failed with status \(status).")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
