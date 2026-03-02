import Foundation
import GRDB

enum FolderStatus: String, Codable, Sendable {
    case indexing
    case reindexing
    case ready
    case failed
    case unavailable
}

struct IndexedFolder: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id: String
    var path: String
    var name: String
    var status: FolderStatus
    var fileCount: Int
    var chunkCount: Int
    var lastIndexedAt: Date?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    var isSelectable: Bool {
        status == .ready
    }

    var statusLabel: String {
        switch status {
        case .indexing: return "Indexing"
        case .reindexing: return "Reindexing"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .unavailable: return "Unavailable"
        }
    }
}

extension IndexedFolder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"

    enum Columns: String, ColumnExpression {
        case id, path, name, status, fileCount, chunkCount
        case lastIndexedAt, errorMessage, createdAt, updatedAt
    }
}

extension IndexedFolder {
    static func new(path: String) -> IndexedFolder {
        let url = URL(fileURLWithPath: path)
        let now = Date()
        return IndexedFolder(
            id: UUID().uuidString,
            path: path,
            name: url.lastPathComponent,
            status: .indexing,
            fileCount: 0,
            chunkCount: 0,
            lastIndexedAt: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
