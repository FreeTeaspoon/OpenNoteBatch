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
    private let helperMigrationKey = "keychain-helper-migration-v1"
    private let helperName = "OpenNoteBatchKeychain"

    func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        _ = try runHelper(command: "save", account: account, input: data)
    }

    func migrateLegacyAccess(accounts: [String]) {
        guard !UserDefaults.standard.bool(forKey: helperMigrationKey), helperURL != nil else { return }

        var migrationSucceeded = true
        for account in accounts {
            do {
                guard let data = try loadDirectData(account: account) else { continue }
                try deleteDirect(account: account)
                do {
                    _ = try runHelper(command: "save", account: account, input: data)
                } catch {
                    // Do not leave an existing login without a recoverable copy if
                    // the first helper-backed write fails.
                    try? saveDirect(data, account: account)
                    throw error
                }
            } catch {
                migrationSucceeded = false
            }
        }

        if migrationSucceeded {
            UserDefaults.standard.set(true, forKey: helperMigrationKey)
        }
    }

    func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let data = try runHelper(command: "read", account: account)
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(account: String) {
        _ = try? runHelper(command: "delete", account: account)
    }

    private var helperURL: URL? {
        var candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(helperName, isDirectory: false),
            URL(fileURLWithPath: "/Applications/OpenNoteBatch.app/Contents/Helpers/\(helperName)")
        ]

        if let executableURL = Bundle.main.executableURL {
            let contentsURL = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(contentsURL
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(helperName, isDirectory: false))
        }

        var seen = Set<String>()
        return candidates.first {
            seen.insert($0.path).inserted && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func saveDirect(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw OpenNoteError.fileSystem("Keychain delete failed with status \(deleteStatus).")
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpenNoteError.fileSystem("Keychain save failed with status \(status).")
        }
    }

    private func loadDirectData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OpenNoteError.fileSystem("Keychain load failed with status \(status).")
        }
        return data
    }

    private func deleteDirect(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenNoteError.fileSystem("Keychain delete failed with status \(status).")
        }
    }

    private func runHelper(command: String, account: String, input: Data? = nil) throws -> Data? {
        guard let helperURL else {
            throw OpenNoteError.fileSystem("The OpenNoteBatch Keychain helper is missing.")
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [command, service, account]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(input.base64EncodedString().utf8))
            inputPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenNoteError.fileSystem(message?.isEmpty == false ? message! : "Keychain helper failed.")
        }

        let response = String(data: output, encoding: .utf8) ?? ""
        if response == "NOT_FOUND\n" || response == "NOT_FOUND" {
            return nil
        }
        guard response.hasPrefix("OK\n") else {
            throw OpenNoteError.fileSystem("Keychain helper returned an invalid response.")
        }
        let encoded = String(response.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encoded.isEmpty else { return Data() }
        guard let data = Data(base64Encoded: encoded) else {
            throw OpenNoteError.fileSystem("Keychain helper returned invalid data.")
        }
        return data
    }
}
