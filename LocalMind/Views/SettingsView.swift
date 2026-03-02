import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            IndexingSettingsTab()
                .tabItem {
                    Label("Indexing", systemImage: "doc.text.magnifyingglass")
                }
        }
        .frame(width: 480, height: 320)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Ollama Connection") {
                TextField("Base URL", text: $state.settings.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(appState.ollamaConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.ollamaConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Test Connection") {
                        Task {
                            appState.settings.save()
                            await appState.checkOllamaConnection()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModelSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Chat Model") {
                TextField("Model Name", text: $state.settings.chatModel)
                    .textFieldStyle(.roundedBorder)
                Text("The Ollama model used for answering questions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !appState.availableModels.isEmpty {
                    Picker("Available Models", selection: $state.settings.chatModel) {
                        ForEach(appState.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
            }

            Section("Embedding Model") {
                TextField("Model Name", text: $state.settings.embeddingModel)
                    .textFieldStyle(.roundedBorder)
                Text("The model used for generating document embeddings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generation") {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", appState.settings.temperature))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $state.settings.temperature, in: 0...2, step: 0.1)

                HStack {
                    Text("Top-K Results")
                    Spacer()
                    Text("\(appState.settings.topK)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: .init(
                    get: { Double(appState.settings.topK) },
                    set: { appState.settings.topK = Int($0) }
                ), in: 1...20, step: 1)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: appState.settings.chatModel) { appState.settings.save() }
        .onChange(of: appState.settings.embeddingModel) { appState.settings.save() }
        .onChange(of: appState.settings.temperature) { appState.settings.save() }
        .onChange(of: appState.settings.topK) { appState.settings.save() }
    }
}

struct IndexingSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Chunking") {
                HStack {
                    Text("Chunk Size (characters)")
                    Spacer()
                    Text("\(appState.settings.chunkSize)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: .init(
                    get: { Double(appState.settings.chunkSize) },
                    set: { appState.settings.chunkSize = Int($0) }
                ), in: 500...5000, step: 100)

                HStack {
                    Text("Overlap (characters)")
                    Spacer()
                    Text("\(appState.settings.chunkOverlap)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: .init(
                    get: { Double(appState.settings.chunkOverlap) },
                    set: { appState.settings.chunkOverlap = Int($0) }
                ), in: 0...1000, step: 50)

                Text("Changing these settings only affects new indexing operations. Existing folders need to be reindexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Supported Formats") {
                let extensions = FileParserRegistry.shared.allSupportedExtensions.sorted()
                Text(extensions.map { ".\($0)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: appState.settings.chunkSize) { appState.settings.save() }
        .onChange(of: appState.settings.chunkOverlap) { appState.settings.save() }
    }
}
