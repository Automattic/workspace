import AppKit

final class DraftOverlayPanel: NSPanel {
    private var allowsClose = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func forceClose() {
        allowsClose = true
        close()
        allowsClose = false
    }

    override func close() {
        guard allowsClose else {
            NSSound.beep()
            return
        }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        NSSound.beep()
    }

    override func performClose(_ sender: Any?) {
        close()
    }
}

final class DraftFocusOverlayManager {
    var onError: ((String) -> Void)?
    var onSaved: ((WPCOMGuideline, URL, Int) -> Void)?

    private var panels: [DraftOverlayPanel] = []
    private weak var focusView: DraftFocusView?
    private var focusTimer: Timer?
    private var client = WPCOMClient()

    var isShowing: Bool {
        !panels.isEmpty
    }

    func show(site: WPCOMSite) {
        dismiss()

        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        guard let primaryScreen = screenForMainOverlay(from: screens) else { return }

        for screen in screens {
            let panel = makePanel(for: screen)
            if screen == primaryScreen {
                let view = DraftFocusView(
                    frame: NSRect(origin: .zero, size: screen.frame.size),
                    siteName: site.displayName,
                    onSaveRequested: { [weak self] body in
                        self?.saveDraft(site: site, body: body)
                    },
                    onCloseRequested: { [weak self] in
                        self?.dismiss()
                    }
                )
                panel.contentView = view
                focusView = view
            } else {
                panel.contentView = DraftFocusBackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            }

            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        bringFocusToFront(focusEditor: true)
        installFocusTimer()
    }

    func dismiss() {
        focusTimer?.invalidate()
        focusTimer = nil

        let panels = panels
        self.panels = []
        focusView = nil
        panels.forEach { panel in
            panel.contentView = nil
            panel.forceClose()
        }
    }

    private func saveDraft(site: WPCOMSite, body: String) {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focusView?.showSaveFailure("Write a little first.")
            return
        }

        focusView?.setSaving(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.client.saveDraftArtifact(
                    siteID: site.id,
                    title: DraftArtifactText.title(for: body, fallback: "Draft Focus Artifact"),
                    excerpt: DraftArtifactText.excerpt(for: body),
                    content: DraftArtifactText.content(body: body)
                )

                await MainActor.run {
                    let editURL = self.client.editURL(for: saved, site: site)
                    self.onSaved?(saved, editURL, site.id)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.focusView?.showSaveFailure("Could not save artifact.")
                    self.onError?("Could not save draft artifact: \(error.localizedDescription)")
                }
            }
        }
    }

    private func makePanel(for screen: NSScreen) -> DraftOverlayPanel {
        let panel = DraftOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func screenForMainOverlay(from screens: [NSScreen]) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? screens.first
    }

    private func installFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.bringFocusToFront(focusEditor: false)
        }
        if let focusTimer {
            RunLoop.main.add(focusTimer, forMode: .common)
        }
    }

    private func bringFocusToFront(focusEditor: Bool) {
        panels.forEach { $0.orderFrontRegardless() }
        guard let panel = focusView?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if focusEditor {
            focusView?.focusEditor()
        }
    }
}

private final class DraftFocusView: NSView, NSTextViewDelegate {
    private let siteName: String?
    private let onSaveRequested: (String) -> Void
    private let onCloseRequested: () -> Void
    private let startedAt = Date()

    private let closeButton = DraftFocusButton(title: "Close", style: .secondary)
    private let saveButton = DraftFocusButton(title: "Save and Close", style: .primary)
    private let titleLabel = NSTextField(labelWithString: "Draft Focus")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let wordCountLabel = NSTextField(labelWithString: "0 words")
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let saveErrorLabel = NSTextField(labelWithString: "")
    private let placeholderLabel = NSTextField(labelWithString: "Begin here.")
    private let editorChrome = DraftFocusEditorChrome(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let textView = NSTextView(frame: .zero)

    private var timer: Timer?
    private var isSaving = false

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        siteName: String?,
        onSaveRequested: @escaping (String) -> Void,
        onCloseRequested: @escaping () -> Void
    ) {
        self.siteName = siteName
        self.onSaveRequested = onSaveRequested
        self.onCloseRequested = onCloseRequested
        super.init(frame: frameRect)
        setupView()
        startTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()
    }

