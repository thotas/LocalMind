import SwiftUI

@Observable
@MainActor
final class AppState {
    // MARK: - Folders
    var folders: [IndexedFolder] = []
    var selectedFolderIds: Set<String> = []
    var indexingProgress: [String: IndexingEngine.Progress] = [:]
    var showFolderPicker = false

    // MARK: - Chat
    var conversations: [Conversation] = []
    var currentConversationId: String?
    var messages: [ChatMessage] = []
    var currentQuestion: String = ""
    var streamingResponse: String = ""
    var isGenerating = false
    var chatError: String?

    // MARK: - Settings
    var settings: AppSettings = .load()

    // MARK: - Connection
    var ollamaConnected = false
    var availableModels: [String] = []

    // MARK: - Services
    private let db = DatabaseManager.shared
    private let indexingEngine = IndexingEngine.shared
    private let retrievalEngine = RetrievalEngine()

    var selectableFolders: [IndexedFolder] {
        folders.filter(\.isSelectable)
    }

    var hasSelectedFolders: Bool {
        !selectedFolderIds.isEmpty
    }

    // MARK: - Initialization

    func initialize() async {
        do {
            try await db.initialize()
            folders = try await db.fetchAllFolders()
            conversations = try await db.fetchConversations()
            await checkOllamaConnection()

            // Verify folder paths still exist
            for (index, folder) in folders.enumerated() where folder.status == .ready {
                if !FileManager.default.fileExists(atPath: folder.path) {
                    folders[index].status = .unavailable
                    try? await db.updateFolder(folders[index])
                }
            }
        } catch {
            print("Initialization error: \(error)")
        }
    }

    // MARK: - Ollama Connection

    func checkOllamaConnection() async {
        let client = OllamaClient(baseURL: settings.ollamaBaseURL)
        ollamaConnected = await client.isAvailable()
        if ollamaConnected {
            availableModels = (try? await client.availableModels()) ?? []
        }
    }

    // MARK: - Folder Management

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to index"
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await addFolderAtPath(url.path)
        }
    }

    func addFolderAtPath(_ path: String) async {
        guard let exists = try? await db.folderExists(path: path), !exists else { return }

        var folder = IndexedFolder.new(path: path)
        do {
            try await db.insertFolder(folder)
            folders.append(folder)
            startIndexing(folder)
        } catch {
            print("Failed to add folder: \(error)")
        }
    }

    func removeFolder(_ folder: IndexedFolder) async {
        // Remove from UI immediately
        folders.removeAll { $0.id == folder.id }
        selectedFolderIds.remove(folder.id)
        indexingProgress.removeValue(forKey: folder.id)

        // Cancel any ongoing indexing
        await indexingEngine.cancelIndexing(folderId: folder.id)

        // Delete from database (cascade deletes chunks)
        do {
            try await db.deleteFolder(id: folder.id)
        } catch {
            print("Failed to remove folder: \(error)")
        }
    }

    func reindexFolder(_ folder: IndexedFolder) async {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }

        // Mark as reindexing
        folders[index].status = .reindexing
        folders[index].updatedAt = Date()
        selectedFolderIds.remove(folder.id)

        do {
            try await db.updateFolder(folders[index])
            // Delete existing chunks
            try await db.deleteChunks(forFolderId: folder.id)
            // Start fresh indexing
            startIndexing(folders[index])
        } catch {
            folders[index].status = .failed
            folders[index].errorMessage = error.localizedDescription
        }
    }

    private func startIndexing(_ folder: IndexedFolder) {
        let settings = self.settings
        Task {
            await indexingEngine.indexFolder(folder, settings: settings) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.indexingProgress[folder.id] = progress

                    if progress.phase == .complete {
                        if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
                            self.folders[index].status = .ready
                            self.folders[index].fileCount = progress.filesTotal
                            self.folders[index].chunkCount = progress.chunksCreated
                            self.folders[index].lastIndexedAt = Date()
                            self.folders[index].errorMessage = nil
                            self.folders[index].updatedAt = Date()
                        }
                        // Remove progress after a delay
                        try? await Task.sleep(for: .seconds(2))
                        self.indexingProgress.removeValue(forKey: folder.id)
                    } else if progress.phase == .failed {
                        if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
                            self.folders[index].status = .failed
                            self.folders[index].updatedAt = Date()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chat

    func sendQuestion() async {
        let question = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, hasSelectedFolders, !isGenerating else { return }

        currentQuestion = ""
        isGenerating = true
        chatError = nil
        streamingResponse = ""

        // Create or use conversation
        let conversationId: String
        if let existingId = currentConversationId {
            conversationId = existingId
        } else {
            let conversation = Conversation(
                id: UUID().uuidString,
                title: String(question.prefix(60)),
                createdAt: Date(),
                updatedAt: Date()
            )
            do {
                try await db.insertConversation(conversation)
                conversations.insert(conversation, at: 0)
                currentConversationId = conversation.id
                conversationId = conversation.id
            } catch {
                chatError = "Failed to create conversation"
                isGenerating = false
                return
            }
        }

        // Add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: .user,
            content: question,
            sources: nil,
            folderIds: Array(selectedFolderIds),
            createdAt: Date()
        )
        messages.append(userMessage)
        try? await db.insertMessage(userMessage)

        do {
            // Retrieve relevant chunks
            let results = try await retrievalEngine.retrieve(
                query: question,
                folderIds: Array(selectedFolderIds),
                topK: settings.topK,
                settings: settings
            )

            let (context, sources) = retrievalEngine.buildContext(from: results)

            // Build prompt
            let systemPrompt = """
            You are a helpful assistant that answers questions about the user's documents. \
            Use the following context from their files to answer the question. \
            If the context doesn't contain enough information to answer, say so. \
            Always cite which source files your answer comes from.

            Context:
            \(context)
            """

            let ollamaMessages = [
                OllamaChatMessage(role: "system", content: systemPrompt),
                OllamaChatMessage(role: "user", content: question)
            ]

            let client = OllamaClient(baseURL: settings.ollamaBaseURL)
            let stream = client.chatStream(
                model: settings.chatModel,
                messages: ollamaMessages,
                temperature: settings.temperature
            )

            for try await token in stream {
                streamingResponse += token
            }

            // Save assistant message
            let assistantMessage = ChatMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                role: .assistant,
                content: streamingResponse,
                sources: sources,
                folderIds: Array(selectedFolderIds),
                createdAt: Date()
            )
            messages.append(assistantMessage)
            try? await db.insertMessage(assistantMessage)
            try? await db.updateConversationTimestamp(id: conversationId)

            streamingResponse = ""
        } catch {
            chatError = error.localizedDescription
        }

        isGenerating = false
    }

    func startNewConversation() {
        currentConversationId = nil
        messages = []
        streamingResponse = ""
        chatError = nil
    }

    func loadConversation(_ conversation: Conversation) async {
        currentConversationId = conversation.id
        messages = (try? await db.fetchMessages(forConversationId: conversation.id)) ?? []
        streamingResponse = ""
        chatError = nil
    }

    // MARK: - Folder Selection

    func toggleFolderSelection(_ folderId: String) {
        if selectedFolderIds.contains(folderId) {
            selectedFolderIds.remove(folderId)
        } else {
            selectedFolderIds.insert(folderId)
        }
    }

    func selectAllFolders() {
        selectedFolderIds = Set(selectableFolders.map(\.id))
    }

    func deselectAllFolders() {
        selectedFolderIds.removeAll()
    }
}
