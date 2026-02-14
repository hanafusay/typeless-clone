import Foundation

protocol GeminiTextTransforming {
    func rewrite(text: String, systemPrompt: String, apiKey: String) async throws -> String
    func correct(selectedText: String, instruction: String, systemPrompt: String, apiKey: String) async throws -> String
}

@MainActor
protocol DictationConfigProviding: AnyObject {
    var recognitionLanguage: String { get }
    var rewriteEnabled: Bool { get }
    var geminiAPIKey: String { get }
    var rewritePrompt: String { get }
    var userContext: String { get }
    var correctionPrompt: String { get }
}

@MainActor
protocol PasteServing: AnyObject {
    func getSelectedText() -> String?
    func paste(text: String)
}
