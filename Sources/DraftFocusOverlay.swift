import AppKit

private enum DraftFocusPaperLayout {
    static let textInsetX: CGFloat = 72
    static let textInsetY: CGFloat = 40
    static let lineHeight: CGFloat = 32
    static let ruleOffsetBelowBaseline: CGFloat = 1
    static let ruleStartX: CGFloat = 44
    static let ruleEndInset: CGFloat = 44
    static let marginX: CGFloat = 52
}

private enum DraftFocusTheme: String, CaseIterable {
    case typewriterStudy = "typewriter-study"
    case rainWindow = "rain-window"
    case mountainCabin = "mountain-cabin"

    private static let storageKey = "draft_focus_theme"

    static var stored: DraftFocusTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let theme = DraftFocusTheme(rawValue: rawValue) else {
            return .typewriterStudy
        }
        return theme
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }

    var displayName: String {
        switch self {
        case .typewriterStudy:
            return "Typewriter Study"
        case .rainWindow:
            return "Rain Window"
        case .mountainCabin:
            return "Mountain Cabin"
        }
    }

    var image: NSImage? {
        DraftFocusThemeImageCache.shared.image(for: self)
    }

    var fallbackBackground: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.045, green: 0.052, blue: 0.043, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.052, green: 0.065, blue: 0.074, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.055, green: 0.064, blue: 0.047, alpha: 1)
        }
    }

    var overlayTint: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.07, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.13, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.075, alpha: 1)
        }
    }

    var sceneDimAlpha: CGFloat {
        switch self {
        case .typewriterStudy:
            return 0.24
        case .rainWindow:
            return 0.30
        case .mountainCabin:
            return 0.26
        }
    }

    var inkColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.80, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.96, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.94, green: 0.91, blue: 0.80, alpha: 1)
        }
    }

    var mutedInkColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.74, green: 0.68, blue: 0.55, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.78, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.70, green: 0.72, blue: 0.60, alpha: 1)
        }
    }

    var paperColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.965, green: 0.925, blue: 0.805, alpha: 0.985)
        case .rainWindow:
            return NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.945, alpha: 0.985)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.970, green: 0.945, blue: 0.850, alpha: 0.985)
        }
    }

    var paperInkColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.145, green: 0.105, blue: 0.070, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.085, green: 0.115, blue: 0.125, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.125, green: 0.110, blue: 0.075, alpha: 1)
        }
    }

    var accentColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.83, green: 0.61, blue: 0.33, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.48, green: 0.70, blue: 0.76, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.56, green: 0.70, blue: 0.42, alpha: 1)
        }
    }

    var buttonInkColor: NSColor {
        switch self {
        case .typewriterStudy:
            return NSColor(calibratedRed: 0.090, green: 0.055, blue: 0.030, alpha: 1)
        case .rainWindow:
            return NSColor(calibratedRed: 0.050, green: 0.080, blue: 0.090, alpha: 1)
        case .mountainCabin:
            return NSColor(calibratedRed: 0.050, green: 0.075, blue: 0.035, alpha: 1)
        }
    }

    var errorColor: NSColor {
        NSColor(calibratedRed: 0.95, green: 0.43, blue: 0.34, alpha: 1)
    }
}

private final class DraftFocusThemeImageCache {
    static let shared = DraftFocusThemeImageCache()

    private var images: [String: NSImage] = [:]

