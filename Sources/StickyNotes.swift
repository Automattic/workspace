import AppKit
import Foundation

struct StickyNoteFrame: Equatable {
    var displayID: Int?
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultWidth: CGFloat = 320
    static let defaultHeight: CGFloat = 220
    static let minimumWidth: CGFloat = 220
    static let minimumHeight: CGFloat = 160

    init(
        displayID: Int? = nil,
        x: Double,
        y: Double,
        width: Double = Double(Self.defaultWidth),
        height: Double = Double(Self.defaultHeight)
    ) {
        self.displayID = displayID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct StickyNoteDocument: Equatable {
    let localID: UUID
    let siteID: Int
    var guidelineID: Int?
    var title: String
    var body: String
    var frame: StickyNoteFrame
    var modified: String?

    init(
        localID: UUID = UUID(),
        siteID: Int,
        guidelineID: Int? = nil,
        title: String = "Sticky Note",
        body: String,
        frame: StickyNoteFrame,
        modified: String? = nil
    ) {
        self.localID = localID
        self.siteID = siteID
        self.guidelineID = guidelineID
        self.title = title
        self.body = body
        self.frame = frame
        self.modified = modified
    }
}

struct StickyNoteSaveSnapshot {
    let localID: UUID
    let siteID: Int
    let guidelineID: Int?
    let fallbackTitle: String
    let body: String

    var shouldCreateOrUpdate: Bool {
        guidelineID != nil || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct StickyNotePendingSave {
    var removeAfterSave: Bool
}

@MainActor
final class StickyNoteWindowManager {
    var onError: ((String) -> Void)?
    var onVisibleWindowsChanged: ((Bool) -> Void)?
    var onOpenArtifactRequested: ((Int, Int, String) -> Void)?

    private var client = WPCOMClient()
    private var activeSiteID: Int?
    private var controllersBySite: [Int: [UUID: StickyNoteWindowController]] = [:]
    private var loadedSiteIDs: Set<Int> = []
    private var stickyTermIDsBySite: [Int: [Int]] = [:]
    private var savingLocalIDs: Set<UUID> = []
    private var pendingSaves: [UUID: StickyNotePendingSave] = [:]
    private var restoreTask: Task<Void, Never>?
    private var cascadeCountsBySite: [Int: Int] = [:]

    var hasVisibleWindows: Bool {
        controllersBySite.values.flatMap(\.values).contains { $0.isVisible }
    }

    func hasVisibleStickies(siteID: Int) -> Bool {
        controllersBySite[siteID]?.values.contains { $0.isVisible } == true
    }

    func resetClient() {
        client = WPCOMClient()
        stickyTermIDsBySite.removeAll()
    }

    func prepareForAppTermination() {
        for controller in controllersBySite.values.flatMap(\.values) {
            controller.prepareForAppTermination()
        }
    }

    func switchToNoSite() {
        restoreTask?.cancel()
        restoreTask = nil
        hideAllWindowsForSiteSwitch()
        activeSiteID = nil
        notifyVisibilityChanged()
    }

    func clearForSignedOutUser() {
        restoreTask?.cancel()
        restoreTask = nil
        for controller in controllersBySite.values.flatMap(\.values) {
            controller.hideForSiteSwitch()
        }
        activeSiteID = nil
        controllersBySite.removeAll()
        loadedSiteIDs.removeAll()
        stickyTermIDsBySite.removeAll()
        savingLocalIDs.removeAll()
        pendingSaves.removeAll()
        notifyVisibilityChanged()
    }

    func switchToSite(siteID: Int) {
        if activeSiteID == siteID {
            if loadedSiteIDs.contains(siteID) {
                showOpenControllers(for: siteID)
            } else {
                restoreTask?.cancel()
                restoreTask = Task { @MainActor [weak self] in
                    await self?.loadSiteStickies(siteID: siteID)
                }
            }
            return
        }

        restoreTask?.cancel()
        hideAllWindowsForSiteSwitch()
        activeSiteID = siteID

        if loadedSiteIDs.contains(siteID) {
            showOpenControllers(for: siteID)
            notifyVisibilityChanged()
            return
        }

        restoreTask = Task { @MainActor [weak self] in
            await self?.loadSiteStickies(siteID: siteID)
        }
    }

    func createNewSticky(siteID: Int, body: String = "") {
        activeSiteID = siteID
        let frame = defaultFrame(siteID: siteID)
        let title = StickyNoteText.title(for: body)
        let document = StickyNoteDocument(
            siteID: siteID,
            title: title,
            body: body,
            frame: frame
        )
        let controller = makeController(document: document)
        controllersBySite[siteID, default: [:]][controller.localID] = controller
        controller.show(focus: true)
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestSave(for: controller, removeAfterSave: false)
        }
        notifyVisibilityChanged()
    }

    func showSiteStickies(siteID: Int) {
        activeSiteID = siteID
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            await self?.loadSiteStickies(siteID: siteID)
        }
    }

    func hideSiteStickies(siteID: Int) {
        guard let controllers = controllersBySite[siteID]?.values else { return }
        for controller in controllers where controller.isVisible {
            controller.hideByUser()
        }
        notifyVisibilityChanged()
    }

    func toggleSiteStickies(siteID: Int) {
        if hasVisibleStickies(siteID: siteID) {
            hideSiteStickies(siteID: siteID)
        } else {
            showSiteStickies(siteID: siteID)
        }
    }

    private func loadSiteStickies(siteID: Int) async {
        do {
            let termIDs = try await stickyTermIDs(siteID: siteID)
            guard let stickyTermID = termIDs.last else {
                return
            }
            let guidelines = try await client.fetchStickyNoteGuidelines(siteID: siteID, stickyTermID: stickyTermID)
            guard activeSiteID == siteID else { return }

            loadedSiteIDs.insert(siteID)
            for guideline in guidelines {
                open(document: document(from: guideline, siteID: siteID))
            }
            showOpenControllers(for: siteID)
            notifyVisibilityChanged()
        } catch is CancellationError {
            return
        } catch {
            onError?("Could not load sticky notes: \(error.localizedDescription)")
        }
    }

    private func open(document: StickyNoteDocument) {
        if let existing = controller(siteID: document.siteID, guidelineID: document.guidelineID) {
            existing.replace(document: document)
            existing.show(focus: false)
            return
        }

        let controller = makeController(document: document)
        controllersBySite[document.siteID, default: [:]][controller.localID] = controller
        controller.show(focus: false)
    }

    private func document(from guideline: WPCOMStickyGuideline, siteID: Int) -> StickyNoteDocument {
        let content = StickyNoteText.removingLegacyMetadataComment(from: guideline.content.bestText)
        let title = StickyNoteText.titleField(for: guideline.title)
        let body = StickyNoteText.editorBody(title: title, content: content)
        return StickyNoteDocument(
            siteID: siteID,
            guidelineID: guideline.id,
            title: title,
            body: body,
            frame: defaultFrame(siteID: siteID),
            modified: guideline.modified
        )
    }

    private func makeController(document: StickyNoteDocument) -> StickyNoteWindowController {
        let controller = StickyNoteWindowController(document: document)
        controller.onSaveRequested = { [weak self, weak controller] removeAfterSave in
            guard let self, let controller else { return }
            self.requestSave(for: controller, removeAfterSave: removeAfterSave)
        }
        controller.onDiscarded = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.removeController(controller)
        }
        controller.onVisibilityChanged = { [weak self] in
            self?.notifyVisibilityChanged()
        }
        controller.onOpenArtifactRequested = { [weak self] siteID, guidelineID, title in
            self?.onOpenArtifactRequested?(siteID, guidelineID, title)
        }
        return controller
    }

    private func requestSave(for controller: StickyNoteWindowController, removeAfterSave: Bool) {
        let snapshot = controller.snapshot()
        guard snapshot.shouldCreateOrUpdate else {
            if removeAfterSave {
                removeController(controller)
            }
            return
        }

        if savingLocalIDs.contains(snapshot.localID) {
            let current = pendingSaves[snapshot.localID]
            pendingSaves[snapshot.localID] = StickyNotePendingSave(
                removeAfterSave: removeAfterSave || current?.removeAfterSave == true
            )
            controller.setSaving(true)
            return
        }

        savingLocalIDs.insert(snapshot.localID)
        controller.setSaving(true)

        Task { @MainActor [weak self, weak controller] in
            guard let self else { return }
            do {
                let saved = try await self.save(snapshot)
                guard let controller else {
                    self.savingLocalIDs.remove(snapshot.localID)
                    return
                }
                controller.applySaved(guidelineID: saved.id, modified: saved.modified)
                self.savingLocalIDs.remove(snapshot.localID)

                if let pending = self.pendingSaves.removeValue(forKey: snapshot.localID) {
                    self.requestSave(for: controller, removeAfterSave: pending.removeAfterSave)
                } else {
                    controller.setSaving(false)
                    if removeAfterSave {
                        self.removeController(controller)
                    }
                }
            } catch {
                self.savingLocalIDs.remove(snapshot.localID)
                self.pendingSaves.removeValue(forKey: snapshot.localID)
                self.onError?("Could not save sticky note: \(error.localizedDescription)")
                if let controller {
                    controller.setSaving(false)
                    if removeAfterSave {
                        self.removeController(controller)
                    }
                }
            }
        }
    }

    private func save(_ snapshot: StickyNoteSaveSnapshot) async throws -> WPCOMStickyGuideline {
        let termIDs = try await stickyTermIDs(siteID: snapshot.siteID)
        var note = StickyNoteText.noteComponents(for: snapshot.body, fallbackTitle: snapshot.fallbackTitle)
        if note.title == snapshot.fallbackTitle,
           let guidelineID = snapshot.guidelineID,
           let current = try? await client.fetchStickyNoteGuideline(siteID: snapshot.siteID, guidelineID: guidelineID) {
            note.title = StickyNoteText.titleField(for: current.title)
        }
        return try await client.saveStickyNoteGuideline(
            siteID: snapshot.siteID,
            guidelineID: snapshot.guidelineID,
            title: note.title,
            excerpt: StickyNoteText.excerpt(for: note.content.isEmpty ? note.title : note.content),
            content: note.content,
            termIDs: termIDs
        )
    }

    private func stickyTermIDs(siteID: Int) async throws -> [Int] {
        if let cached = stickyTermIDsBySite[siteID] {
            return cached
        }

        let termIDs = try await client.resolveStickyNoteTermIDs(siteID: siteID)
        stickyTermIDsBySite[siteID] = termIDs
        return termIDs
    }

    private func controller(siteID: Int, guidelineID: Int?) -> StickyNoteWindowController? {
        guard let guidelineID else { return nil }
        return controllersBySite[siteID]?.values.first { $0.guidelineID == guidelineID }
    }

    private func removeController(_ controller: StickyNoteWindowController) {
        controllersBySite[controller.siteID]?[controller.localID] = nil
        notifyVisibilityChanged()
    }

    private func hideAllWindowsForSiteSwitch() {
        for controller in controllersBySite.values.flatMap(\.values) {
            controller.hideForSiteSwitch()
        }
    }

    private func showOpenControllers(for siteID: Int) {
        guard let controllers = controllersBySite[siteID]?.values else { return }
        for controller in controllers where controller.isOpen {
            controller.show(focus: false)
        }
    }

    private func notifyVisibilityChanged() {
        onVisibleWindowsChanged?(hasVisibleWindows)
    }

    private func defaultFrame(siteID: Int) -> StickyNoteFrame {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let count = cascadeCountsBySite[siteID, default: 0]
        cascadeCountsBySite[siteID] = count + 1
        let offset = CGFloat((count % 8) * 28)
        let width = min(StickyNoteFrame.defaultWidth, max(StickyNoteFrame.minimumWidth, visibleFrame.width - 80))
        let height = min(StickyNoteFrame.defaultHeight, max(StickyNoteFrame.minimumHeight, visibleFrame.height - 80))
        let left = max(visibleFrame.minX + 32, visibleFrame.maxX - width - 64 - offset)
        let top = visibleFrame.minY + min(80 + offset, max(80, visibleFrame.height - height - 32))
        let x = Double((left - visibleFrame.minX) / max(visibleFrame.width, 1))
        let y = Double((top - visibleFrame.minY) / max(visibleFrame.height, 1))
        return StickyNoteFrame(
            displayID: screen?.stickyDisplayID,
            x: x.clamped(to: 0...1),
            y: y.clamped(to: 0...1),
            width: Double(width),
            height: Double(height)
        )
    }
}

private final class StickyNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class StickyNoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    var onSaveRequested: ((Bool) -> Void)?
    var onDiscarded: (() -> Void)?
    var onVisibilityChanged: (() -> Void)?
    var onOpenArtifactRequested: ((Int, Int, String) -> Void)?