    override func layout() {
        super.layout()
        layoutFocus()
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    func setSaving(_ saving: Bool) {
        isSaving = saving
        saveButton.title = saving ? "Saving..." : "Save and Close"
        saveButton.isEnabled = !saving
        closeButton.isEnabled = !saving
        saveErrorLabel.stringValue = ""
        needsDisplay = true
    }

    func showSaveFailure(_ message: String) {
        isSaving = false
        saveButton.title = "Try Again"
        saveButton.isEnabled = true
        closeButton.isEnabled = true
        saveErrorLabel.stringValue = message
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        updateMetadata()
        saveErrorLabel.stringValue = ""
    }

    @objc private func saveButtonPressed() {
        guard !isSaving else { return }
        onSaveRequested(textView.string)
    }

    @objc private func closeButtonPressed() {
        guard !isSaving else { return }
        onCloseRequested()
    }

    private func setupView() {
        wantsLayer = true
        layer?.isOpaque = false

        for label in [titleLabel, subtitleLabel, wordCountLabel, elapsedLabel, saveErrorLabel, placeholderLabel] {
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            addSubview(label)
        }

        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .draftFocusInk
        titleLabel.lineBreakMode = .byTruncatingTail

        let site = siteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitleLabel.stringValue = site?.isEmpty == false ? "Artifact for \(site!)" : "Artifact"
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .draftFocusMutedInk
        subtitleLabel.lineBreakMode = .byTruncatingTail

        for metadataLabel in [wordCountLabel, elapsedLabel] {
            metadataLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            metadataLabel.textColor = .draftFocusMutedInk
        }

        saveErrorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        saveErrorLabel.textColor = .draftFocusRed
        saveErrorLabel.lineBreakMode = .byTruncatingTail

        placeholderLabel.font = .systemFont(ofSize: 21, weight: .regular)
        placeholderLabel.textColor = .draftFocusPaperInk.withAlphaComponent(0.32)

        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        saveButton.target = self
        saveButton.action = #selector(saveButtonPressed)
        saveButton.isEnabled = false
        addSubview(closeButton)
        addSubview(saveButton)

        editorChrome.addSubview(scrollView)
        editorChrome.addSubview(placeholderLabel)
        addSubview(editorChrome)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.delegate = self
        textView.string = ""
        textView.font = NSFont.systemFont(ofSize: 21, weight: .regular)
        textView.textColor = .draftFocusPaperInk
        textView.insertionPointColor = .draftFocusAccent
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.textContainerInset = NSSize(width: 36, height: 36)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 860, height: CGFloat.greatestFiniteMagnitude)

        updateMetadata()
    }

    private func startTimer() {
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateMetadata()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateMetadata() {
        let body = textView.string
        let wordCount = DraftArtifactText.wordCount(body)
        wordCountLabel.stringValue = "\(wordCount) \(wordCount == 1 ? "word" : "words")"
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        elapsedLabel.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        placeholderLabel.isHidden = !body.isEmpty
        saveButton.isEnabled = !isSaving && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func layoutFocus() {
        let horizontalInset = max(CGFloat(42), bounds.width * 0.105)
        let verticalInset = max(CGFloat(28), bounds.height * 0.065)
        let safe = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        let contentWidth = min(CGFloat(920), safe.width)
        let left = safe.midX - contentWidth / 2
        let top = safe.minY

        closeButton.frame = NSRect(x: left, y: top, width: 96, height: 38)
        saveButton.frame = NSRect(x: left + contentWidth - 168, y: top, width: 168, height: 38)

        titleLabel.frame = NSRect(x: left, y: top + 64, width: contentWidth, height: 42)
        subtitleLabel.frame = NSRect(x: left + 2, y: top + 108, width: contentWidth - 4, height: 22)

        let editorTop = top + 152
        let metadataHeight: CGFloat = 34
        let editorHeight = max(CGFloat(320), safe.maxY - editorTop - metadataHeight)
        editorChrome.frame = NSRect(x: left, y: editorTop, width: contentWidth, height: editorHeight)
        scrollView.frame = editorChrome.bounds.insetBy(dx: 1, dy: 1)
        textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(editorHeight, textView.frame.height))
        placeholderLabel.frame = NSRect(x: 38, y: 34, width: editorChrome.bounds.width - 76, height: 28)

        let metaTop = editorTop + editorHeight + 14
        wordCountLabel.frame = NSRect(x: left, y: metaTop, width: 120, height: 18)
        elapsedLabel.frame = NSRect(x: left + contentWidth - 84, y: metaTop, width: 84, height: 18)
        saveErrorLabel.frame = NSRect(x: left + 132, y: metaTop, width: contentWidth - 228, height: 18)
    }

    private func drawBackground() {
        NSColor.draftFocusBackground.setFill()
        bounds.fill()

        NSColor.draftFocusAccent.withAlphaComponent(0.22).setStroke()
        let rulePath = NSBezierPath()
        for x in stride(from: CGFloat(0), through: bounds.width, by: 72) {
            rulePath.move(to: NSPoint(x: x, y: 0))
            rulePath.line(to: NSPoint(x: x - bounds.height * 0.32, y: bounds.height))
        }
        rulePath.lineWidth = 1
        rulePath.stroke()

        let quietBand = NSRect(x: 0, y: 0, width: bounds.width, height: max(160, bounds.height * 0.18))
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.105, alpha: 0.72).setFill()
        quietBand.fill()
    }
}