    func image(for theme: DraftFocusTheme) -> NSImage? {
        if let image = images[theme.rawValue] {
            return image
        }

        guard let url = Bundle.main.url(
            forResource: theme.rawValue,
            withExtension: "jpg",
            subdirectory: "DraftFocusThemes"
        ),
        let image = NSImage(contentsOf: url) else {
            return nil
        }

        images[theme.rawValue] = image
        return image
    }
}

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
    var onWriteToEscapeRequested: ((WPCOMSite, String) -> Void)?

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
                    },
                    onWriteToEscapeRequested: { [weak self] in
                        let body = self?.focusView?.body ?? ""
                        self?.dismiss()
                        self?.onWriteToEscapeRequested?(site, body)
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
    private let onWriteToEscapeRequested: () -> Void
    private let startedAt = Date()

    private let closeButton = DraftFocusButton(title: "Close", style: .secondary)
    private let saveButton = DraftFocusButton(title: "Save and Close", style: .primary)
    private let themePicker = DraftFocusPickerButton(prefix: "Scene", frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "Draft Focus")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let wordCountLabel = NSTextField(labelWithString: "0 words")
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let saveErrorLabel = NSTextField(labelWithString: "")
    private let placeholderLabel = NSTextField(labelWithString: "Begin here.")
    private let editorChrome = DraftFocusEditorChrome(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let textView = DraftFocusTextView(frame: .zero)

    private var timer: Timer?
    private var isSaving = false
    private var theme = DraftFocusTheme.stored
    private var isApplyingTextStyle = false

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        siteName: String?,
        onSaveRequested: @escaping (String) -> Void,
        onCloseRequested: @escaping () -> Void,
        onWriteToEscapeRequested: @escaping () -> Void
    ) {
        self.siteName = siteName
        self.onSaveRequested = onSaveRequested
        self.onCloseRequested = onCloseRequested
        self.onWriteToEscapeRequested = onWriteToEscapeRequested
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

    var body: String {
        textView.string
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
        normalizeTextStyle()
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

    @objc private func themePickerPressed() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for draftTheme in DraftFocusTheme.allCases {
            let item = NSMenuItem(
                title: draftTheme.displayName,
                action: #selector(themeMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = draftTheme.rawValue
            item.state = draftTheme == theme ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let writeToEscapeItem = NSMenuItem(
            title: "Write to Escape",
            action: #selector(themeMenuItemSelected(_:)),
            keyEquivalent: ""
        )
        writeToEscapeItem.target = self
        writeToEscapeItem.representedObject = "write-to-escape"
        menu.addItem(writeToEscapeItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: themePicker.bounds.height + 6),
            in: themePicker
        )
    }

    @objc private func themeMenuItemSelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }

        if rawValue == "write-to-escape" {
            onWriteToEscapeRequested()
            return
        }

        guard let selectedTheme = DraftFocusTheme(rawValue: rawValue) else { return }

        theme = selectedTheme
        theme.persist()
        applyTheme()
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

        titleLabel.font = .monospacedSystemFont(ofSize: 33, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let site = siteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitleLabel.stringValue = site?.isEmpty == false ? "Artifact for \(site!)" : "Artifact"
        subtitleLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        subtitleLabel.lineBreakMode = .byTruncatingTail

        for metadataLabel in [wordCountLabel, elapsedLabel] {
            metadataLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        saveErrorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        saveErrorLabel.lineBreakMode = .byTruncatingTail

        placeholderLabel.font = .monospacedSystemFont(ofSize: 20, weight: .regular)

        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        saveButton.target = self
        saveButton.action = #selector(saveButtonPressed)
        saveButton.isEnabled = false
        addSubview(closeButton)
        addSubview(saveButton)

        themePicker.target = self
        themePicker.action = #selector(themePickerPressed)
        addSubview(themePicker)

        editorChrome.addSubview(scrollView)
        editorChrome.addSubview(placeholderLabel)
        addSubview(editorChrome)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.delegate = self
        textView.string = ""
        textView.font = NSFont.monospacedSystemFont(ofSize: 19, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.textContainerInset = NSSize(
            width: DraftFocusPaperLayout.textInsetX,
            height: DraftFocusPaperLayout.textInsetY
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 860, height: CGFloat.greatestFiniteMagnitude)
        applyPaperParagraphStyle()

        applyTheme()
        updateMetadata()
    }

    private func applyTheme() {
        titleLabel.textColor = theme.inkColor
        subtitleLabel.textColor = theme.mutedInkColor
        wordCountLabel.textColor = theme.mutedInkColor
        elapsedLabel.textColor = theme.mutedInkColor
        saveErrorLabel.textColor = theme.errorColor
        placeholderLabel.textColor = theme.paperInkColor.withAlphaComponent(0.28)
        textView.textColor = theme.paperInkColor
        textView.insertionPointColor = theme.accentColor
        textView.focusTheme = theme
        editorChrome.theme = theme
        closeButton.theme = theme
        saveButton.theme = theme
        themePicker.theme = theme
        themePicker.selectedTitle = theme.displayName
        applyPaperParagraphStyle()
        needsDisplay = true
        needsLayout = true
    }

    private func applyPaperParagraphStyle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = DraftFocusPaperLayout.lineHeight
        paragraphStyle.maximumLineHeight = DraftFocusPaperLayout.lineHeight
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.paragraphSpacingBefore = 0
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
            .foregroundColor: theme.paperInkColor,
            .paragraphStyle: paragraphStyle
        ]
        normalizeTextStyle()
        textView.needsDisplay = true
    }

    private func normalizeTextStyle() {
        guard !isApplyingTextStyle else { return }
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }

        isApplyingTextStyle = true
        let selectedRanges = textView.selectedRanges
        let paragraphStyle = textView.defaultParagraphStyle ?? NSParagraphStyle.default
        textStorage.beginEditing()
        textStorage.addAttributes(
            [
                .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
                .foregroundColor: theme.paperInkColor,
                .paragraphStyle: paragraphStyle
            ],
            range: NSRange(location: 0, length: textStorage.length)
        )
        textStorage.endEditing()
        textView.selectedRanges = selectedRanges
        isApplyingTextStyle = false
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
        themePicker.frame = NSRect(x: saveButton.frame.minX - 236, y: top, width: 220, height: 38)

        titleLabel.frame = NSRect(x: left, y: top + 64, width: contentWidth, height: 42)
        subtitleLabel.frame = NSRect(x: left + 2, y: top + 108, width: contentWidth - 4, height: 22)

        let editorTop = top + 152
        let metadataHeight: CGFloat = 34
        let editorHeight = max(CGFloat(320), safe.maxY - editorTop - metadataHeight)
        editorChrome.frame = NSRect(x: left, y: editorTop, width: contentWidth, height: editorHeight)
        scrollView.frame = editorChrome.bounds.insetBy(dx: 1, dy: 1)
        textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(editorHeight, textView.frame.height))
        placeholderLabel.frame = NSRect(
            x: DraftFocusPaperLayout.textInsetX,
            y: DraftFocusPaperLayout.textInsetY - 4,
            width: editorChrome.bounds.width - DraftFocusPaperLayout.textInsetX - 44,
            height: 28
        )

        let metaTop = editorTop + editorHeight + 14
        wordCountLabel.frame = NSRect(x: left, y: metaTop, width: 120, height: 18)
        elapsedLabel.frame = NSRect(x: left + contentWidth - 84, y: metaTop, width: 84, height: 18)
        saveErrorLabel.frame = NSRect(x: left + 132, y: metaTop, width: contentWidth - 228, height: 18)
    }

    private func drawBackground() {
        theme.fallbackBackground.setFill()
        bounds.fill()

        if let image = theme.image {
            image.drawAspectFill(in: bounds)
        }

        theme.overlayTint.withAlphaComponent(theme.sceneDimAlpha).setFill()
        bounds.fill()

        NSColor.black.withAlphaComponent(0.18).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: max(118, bounds.height * 0.16)).fill()
        NSRect(x: 0, y: max(0, bounds.height - 150), width: bounds.width, height: 150).fill()

        NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.34),
            NSColor.black.withAlphaComponent(0.02),
            NSColor.black.withAlphaComponent(0.42)
        ])?.draw(in: bounds, angle: 0)

        NSColor.white.withAlphaComponent(0.035).setStroke()
        let glintPath = NSBezierPath()
        for x in stride(from: CGFloat(-bounds.height), through: bounds.width, by: 96) {
            glintPath.move(to: NSPoint(x: x, y: 0))
            glintPath.line(to: NSPoint(x: x + bounds.height * 0.26, y: bounds.height))
        }
        glintPath.lineWidth = 1
        glintPath.stroke()
    }
}