    private(set) var document: StickyNoteDocument
    private let window: StickyNotePanel
    private let headerTitleField: NSTextField
    private let openArtifactButton: NSButton
    private let saveProgressIndicator: NSProgressIndicator
    private let textView: NSTextView
    private var saveTimer: Timer?
    private var isPreparingForTermination = false
    private var isApplyingTitleStyle = false
    private var isHiddenByUser = false
    private var hasTextChanges = false

    var localID: UUID { document.localID }
    var siteID: Int { document.siteID }
    var guidelineID: Int? { document.guidelineID }
    var isOpen: Bool { !isHiddenByUser }
    var isVisible: Bool { window.isVisible }

    init(document: StickyNoteDocument) {
        self.document = document

        headerTitleField = NSTextField(labelWithString: StickyNoteText.title(for: document.body))
        headerTitleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerTitleField.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        headerTitleField.lineBreakMode = .byTruncatingTail
        headerTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openArtifactButton = NSButton()
        openArtifactButton.image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: "Open Artifact"
        )
        openArtifactButton.image?.isTemplate = true
        openArtifactButton.imagePosition = .imageOnly
        openArtifactButton.bezelStyle = .texturedRounded
        openArtifactButton.isBordered = false
        openArtifactButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.74)
        openArtifactButton.toolTip = "Open artifact"

        saveProgressIndicator = NSProgressIndicator()
        saveProgressIndicator.style = .spinning
        saveProgressIndicator.controlSize = .small
        saveProgressIndicator.isIndeterminate = true
        saveProgressIndicator.isDisplayedWhenStopped = false
        saveProgressIndicator.isHidden = true
        saveProgressIndicator.toolTip = "Saving"

        textView = NSTextView(frame: .zero)
        textView.string = document.body
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 10)
        textView.minSize = NSSize(width: 0, height: StickyNoteFrame.minimumHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: StickyNoteFrame.defaultWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        let contentView = StickyNoteBackgroundView(frame: .zero)
        let headerView = StickyNoteHeaderView(frame: .zero)
        headerView.addSubview(headerTitleField)
        headerView.addSubview(openArtifactButton)
        headerView.addSubview(saveProgressIndicator)
        contentView.addSubview(headerView)
        contentView.addSubview(scrollView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerTitleField.translatesAutoresizingMaskIntoConstraints = false
        openArtifactButton.translatesAutoresizingMaskIntoConstraints = false
        saveProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),
            headerTitleField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 92),
            headerTitleField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: 1),
            openArtifactButton.leadingAnchor.constraint(greaterThanOrEqualTo: headerTitleField.trailingAnchor, constant: 8),
            openArtifactButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            openArtifactButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            openArtifactButton.widthAnchor.constraint(equalToConstant: 24),
            openArtifactButton.heightAnchor.constraint(equalToConstant: 24),
            saveProgressIndicator.centerXAnchor.constraint(equalTo: openArtifactButton.centerXAnchor),
            saveProgressIndicator.centerYAnchor.constraint(equalTo: openArtifactButton.centerYAnchor),
            saveProgressIndicator.widthAnchor.constraint(equalToConstant: 16),
            saveProgressIndicator.heightAnchor.constraint(equalToConstant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window = StickyNotePanel(
            contentRect: Self.windowFrame(for: document.frame),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = StickyNoteText.title(for: document.body)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.minSize = NSSize(width: StickyNoteFrame.minimumWidth, height: StickyNoteFrame.minimumHeight)

        super.init()

        textView.delegate = self
        window.delegate = self
        openArtifactButton.target = self
        openArtifactButton.action = #selector(openArtifact)
        refreshTitlePresentation()
        updateOpenArtifactButton()
        setSaving(false)
    }

    deinit {
        saveTimer?.invalidate()
    }

    func show(focus: Bool) {
        isHiddenByUser = false
        updateMetadataFrameFromWindow()
        window.hidesOnDeactivate = false
        NSApp.setActivationPolicy(.regular)
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
        } else {
            window.orderFrontRegardless()
        }
        onVisibilityChanged?()
    }

    func hideByUser() {
        saveTimer?.invalidate()
        saveTimer = nil
        document.body = textView.string
        isHiddenByUser = true
        updateMetadataFrameFromWindow()

        if document.guidelineID == nil && document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            window.orderOut(nil)
            onDiscarded?()
        } else if shouldSaveTextChanges {
            window.orderOut(nil)
            onSaveRequested?(false)
        } else {
            window.orderOut(nil)
        }
        onVisibilityChanged?()
    }

    func hideForSiteSwitch() {
        saveTimer?.invalidate()
        saveTimer = nil
        updateMetadataFrameFromWindow()
        window.orderOut(nil)
        onVisibilityChanged?()
    }

    func prepareForAppTermination() {
        isPreparingForTermination = true
        saveTimer?.invalidate()
        saveTimer = nil
        document.body = textView.string
        updateMetadataFrameFromWindow()
        if shouldSaveTextChanges {
            onSaveRequested?(false)
        }
    }

    func replace(document: StickyNoteDocument) {
        self.document = document
        textView.string = document.body
        window.setFrame(Self.windowFrame(for: document.frame), display: true)
        hasTextChanges = false
        refreshTitlePresentation()
        updateOpenArtifactButton()
    }

    func snapshot() -> StickyNoteSaveSnapshot {
        updateMetadataFrameFromWindow()
        document.body = textView.string
        return StickyNoteSaveSnapshot(
            localID: document.localID,
            siteID: document.siteID,
            guidelineID: document.guidelineID,
            fallbackTitle: document.title,
            body: document.body
        )
    }

    func applySaved(guidelineID: Int, modified: String?) {
        document.guidelineID = guidelineID
        document.modified = modified
        document.title = StickyNoteText.noteComponents(
            for: textView.string,
            fallbackTitle: document.title
        ).title
        hasTextChanges = false
        updateOpenArtifactButton()
    }

    func setSaving(_ saving: Bool) {
        if saving {
            openArtifactButton.isHidden = true
            saveProgressIndicator.isHidden = false
            saveProgressIndicator.startAnimation(nil)
        } else {
            saveProgressIndicator.stopAnimation(nil)
            saveProgressIndicator.isHidden = true
            openArtifactButton.isHidden = false
            updateOpenArtifactButton()
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingTitleStyle else { return }
        document.body = textView.string
        hasTextChanges = true
        refreshTitlePresentation()
        scheduleSave()
    }

    func windowDidMove(_ notification: Notification) {
        updateMetadataFrameFromWindow()
    }

    func windowDidResize(_ notification: Notification) {
        updateMetadataFrameFromWindow()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isPreparingForTermination else {
            onVisibilityChanged?()
            return
        }

        saveTimer?.invalidate()
        saveTimer = nil
        document.body = textView.string
        updateMetadataFrameFromWindow()

        if document.guidelineID == nil && document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onDiscarded?()
        } else if shouldSaveTextChanges {
            onSaveRequested?(true)
        } else {
            onDiscarded?()
        }
        onVisibilityChanged?()
    }

    private var shouldSaveTextChanges: Bool {
        hasTextChanges || (document.guidelineID == nil && !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetadataFrameFromWindow()
                self?.onSaveRequested?(false)
            }
        }
    }

    private func updateMetadataFrameFromWindow() {
        document.frame = Self.metadataFrame(for: window)
    }

    private func refreshTitlePresentation() {
        let title = StickyNoteText.title(for: textView.string)
        window.title = title
        headerTitleField.stringValue = title
        applyTitleStyle()
    }

    private func updateOpenArtifactButton() {
        openArtifactButton.isEnabled = document.guidelineID != nil
        openArtifactButton.alphaValue = document.guidelineID == nil ? 0.34 : 1
    }

    @objc private func openArtifact() {
        guard let guidelineID = document.guidelineID else { return }
        onOpenArtifactRequested?(document.siteID, guidelineID, StickyNoteText.title(for: textView.string))
    }

    private func applyTitleStyle() {
        guard let storage = textView.textStorage else { return }
        isApplyingTitleStyle = true
        defer { isApplyingTitleStyle = false }

        let selectedRanges = textView.selectedRanges
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes([
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        let titleRange = StickyNoteText.firstLineRange(in: textView.string)
        if titleRange.length > 0 {
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ], range: titleRange)
        }
        storage.endEditing()
        textView.selectedRanges = selectedRanges
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private static func windowFrame(for metadataFrame: StickyNoteFrame) -> NSRect {
        let screen = screen(displayID: metadataFrame.displayID) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = CGFloat(metadataFrame.width)
            .clamped(to: StickyNoteFrame.minimumWidth...max(StickyNoteFrame.minimumWidth, visibleFrame.width))
        let height = CGFloat(metadataFrame.height)
            .clamped(to: StickyNoteFrame.minimumHeight...max(StickyNoteFrame.minimumHeight, visibleFrame.height))
        let topLeftX = visibleFrame.minX + CGFloat(metadataFrame.x.clamped(to: 0...1)) * visibleFrame.width
        let topOffset = CGFloat(metadataFrame.y.clamped(to: 0...1)) * visibleFrame.height
        let originY = visibleFrame.maxY - topOffset - height
        return NSRect(
            x: topLeftX,
            y: originY,
            width: width,
            height: height
        ).clampedInside(visibleFrame)
    }

    private static func metadataFrame(for window: NSWindow) -> StickyNoteFrame {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = window.frame.clampedInside(visibleFrame)
        let x = Double((frame.minX - visibleFrame.minX) / max(visibleFrame.width, 1))
        let topOffset = visibleFrame.maxY - frame.maxY
        let y = Double(topOffset / max(visibleFrame.height, 1))
        return StickyNoteFrame(
            displayID: screen?.stickyDisplayID,
            x: x.clamped(to: 0...1),
            y: y.clamped(to: 0...1),
            width: Double(frame.width),
            height: Double(frame.height)
        )
    }

    private static func screen(displayID: Int?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { $0.stickyDisplayID == displayID }
    }
}

