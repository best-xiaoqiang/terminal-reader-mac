import Foundation

struct EpubChapter: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

struct EpubBook {
    let title: String
    let chapters: [EpubChapter]

    init(url: URL) throws {
        guard url.pathExtension.lowercased() == "epub" else {
            throw ReaderError.unsupportedFormat
        }
        let container = try Self.unzip(url, "META-INF/container.xml")
        let containerParser = EpubXMLParser()
        containerParser.parseContainer(container)
        let opfPath = containerParser.rootFile
        guard !opfPath.isEmpty else { throw ReaderError.invalidEpub }

        let opf = try Self.unzip(url, opfPath)
        let opfParser = EpubXMLParser()
        opfParser.parseOpf(opf)
        let base = (opfPath as NSString).deletingLastPathComponent
        let hrefs = opfParser.spine.compactMap { opfParser.manifest[$0] }
        let fallback = try Self.listFiles(url).filter { ["html", "htm", "xhtml"].contains(($0 as NSString).pathExtension.lowercased()) }
        let files = hrefs.isEmpty ? fallback : hrefs.map { base.isEmpty ? $0 : base + "/" + $0 }
        let loaded = files.compactMap { path -> EpubChapter? in
            guard let raw = try? Self.unzip(url, path), let text = Self.plainText(raw), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return EpubChapter(title: (path as NSString).lastPathComponent, text: text)
        }
        guard !loaded.isEmpty else { throw ReaderError.noReadableChapter }
        title = url.deletingPathExtension().lastPathComponent
        chapters = loaded
    }

    private static func unzip(_ url: URL, _ path: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw ReaderError.invalidEpub }
        return data
    }

    private static func listFiles(_ url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
    }

    private static func plainText(_ data: Data) -> String? {
        let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        guard var text = source else { return nil }
        text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?(p|div|h[1-6]|li|br|tr|section|article)[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        entities.forEach { text = text.replacingOccurrences(of: $0.key, with: $0.value) }
        text = text.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class EpubXMLParser: NSObject, XMLParserDelegate {
    var rootFile = ""
    var manifest: [String: String] = [:]
    var spine: [String] = []

    func parseContainer(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parseOpf(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName.lowercased() {
        case "rootfile": rootFile = attributeDict["full-path"] ?? rootFile
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] { manifest[id] = href }
        case "itemref":
            if let idref = attributeDict["idref"] { spine.append(idref) }
        default: break
        }
    }
}

enum ReaderError: LocalizedError {
    case unsupportedFormat, invalidEpub, noReadableChapter
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "This version supports EPUB only. Convert MOBI files with Calibre first."
        case .invalidEpub: return "The EPUB structure could not be read."
        case .noReadableChapter: return "No readable EPUB chapters were found."
        }
    }
}
