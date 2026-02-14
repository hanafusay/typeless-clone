import Foundation

@MainActor
protocol DictationConfigProviding: AnyObject {
    var recognitionLanguage: String { get }
    var rewriteEnabled: Bool { get }
    var geminiAPIKey: String { get }
    var rewritePrompt: String { get }
    var rewriteUserContext: String { get }
    var correctionPrompt: String { get }
}

@MainActor
protocol PasteServing: AnyObject {
    func getSelectedText() -> String?
    func paste(text: String)
}