private final class DraftFocusEditorChrome: NSView {
    var theme: DraftFocusTheme = .typewriterStudy {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let pageRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: pageRect, xRadius: 7, yRadius: 7)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.46)
        shadow.shadowBlurRadius = 34
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        shadow.set()
        theme.paperColor.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        theme.paperColor.setFill()
        path.fill()

        theme.accentColor.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        NSColor.white.withAlphaComponent(0.12).setFill()
        NSRect(x: pageRect.minX + 1, y: pageRect.minY + 1, width: pageRect.width - 2, height: 34).fill()
    }
}

private final class DraftFocusTextView: NSTextView {
    var focusTheme: DraftFocusTheme = .typewriterStudy {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawPaperLines(in: dirtyRect)
        super.draw(dirtyRect)
    }

    private func drawPaperLines(in dirtyRect: NSRect) {
        let lineColor = focusTheme.paperInkColor.withAlphaComponent(0.045)
        lineColor.setFill()

        let firstLineY = firstRuleY()
        let pitch = linePitch()
        let startIndex = max(0, floor((dirtyRect.minY - firstLineY) / pitch))
        var y = firstLineY + startIndex * pitch
        while y <= dirtyRect.maxY + DraftFocusPaperLayout.lineHeight {
            NSRect(
                x: DraftFocusPaperLayout.ruleStartX,
                y: y,
                width: max(0, bounds.width - DraftFocusPaperLayout.ruleStartX - DraftFocusPaperLayout.ruleEndInset),
                height: 1
            ).fill()
            y += pitch
        }

        focusTheme.accentColor.withAlphaComponent(0.10).setFill()
        NSRect(
            x: DraftFocusPaperLayout.marginX,
            y: dirtyRect.minY,
            width: 1,
            height: dirtyRect.height
        ).fill()
    }

