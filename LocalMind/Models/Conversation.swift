import Foundation
import GRDB

struct Conversation: Identifiable, Codable, Sendable {
    var id: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date
}

extension Conversation: FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"
}

struct ChatMessage: Identifiable, Codable, Sendable {
    var id: String
    var conversationId: String
    var role: Role
    var content: String
    var sources: [SourceReference]?
    var folderIds: [String]?
    var createdAt: Date

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }
}

extension ChatMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    // Custom encoding for JSON array fields
    enum Columns: String, ColumnExpression {
        case id, conversationId, role, content, sources, folderIds, createdAt
    }
}

struct SourceReference: Codable, Sendable, Identifiable, Hashable {
    var id: String { "\(filePath):\(chunkIndex)" }
    var filePath: String
    var fileName: String
    var chunkIndex: Int
    var relevance: Float
    var snippet: String
}
