import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            ChatView()
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await appState.initialize()
        }
        .sheet(isPresented: $state.showFolderPicker) {
            FolderPickerSheet()
        }
        .overlay {
            if !appState.ollamaConnected {
                OllamaConnectionOverlay()
            }
        }
    }
}

struct OllamaConnectionOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.yellow)
                        .offset(x: 24, y: 24)
                )

            Text("Ollama Not Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Make sure Ollama is running on your machine.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Retry") {
                    Task {
                        await appState.checkOllamaConnection()
                    }
                }
                .buttonStyle(.borderedProminent)

                Link("Get Ollama", destination: URL(string: "https://ollama.com")!)
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 20)
    }
}
