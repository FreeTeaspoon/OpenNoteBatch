import Foundation

struct MultipartBuilder {
    let boundary = "OpenNoteBatch-\(UUID().uuidString)"
    private(set) var data = Data()

    mutating func addTextPart(name: String, value: String, contentType: String = "text/html") {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFilePart(name: String, filename: String, contentType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> Data {
        append("--\(boundary)--\r\n")
        return data
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

