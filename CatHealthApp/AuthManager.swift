import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Observation

struct AuthUser: Codable {
    let id: String
    let email: String
    let name: String
    let pictureURL: String?
}

enum AuthProvider {
    case google, apple, none
}

private final class PresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding,
    ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { keyWindow() }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { keyWindow() }

    private func keyWindow() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    init(_ cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) { self.cont = cont }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            cont.resume(throwing: NSError(domain: "AppleAuth", code: -1)); return
        }
        cont.resume(returning: cred)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        cont.resume(throwing: error)
    }
}

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()

    var isLoggedIn = false
    var user: AuthUser?
    var isLoading = false
    var loadingProvider: AuthProvider = .none
    var errorMessage: String?

    private let clientID = "778316848016-8pi2vcnfq1t64uuhgqg7nsk3ult5n44m.apps.googleusercontent.com"
    private let redirectScheme = "com.googleusercontent.apps.778316848016-8pi2vcnfq1t64uuhgqg7nsk3ult5n44m"
    private var codeVerifier = ""
    private let contextProvider = PresentationContextProvider()
    private var authSession: ASWebAuthenticationSession?
    private var appleDelegate: AppleSignInDelegate?

    init() {
        if let data = UserDefaults.standard.data(forKey: "authUser"),
           let saved = try? JSONDecoder().decode(AuthUser.self, from: data) {
            user = saved
            isLoggedIn = true
        }
    }

    func signInWithApple() async {
        isLoading = true
        loadingProvider = .apple
        errorMessage = nil
        defer { isLoading = false; loadingProvider = .none }

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        do {
            let credential: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { cont in
                let delegate = AppleSignInDelegate(cont)
                self.appleDelegate = delegate
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = delegate
                controller.presentationContextProvider = self.contextProvider
                controller.performRequests()
            }
            appleDelegate = nil

            let userId = credential.user
            let email = credential.email ?? "\(userId)@privaterelay.appleid.com"
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let name = fullName.isEmpty ? "Apple User" : fullName

            let fetched = AuthUser(id: userId, email: email, name: name, pictureURL: nil)
            user = fetched
            isLoggedIn = true
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: "authUser")
            }
        } catch {
            appleDelegate = nil
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        loadingProvider = .google
        errorMessage = nil
        defer { isLoading = false; loadingProvider = .none }

        let verifier = makeCodeVerifier()
        codeVerifier = verifier
        let challenge = makeCodeChallenge(verifier)
        guard let authURL = buildAuthURL(challenge: challenge) else { return }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
                let session = ASWebAuthenticationSession(
                    url: authURL, callbackURLScheme: redirectScheme
                ) { url, error in
                    if let error { cont.resume(throwing: error) }
                    else if let url { cont.resume(returning: url) }
                }
                session.presentationContextProvider = self.contextProvider
                session.prefersEphemeralWebBrowserSession = false
                self.authSession = session
                session.start()
            }
            authSession = nil

            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                errorMessage = "Authorization failed"; return
            }

            let token = try await exchangeCode(code)
            let fetched = try await fetchUser(accessToken: token)
            user = fetched
            isLoggedIn = true
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: "authUser")
            }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        user = nil; isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: "authUser")
    }

    // MARK: - PKCE
    private func makeCodeVerifier() -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Data(buf).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeCodeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func buildAuthURL(challenge: String) -> URL? {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        c?.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: "\(redirectScheme):/oauth2redirect"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return c?.url
    }

    // MARK: - Network
    private struct TokenResponse: Decodable { let access_token: String }

    private func exchangeCode(_ code: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "code": code, "client_id": clientID,
            "redirect_uri": "\(redirectScheme):/oauth2redirect",
            "grant_type": "authorization_code", "code_verifier": codeVerifier,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    private struct GoogleUserInfo: Decodable {
        let sub: String; let email: String; let name: String; let picture: String?
    }

    private func fetchUser(accessToken: String) async throws -> AuthUser {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let g = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
        return AuthUser(id: g.sub, email: g.email, name: g.name, pictureURL: g.picture)
    }
}
