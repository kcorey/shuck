import AppKit
import Vision
import PDFKit

// MARK: - File Type Detection

enum FileCategory {
    case pdf
    case image
    case richDocument
    case plainText
}

func fileCategory(for path: String) -> FileCategory {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf":
        return .pdf
    case "png", "jpg", "jpeg", "tiff", "tif", "heic", "heics", "webp",
         "gif", "bmp", "jp2", "jxl":
        return .image
    case "docx", "doc", "odt", "rtf", "rtfd":
        return .richDocument
    default:
        return .plainText
    }
}

// MARK: - Text Sanitization

/// Removes non-displayable Unicode characters while preserving legitimate Unicode
/// (CJK, emoji, accented Latin, Arabic, Cyrillic, etc.)
func sanitizeText(_ text: String) -> String {
    return String(text.unicodeScalars.filter { scalar in
        let cat = scalar.properties.generalCategory

        // Remove control characters, except tab/newline/CR
        if cat == .control {
            return scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
        }

        // Remove Private Use Area (custom PDF glyphs with no standard rendering)
        if cat == .privateUse { return false }

        // Remove format/invisible characters (zero-width spaces, soft hyphens, bidi marks, BOM)
        if cat == .format { return false }

        // Remove replacement characters (U+FFFD box-with-question-mark, U+FFFC object replacement)
        if scalar.value == 0xFFFD || scalar.value == 0xFFFC { return false }

        return true
    })
}

// MARK: - Text Extraction

func extractPDF(from url: URL) -> String {
    guard let doc = PDFDocument(url: url) else {
        return "[Could not open PDF]"
    }
    return doc.string ?? "[No text found in PDF]"
}

func extractImageOCR(from url: URL) -> String {
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        return "[Could not load image]"
    }

    let semaphore = DispatchSemaphore(value: 0)
    var recognizedText = ""

    let request = VNRecognizeTextRequest { request, error in
        defer { semaphore.signal() }
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
        recognizedText = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    semaphore.wait()

    return recognizedText.isEmpty ? "[No text recognized in image]" : recognizedText
}

func extractRichDocument(from url: URL) -> String {
    do {
        let attrString = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return attrString.string
    } catch {
        return "[Could not read document: \(error.localizedDescription)]"
    }
}

func extractPlainText(from url: URL) -> String {
    if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
    if let text = try? String(contentsOf: url, encoding: .macOSRoman) { return text }
    if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
    return "[Could not read file as text]"
}

func extractText(from path: String) -> String {
    let url = URL(fileURLWithPath: path)
    let raw: String
    switch fileCategory(for: path) {
    case .pdf:          raw = extractPDF(from: url)
    case .image:        raw = extractImageOCR(from: url)
    case .richDocument: raw = extractRichDocument(from: url)
    case .plainText:    raw = extractPlainText(from: url)
    }
    return sanitizeText(raw)
}

// MARK: - Combine Text

func combineTexts(from paths: [String]) -> String {
    var sections: [String] = []
    for path in paths {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let text = extractText(from: path)
        sections.append("--- \(filename) ---\n\(text)")
    }
    return sections.joined(separator: "\n\n")
}

// MARK: - AppKit Window

class AppDelegate: NSObject, NSApplicationDelegate {
    let combinedText: String
    var window: NSWindow!
    var scrollView: NSScrollView!
    var textView: NSTextView!
    var numberedCheckbox: NSButton!
    var wrapCheckbox: NSButton!
    var currentToast: NSView?

    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    lazy var charWidth: CGFloat = font.maximumAdvancement.width
    // "%6d " — 6-digit number + 1 space separator
    lazy var numberColumnWidth: CGFloat = charWidth * 7

