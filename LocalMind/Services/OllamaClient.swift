import Foundation

struct OllamaClient: Sendable {
    let baseURL: String

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL
    }

    // MARK: - Health Check

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.models.map(\.name)
    }

    // MARK: - Embeddings

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        guard let url = URL(string: "\(baseURL)/api/embed") else {
            throw OllamaError.invalidURL
        }

        let body = EmbedRequest(model: model, input: texts)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.serverError(httpResponse.statusCode, errorBody)
        }

        let embedResponse = try JSONDecoder().decode(EmbedResponse.self, from: data)
        return embedResponse.embeddings
    }

    func embedSingle(text: String, model: String) async throws -> [Float] {
        let results = try await embed(texts: [text], model: model)
        guard let first = results.first else {
            throw OllamaError.emptyResponse
        }
        return first
    }

    // MARK: - Chat (Streaming)

    func chatStream(
        model: String,
        messages: [OllamaChatMessage],
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/chat") else {
                        throw OllamaError.invalidURL
                    }

                    let body = ChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        options: ChatOptions(temperature: temperature)
                    )

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw OllamaError.invalidResponse
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        let chatResponse = try JSONDecoder().decode(ChatStreamResponse.self, from: data)
                        if let content = chatResponse.message?.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                        if chatResponse.done == true {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Request/Response Types

struct EmbedRequest: Codable, Sendable {
    let model: String
    let input: [String]
}

struct EmbedResponse: Codable, Sendable {
    let embeddings: [[Float]]
}

struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct ChatRequest: Codable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: ChatOptions
}

struct ChatOptions: Codable, Sendable {
    let temperature: Double
}

struct ChatStreamResponse: Codable, Sendable {
    let message: ChatStreamMessage?
    let done: Bool?
}

struct ChatStreamMessage: Codable, Sendable {
    let role: String?
    let content: String?
}

struct TagsResponse: Codable, Sendable {
    let models: [TagModel]
}

struct TagModel: Codable, Sendable {
    let name: String
}

enum OllamaError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case serverError(Int, String)
    case modelNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Ollama URL"
        case .invalidResponse: return "Invalid response from Ollama"
        case .emptyResponse: return "Empty response from Ollama"
        case .serverError(let code, let body): return "Ollama error (\(code)): \(body)"
        case .modelNotAvailable(let model): return "Model '\(model)' is not available. Pull it with: ollama pull \(model)"
        }
    }
}
