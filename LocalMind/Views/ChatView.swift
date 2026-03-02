import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if appState.messages.isEmpty && appState.streamingResponse.isEmpty {
                            EmptyStateView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            ForEach(appState.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            // Streaming response
                            if !appState.streamingResponse.isEmpty {
                                StreamingBubble(content: appState.streamingResponse)
                                    .id("streaming")
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .onChange(of: appState.streamingResponse) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: appState.messages.count) {
                    if let lastMessage = appState.messages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Error banner
            if let error = appState.chatError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        appState.chatError = nil
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.red.opacity(0.1))
                .foregroundStyle(.red)
            }

            Divider()

            // Input area
            InputBar()
        }
        .background(.background)
    }
}

struct EmptyStateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(spacing: 8) {
                Text("Ask Your Documents")
                    .font(.title2)
                    .fontWeight(.semibold)

                if appState.selectableFolders.isEmpty {
                    Text("Add and index a folder to get started.")
                        .foregroundStyle(.secondary)
                } else if !appState.hasSelectedFolders {
                    Text("Select one or more folders from the sidebar, then ask a question.")
                        .foregroundStyle(.secondary)
                } else {
                    let count = appState.selectedFolderIds.count
                    Text("Searching across \(count) folder\(count == 1 ? "" : "s"). Ask anything.")
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            if !appState.selectableFolders.isEmpty && !appState.hasSelectedFolders {
                Button("Select All Folders") {
                    appState.selectAllFolders()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

struct InputBar: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var state = appState

        HStack(alignment: .bottom, spacing: 12) {
            // Selected folder pills
            if appState.hasSelectedFolders {
                HStack(spacing: 4) {
                    let count = appState.selectedFolderIds.count
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }

            TextField("Ask a question about your documents...", text: $state.currentQuestion, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit {
                    if !appState.currentQuestion.isEmpty {
                        Task { await appState.sendQuestion() }
                    }
                }
                .disabled(!appState.hasSelectedFolders || appState.isGenerating)

            Button {
                Task { await appState.sendQuestion() }
            } label: {
                Image(systemName: appState.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.gray.opacity(0.3))
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !appState.currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && appState.hasSelectedFolders
        && !appState.isGenerating
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                    // Role indicator
                    HStack(spacing: 6) {
                        if message.role == .user {
                            Image(systemName: "person.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image("AppLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(message.role == .user ? "You" : "LocalMind")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    // Content
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(
                            message.role == .user
                                ? Color.accentColor.opacity(0.08)
                                : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    // Sources
                    if let sources = message.sources, !sources.isEmpty {
                        SourcesList(sources: sources)
                    }
                }

                if message.role == .assistant {
                    Spacer(minLength: 60)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct StreamingBubble: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text("LocalMind")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                        ProgressView()
                            .scaleEffect(0.5)
                    }

                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SourcesList: View {
    let sources: [SourceReference]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text("\(sources.count) source\(sources.count == 1 ? "" : "s")")
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sources) { source in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.fileName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(String(source.snippet.prefix(100)) + "...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", source.relevance * 100))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
