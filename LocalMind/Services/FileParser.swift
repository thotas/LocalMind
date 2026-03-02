import Foundation
import PDFKit
import ZIPFoundation

protocol FileParser: Sendable {
    var supportedExtensions: Set<String> { get }
    func parse(fileAt url: URL) throws -> String
}

struct TextFileParser: FileParser {
    let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "xml", "yaml", "yml",
        "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java",
        "c", "cpp", "h", "hpp", "rb", "sh", "bash", "zsh", "fish",
        "html", "css", "scss", "less", "sql", "r", "m", "mm",
        "kt", "scala", "clj", "ex", "exs", "hs", "lua", "pl",
        "toml", "ini", "cfg", "conf", "env", "log"
    ]

    func parse(fileAt url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

struct PDFFileParser: FileParser {
    let supportedExtensions: Set<String> = ["pdf"]

    func parse(fileAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ParserError.cannotOpen(url.path)
        }

        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText
                text += "\n\n"
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.noContent(url.path)
        }

        return text
    }
}

struct DocxFileParser: FileParser {
    let supportedExtensions: Set<String> = ["docx"]

    func parse(fileAt url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ParserError.cannotOpen(url.path)
        }

        guard let entry = archive["word/document.xml"] else {
            throw ParserError.invalidFormat(url.path)
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { data in
            xmlData.append(data)
        }

        let parser = DocxXMLParser(data: xmlData)
        return parser.parse()
    }
}

/// Simple XML parser for DOCX word/document.xml
final class DocxXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let data: Data
    private var text = ""
    private var currentElement = ""
    private var isInParagraph = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return text
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "w:p" {
            isInParagraph = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "w:t" {
            text += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "w:p" && isInParagraph {
            text += "\n"
            isInParagraph = false
        }
    }
}

/// Registry of all available file parsers
struct FileParserRegistry: Sendable {
    static let shared = FileParserRegistry()

    private let parsers: [any FileParser] = [
        TextFileParser(),
        PDFFileParser(),
        DocxFileParser()
    ]

    func parser(for extension: String) -> (any FileParser)? {
        let ext = `extension`.lowercased()
        return parsers.first { $0.supportedExtensions.contains(ext) }
    }

    var allSupportedExtensions: Set<String> {
        parsers.reduce(into: Set<String>()) { result, parser in
            result.formUnion(parser.supportedExtensions)
        }
    }
}

enum ParserError: LocalizedError {
    case cannotOpen(String)
    case noContent(String)
    case invalidFormat(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "Cannot open file: \(path)"
        case .noContent(let path): return "No extractable content in: \(path)"
        case .invalidFormat(let path): return "Invalid file format: \(path)"
        case .unsupportedFormat(let ext): return "Unsupported format: \(ext)"
        }
    }
}
