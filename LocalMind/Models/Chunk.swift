import Foundation
import GRDB

struct DocumentChunk: Identifiable, Codable, Sendable {
    var id: String
    var folderId: String
    var filePath: String
    var fileName: String
    var chunkIndex: Int
    var content: String
    var charOffset: Int
    var embedding: Data?
    var createdAt: Date
}

extension DocumentChunk: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chunks"

    enum Columns: String, ColumnExpression {
        case id, folderId, filePath, fileName, chunkIndex
        case content, charOffset, embedding, createdAt
    }
}

extension DocumentChunk {
    static func new(
        folderId: String,
        filePath: String,
        chunkIndex: Int,
        content: String,
        charOffset: Int
    ) -> DocumentChunk {
        let url = URL(fileURLWithPath: filePath)
        return DocumentChunk(
            id: UUID().uuidString,
            folderId: folderId,
            filePath: filePath,
            fileName: url.lastPathComponent,
            chunkIndex: chunkIndex,
            content: content,
            charOffset: charOffset,
            embedding: nil,
            createdAt: Date()
        )
    }
}