    init(text: String) {
        self.combinedText = text
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main?.visibleFrame else {
            fputs("No screen available\n", stderr)
            NSApplication.shared.terminate(nil)
            return
        }

        // Size the window to fit the widest line, capped at 2/3 of the screen
        let textPadding: CGFloat = 32  // 16px inset × 2 sides
        let maxLineWidth = combinedText
            .components(separatedBy: "\n")
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 400
        let windowWidth = max(
            min((maxLineWidth + textPadding) * 1.05, screen.width * 2.0 / 3.0),
            400
        )
        let windowHeight = screen.height * 0.8

        window = NSWindow(
            contentRect: NSRect(
                x: screen.origin.x + (screen.width - windowWidth) / 2,
                y: screen.origin.y + (screen.height - windowHeight) / 2,
                width: windowWidth,
                height: windowHeight
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shucked Text"
        window.isReleasedWhenClosed = false

        setupUI()
        setupKeyHandler()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in NSApplication.shared.terminate(nil) }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
    }

    // MARK: UI Setup

    func setupUI() {
        let contentView = window.contentView!

        // Toolbar
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        numberedCheckbox = NSButton(checkboxWithTitle: "Numbered", target: self, action: #selector(updateDisplay))
        numberedCheckbox.state = .off
        numberedCheckbox.translatesAutoresizingMaskIntoConstraints = false

        wrapCheckbox = NSButton(checkboxWithTitle: "Wrap", target: self, action: #selector(updateDisplay))
        wrapCheckbox.state = .off
        wrapCheckbox.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(numberedCheckbox)
        toolbar.addSubview(wrapCheckbox)

        // Separator line below toolbar
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Text view
        textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        contentView.addSubview(toolbar)
        contentView.addSubview(separator)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            wrapCheckbox.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            wrapCheckbox.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            numberedCheckbox.trailingAnchor.constraint(equalTo: wrapCheckbox.leadingAnchor, constant: -16),
            numberedCheckbox.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Resolve auto-layout so contentSize is accurate before populating text
        contentView.layoutSubtreeIfNeeded()
        updateDisplay()
        setupSelectionObserver()
    }

    // MARK: Key Handler

    func setupKeyHandler() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 {  // Escape
                NSApplication.shared.terminate(nil)
                return nil
            }
            // Cmd-A / Cmd-C (accessory-policy apps have no menu bar to route these)
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "a": self.textView.selectAll(nil); return nil
                case "c": self.textView.copy(nil);      return nil
                case "n": self.numberedCheckbox.performClick(nil); return nil
                case "w": self.wrapCheckbox.performClick(nil);     return nil
                default: break
                }
            }
            // Left/right arrow keys scroll horizontally when wrap is off
            if self.wrapCheckbox.state == .off {
                let amount = self.charWidth * 4
                let clip = self.scrollView.contentView
                var origin = clip.bounds.origin
                if event.keyCode == 123 {  // left arrow
                    origin.x = max(0, origin.x - amount)
                    clip.scroll(to: origin)
                    self.scrollView.reflectScrolledClipView(clip)
                    return nil
                } else if event.keyCode == 124 {  // right arrow
                    let maxX = max(0, (self.scrollView.documentView?.frame.width ?? 0) - clip.bounds.width)
                    origin.x = min(maxX, origin.x + amount)
                    clip.scroll(to: origin)
                    self.scrollView.reflectScrolledClipView(clip)
                    return nil
                }
            }
            return event
        }
    }

    // MARK: Display

    @objc func updateDisplay() {
        let isNumbered = numberedCheckbox.state == .on
        let isWrapping = wrapCheckbox.state == .on

        if isWrapping {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.autoresizingMask = [.width]
            // Snap the frame width to match the scroll view before layout
            var f = textView.frame
            f.size.width = scrollView.contentSize.width
            textView.frame = f
        } else {
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = [.height]
        }

        // Paragraph style: indent continuation lines when wrapping
        let ps = NSMutableParagraphStyle()
        if isWrapping {
            ps.headIndent = isNumbered ? numberColumnWidth : charWidth
        }

        // Build attributed string
        let lines = combinedText.components(separatedBy: "\n")
        let attrStr = NSMutableAttributedString()

        for (i, line) in lines.enumerated() {
            let nl = i < lines.count - 1 ? "\n" : ""
            if isNumbered {
                attrStr.append(NSAttributedString(
                    string: String(format: "%6d ", i + 1),
                    attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: ps]
                ))
            }
            attrStr.append(NSAttributedString(
                string: line + nl,
                attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: ps]
            ))
        }

        textView.textStorage?.setAttributedString(attrStr)

        if !isWrapping {
            textView.sizeToFit()
        }
    }

    // MARK: Selection → auto-copy

    func setupSelectionObserver() {
        NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Only fire on mouse-up (i.e. the user finished dragging a selection)
            guard NSApp.currentEvent?.type == .leftMouseUp else { return }
            guard self.textView.selectedRange().length > 0 else { return }
            self.textView.copy(nil)
            self.showCopiedToast()
        }
    }

    // MARK: Toast

    func showCopiedToast() {
        guard let contentView = window.contentView else { return }

        // Remove any in-flight toast
        currentToast?.removeFromSuperview()

        let toast = NSView()
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        toast.layer?.cornerRadius = 8
        toast.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Copied!")
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(label)

        contentView.addSubview(toast)
        currentToast = toast

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: toast.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: toast.centerYAnchor),
            toast.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 24),
            toast.heightAnchor.constraint(equalTo: label.heightAnchor, constant: 12),
            toast.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak toast] in
            guard let toast = toast, toast === self?.currentToast else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                toast.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                toast.removeFromSuperview()
                if toast === self?.currentToast { self?.currentToast = nil }
            }
        }
    }
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    fputs("Usage: shuck <file1> [file2] ...\n", stderr)
    exit(1)
}

let combinedText = combineTexts(from: args)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate(text: combinedText)
app.delegate = delegate
app.run()
