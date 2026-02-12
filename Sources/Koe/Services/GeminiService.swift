import Foundation

final class GeminiService {
    private let model = "gemini-2.0-flash-lite"
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
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!

        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(parts: [GeminiRequest.Part(text: text)])
            ],
            systemInstruction: GeminiRequest.SystemInstruction(
                parts: [GeminiRequest.Part(text: systemPrompt)]
            )
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

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: body)
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

    func correct(selectedText: String, instruction: String, systemPrompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!

        let userMessage = """
        【対象テキスト】
        \(selectedText)

        【指示】
        \(instruction)
        """

        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(parts: [GeminiRequest.Part(text: userMessage)])
            ],
            systemInstruction: GeminiRequest.SystemInstruction(
                parts: [GeminiRequest.Part(text: systemPrompt)]
            )
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

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: body)
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

    enum GeminiError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case noContent

        var errorDescription: String? {
            switch self {
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
