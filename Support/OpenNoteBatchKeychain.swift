import Darwin
import Foundation
import Security

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fputs("Usage: OpenNoteBatchKeychain <read|save|delete> <service> <account>\n", stderr)
    exit(2)
}

let command = arguments[1]
let service = arguments[2]
let account = arguments[3]

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account
]

func reportFailure(_ status: OSStatus) -> Never {
    fputs("Keychain operation failed with status \(status).\n", stderr)
    exit(1)
}

switch command {
case "read":
    var readQuery = query
    readQuery[kSecReturnData as String] = true
    readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
    if status == errSecItemNotFound {
        print("NOT_FOUND")
    } else if status == errSecSuccess, let data = result as? Data {
        print("OK")
        print(data.base64EncodedString())
    } else {
        reportFailure(status)
    }

case "save":
    let encoded = FileHandle.standardInput.readDataToEndOfFile()
    guard let data = Data(base64Encoded: encoded) else {
        fputs("Invalid base64 input.\n", stderr)
        exit(2)
    }

    let deleteStatus = SecItemDelete(query as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
        reportFailure(deleteStatus)
    }

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(attributes as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        reportFailure(addStatus)
    }
    print("OK")

case "delete":
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        reportFailure(status)
    }
    print("OK")

default:
    fputs("Unknown command.\n", stderr)
    exit(2)
}
