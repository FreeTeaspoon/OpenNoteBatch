import Foundation
import Testing
@testable import OpenNoteBatch

@Suite("PKCE")
struct PKCETests {
    @Test func challengeMatchesKnownVerifier() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafe() {
        let verifier = PKCE.verifier()
        #expect(!verifier.contains("+"))
        #expect(!verifier.contains("/"))
        #expect(!verifier.contains("="))
        #expect(verifier.count > 20)
    }
}

