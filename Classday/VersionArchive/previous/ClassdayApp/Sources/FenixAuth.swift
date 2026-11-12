import AuthenticationServices
import CryptoKit
import Security
import UIKit
import Foundation
import ClassdayCore

private enum KeychainStore {
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

enum FenixConfig {
    private static let idKey = "classday.fenix.clientID"
    private static let secretKey = "classday.fenix.clientSecret"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: idKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: idKey) }
    }

    static var clientSecret: String {
        get {
            if let stored = KeychainStore.get(secretKey) { return stored }
            // Migrate a secret saved by older versions from UserDefaults.
            if let legacy = UserDefaults.standard.string(forKey: secretKey), !legacy.isEmpty {
                KeychainStore.set(legacy, for: secretKey)
                UserDefaults.standard.removeObject(forKey: secretKey)
                return legacy
            }
            return ""
        }
        set {
            KeychainStore.set(newValue, for: secretKey)
            UserDefaults.standard.removeObject(forKey: secretKey)
        }
    }

    static let redirect = "classday://fenix"
    static let authorize = "https://fenix.tecnico.ulisboa.pt/oauth/userdialog"
    static let token = "https://fenix.tecnico.ulisboa.pt/oauth/access_token"
    static let classes = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/classes"
    static let evaluations = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/evaluations"
}

enum FenixAuth {
    private static var pendingState: String?
    private static var pendingVerifier: String?

    @MainActor
    static func signIn(model: AppModel) async {
        guard !FenixConfig.clientID.isEmpty, !FenixConfig.clientSecret.isEmpty else {
            model.banner = "先填写 Fénix 的 client id 和 secret"
            return
        }
        let state = randomToken(length: 32)
        let verifier = randomToken(length: 64)
        pendingState = state
        pendingVerifier = verifier
        var components = URLComponents(string: FenixConfig.authorize)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: FenixConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: FenixConfig.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkceChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { return }
        do {
            let callback = try await WebLogin.start(url: url, callbackScheme: "classday")
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state else {
                model.banner = "Fénix 登录校验失败，请重试"
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                model.banner = "Fénix 没有返回授权码"
                return
            }
            let access = try await exchange(code: code, verifier: verifier)
            let (classData, _) = try await authorized(FenixConfig.classes, token: access)
            let (examData, _) = try await authorized(FenixConfig.evaluations, token: access)
            let classes = FenixCalendar.decodeClasses(classData)
            let exams = FenixCalendar.exams(from: FenixCalendar.decodeEvaluations(examData), calendar: model.calendar)
            model.importCalendar(ImportedCalendar(
                courses: FenixCalendar.courses(from: classes, calendar: model.calendar, totalWeeks: model.document.semester.totalWeeks),
                exams: exams,
                homework: [],
                warnings: []
            ))
        } catch {
            model.banner = "Fénix 登录没有完成"
        }
        pendingState = nil
        pendingVerifier = nil
    }

    private static func randomToken(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func exchange(code: String, verifier: String) async throws -> String {
        guard let tokenURL = URL(string: FenixConfig.token) else { throw URLError(.badURL) }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: FenixConfig.clientID),
            URLQueryItem(name: "client_secret", value: FenixConfig.clientSecret),
            URLQueryItem(name: "redirect_uri", value: FenixConfig.redirect),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw URLError(.userAuthenticationRequired)
        }
        return token
    }

    private static func authorized(_ raw: String, token: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: raw) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result = try await URLSession.shared.data(for: request)
        guard let http = result.1 as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        return result
    }
}

private enum WebLogin {
    @MainActor
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                Anchor.shared.session = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            Anchor.shared.session = session
            session.presentationContextProvider = Anchor.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                Anchor.shared.session = nil
                continuation.resume(throwing: URLError(.cannotOpenFile))
            }
        }
    }
}

private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Anchor()
    var session: ASWebAuthenticationSession?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
