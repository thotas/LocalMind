import Foundation

actor ExpertManager {
    static let shared = ExpertManager()

    private init() {}

    /// Scans indexed folders for expert markdown files
    /// Experts are identified by:
    /// 1. Files named "Expert*.md" or "expert*.md"
    /// 2. Folders named "Expert*" or "expert*"
    func detectExperts(from folders: [IndexedFolder]) -> [Expert] {
        var experts: [Expert] = []

        for folder in folders where folder.status == .ready {
            let folderPath = folder.path
            let expertsInFolder = scanFolderForExperts(at: folderPath)
            experts.append(contentsOf: expertsInFolder)
        }

        return experts
    }

    private func scanFolderForExperts(at path: String) -> [Expert] {
        var experts: [Expert] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return experts
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent
            let isExpertFile = isExpertFile(named: fileName)

            if isExpertFile {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    if let expert = Expert.parse(from: fileURL.path, content: content) {
                        experts.append(expert)
                    }
                }
            }
        }

        return experts
    }

    private func isExpertFile(named fileName: String) -> Bool {
        let lowercased = fileName.lowercased()

        // Check for Expert: prefix or expert: prefix
        if lowercased.hasPrefix("expert") && lowercased.contains(".md") {
            return true
        }

        // Check if file is in an Expert: named folder
        // This is handled by the folder scanning

        return false
    }

    /// Loads expert instructions for a specific expert
    func loadExpertInstructions(expert: Expert) -> String? {
        guard let content = try? String(contentsOf: URL(fileURLWithPath: expert.sourcePath), encoding: .utf8) else {
            return nil
        }

        // Re-parse to get the latest instructions
        if let updatedExpert = Expert.parse(from: expert.sourcePath, content: content) {
            return updatedExpert.instructions
        }

        return expert.instructions
    }
}
