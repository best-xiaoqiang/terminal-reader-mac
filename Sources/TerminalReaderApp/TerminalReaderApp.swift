import SwiftUI
import AppKit

private extension NSAttributedString.Key {
    static let terminalParagraphIndex = NSAttributedString.Key("TerminalReaderParagraphIndex")
}

@main
struct TerminalReaderApp: App {
    var body: some Scene {
        WindowGroup("Terminal Reader") {
            ReaderWindow()
                .frame(minWidth: 680, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ReaderWindow: View {
    @AppStorage("readerLastBookPath") private var lastBookPath = ""
    @State private var progress = 0.0
    @AppStorage("readerFontSize") private var fontSize = 15.0
    @AppStorage("readerLineSpacing") private var lineSpacing = 6.0
    @State private var book: EpubBook?
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var documentText: String {
        guard let book else { return "" }
        return book.chapters.enumerated().map { index, chapter in
            let heading = "[ CHAPTER " + String(index + 1) + " / " + String(book.chapters.count) + " ]"
            return heading + "\n" + chapter.title + "\n\n" + chapter.text
        }.joined(separator: "\n\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if book != nil {
                ReaderDocumentView(text: documentText, fontSize: fontSize, lineSpacing: lineSpacing, progress: $progress)
            } else {
                emptyState
            }
            statusBar
        }
        .background(terminalBlack)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.epub]) { result in
            switch result {
            case .success(let url): openBook(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Unable to Open Book", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: progress) { value in
            saveProgress(value)
        }
        .onAppear {
            // Older builds allowed an oversized value to persist in preferences.
            if fontSize > 18 { fontSize = 15 }
            guard book == nil, !lastBookPath.isEmpty else { return }
            do {
                let url = URL(fileURLWithPath: lastBookPath)
                let loadedBook = try EpubBook(url: url)
                progress = savedProgress(for: url)
                book = loadedBook
            } catch {
                lastBookPath = ""
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("TERMINAL READER")
                .fontWeight(.semibold)
            Text(book?.title ?? "NO BOOK OPEN")
                .foregroundColor(terminalGreen.opacity(0.72))
                .lineLimit(1)
            Spacer()
            Button("A−") { fontSize = max(12, fontSize - 1) }
                .buttonStyle(.plain)
            Text(String(Int(fontSize)) + "px")
                .foregroundColor(terminalGreen.opacity(0.65))
            Button("A+") { fontSize = min(20, fontSize + 1) }
                .buttonStyle(.plain)
            Button("L−") { lineSpacing = max(0, lineSpacing - 1) }
                .buttonStyle(.plain)
            Text("L " + String(Int(lineSpacing)))
                .foregroundColor(terminalGreen.opacity(0.65))
            Button("L+") { lineSpacing = min(16, lineSpacing + 1) }
                .buttonStyle(.plain)
            Button("Open EPUB…") { isImporting = true }
                .buttonStyle(.plain)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(terminalGreen)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(terminalBlack)
        .overlay(alignment: .bottom) { Divider().background(terminalGreen.opacity(0.25)) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("NO BOOK OPEN")
                .fontWeight(.semibold)
            Text("Select an EPUB file to start reading.")
                .foregroundColor(terminalGreen.opacity(0.65))
            Button("Open EPUB…") { isImporting = true }
                .buttonStyle(.bordered)
        }
        .font(.system(size: 15, design: .monospaced))
        .foregroundColor(terminalGreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text(book == nil ? "WAITING" : String(book?.chapters.count ?? 0) + " CHAPTERS LOADED")
            Spacer()
            Text(String(Int(progress * 100)) + "%")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(terminalGreen.opacity(0.68))
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(terminalBlack)
        .overlay(alignment: .top) { Divider().background(terminalGreen.opacity(0.22)) }
    }

    private func openBook(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let loadedBook = try EpubBook(url: url)
            lastBookPath = bookKey(for: url)
            progress = savedProgress(for: url)
            book = loadedBook
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bookKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func savedProgress(for url: URL) -> Double {
        let map = UserDefaults.standard.dictionary(forKey: "readerProgressByBook") ?? [:]
        return (map[bookKey(for: url)] as? NSNumber)?.doubleValue ?? 0
    }

    private func saveProgress(_ value: Double) {
        guard !lastBookPath.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: "readerProgressByBook") ?? [:]
        map[lastBookPath] = min(1, max(0, value))
        UserDefaults.standard.set(map, forKey: "readerProgressByBook")
    }

    private var terminalBlack: Color { Color(red: 0.025, green: 0.025, blue: 0.025) }
    private var terminalGreen: Color { Color(red: 0.56, green: 0.78, blue: 0.62) }
}

struct ReaderDocumentView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    @Binding var progress: Double

    func makeCoordinator() -> Coordinator { Coordinator(progress: $progress) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = true
        scroll.backgroundColor = terminalBlack
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let textView = PagingTextView(frame: .zero, textContainer: container)
        scroll.documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.selectedTextAttributes = [
            .foregroundColor: NSColor.black,
            .backgroundColor: NSColor(red: 0.56, green: 0.78, blue: 0.62, alpha: 1)
        ]
        textView.drawsBackground = false
        textView.backgroundColor = terminalBlack
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scroll
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak coordinator = context.coordinator] _ in
            coordinator?.recordProgress()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let signature = String(text.hashValue) + ":" + String(fontSize) + ":" + String(lineSpacing)
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        context.coordinator.isRestoring = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(lineSpacing)
        paragraph.paragraphSpacing = 5
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let styledText = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var contentIndex = 0
        (text as NSString).enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, paragraphRange, _, _ in
            let paragraphText = (text as NSString).substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isContent = !paragraphText.isEmpty
            if isContent {
                styledText.addAttribute(.terminalParagraphIndex, value: contentIndex, range: paragraphRange)
                contentIndex += 1
            }
        }
        textView.textStorage?.setAttributedString(styledText)
        DispatchQueue.main.async {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            context.coordinator.restoreProgress()
            scroll.window?.makeFirstResponder(textView)
        }
    }

    private var terminalBlack: NSColor { NSColor(red: 0.025, green: 0.025, blue: 0.025, alpha: 1) }

    final class PagingTextView: NSTextView {
        override func draw(_ dirtyRect: NSRect) {
            backgroundColor.setFill()
            dirtyRect.fill()

            if let layoutManager, let textContainer, let storage = textStorage {
                let origin = textContainerOrigin
                var paragraphs: [(index: Int, rect: NSRect)] = []
                let fullCharacterRange = NSRange(location: 0, length: storage.length)
                storage.enumerateAttribute(.terminalParagraphIndex, in: fullCharacterRange) { value, characterRange, _ in
                    guard let index = value as? Int, characterRange.length > 0 else { return }
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    paragraphs.append((index: index, rect: rect))
                }
                for position in paragraphs.indices where !paragraphs[position].index.isMultiple(of: 2) {
                    let paragraphRect = paragraphs[position].rect
                    let top = position > 0
                        ? (paragraphs[position - 1].rect.maxY + paragraphRect.minY) / 2
                        : paragraphRect.minY
                    let bottom = position + 1 < paragraphs.count
                        ? (paragraphRect.maxY + paragraphs[position + 1].rect.minY) / 2
                        : paragraphRect.maxY
                    let fullWidthRect = NSRect(
                        x: self.bounds.minX,
                        y: top + origin.y,
                        width: self.bounds.width,
                        height: max(0, bottom - top)
                    )
                    guard fullWidthRect.intersects(dirtyRect) else { continue }
                    NSColor(red: 0.115, green: 0.115, blue: 0.115, alpha: 1).setFill()
                    fullWidthRect.intersection(dirtyRect).fill()
                }
            }

            super.draw(dirtyRect)
        }

        override func keyDown(with event: NSEvent) {
            guard event.charactersIgnoringModifiers == " ", let scroll = enclosingScrollView else {
                super.keyDown(with: event)
                return
            }
            let visible = scroll.contentView.bounds
            let maximum = max(0, bounds.height - visible.height)
            let isBackwards = event.modifierFlags.contains(.shift)
            let offset = visible.height * 0.88 * (isBackwards ? -1 : 1)
            let nextY = min(maximum, max(0, visible.origin.y + offset))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: nextY))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    final class Coordinator {
        var signature = ""
        var progress: Binding<Double>
        weak var scrollView: NSScrollView?
        var observer: NSObjectProtocol?
        var isRestoring = false

        init(progress: Binding<Double>) { self.progress = progress }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func recordProgress() {
            guard !isRestoring, let scroll = scrollView, let document = scroll.documentView else { return }
            let maximum = max(1, document.bounds.height - scroll.contentView.bounds.height)
            progress.wrappedValue = min(1, max(0, Double(scroll.contentView.bounds.origin.y / maximum)))
        }

        func restoreProgress() {
            guard let scroll = scrollView, let document = scroll.documentView else { return }
            isRestoring = true
            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(progress.wrappedValue)))
            scroll.reflectScrolledClipView(scroll.contentView)
            DispatchQueue.main.async { self.isRestoring = false }
        }
    }
}
