import Foundation
import Accelerate

struct RetrievalEngine: Sendable {
    private let db = DatabaseManager.shared

    struct RetrievalResult: Sendable {
        let chunk: DocumentChunk
        let similarity: Float
    }

    func retrieve(
        query: String,
        folderIds: [String],
        topK: Int,
        settings: AppSettings
    ) async throws -> [RetrievalResult] {
        let ollama = OllamaClient(baseURL: settings.ollamaBaseURL)

        // Embed the query
        let queryEmbedding = try await ollama.embedSingle(text: query, model: settings.embeddingModel)

        // Fetch all chunks with embeddings for selected folders
        let chunks = try await db.fetchChunksWithEmbeddings(forFolderIds: folderIds)

        guard !chunks.isEmpty else { return [] }

        // Compute cosine similarity using Accelerate
        var results: [RetrievalResult] = []

        for chunk in chunks {
            guard let embeddingData = chunk.embedding else { continue }

            let chunkEmbedding = embeddingData.withUnsafeBytes { buffer -> [Float] in
                Array(buffer.bindMemory(to: Float.self))
            }

            guard chunkEmbedding.count == queryEmbedding.count else { continue }

            let similarity = cosineSimilarity(queryEmbedding, chunkEmbedding)
            results.append(RetrievalResult(chunk: chunk, similarity: similarity))
        }

        // Sort by similarity descending and take top-K
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK))
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let count = vDSP_Length(a.count)

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)

        var normA: Float = 0
        vDSP_svesq(a, 1, &normA, count)
        normA = sqrt(normA)

        var normB: Float = 0
        vDSP_svesq(b, 1, &normB, count)
        normB = sqrt(normB)

        guard normA > 0, normB > 0 else { return 0 }
        return dotProduct / (normA * normB)
    }

    func buildContext(from results: [RetrievalResult]) -> (context: String, sources: [SourceReference]) {
        var contextParts: [String] = []
        var sources: [SourceReference] = []

        for (index, result) in results.enumerated() {
            let chunk = result.chunk
            contextParts.append("""
            [Source \(index + 1): \(chunk.fileName)]
            \(chunk.content)
            """)

            sources.append(SourceReference(
                filePath: chunk.filePath,
                fileName: chunk.fileName,
                chunkIndex: chunk.chunkIndex,
                relevance: result.similarity,
                snippet: String(chunk.content.prefix(200))
            ))
        }

        return (context: contextParts.joined(separator: "\n\n---\n\n"), sources: sources)
    }
}
