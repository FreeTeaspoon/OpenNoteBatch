import AppKit
import Foundation

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var account: GraphAccount?
    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    private let keychain = KeychainStore()
    private var loginSession: LoginSession?
    private let tokenAccountKey = "microsoft-token"
    private let graphAccountKey = "microsoft-account"
    private let requestTimeout: TimeInterval = 30

    struct LoginSession {
        var accountKind: AccountKind
        var tenant: String
        var verifier: String
        var state: String
        var settings: AppSettings
    }

    init() {
        keychain.migrateLegacyAccess(accounts: [tokenAccountKey, graphAccountKey])
        restoreAccount()
    }

    func restoreAccount() {
        do {
            account = try keychain.load(GraphAccount.self, account: graphAccountKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signIn(accountKind: AccountKind, settings: AppSettings) async throws {
        let clientID = settings.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw OpenNoteError.missingClientID }

        let verifier = PKCE.verifier()
        let state = UUID().uuidString
        let tenant = settings.tenant(for: accountKind)
        loginSession = LoginSession(
            accountKind: accountKind,
            tenant: tenant,
            verifier: verifier,
            state: state,
            settings: settings
        )
        isSigningIn = true
        lastError = nil

        var components = URLComponents(string: "\(accountKind.authorityHost)/\(tenant)/oauth2/v2.0/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: settings.redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: settings.permissionPreset.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components.url else { throw OpenNoteError.invalidCallback }
        NSWorkspace.shared.open(url)
    }

    func handleCallback(_ url: URL) async {
        do {
            guard let session = loginSession else { throw OpenNoteError.invalidCallback }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw OpenNoteError.invalidCallback
            }
            let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = items["error"] {
                throw OpenNoteError.graph(items["error_description"] ?? error)
            }
            guard items["state"] == session.state else { throw OpenNoteError.authStateMismatch }
            guard let code = items["code"], !code.isEmpty else { throw OpenNoteError.invalidCallback }

            let token = try await exchangeCode(code, session: session)
            try keychain.save(token, account: tokenAccountKey)
            let profile = try await fetchProfile(token: token, accountKind: session.accountKind)
            try keychain.save(profile, account: graphAccountKey)
            account = profile
            loginSession = nil
            isSigningIn = false
        } catch {
            isSigningIn = false
            lastError = error.localizedDescription
        }
    }

    func validAccessToken(settings: AppSettings) async throws -> (String, String) {
        guard let token: TokenSet = try keychain.load(TokenSet.self, account: tokenAccountKey) else {
            throw OpenNoteError.tokenUnavailable
        }
        guard let account else { throw OpenNoteError.tokenUnavailable }
        if !token.isExpired {
            return (token.accessToken, account.accountKind.graphRoot)
        }
        guard let refreshToken = token.refreshToken else { throw OpenNoteError.tokenUnavailable }
        let refreshed = try await refresh(token: refreshToken, accountKind: account.accountKind, settings: settings)
        try keychain.save(refreshed, account: tokenAccountKey)
        return (refreshed.accessToken, account.accountKind.graphRoot)
    }

    func signOut() {
        keychain.delete(account: tokenAccountKey)
        keychain.delete(account: graphAccountKey)
        account = nil
        loginSession = nil
    }

    private func exchangeCode(_ code: String, session: LoginSession) async throws -> TokenSet {
        let url = URL(string: "\(session.accountKind.authorityHost)/\(session.tenant)/oauth2/v2.0/token")!
        let fields = [
            "client_id": session.settings.clientID,
            "scope": session.settings.permissionPreset.scopes.joined(separator: " "),
            "code": code,
            "redirect_uri": session.settings.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": session.verifier
        ]
        return try await tokenRequest(url: url, fields: fields)
    }

    private func refresh(token refreshToken: String, accountKind: AccountKind, settings: AppSettings) async throws -> TokenSet {
        let tenant = settings.tenant(for: accountKind)
        let url = URL(string: "\(accountKind.authorityHost)/\(tenant)/oauth2/v2.0/token")!
        let fields = [
            "client_id": settings.clientID,
            "scope": settings.permissionPreset.scopes.joined(separator: " "),
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        return try await tokenRequest(url: url, fields: fields)
    }

    private func tokenRequest(url: URL, fields: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(data: data, response: response)
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn) - 120),
            scope: payload.scope,
            tokenType: payload.tokenType
        )
    }

    private func fetchProfile(token: TokenSet, accountKind: AccountKind) async throws -> GraphAccount {
        var request = URLRequest(url: URL(string: "\(accountKind.graphRoot)/me?$select=id,displayName,userPrincipalName,mail")!)
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(data: data, response: response)
        let payload = try JSONDecoder().decode(ProfileResponse.self, from: data)
        return GraphAccount(
            id: payload.id,
            displayName: payload.displayName ?? "Microsoft Account",
            email: payload.mail ?? payload.userPrincipalName ?? "",
            accountKind: accountKind
        )
    }

    private func validateHTTP(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let message = (try? JSONDecoder().decode(GraphErrorResponse.self, from: data).message)
            ?? String(data: data, encoding: .utf8)
            ?? "HTTP \(http.statusCode)"
        throw OpenNoteError.graph(message)
    }
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
    var scope: String?
    var tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

private struct ProfileResponse: Decodable {
    var id: String
    var displayName: String?
    var userPrincipalName: String?
    var mail: String?
}

struct GraphErrorResponse: Decodable {
    struct ErrorPayload: Decodable {
        var message: String?
    }
    var error: ErrorPayload?
    var errorDescription: String?

    var message: String {
        error?.message ?? errorDescription ?? "Microsoft Graph request failed."
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
