import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List {
            // Folders section
            Section {
                if appState.folders.isEmpty {
                    ContentUnavailableView {
                        Label("No Folders", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Add a folder to start indexing documents.")
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(appState.folders) { folder in
                        FolderRow(folder: folder)
                    }
                }
            } header: {
                HStack {
                    Text("Knowledge Base")
                        .font(.headline)
                    Spacer()
                    Button {
                        appState.addFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Folder")
                }
            }

            // Selection controls
            if !appState.selectableFolders.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Button("Select All") {
                            appState.selectAllFolders()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Button("Deselect All") {
                            appState.deselectAllFolders()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
                .listRowSeparator(.hidden)

            // Experts section
            Section {
                if appState.experts.isEmpty {
                    ContentUnavailableView {
                        Label("No Experts", systemImage: "person.badge.key")
                    } description: {
                        Text("Create .md files with 'Expert' prefix in your folders.")
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(appState.experts) { expert in
                        ExpertRow(expert: expert)
                    }
                }
            } header: {
                HStack {
                    Text("Experts")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await appState.refreshExperts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Experts")
                }
            }

            Divider()
                .listRowSeparator(.hidden)

            // Conversations section
            Section {
                Button {
                    appState.startNewConversation()
                } label: {
                    Label("New Conversation", systemImage: "plus.message")
                }
                .buttonStyle(.borderless)

                ForEach(appState.conversations) { conversation in
                    ConversationRow(conversation: conversation)
                }
            } header: {
                Text("History")
                    .font(.headline)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.addFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }
}

struct FolderRow: View {
    @Environment(AppState.self) private var appState
    let folder: IndexedFolder
    @State private var isHovering = false
    @State private var showActions = false

    private var isSelected: Bool {
        appState.selectedFolderIds.contains(folder.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox (only for selectable folders)
            if folder.isSelectable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.body)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) {
                            appState.toggleFolderSelection(folder.id)
                        }
                    }
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.quaternary)
                    .font(.body)
            }

            // Folder icon
            Image(systemName: folderIcon)
                .foregroundStyle(folderColor)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    statusBadge
                    if folder.status == .ready, folder.chunkCount > 0 {
                        Text("\(folder.chunkCount) chunks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Progress indicator for indexing
            if let progress = appState.indexingProgress[folder.id] {
                if progress.phase != .complete && progress.phase != .failed {
                    ProgressView(value: progress.fractionComplete)
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if folder.status == .ready || folder.status == .failed {
                Button("Reindex") {
                    Task { await appState.reindexFolder(folder) }
                }
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            }

            Divider()

            Button("Remove", role: .destructive) {
                Task { await appState.removeFolder(folder) }
            }
        }
    }

    private var folderIcon: String {
        switch folder.status {
        case .ready: return "folder.fill"
        case .indexing, .reindexing: return "folder.fill.badge.gearshape"
        case .failed: return "folder.fill.badge.questionmark"
        case .unavailable: return "folder.badge.questionmark"
        }
    }

    private var folderColor: Color {
        switch folder.status {
        case .ready: return .accentColor
        case .indexing, .reindexing: return .orange
        case .failed: return .red
        case .unavailable: return .gray
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch folder.status {
        case .ready:
            Text("Ready")
                .font(.caption2)
                .foregroundStyle(.green)
        case .indexing:
            Text("Indexing...")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .reindexing:
            Text("Reindexing...")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .failed:
            Text("Failed")
                .font(.caption2)
                .foregroundStyle(.red)
        case .unavailable:
            Text("Unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ConversationRow: View {
    @Environment(AppState.self) private var appState
    let conversation: Conversation
    @State private var isHovering = false

    private var isActive: Bool {
        appState.currentConversationId == conversation.id
    }

    var body: some View {
        Button {
            Task { await appState.loadConversation(conversation) }
        } label: {
            HStack {
                Image(systemName: "bubble.left")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .font(.caption)

                Text(conversation.title ?? "Untitled")
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer()
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}

struct ExpertRow: View {
    @Environment(AppState.self) private var appState
    let expert: Expert
    @State private var isHovering = false

    private var isActive: Bool {
        appState.selectedExpert?.id == expert.id
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isActive {
                    appState.selectedExpert = nil
                } else {
                    appState.selectedExpert = expert
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Selection indicator
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.orange : Color.secondary)
                    .font(.body)

                // Expert icon
                Image(systemName: "person.badge.key.fill")
                    .foregroundStyle(.orange)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(expert.name)
                        .font(.body)
                        .lineLimit(1)

                    if let description = expert.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else {
                        Text("from \(expert.sourceFolder)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
    }
}
