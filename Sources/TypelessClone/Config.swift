import Foundation

final class Config: ObservableObject {
    static let shared = Config()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let geminiAPIKey = "geminiAPIKey"
        static let recognitionLanguage = "recognitionLanguage"
        static let rewriteEnabled = "rewriteEnabled"
        static let rewritePrompt = "rewritePrompt"
    }

    static let defaultRewritePrompt = """
    あなたは音声認識テキストのリライターです。
    以下の音声認識結果を自然な日本語に修正してください。
    - 句読点を適切に追加
    - 明らかな認識ミスを修正
    - 文法を自然に整える
    - 元の意味を変えない
    リライト結果のテキストのみを返してください。説明や補足は不要です。
    """

    @Published var geminiAPIKey: String {
        didSet { defaults.set(geminiAPIKey, forKey: Keys.geminiAPIKey) }
    }

    @Published var recognitionLanguage: String {
        didSet { defaults.set(recognitionLanguage, forKey: Keys.recognitionLanguage) }
    }

    @Published var rewriteEnabled: Bool {
        didSet { defaults.set(rewriteEnabled, forKey: Keys.rewriteEnabled) }
    }

    @Published var rewritePrompt: String {
        didSet { defaults.set(rewritePrompt, forKey: Keys.rewritePrompt) }
    }

    private init() {
        // Load from .env file if API key not in UserDefaults
        let savedKey = defaults.string(forKey: Keys.geminiAPIKey) ?? ""
        if savedKey.isEmpty {
            self.geminiAPIKey = Config.loadFromEnvFile() ?? ""
        } else {
            self.geminiAPIKey = savedKey
        }

        self.recognitionLanguage = defaults.string(forKey: Keys.recognitionLanguage) ?? "ja-JP"

        if defaults.object(forKey: Keys.rewriteEnabled) == nil {
            self.rewriteEnabled = true
        } else {
            self.rewriteEnabled = defaults.bool(forKey: Keys.rewriteEnabled)
        }

        self.rewritePrompt = defaults.string(forKey: Keys.rewritePrompt) ?? Config.defaultRewritePrompt
    }

    private static func loadFromEnvFile() -> String? {
        let fileManager = FileManager.default

        // Look for .env in several locations:
        // 1. Inside the app bundle (Contents/Resources/.env)
        // 2. Next to the app bundle (e.g. /Applications/.env)
        let candidates = [
            Bundle.main.resourcePath.map { $0 + "/.env" },
            Optional(Bundle.main.bundlePath + "/../.env"),
        ].compactMap { $0 }

        var envPath: String?
        for path in candidates {
            if fileManager.fileExists(atPath: path) {
                envPath = path
                break
            }
        }

        guard let resolvedPath = envPath,
              let content = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("GEMINI_API_KEY=") {
                let value = String(trimmed.dropFirst("GEMINI_API_KEY=".count))
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
