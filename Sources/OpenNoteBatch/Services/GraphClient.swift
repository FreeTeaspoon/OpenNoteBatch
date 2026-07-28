import Foundation

struct GraphClient {
    let accessToken: String
    let root: String
    var session: URLSession = .shared
    var requestTimeout: TimeInterval = 30

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path, accept: "application/json")
        return try jsonDecoder.decode(T.self, from: data)
    }

    func getPaged<T: Decodable>(_ path: String) async throws -> [T] {
        var urlString = absolute(path).absoluteString
        var results: [T] = []
        var visitedURLs: Set<String> = []
        while !urlString.isEmpty {
            guard visitedURLs.insert(urlString).inserted else {
                throw OpenNoteError.graph("Microsoft Graph returned a repeated pagination link. Loading was stopped to avoid an endless loop.")
            }
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

    func getPageContent(_ path: String, includeInkML: Bool) async throws -> OneNotePageContent {
        var request = URLRequest(url: absolute(path))
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(includeInkML ? "multipart/mixed, text/html" : "text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        return OneNoteContentParser.parse(data: data, contentType: contentType)
    }

    func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
        return data
    }

    func postHTML(_ path: String, html: String) async throws {
        var request = URLRequest(url: absolute(path))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/html", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(html.utf8)
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
    }

    func postMultipart(_ path: String, builder: MultipartBuilder) async throws {
        var builder = builder
        var request = URLRequest(url: absolute(path))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(builder.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.finalize()
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
    }

    func patchJSON(_ path: String, body: [String: String]) async throws {
        var request = URLRequest(url: absolute(path))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await data(for: request)
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
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await data(for: request)
        try validate(data: data, response: response)
        return data
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenNoteError.graph("Microsoft Graph did not respond within \(Int(requestTimeout)) seconds. Check your connection and try Load again.")
        }
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
