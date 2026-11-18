import Foundation

// MARK: - Gemini 调用唯一入口（App 层只留这一个客户端）
//
// 三个识别器（记分规则 / 校历 / 邮件停课）的网络调用都走这里：
// 同一个模型、同一份 URL 构造、同一份请求结构与错误处理。
// 密钥只存钥匙串（GradeAIKeyStore），绝不写进仓库、日志或测试；
// 空密钥时直接抛错、不发请求。

enum GeminiClient {
    enum Failure: LocalizedError {
        case emptyApiKey
        case badResponse(Int)
        case noText

        var errorDescription: String? {
            switch self {
            case .emptyApiKey:
                return "请先粘贴 Gemini 密钥并保存，再点识别。"
            case .badResponse(let code):
                return "识别服务返回 \(code)，请检查密钥是否有效、额度是否充足。"
            case .noText:
                return "识别服务没有返回内容，请稍后再试。"
            }
        }
    }

    /// 唯一的 Gemini 网络调用点。`parts` 是 generateContent 的 contents[0].parts。
    static func call(parts: [[String: Any]], apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw Failure.emptyApiKey }
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1]
        ]
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.badResponse(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw Failure.noText
        }
        return text
    }

    /// 纯文字识别：prompt 即全部输入。
    static func recognizeText(prompt: String, apiKey: String) async throws -> String {
        try await call(parts: [["text": prompt]], apiKey: apiKey)
    }

    /// 图片识别：prompt + 一张 JPEG。
    static func recognizeImage(jpegData: Data, prompt: String, apiKey: String) async throws -> String {
        try await call(parts: [
            ["text": prompt],
            ["inlineData": ["mimeType": "image/jpeg", "data": jpegData.base64EncodedString()]]
        ], apiKey: apiKey)
    }
}