private final class DraftFocusEditorChrome: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.draftFocusPaper.setFill()
        path.fill()

        NSColor.draftFocusAccent.withAlphaComponent(0.34).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        NSColor.black.withAlphaComponent(0.04).setFill()
        for y in stride(from: CGFloat(74), through: bounds.height, by: 34) {
            NSRect(x: 36, y: y, width: bounds.width - 72, height: 1).fill()
        }
    }
}

private final class DraftFocusButton: NSControl {
    enum Style {
        case primary
        case secondary
    }

    var title: String {
        didSet { needsDisplay = true }
    }

    private let style: Style

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    init(title: String, style: Style) {
        self.title = title
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let fill: NSColor
        let stroke: NSColor
        let textColor: NSColor

        switch (style, isEnabled) {
        case (.primary, true):
            fill = .draftFocusAccent
            stroke = NSColor.white.withAlphaComponent(0.35)
            textColor = .draftFocusButtonInk
        case (.primary, false):
            fill = NSColor.draftFocusAccent.withAlphaComponent(0.26)
            stroke = NSColor.draftFocusAccent.withAlphaComponent(0.28)
            textColor = NSColor.draftFocusInk.withAlphaComponent(0.44)
        case (.secondary, true):
            fill = NSColor.white.withAlphaComponent(0.08)
            stroke = NSColor.white.withAlphaComponent(0.22)
            textColor = .draftFocusInk
        case (.secondary, false):
            fill = NSColor.white.withAlphaComponent(0.05)
            stroke = NSColor.white.withAlphaComponent(0.12)
            textColor = NSColor.draftFocusInk.withAlphaComponent(0.46)
        }

        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
        let measured = (title as NSString).boundingRect(
            with: NSSize(width: rect.width - 18, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        title.draw(
            in: NSRect(
                x: rect.minX + 9,
                y: rect.midY - measured.height / 2,
                width: rect.width - 18,
                height: measured.height + 2
            ),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            NSSound.beep()
            return
        }
        sendAction(action, to: target)
    }
}

private final class DraftFocusBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.draftFocusBackground.setFill()
        bounds.fill()

        let text = "Draft Focus is active on another display"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.draftFocusInk.withAlphaComponent(0.52)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

enum DraftArtifactText {
    static func title(for body: String, fallback: String = "Write to Escape Draft") -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = firstLine?.isEmpty == false ? firstLine! : fallback
        return base.count > 68 ? String(base.prefix(68)) + "..." : base
    }

    static func excerpt(for body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 180 else { return collapsed }
        return String(collapsed.prefix(180)) + "..."
    }

    static func content(body: String) -> String {
        body
    }

    static func wordCount(_ body: String) -> Int {
        body.split { $0.isWhitespace || $0.isNewline }.count
    }
}

private extension NSColor {
    static let draftFocusBackground = NSColor(calibratedRed: 0.045, green: 0.060, blue: 0.055, alpha: 0.985)
    static let draftFocusInk = NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.84, alpha: 1)
    static let draftFocusMutedInk = NSColor(calibratedRed: 0.66, green: 0.70, blue: 0.62, alpha: 1)
    static let draftFocusPaper = NSColor(calibratedRed: 0.985, green: 0.975, blue: 0.93, alpha: 0.99)
    static let draftFocusPaperInk = NSColor(calibratedRed: 0.12, green: 0.115, blue: 0.095, alpha: 1)
    static let draftFocusAccent = NSColor(calibratedRed: 0.55, green: 0.84, blue: 0.62, alpha: 1)
    static let draftFocusButtonInk = NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.050, alpha: 1)
    static let draftFocusRed = NSColor(calibratedRed: 0.93, green: 0.38, blue: 0.32, alpha: 1)
}
