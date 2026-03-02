import Foundation

struct AppSettings: Sendable {
    var ollamaBaseURL: String
    var chatModel: String
    var embeddingModel: String
    var chunkSize: Int
    var chunkOverlap: Int
    var topK: Int
    var temperature: Double

    static let `default` = AppSettings(
        ollamaBaseURL: "http://localhost:11434",
        chatModel: "llama3.2",
        embeddingModel: "nomic-embed-text",
        chunkSize: 2000,
        chunkOverlap: 200,
        topK: 5,
        temperature: 0.7
    )

    // UserDefaults keys
    private enum Keys {
        static let ollamaBaseURL = "ollamaBaseURL"
        static let chatModel = "chatModel"
        static let embeddingModel = "embeddingModel"
        static let chunkSize = "chunkSize"
        static let chunkOverlap = "chunkOverlap"
        static let topK = "topK"
        static let temperature = "temperature"
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        return AppSettings(
            ollamaBaseURL: defaults.string(forKey: Keys.ollamaBaseURL) ?? AppSettings.default.ollamaBaseURL,
            chatModel: defaults.string(forKey: Keys.chatModel) ?? AppSettings.default.chatModel,
            embeddingModel: defaults.string(forKey: Keys.embeddingModel) ?? AppSettings.default.embeddingModel,
            chunkSize: defaults.integer(forKey: Keys.chunkSize).nonZero ?? AppSettings.default.chunkSize,
            chunkOverlap: defaults.integer(forKey: Keys.chunkOverlap).nonZero ?? AppSettings.default.chunkOverlap,
            topK: defaults.integer(forKey: Keys.topK).nonZero ?? AppSettings.default.topK,
            temperature: defaults.double(forKey: Keys.temperature).nonZero ?? AppSettings.default.temperature
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL)
        defaults.set(chatModel, forKey: Keys.chatModel)
        defaults.set(embeddingModel, forKey: Keys.embeddingModel)
        defaults.set(chunkSize, forKey: Keys.chunkSize)
        defaults.set(chunkOverlap, forKey: Keys.chunkOverlap)
        defaults.set(topK, forKey: Keys.topK)
        defaults.set(temperature, forKey: Keys.temperature)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
