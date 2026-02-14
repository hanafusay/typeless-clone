import Foundation
import ServiceManagement

final class Config: ObservableObject {
    static let shared = Config()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let geminiAPIKey = "geminiAPIKey"
        static let recognitionLanguage = "recognitionLanguage"
        static let rewriteEnabled = "rewriteEnabled"
        static let rewritePrompt = "rewritePrompt"
        static let rewriteUserContext = "rewriteUserContext"
        static let audioInputDeviceUID = "audioInputDeviceUID"
        static let triggerKey = "triggerKey"
    }

    static let maxUserContextLength = 400

    static let legacyDefaultRewritePrompt = """
    あなたは音声認識テキストのリライターです。
    以下の音声認識結果を自然な日本語に修正してください。
    - 句読点を適切に追加
    - 明らかな認識ミスを修正
    - 文法を自然に整える
    - 元の意味を変えない
    リライト結果のテキストのみを返してください。説明や補足は不要です。
    """

    static let defaultRewritePrompt = """
    あなたは音声認識結果の「校正専用」エンジンです。質問への回答者ではありません。
    入力テキストに対して、次だけを行ってください。
    - 明らかな誤認識の修正
    - 句読点・かな漢字・表記ゆれの最小限の補正
    - 文法上の不自然さの最小限の補正

    以下は禁止です。
    - 質問に答える、補足説明を足す、要約する、言い換えて意味を変える
    - 新しい事実や主張を追加する
    - 丁寧化・断定化など、話者の意図を変える編集

    重要:
    - 入力が「うまくいきましたか？」なら、出力も必ず質問文のままにする
      （例: 「はい、うまくいきました」などの回答に変換しない）
    - 不確かな固有名詞は無理に置換しない（必要なら元表記を残す）
    - 出力は「校正後テキストのみ」。説明・注釈・前置きは一切不要。
    """

    static let defaultCorrectionPrompt = """
    あなたはテキスト修正アシスタントです。
    ユーザーから「対象テキスト」と「指示」が与えられます。
    指示に従って対象テキストを修正し、修正後のテキストのみを出力してください。

    ルール:
    - 指示に忠実に従う
    - 指示の範囲外の変更は行わない
    - 出力は修正後のテキストのみ。説明・注釈・前置きは一切不要
    - 指示が曖昧な場合は、最も自然な解釈で修正する
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

    @Published var rewriteUserContext: String {
        didSet { defaults.set(rewriteUserContext, forKey: Keys.rewriteUserContext) }
    }

    @Published var audioInputDeviceUID: String {
        didSet { defaults.set(audioInputDeviceUID, forKey: Keys.audioInputDeviceUID) }
    }

    @Published var triggerKey: TriggerKey {
        didSet { defaults.set(triggerKey.rawValue, forKey: Keys.triggerKey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.d("[Config] Failed to \(launchAtLogin ? "register" : "unregister") launch at login: \(error)")
                // Revert to actual state on failure
                let actual = SMAppService.mainApp.status == .enabled
                if actual != launchAtLogin {
                    launchAtLogin = actual
                }
            }
        }
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

        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        self.audioInputDeviceUID = defaults.string(forKey: Keys.audioInputDeviceUID) ?? ""

        if let savedTriggerKey = defaults.string(forKey: Keys.triggerKey),
           let key = TriggerKey(rawValue: savedTriggerKey) {
            self.triggerKey = key
        } else {
            self.triggerKey = .fn
        }

        self.rewriteUserContext = defaults.string(forKey: Keys.rewriteUserContext) ?? ""

        let savedPrompt = defaults.string(forKey: Keys.rewritePrompt)
        if let savedPrompt {
            if savedPrompt == Config.legacyDefaultRewritePrompt {
                self.rewritePrompt = Config.defaultRewritePrompt
                defaults.set(Config.defaultRewritePrompt, forKey: Keys.rewritePrompt)
            } else {
                self.rewritePrompt = savedPrompt
            }
        } else {
            self.rewritePrompt = Config.defaultRewritePrompt
        }
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

@MainActor
extension Config: DictationConfigProviding {
    var correctionPrompt: String {
        Self.defaultCorrectionPrompt
    }
}
