import Foundation

actor IndexingEngine {
    static let shared = IndexingEngine()

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let db = DatabaseManager.shared

    struct Progress: Sendable {
        var folderId: String
        var phase: Phase
        var filesTotal: Int
        var filesProcessed: Int
        var chunksCreated: Int

        enum Phase: String, Sendable {
            case scanning = "Scanning files"
            case parsing = "Parsing documents"
            case chunking = "Chunking text"
            case embedding = "Generating embeddings"
            case storing = "Storing vectors"
            case complete = "Complete"
            case failed = "Failed"
        }

        var fractionComplete: Double {
            guard filesTotal > 0 else { return 0 }
            return Double(filesProcessed) / Double(filesTotal)
        }
    }

    typealias ProgressHandler = @Sendable (Progress) -> Void

    func indexFolder(_ folder: IndexedFolder, settings: AppSettings, onProgress: @escaping ProgressHandler) {
        // Cancel any existing task for this folder
        activeTasks[folder.id]?.cancel()

        let task = Task {
            do {
                try await performIndexing(folder: folder, settings: settings, onProgress: onProgress)
            } catch is CancellationError {
                // Expected cancellation
            } catch {
                var failed = folder
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                failed.updatedAt = Date()
                try? await db.updateFolder(failed)
                onProgress(Progress(
                    folderId: folder.id,
                    phase: .failed,
                    filesTotal: 0,
                    filesProcessed: 0,
                    chunksCreated: 0
                ))
            }
        }

        activeTasks[folder.id] = task
    }

    func cancelIndexing(folderId: String) {
        activeTasks[folderId]?.cancel()
        activeTasks.removeValue(forKey: folderId)
    }

    private func performIndexing(
        folder: IndexedFolder,
        settings: AppSettings,
        onProgress: @escaping ProgressHandler
    ) async throws {
        let folderURL = URL(fileURLWithPath: folder.path)
        let registry = FileParserRegistry.shared
        let chunker = TextChunker(chunkSize: settings.chunkSize, overlap: settings.chunkOverlap)
        let ollama = OllamaClient(baseURL: settings.ollamaBaseURL)

        // Phase 1: Scan files
        onProgress(Progress(folderId: folder.id, phase: .scanning, filesTotal: 0, filesProcessed: 0, chunksCreated: 0))

        let supportedFiles = try scanFiles(at: folderURL, supportedExtensions: registry.allSupportedExtensions)
        let totalFiles = supportedFiles.count

        try Task.checkCancellation()

        // Phase 2-3: Parse and chunk
        onProgress(Progress(folderId: folder.id, phase: .parsing, filesTotal: totalFiles, filesProcessed: 0, chunksCreated: 0))

        var allChunks: [DocumentChunk] = []
        var processedCount = 0

        for fileURL in supportedFiles {
            try Task.checkCancellation()

            let ext = fileURL.pathExtension.lowercased()
            guard let parser = registry.parser(for: ext) else { continue }

            do {
                let text = try parser.parse(fileAt: fileURL)
                let textChunks = chunker.chunk(text: text)

                for (index, chunk) in textChunks.enumerated() {
                    allChunks.append(DocumentChunk.new(
                        folderId: folder.id,
                        filePath: fileURL.path,
                        chunkIndex: index,
                        content: chunk.content,
                        charOffset: chunk.offset
                    ))
                }
            } catch {
                // Skip files that fail to parse, log for debugging
                print("Failed to parse \(fileURL.lastPathComponent): \(error)")
            }

            processedCount += 1
            onProgress(Progress(
                folderId: folder.id,
                phase: .parsing,
                filesTotal: totalFiles,
                filesProcessed: processedCount,
                chunksCreated: allChunks.count
            ))
        }

        guard !allChunks.isEmpty else {
            // No content found, mark as ready with 0 chunks
            var updated = folder
            updated.status = .ready
            updated.fileCount = totalFiles
            updated.chunkCount = 0
            updated.lastIndexedAt = Date()
            updated.updatedAt = Date()
            try await db.updateFolder(updated)
            onProgress(Progress(folderId: folder.id, phase: .complete, filesTotal: totalFiles, filesProcessed: totalFiles, chunksCreated: 0))
            return
        }

        try Task.checkCancellation()

        // Store chunks first (without embeddings)
        try await db.insertChunks(allChunks)

        // Phase 4: Generate embeddings in batches
        onProgress(Progress(folderId: folder.id, phase: .embedding, filesTotal: totalFiles, filesProcessed: processedCount, chunksCreated: allChunks.count))

        let batchSize = 32
        for batchStart in stride(from: 0, to: allChunks.count, by: batchSize) {
            try Task.checkCancellation()

            let batchEnd = min(batchStart + batchSize, allChunks.count)
            let batch = Array(allChunks[batchStart..<batchEnd])
            let texts = batch.map(\.content)

            do {
                let embeddings = try await ollama.embed(texts: texts, model: settings.embeddingModel)

                for (i, embedding) in embeddings.enumerated() {
                    let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
                    try await db.updateChunkEmbedding(id: batch[i].id, embedding: data)
                }
            } catch {
                print("Embedding batch failed: \(error)")
                // Continue with remaining batches
            }

            onProgress(Progress(
                folderId: folder.id,
                phase: .embedding,
                filesTotal: totalFiles,
                filesProcessed: processedCount,
                chunksCreated: min(batchEnd, allChunks.count)
            ))
        }

        try Task.checkCancellation()

        // Phase 5: Finalize
        var updated = folder
        updated.status = .ready
        updated.fileCount = totalFiles
        updated.chunkCount = allChunks.count
        updated.lastIndexedAt = Date()
        updated.errorMessage = nil
        updated.updatedAt = Date()
        try await db.updateFolder(updated)

        onProgress(Progress(folderId: folder.id, phase: .complete, filesTotal: totalFiles, filesProcessed: totalFiles, chunksCreated: allChunks.count))
        activeTasks.removeValue(forKey: folder.id)
    }

    private func scanFiles(at url: URL, supportedExtensions: Set<String>) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            // Skip very large files (> 50MB)
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize, size > 50_000_000 {
                continue
            }

            files.append(fileURL)
        }

        return files
    }
}