    private func firstRuleY() -> CGFloat {
        if let textContainer,
           let layoutManager,
           layoutManager.numberOfGlyphs > 0 {
            layoutManager.ensureLayout(for: textContainer)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let glyphLocation = layoutManager.location(forGlyphAt: 0)
            return textContainerOrigin.y
                + lineFragmentRect.minY
                + glyphLocation.y
                + DraftFocusPaperLayout.ruleOffsetBelowBaseline
        }

        guard let font else {
            return textContainerOrigin.y + DraftFocusPaperLayout.lineHeight
        }

        let fontLineHeight = font.ascender - font.descender + font.leading
        let verticalPadding = max(0, (linePitch() - fontLineHeight) / 2)
        return textContainerOrigin.y
            + verticalPadding
            + font.ascender
            + DraftFocusPaperLayout.ruleOffsetBelowBaseline
    }

    private func linePitch() -> CGFloat {
        guard let paragraphStyle = defaultParagraphStyle else {
            return DraftFocusPaperLayout.lineHeight
        }

        let maxLineHeight = paragraphStyle.maximumLineHeight
        return maxLineHeight > 0 ? maxLineHeight : DraftFocusPaperLayout.lineHeight
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
    var theme: DraftFocusTheme = .typewriterStudy {
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
            fill = theme.accentColor
            stroke = NSColor.white.withAlphaComponent(0.35)
            textColor = theme.buttonInkColor
        case (.primary, false):
            fill = theme.accentColor.withAlphaComponent(0.24)
            stroke = theme.accentColor.withAlphaComponent(0.28)
            textColor = theme.inkColor.withAlphaComponent(0.45)
        case (.secondary, true):
            fill = NSColor.black.withAlphaComponent(0.18)
            stroke = NSColor.white.withAlphaComponent(0.22)
            textColor = theme.inkColor
        case (.secondary, false):
            fill = NSColor.black.withAlphaComponent(0.10)
            stroke = NSColor.white.withAlphaComponent(0.12)
            textColor = theme.inkColor.withAlphaComponent(0.46)
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

private final class DraftFocusPickerButton: NSControl {
    var selectedTitle: String = "" {
        didSet { needsDisplay = true }
    }
    var theme: DraftFocusTheme = .typewriterStudy {
        didSet { needsDisplay = true }
    }

    private let prefix: String

    override var isFlipped: Bool { true }

    init(prefix: String, frame frameRect: NSRect) {
        self.prefix = prefix
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)

        NSColor.black.withAlphaComponent(0.28).setFill()
        path.fill()

        theme.accentColor.withAlphaComponent(0.34).setStroke()
        path.lineWidth = 1
        path.stroke()

        theme.accentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 6, y: rect.minY + 6, width: 26, height: rect.height - 12),
            xRadius: 6,
            yRadius: 6
        ).fill()

        let title = "\(prefix): \(selectedTitle)  v"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: theme.inkColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: rect.minX + 42, y: rect.minY, width: rect.width - 54, height: rect.height)
        let measured = (title as NSString).boundingRect(
            with: NSSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        title.draw(
            in: NSRect(
                x: textRect.minX,
                y: textRect.midY - measured.height / 2,
                width: textRect.width,
                height: measured.height + 2
            ),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

private final class DraftFocusBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let theme = DraftFocusTheme.stored
        theme.fallbackBackground.setFill()
        bounds.fill()
        if let image = theme.image {
            image.drawAspectFill(in: bounds)
        }
        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        let text = "Draft Focus is active on another display"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: theme.inkColor.withAlphaComponent(0.72)
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

private extension NSImage {
    func drawAspectFill(in targetRect: NSRect) {
        guard size.width > 0, size.height > 0, targetRect.width > 0, targetRect.height > 0 else { return }

        let sourceAspect = size.width / size.height
        let targetAspect = targetRect.width / targetRect.height
        let sourceRect: NSRect

        if sourceAspect > targetAspect {
            let width = size.height * targetAspect
            sourceRect = NSRect(
                x: (size.width - width) / 2,
                y: 0,
                width: width,
                height: size.height
            )
        } else {
            let height = size.width / targetAspect
            sourceRect = NSRect(
                x: 0,
                y: (size.height - height) / 2,
                width: size.width,
                height: height
            )
        }

        draw(
            in: targetRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
