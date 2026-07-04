import Foundation

struct GraphClient {
    let accessToken: String
    let root: String
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path, accept: "application/json")
        return try jsonDecoder.decode(T.self, from: data)
    }

    func getPaged<T: Decodable>(_ path: String) async throws -> [T] {
        var urlString = absolute(path).absoluteString
        var results: [T] = []
        while !urlString.isEmpty {
            let page: GraphCollection<T> = try await getAbsolute(urlString)
            results.append(contentsOf: page.value)
            urlString = page.nextLink ?? ""
        }
        return results
    }

    func getText(_ path: String) async throws -> String {
        let data = try await request(path, accept: "text/html")
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return data
    }

    func postHTML(_ path: String, html: String) async throws {
        var request = URLRequest(url: absolute(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/html", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(html.utf8)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func postMultipart(_ path: String, builder: MultipartBuilder) async throws {
        var builder = builder
        var request = URLRequest(url: absolute(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(builder.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.finalize()
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func patchJSON(_ path: String, body: [String: String]) async throws {
        var request = URLRequest(url: absolute(path))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    private func getAbsolute<T: Decodable>(_ urlString: String) async throws -> T {
        let data = try await request(URL(string: urlString)!, accept: "application/json")
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func request(_ path: String, accept: String) async throws -> Data {
        try await request(absolute(path), accept: accept)
    }

    private func request(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return data
    }

    private func absolute(_ path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return URL(string: root + path)!
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? jsonDecoder.decode(GraphErrorResponse.self, from: data).message)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw OpenNoteError.graph(message)
        }
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct GraphCollection<T: Decodable>: Decodable {
    var value: [T]
    var nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

