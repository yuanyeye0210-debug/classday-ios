import AuthenticationServices
import UIKit
import Foundation
import ClassdayCore

enum FenixConfig {
    private static let idKey = "classday.fenix.clientID"
    private static let secretKey = "classday.fenix.clientSecret"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: idKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: idKey) }
    }

    static var clientSecret: String {
        get { UserDefaults.standard.string(forKey: secretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: secretKey) }
    }

    static let redirect = "classday://fenix"
    static let authorize = "https://fenix.tecnico.ulisboa.pt/oauth/userdialog"
    static let token = "https://fenix.tecnico.ulisboa.pt/oauth/access_token"
    static let classes = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/classes"
    static let evaluations = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/evaluations"
}

enum FenixAuth {
    @MainActor
    static func signIn(model: AppModel) async {
        guard !FenixConfig.clientID.isEmpty, !FenixConfig.clientSecret.isEmpty else {
            model.banner = "先填写 Fénix 的 client id 和 secret"
            return
        }
        var components = URLComponents(string: FenixConfig.authorize)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: FenixConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: FenixConfig.redirect),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        guard let url = components?.url else { return }
        do {
            let callback = try await WebLogin.start(url: url, callbackScheme: "classday")
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                model.banner = "Fénix 没有返回授权码"
                return
            }
            let access = try await exchange(code: code)
            let (classData, _) = try await authorized(FenixConfig.classes, token: access)
            let (examData, _) = try await authorized(FenixConfig.evaluations, token: access)
            let classes = FenixCalendar.decodeClasses(classData)
            let exams = FenixCalendar.exams(from: FenixCalendar.decodeEvaluations(examData), calendar: model.calendar)
            model.importCalendar(ImportedCalendar(
                courses: FenixCalendar.courses(from: classes, calendar: model.calendar),
                exams: exams,
                homework: [],
                warnings: []
            ))
        } catch {
            model.banner = "Fénix 登录没有完成"
        }
    }

    private static func exchange(code: String) async throws -> String {
        var request = URLRequest(url: URL(string: FenixConfig.token)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(FenixConfig.clientID)",
            "client_secret=\(FenixConfig.clientSecret)",
            "redirect_uri=\(FenixConfig.redirect)",
            "code=\(code)",
            "grant_type=authorization_code",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw URLError(.userAuthenticationRequired)
        }
        return token
    }

    private static func authorized(_ raw: String, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: raw)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
    }
}

private enum WebLogin {
    @MainActor
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
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
