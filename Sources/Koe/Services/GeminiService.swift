import Foundation

final class GeminiService: GeminiTextTransforming {
    private let model = "gemini-2.5-flash-lite"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    struct GeminiRequest: Encodable {
        let contents: [Content]
        let systemInstruction: SystemInstruction?

        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct SystemInstruction: Encodable {
            let parts: [Part]
        }
    }

    struct GeminiResponse: Decodable {
        let candidates: [Candidate]?
        let error: GeminiError?

        struct Candidate: Decodable {
            let content: Content
        }

        struct Content: Decodable {
            let parts: [Part]
        }

        struct Part: Decodable {
            let text: String
        }

        struct GeminiError: Decodable {
            let message: String
        }
    }

    func rewrite(text: String, systemPrompt: String, apiKey: String) async throws -> String {
        try await requestText(
            userMessage: text,
            systemPrompt: systemPrompt,
            apiKey: apiKey
        )
    }

    func correct(selectedText: String, instruction: String, systemPrompt: String, apiKey: String) async throws -> String {
        let userMessage = """
        【対象テキスト】
        \(selectedText)

        【指示】
        \(instruction)
        """

        return try await requestText(
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            apiKey: apiKey
        )
    }

    private func requestText(userMessage: String, systemPrompt: String, apiKey: String) async throws -> String {
        let url = try buildURL(apiKey: apiKey)
        let normalizedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(parts: [GeminiRequest.Part(text: userMessage)])
            ],
            systemInstruction: normalizedPrompt.isEmpty
                ? nil
                : GeminiRequest.SystemInstruction(parts: [GeminiRequest.Part(text: normalizedPrompt)])
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let message = parseAPIErrorMessage(data: data) ?? (String(data: data, encoding: .utf8) ?? "Unknown error")
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let error = geminiResponse.error {
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: error.message)
        }

        guard let text = geminiResponse.candidates?.first?.content.parts.first?.text else {
            throw GeminiError.noContent
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildURL(apiKey: String) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/\(model):generateContent") else {
            throw GeminiError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw GeminiError.invalidRequest
        }
        return url
    }

    private func parseAPIErrorMessage(data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
            return nil
        }
        return response.error?.message
    }

    enum GeminiError: LocalizedError {
        case invalidRequest
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "API リクエストの生成に失敗しました"
            case .invalidResponse:
                return "無効なレスポンスです"
            case .apiError(let statusCode, let message):
                return "API エラー (\(statusCode)): \(message)"
            case .noContent:
                return "レスポンスにテキストが含まれていません"
            }
        }
    }
}
