import Foundation

struct TextChunker: Sendable {
    let chunkSize: Int
    let overlap: Int

    init(chunkSize: Int = 2000, overlap: Int = 200) {
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    func chunk(text: String) -> [(content: String, offset: Int)] {
        guard !text.isEmpty else { return [] }
        guard text.count > chunkSize else {
            return [(content: text, offset: 0)]
        }

        var chunks: [(content: String, offset: Int)] = []
        let paragraphs = splitIntoParagraphs(text)

        var currentChunk = ""
        var currentOffset = 0
        var chunkStartOffset = 0

        for paragraph in paragraphs {
            if currentChunk.isEmpty {
                chunkStartOffset = currentOffset
            }

            // If adding this paragraph exceeds chunk size, finalize current chunk
            if !currentChunk.isEmpty && (currentChunk.count + paragraph.count + 1) > chunkSize {
                chunks.append((content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                               offset: chunkStartOffset))

                // Start new chunk with overlap from end of previous
                let overlapText = String(currentChunk.suffix(overlap))
                currentChunk = overlapText
                chunkStartOffset = currentOffset - overlapText.count
            }

            if !currentChunk.isEmpty {
                currentChunk += "\n"
            }
            currentChunk += paragraph
            currentOffset += paragraph.count + 1
        }

        // Don't forget the last chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append((content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                           offset: chunkStartOffset))
        }

        return chunks
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .flatMap { paragraph -> [String] in
                // If a single paragraph is still too large, split by sentences or hard limit
                if paragraph.count <= chunkSize {
                    return [paragraph]
                }
                return splitLongParagraph(paragraph)
            }
    }

    private func splitLongParagraph(_ text: String) -> [String] {
        // Try splitting by sentences
        let sentences = text.components(separatedBy: ". ")
        if sentences.count > 1 {
            var parts: [String] = []
            var current = ""
            for sentence in sentences {
                let candidate = current.isEmpty ? sentence : current + ". " + sentence
                if candidate.count > chunkSize && !current.isEmpty {
                    parts.append(current)
                    current = sentence
                } else {
                    current = candidate
                }
            }
            if !current.isEmpty {
                parts.append(current)
            }
            return parts
        }

        // Hard split as last resort
        var parts: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            parts.append(String(text[start..<end]))
            start = end
        }
        return parts
    }
}
