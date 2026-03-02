import SwiftUI

struct FolderPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)

                Text("Add a Folder")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select a folder to index its contents for question answering.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let path = selectedPath {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(path)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        selectedPath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Choose Folder...") {
                    chooseFolder()
                }
                .buttonStyle(.bordered)

                if let path = selectedPath {
                    Button("Add & Index") {
                        Task {
                            await appState.addFolderAtPath(path)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to index"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }
}
