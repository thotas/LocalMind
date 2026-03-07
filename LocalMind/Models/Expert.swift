import Foundation

struct Expert: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var instructions: String
    var icon: String?
    var sourcePath: String
    var sourceFolder: String
    var lastModified: Date

    static func parse(from filePath: String, content: String) -> Expert? {
        // Parse YAML frontmatter between --- blocks
        var frontmatter: [String: String] = [:]
        var instructionsContent = content

        let lines = content.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var frontmatterLines: [String] = []
            var inFrontmatter = false
            var firstDashFound = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed == "---" {
                    if !firstDashFound {
                        firstDashFound = true
                        inFrontmatter = true
                        continue
                    } else {
                        inFrontmatter = false
                        continue
                    }
                }

                if inFrontmatter {
                    if let colonIndex = line.firstIndex(of: ":") {
                        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                        frontmatter[key] = value
                    }
                } else if firstDashFound {
                    // This is the content after frontmatter
                    if let dashIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                        let contentLines = Array(lines[(dashIndex + 1)...])
                        instructionsContent = contentLines
                            .joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    break
                }
            }
        }

        // Extract name from frontmatter or filename
        let fileName = (filePath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")

        let name = frontmatter["name"] ?? fileName.replacingOccurrences(of: "Expert:", with: "").trimmingCharacters(in: .whitespaces)
        let description = frontmatter["description"]
        let icon = frontmatter["icon"]

        // If no frontmatter, use entire content as instructions
        if instructionsContent.isEmpty || instructionsContent == content {
            instructionsContent = content
        }

        let parentFolder = (filePath as NSString).deletingLastPathComponent
        let folderName = (parentFolder as NSString).lastPathComponent

        let lastModified = (try? FileManager.default.attributesOfItem(atPath: filePath)[.modificationDate] as? Date) ?? Date()

        return Expert(
            id: UUID().uuidString,
            name: name,
            description: description,
            instructions: instructionsContent,
            icon: icon,
            sourcePath: filePath,
            sourceFolder: folderName,
            lastModified: lastModified
        )
    }
}
