import Foundation
import GRDB

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var dbPool: DatabasePool?

    private var pool: DatabasePool {
        get throws {
            guard let dbPool else {
                throw DatabaseError(message: "Database not initialized")
            }
            return dbPool
        }
    }

    func initialize() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("LocalMind", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("localmind.sqlite").path
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }

        dbPool = try DatabasePool(path: dbPath, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "folders") { t in
                t.column("id", .text).primaryKey()
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("status", .text).notNull()
                t.column("fileCount", .integer).defaults(to: 0)
                t.column("chunkCount", .integer).defaults(to: 0)
                t.column("lastIndexedAt", .datetime)
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "chunks") { t in
                t.column("id", .text).primaryKey()
                t.column("folderId", .text).notNull().references("folders", onDelete: .cascade)
                t.column("filePath", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("charOffset", .integer).notNull()
                t.column("embedding", .blob)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_chunks_folder", on: "chunks", columns: ["folderId"])

            try db.create(table: "conversations") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text).notNull().references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sources", .text) // JSON
                t.column("folderIds", .text) // JSON
                t.column("createdAt", .datetime).notNull()
            }
        }

        try migrator.migrate(pool)
    }

    // MARK: - Folders

    func fetchAllFolders() throws -> [IndexedFolder] {
        try pool.read { db in
            try IndexedFolder.order(Column("createdAt").asc).fetchAll(db)
        }
    }

    func insertFolder(_ folder: IndexedFolder) throws {
        try pool.write { db in
            try folder.insert(db)
        }
    }

    func updateFolder(_ folder: IndexedFolder) throws {
        try pool.write { db in
            try folder.update(db)
        }
    }

    func deleteFolder(id: String) throws {
        try pool.write { db in
            _ = try IndexedFolder.deleteOne(db, id: id)
        }
    }

    func folderExists(path: String) throws -> Bool {
        try pool.read { db in
            try IndexedFolder.filter(Column("path") == path).fetchCount(db) > 0
        }
    }

    // MARK: - Chunks

    func insertChunks(_ chunks: [DocumentChunk]) throws {
        try pool.write { db in
            for chunk in chunks {
                try chunk.insert(db)
            }
        }
    }

    func deleteChunks(forFolderId folderId: String) throws {
        try pool.write { db in
            _ = try DocumentChunk.filter(Column("folderId") == folderId).deleteAll(db)
        }
    }

    func fetchChunksWithEmbeddings(forFolderIds folderIds: [String]) throws -> [DocumentChunk] {
        try pool.read { db in
            try DocumentChunk
                .filter(folderIds.contains(Column("folderId")))
                .filter(Column("embedding") != nil)
                .fetchAll(db)
        }
    }

    func updateChunkEmbedding(id: String, embedding: Data) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE chunks SET embedding = ? WHERE id = ?",
                arguments: [embedding, id]
            )
        }
    }

    func chunkCount(forFolderId folderId: String) throws -> Int {
        try pool.read { db in
            try DocumentChunk.filter(Column("folderId") == folderId).fetchCount(db)
        }
    }

    // MARK: - Conversations

    func fetchConversations() throws -> [Conversation] {
        try pool.read { db in
            try Conversation.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func insertConversation(_ conversation: Conversation) throws {
        try pool.write { db in
            try conversation.insert(db)
        }
    }

    func fetchMessages(forConversationId id: String) throws -> [ChatMessage] {
        try pool.read { db in
            try ChatMessage
                .filter(Column("conversationId") == id)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func insertMessage(_ message: ChatMessage) throws {
        try pool.write { db in
            try message.insert(db)
        }
    }

    func updateConversationTimestamp(id: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE conversations SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
}

struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