private final class StickyNoteHeaderView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.05).setFill()
        bounds.fill()

        NSColor.black.withAlphaComponent(0.10).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
        separator.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        separator.lineWidth = 1
        separator.stroke()
    }
}

private final class StickyNoteBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 1.0, green: 0.94, blue: 0.56, alpha: 0.98).setFill()
        bounds.fill()

        NSColor.black.withAlphaComponent(0.10).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

private enum StickyNoteText {
    private static let legacyMetadataPrefix = "<!-- wpworkspace-sticky:"
    private static let legacyMetadataSuffix = "-->"

    struct Components {
        var title: String
        let content: String
    }

    static func title(for body: String) -> String {
        let line = body
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = line?.isEmpty == false ? line! : "Sticky Note"
        return title.count > 64 ? String(title.prefix(64)) + "..." : title
    }

    static func titleField(for field: WPCOMRESTTextField) -> String {
        let candidates = [field.raw, field.rendered]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map(strippingHTML)
            .filter { !$0.isEmpty }
        return candidates.first ?? "Sticky Note"
    }

    static func excerpt(for body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 180 else { return collapsed }
        return String(collapsed.prefix(180)) + "..."
    }

    static func editorBody(title: String, content: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return content
        }

        let contentFirstLine = content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if contentFirstLine == trimmedTitle {
            return content
        }
        guard !content.isEmpty else {
            return trimmedTitle
        }
        return "\(trimmedTitle)\n\(content)"
    }

    static func noteComponents(for editorBody: String, fallbackTitle: String) -> Components {
        let trimmedFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedFallback.isEmpty ? "Sticky Note" : trimmedFallback
        let title = title(for: editorBody)
        guard let firstNewline = editorBody.rangeOfCharacter(from: .newlines) else {
            return Components(title: title == "Sticky Note" ? fallback : title, content: "")
        }

        var content = String(editorBody[firstNewline.upperBound...])
        if content.hasPrefix("\n") {
            content.removeFirst()
        }
        return Components(title: title, content: content)
    }

    static func firstLineRange(in body: String) -> NSRange {
        let nsBody = body as NSString
        guard nsBody.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let newlineRange = nsBody.rangeOfCharacter(from: .newlines)
        let length = newlineRange.location == NSNotFound ? nsBody.length : newlineRange.location
        return NSRange(location: 0, length: length)
    }

    static func removingLegacyMetadataComment(from content: String) -> String {
        guard content.hasPrefix(legacyMetadataPrefix),
              let endRange = content.range(of: legacyMetadataSuffix) else {
            return content
        }

        var body = String(content[endRange.upperBound...])
        if body.hasPrefix("\r\n") {
            body.removeFirst(2)
        } else if body.hasPrefix("\n") {
            body.removeFirst()
        }
        return body
    }

    private static func strippingHTML(from value: String) -> String {
        let data = Data(value.utf8)
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

private extension NSScreen {
    var stickyDisplayID: Int? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map(\.intValue)
    }
}

private extension NSRect {
    func clampedInside(_ bounds: NSRect) -> NSRect {
        var rect = self
        rect.size.width = min(max(rect.width, StickyNoteFrame.minimumWidth), bounds.width)
        rect.size.height = min(max(rect.height, StickyNoteFrame.minimumHeight), bounds.height)
        rect.origin.x = min(max(rect.origin.x, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), bounds.maxY - rect.height)
        return rect
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
