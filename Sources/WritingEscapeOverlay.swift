import AppKit

struct WritingEscapeMetrics {
    let startedAt: Date
    let completedAt: Date
    let duration: TimeInterval
    let peakWPM: Double
    let words: Int
    let characters: Int
    let comboBreaks: Int
}

final class WritingEscapeOverlayManager {
    var onError: ((String) -> Void)?
    var onSaved: ((WPCOMGuideline, URL, Int) -> Void)?

    private var panels: [DraftOverlayPanel] = []
    private weak var gameView: WritingEscapeGameView?
    private var focusTimer: Timer?
    private var localKeyMonitor: Any?
    private var client = WPCOMClient()

    var isShowing: Bool {
        !panels.isEmpty
    }

    func show(site: WPCOMSite, initialText: String = "") {
        dismiss()

        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        guard let primaryScreen = screenForMainOverlay(from: screens) else { return }

        for screen in screens {
            let panel = makePanel(for: screen)
            if screen == primaryScreen {
                let view = WritingEscapeGameView(
                    frame: NSRect(origin: .zero, size: screen.frame.size),
                    siteName: site.displayName,
                    initialText: initialText,
                    onEscapeRequested: { [weak self] body, metrics in
                        self?.saveAndEscape(site: site, body: body, metrics: metrics)
                    },
                    onEmergencyEscapeRequested: { [weak self] in
                        self?.dismiss()
                    }
                )
                panel.contentView = view
                gameView = view
            } else {
                panel.contentView = WritingEscapeBackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            }

            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        bringGameToFront(focusEditor: true)
        installFocusTimer()
        installEscapeHatchMonitor()
    }

    func dismiss() {
        focusTimer?.invalidate()
        focusTimer = nil
        removeEscapeHatchMonitor()

        let panels = panels
        self.panels = []
        gameView = nil
        panels.forEach { panel in
            panel.contentView = nil
            panel.forceClose()
        }
    }

    private func saveAndEscape(site: WPCOMSite, body: String, metrics: WritingEscapeMetrics) {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            gameView?.showSaveFailure("The gate refuses an empty relic. Write something real.")
            return
        }

        gameView?.setSaving(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.client.saveDraftArtifact(
                    siteID: site.id,
                    title: DraftArtifactText.title(for: body),
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
                    self.gameView?.showSaveFailure("Could not save artifact: \(error.localizedDescription)")
                    self.onError?("Could not save writing artifact: \(error.localizedDescription)")
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
        focusTimer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.bringGameToFront(focusEditor: false)
        }
        if let focusTimer {
            RunLoop.main.add(focusTimer, forMode: .common)
        }
    }

    private func bringGameToFront(focusEditor: Bool) {
        panels.forEach { $0.orderFrontRegardless() }
        guard let panel = gameView?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if focusEditor {
            gameView?.focusEditor()
        }
    }

    private func installEscapeHatchMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            switch event.type {
            case .keyDown:
                self?.gameView?.beginEmergencyEscapeHold()
            case .keyUp:
                self?.gameView?.cancelEmergencyEscapeHold()
            default:
                break
            }
            return nil
        }
    }

    private func removeEscapeHatchMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}

private final class WritingEscapeGameView: NSView, NSTextViewDelegate {
    private struct InputBurst {
        let time: TimeInterval
        let characters: Int
    }

    private enum ParticleKind {
        case shootingStar
        case spark
        case firework
    }

    private struct Particle {
        var kind: ParticleKind
        var position: CGPoint
        var velocity: CGVector
        var color: NSColor
        var radius: CGFloat
        var age: TimeInterval
        var lifetime: TimeInterval
        var trailLength: CGFloat
    }

    private let siteName: String?
    private let initialText: String
    private let onEscapeRequested: (String, WritingEscapeMetrics) -> Void
    private let onEmergencyEscapeRequested: () -> Void
    private let startedAt = Date()
    private let targetWPM: Double = 24
    private let requiredStreak: TimeInterval = 30
    private let emergencyEscapeDuration: TimeInterval = 10
    private let rollingWindow: TimeInterval = 8

    private let titleLabel = NSTextField(labelWithString: "WRITE TO ESCAPE")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Start typing. The gate can smell hesitation.")
    private let statsLabel = NSTextField(labelWithString: "0.0s / 30.0s")
    private let wpmLabel = NSTextField(labelWithString: "0 WPM")
    private let targetLabel = NSTextField(labelWithString: "TARGET 24 WPM")
    private let hardModeLabel = NSTextField(labelWithString: "HARD MODE: THE SENTENCES HAVE TEETH")
    private let saveErrorLabel = NSTextField(labelWithString: "")
    private let escapeButton = WritingEscapeActionButton(frame: .zero)
    private let hatchLabel = NSTextField(labelWithString: "Emergency hatch: hold Esc for 10s")
    private let hatchProgressView = WritingEscapeProgressView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let textView = NSTextView(frame: .zero)
    private let editorChrome = WritingEscapeEditorChrome(frame: .zero)
    private let progressView = WritingEscapeProgressView(frame: .zero)

    private var timer: Timer?
    private var bursts: [InputBurst] = []
    private var lastUpdateTime: TimeInterval
    private var lastTypedAt: TimeInterval?
    private var lastTextLength = 0
    private var streak: TimeInterval = 0
    private var peakWPM: Double = 0
    private var comboBreaks = 0
    private var wasQualified = false
    private var isUnlocked = false
    private var isSaving = false
    private var emergencyHoldStartedAt: TimeInterval?
    private var emergencyEscapeProgress: TimeInterval = 0
    private var shakePhase: CGFloat = 0
    private var currentWPM: Double = 0
    private var particles: [Particle] = []
    private var lastShootingStarAt: TimeInterval = 0
    private var lastFireworkAt: TimeInterval = 0
    private var didSpawnUnlockBurst = false

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        siteName: String?,
        initialText: String,
        onEscapeRequested: @escaping (String, WritingEscapeMetrics) -> Void,
        onEmergencyEscapeRequested: @escaping () -> Void
    ) {
        self.siteName = siteName
        self.initialText = initialText
        self.onEscapeRequested = onEscapeRequested
        self.onEmergencyEscapeRequested = onEmergencyEscapeRequested
        self.lastUpdateTime = startedAt.timeIntervalSinceReferenceDate
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
        layoutGame()
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    func setSaving(_ saving: Bool) {
        isSaving = saving
        escapeButton.isEnabled = !saving
        escapeButton.title = saving ? "Saving and Closing..." : "Save and Close"
        statusLabel.stringValue = saving ? "The artifact chute is opening. Do not anger the chute." : statusLabel.stringValue
        saveErrorLabel.stringValue = ""
        needsDisplay = true
    }

    func showSaveFailure(_ message: String) {
        isSaving = false
        escapeButton.isEnabled = true
        escapeButton.title = "Try Save and Close Again"
        saveErrorLabel.stringValue = message
        statusLabel.stringValue = "The gate remains unlocked, but WordPress.com coughed."
        needsDisplay = true
    }

    func beginEmergencyEscapeHold() {
        if emergencyHoldStartedAt == nil {
            emergencyHoldStartedAt = Date.timeIntervalSinceReferenceDate
        }
    }

    func cancelEmergencyEscapeHold() {
        emergencyHoldStartedAt = nil
        emergencyEscapeProgress = 0
        hatchProgressView.progress = 0
        hatchProgressView.isHardMode = false
        hatchLabel.stringValue = "Emergency hatch: hold Esc for 10s"
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        let now = Date.timeIntervalSinceReferenceDate
        let length = textView.string.count
        let delta = max(0, length - lastTextLength)
        lastTextLength = length
        guard delta > 0 else { return }

        bursts.append(InputBurst(time: now, characters: delta))
        lastTypedAt = now
        saveErrorLabel.stringValue = ""
    }

    @objc private func escapeButtonPressed() {
        guard isUnlocked, !isSaving else { return }
        let now = Date()
        let body = textView.string
        let metrics = WritingEscapeMetrics(
            startedAt: startedAt,
            completedAt: now,
            duration: now.timeIntervalSince(startedAt),
            peakWPM: peakWPM,
            words: DraftArtifactText.wordCount(body),
            characters: body.count,
            comboBreaks: comboBreaks
        )
        onEscapeRequested(body, metrics)
    }

    private func setupView() {
        wantsLayer = true
        layer?.isOpaque = false

        for label in [titleLabel, subtitleLabel, statusLabel, statsLabel, wpmLabel, targetLabel, hardModeLabel, saveErrorLabel, hatchLabel] {
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }

        titleLabel.font = .systemFont(ofSize: 42, weight: .black)
        titleLabel.textColor = .escapeInk
        let site = siteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let site, !site.isEmpty {
            subtitleLabel.stringValue = "The Draft Gate is locked to \(site). Maintain velocity for 30 seconds."
        } else {
            subtitleLabel.stringValue = "The Draft Gate is locked. Maintain velocity for 30 seconds."
        }
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.textColor = .escapeMutedInk
        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .escapeGreen
        statsLabel.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        statsLabel.textColor = .escapeInk
        wpmLabel.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        wpmLabel.textColor = .escapeInk
        targetLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        targetLabel.textColor = .escapeAmber
        hardModeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .heavy)
        hardModeLabel.textColor = .escapeRed
        hardModeLabel.alphaValue = 0
        saveErrorLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        saveErrorLabel.textColor = .escapeRed
        hatchLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        hatchLabel.textColor = .escapeMutedInk

        editorChrome.addSubview(scrollView)
        addSubview(editorChrome)
        addSubview(progressView)
        addSubview(hatchProgressView)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.delegate = self
        textView.string = initialText
        lastTextLength = initialText.count
        textView.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        textView.textColor = .escapePaperInk
        textView.insertionPointColor = .escapeGreen
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)

        escapeButton.target = self
        escapeButton.action = #selector(escapeButtonPressed)
        escapeButton.title = "No escape without a draft: Write continuously for 30 seconds to escape"
        escapeButton.isEnabled = false
        escapeButton.wantsLayer = true
        escapeButton.layer?.zPosition = 1000
        hatchLabel.wantsLayer = true
        hatchLabel.layer?.zPosition = 1000
        hatchProgressView.wantsLayer = true
        hatchProgressView.layer?.zPosition = 1000
        addSubview(escapeButton)
    }

    private func startTimer() {
        timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        let now = Date.timeIntervalSinceReferenceDate
        let delta = min(0.25, now - lastUpdateTime)
        lastUpdateTime = now

        bursts.removeAll { now - $0.time > rollingWindow }
        currentWPM = rollingWPM(now: now)
        peakWPM = max(peakWPM, currentWPM)

        let recentlyTyped = lastTypedAt.map { now - $0 < 1.2 } ?? false
        let qualified = recentlyTyped && currentWPM >= targetWPM
        if qualified {
            streak = min(requiredStreak, streak + delta)
        } else if wasQualified && !qualified {
            streak = 0
            comboBreaks += 1
        }
        wasQualified = qualified

        if streak >= requiredStreak && !isUnlocked {
            unlockEscape()
        }

        updateEmergencyEscape(now: now)
        updateLabels(qualified: qualified)
        updateEffects()
        updateParticles(delta: delta, now: now)
        needsDisplay = true
        layoutGame()
    }

    private func rollingWPM(now: TimeInterval) -> Double {
        let characterCount = bursts.reduce(0) { $0 + $1.characters }
        guard characterCount > 0 else { return 0 }
        let oldest = bursts.first?.time ?? now
        let elapsed = max(1.5, min(rollingWindow, now - oldest))
        return (Double(characterCount) / 5.0) / (elapsed / 60.0)
    }

    private func updateLabels(qualified: Bool) {
        let seconds = String(format: "%.1f", streak)
        statsLabel.stringValue = "\(seconds)s / 30.0s"
        wpmLabel.stringValue = "\(Int(currentWPM.rounded())) WPM"
        progressView.progress = CGFloat(streak / requiredStreak)
        progressView.isHardMode = currentWPM >= targetWPM * 1.8
        hatchProgressView.progress = CGFloat(emergencyEscapeProgress / emergencyEscapeDuration)
        hatchProgressView.isHardMode = emergencyEscapeProgress > 0
        escapeButton.progress = CGFloat(streak / requiredStreak)

        if isUnlocked {
            statusLabel.stringValue = isSaving
                ? "Saving the relic. The gate is humming in lowercase."
                : "ESCAPE UNLOCKED. Save and close before the draft changes its mind."
        } else if currentWPM >= targetWPM * 2.4 {
            statusLabel.stringValue = "ABSOLUTE NONSENSE VELOCITY. THE DRAFT GATE IS PANICKING."
        } else if currentWPM >= targetWPM * 1.8 {
            statusLabel.stringValue = "Hard mode engaged. The room is now editorially unstable."
        } else if qualified {
            statusLabel.stringValue = "Good. Keep writing. Do not look directly at the cursor."
        } else if textView.string.isEmpty {
            statusLabel.stringValue = "Start typing. The gate can smell hesitation."
        } else {
            statusLabel.stringValue = "Combo broken. More words. Fewer thoughts about escape."
        }
    }

    private func updateEffects() {
        let intensity = max(0, min(1, CGFloat((currentWPM - targetWPM * 1.6) / (targetWPM * 1.4))))
        hardModeLabel.alphaValue = intensity > 0.2 && !isUnlocked ? 1 : 0
        editorChrome.intensity = intensity
        progressView.intensity = intensity
        shakePhase += 0.44 + intensity * 0.4
    }

    private func updateParticles(delta: TimeInterval, now: TimeInterval) {
        particles = particles.compactMap { particle in
            var next = particle
            next.age += delta
            guard next.age < next.lifetime else { return nil }
            next.position.x += next.velocity.dx * CGFloat(delta)
            next.position.y += next.velocity.dy * CGFloat(delta)
            next.velocity.dy += gravity(for: next.kind) * CGFloat(delta)
            return next
        }

        let progress = streak / requiredStreak
        if progress > 0.45, now - lastShootingStarAt > shootingStarInterval(progress: progress) {
            spawnShootingStar(progress: progress)
            lastShootingStarAt = now
        }

        if progress > 0.82, now - lastFireworkAt > fireworkInterval(progress: progress) {
            spawnFirework(
                at: CGPoint(
                    x: CGFloat.random(in: bounds.width * 0.18...bounds.width * 0.82),
                    y: CGFloat.random(in: bounds.height * 0.08...bounds.height * 0.24)
                ),
                scale: 0.74,
                color: progress > 0.94 ? .escapeGreen : .escapeAmber
            )
            lastFireworkAt = now
        }
    }

    private func shootingStarInterval(progress: TimeInterval) -> TimeInterval {
        max(0.38, 1.4 - progress * 0.85)
    }

    private func fireworkInterval(progress: TimeInterval) -> TimeInterval {
        max(0.42, 1.1 - progress * 0.55)
    }

    private func gravity(for kind: ParticleKind) -> CGFloat {
        switch kind {
        case .shootingStar:
            return 10
        case .spark:
            return 55
        case .firework:
            return 90
        }
    }

    private func spawnShootingStar(progress: TimeInterval) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let startX = CGFloat.random(in: bounds.width * 0.04...bounds.width * 0.9)
        let startY = CGFloat.random(in: bounds.height * 0.04...bounds.height * 0.22)
        let speed = CGFloat.random(in: 420...620) * (0.86 + CGFloat(progress) * 0.28)
        let color: NSColor = progress > 0.78 ? .escapeGreen : .escapeAmber
        particles.append(Particle(
            kind: .shootingStar,
            position: CGPoint(x: startX, y: startY),
            velocity: CGVector(dx: speed, dy: CGFloat.random(in: 95...165)),
            color: color,
            radius: CGFloat.random(in: 2.2...3.6),
            age: 0,
            lifetime: 1.1,
            trailLength: CGFloat.random(in: 70...130)
        ))

        if progress > 0.68 {
            spawnProgressSparks(progress: progress)
        }
    }

    private func spawnProgressSparks(progress: TimeInterval) {
        let progressWidth = progressView.frame.width * CGFloat(min(max(progress, 0), 1))
        let origin = CGPoint(
            x: progressView.frame.minX + progressWidth,
            y: progressView.frame.midY
        )
        for _ in 0..<4 {
            particles.append(Particle(
                kind: .spark,
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: -70...60), dy: CGFloat.random(in: -95...45)),
                color: .escapeGreen,
                radius: CGFloat.random(in: 1.4...2.6),
                age: 0,
                lifetime: TimeInterval(CGFloat.random(in: 0.45...0.8)),
                trailLength: 0
            ))
        }
    }

    private func spawnFirework(at origin: CGPoint, scale: CGFloat, color: NSColor) {
        let count = Int(18 * scale)
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * CGFloat.pi * 2 + CGFloat.random(in: -0.12...0.12)
            let speed = CGFloat.random(in: 70...160) * scale
            let resolvedColor: NSColor = Bool.random() ? color : .escapeAmber
            particles.append(Particle(
                kind: .firework,
                position: origin,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                color: resolvedColor,
                radius: CGFloat.random(in: 1.8...3.4) * scale,
                age: 0,
                lifetime: TimeInterval(CGFloat.random(in: 0.75...1.25)),
                trailLength: 0
            ))
        }
    }

    private func updateEmergencyEscape(now: TimeInterval) {
        guard let emergencyHoldStartedAt else {
            emergencyEscapeProgress = 0
            hatchProgressView.progress = 0
            return
        }

        emergencyEscapeProgress = min(emergencyEscapeDuration, now - emergencyHoldStartedAt)
        hatchLabel.stringValue = "Emergency hatch opening: \(String(format: "%.1f", emergencyEscapeProgress))s / 10.0s"
        if emergencyEscapeProgress >= emergencyEscapeDuration {
            onEmergencyEscapeRequested()
        }
    }

    private func unlockEscape() {
        isUnlocked = true
        escapeButton.isEnabled = true
        escapeButton.title = "Save and Close"
        if !didSpawnUnlockBurst {
            didSpawnUnlockBurst = true
            spawnFirework(at: CGPoint(x: bounds.midX, y: bounds.height * 0.18), scale: 1.35, color: .escapeGreen)
            spawnFirework(at: CGPoint(x: bounds.width * 0.72, y: bounds.height * 0.15), scale: 0.95, color: .escapeAmber)
        }
        escapeButton.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            escapeButton.animator().alphaValue = 1
        }
    }

    private func layoutGame() {
        let safe = bounds.insetBy(dx: max(48, bounds.width * 0.08), dy: max(32, bounds.height * 0.06))
        let contentWidth = min(980, safe.width)
        let left = safe.midX - contentWidth / 2
        let top = safe.minY

        let controlsTop = top + 8
        hatchLabel.frame = NSRect(x: left, y: controlsTop + 8, width: 278, height: 18)
        hatchProgressView.frame = NSRect(x: left + 286, y: controlsTop + 12, width: 150, height: 10)
        let buttonWidth = min(520, max(300, contentWidth - 460))
        escapeButton.frame = NSRect(x: left + contentWidth - buttonWidth, y: controlsTop, width: buttonWidth, height: 48)

        titleLabel.frame = NSRect(x: left, y: top + 62, width: contentWidth, height: 54)
        subtitleLabel.frame = NSRect(x: left + 2, y: top + 116, width: contentWidth, height: 24)
        targetLabel.frame = NSRect(x: left + contentWidth - 180, y: top + 124, width: 180, height: 18)

        let statTop = top + 160
        statsLabel.frame = NSRect(x: left, y: statTop, width: 190, height: 26)
        wpmLabel.frame = NSRect(x: left + 202, y: statTop, width: 140, height: 26)
        hardModeLabel.frame = NSRect(x: left + 356, y: statTop + 2, width: contentWidth - 356, height: 22)
        progressView.frame = NSRect(x: left, y: statTop + 36, width: contentWidth, height: 18)

        let editorTop = statTop + 72
        let bottomReserved: CGFloat = 126
        let editorHeight = max(280, safe.maxY - editorTop - bottomReserved)
        let intensity = editorChrome.intensity
        let shakeX = sin(shakePhase) * 14 * intensity
        let shakeY = cos(shakePhase * 1.27) * 8 * intensity
        editorChrome.frame = NSRect(
            x: left + shakeX,
            y: editorTop + shakeY,
            width: contentWidth,
            height: editorHeight
        )
        scrollView.frame = editorChrome.bounds.insetBy(dx: 1, dy: 1)
        textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(editorHeight, textView.frame.height))

        statusLabel.frame = NSRect(x: left, y: editorTop + editorHeight + 18, width: contentWidth, height: 22)
        saveErrorLabel.frame = NSRect(x: left, y: editorTop + editorHeight + 44, width: contentWidth, height: 22)
    }

    private func drawBackground() {
        NSColor(calibratedRed: 0.045, green: 0.046, blue: 0.052, alpha: 0.97).setFill()
        bounds.fill()

        let glowColor = currentWPM >= targetWPM * 1.8
            ? NSColor(calibratedRed: 0.85, green: 0.12, blue: 0.18, alpha: 0.30)
            : NSColor(calibratedRed: 0.12, green: 0.65, blue: 0.48, alpha: 0.22)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        NSGradient(colors: [glowColor, .clear])?.draw(
            fromCenter: center,
            radius: 20,
            toCenter: center,
            radius: max(bounds.width, bounds.height) * 0.72,
            options: []
        )

        NSColor.black.withAlphaComponent(0.25).setFill()
        for y in stride(from: CGFloat(0), through: bounds.height, by: 5) {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }

        drawParticles()

        let warning = "NO ESCAPE WITHOUT A DRAFT"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.08)
        ]
        for y in stride(from: CGFloat(24), through: bounds.height, by: 86) {
            warning.draw(at: NSPoint(x: 24, y: y), withAttributes: attributes)
            warning.draw(at: NSPoint(x: bounds.width - 250, y: y + 38), withAttributes: attributes)
        }
    }

    private func drawParticles() {
        guard !particles.isEmpty else { return }
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        cgContext.saveGState()
        cgContext.setBlendMode(.plusLighter)

        for particle in particles {
            let remaining = max(0, 1 - CGFloat(particle.age / particle.lifetime))
            let color = particle.color.withAlphaComponent(0.18 + 0.78 * remaining)
            color.setFill()
            color.setStroke()

            switch particle.kind {
            case .shootingStar:
                let speed = max(1, sqrt(particle.velocity.dx * particle.velocity.dx + particle.velocity.dy * particle.velocity.dy))
                let tail = CGPoint(
                    x: particle.position.x - particle.velocity.dx / speed * particle.trailLength,
                    y: particle.position.y - particle.velocity.dy / speed * particle.trailLength
                )
                let path = NSBezierPath()
                path.move(to: tail)
                path.line(to: particle.position)
                path.lineWidth = max(1, particle.radius * remaining)
                path.stroke()
                drawStar(at: particle.position, radius: particle.radius * (1.3 + remaining), color: color)
            case .spark, .firework:
                let radius = max(0.6, particle.radius * remaining)
                NSBezierPath(ovalIn: NSRect(
                    x: particle.position.x - radius,
                    y: particle.position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )).fill()
            }
        }

        cgContext.restoreGState()
    }

    private func drawStar(at point: CGPoint, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        let points = 5
        for index in 0..<(points * 2) {
            let angle = CGFloat(index) * CGFloat.pi / CGFloat(points) - CGFloat.pi / 2
            let resolvedRadius = index.isMultiple(of: 2) ? radius : radius * 0.42
            let vertex = CGPoint(
                x: point.x + cos(angle) * resolvedRadius,
                y: point.y + sin(angle) * resolvedRadius
            )
            if index == 0 {
                path.move(to: vertex)
            } else {
                path.line(to: vertex)
            }
        }
        path.close()
        color.setFill()
        path.fill()
    }
}

private final class WritingEscapeEditorChrome: NSView {
    var intensity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.985, green: 0.974, blue: 0.932, alpha: 0.98).setFill()
        path.fill()

        let stroke = intensity > 0.2
            ? NSColor.escapeRed.withAlphaComponent(0.75)
            : NSColor.escapeGreen.withAlphaComponent(0.45)
        stroke.setStroke()
        path.lineWidth = 2
        path.stroke()

        NSColor.black.withAlphaComponent(0.055 + intensity * 0.04).setFill()
        for y in stride(from: CGFloat(68), through: bounds.height, by: 32) {
            NSRect(x: 26, y: y, width: bounds.width - 52, height: 1).fill()
        }
    }
}

private final class WritingEscapeProgressView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var intensity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var isHardMode = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.14).setFill()
        track.fill()

        let width = max(bounds.height, bounds.width * min(max(progress, 0), 1))
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let color = isHardMode ? NSColor.escapeRed : NSColor.escapeGreen
        color.withAlphaComponent(0.72 + intensity * 0.22).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        track.lineWidth = 1
        track.stroke()
    }
}

private final class WritingEscapeActionButton: NSControl {
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let clampedProgress = min(max(progress, 0), 1)
        let fill = isEnabled
            ? NSColor.escapeGreen
            : NSColor(
                calibratedRed: 0.11 + 0.12 * clampedProgress,
                green: 0.13 + 0.19 * clampedProgress,
                blue: 0.12,
                alpha: 0.96
            )
        fill.setFill()
        path.fill()

        if !isEnabled, clampedProgress > 0.05 {
            NSColor.escapeGreen.withAlphaComponent(0.18 + 0.18 * clampedProgress).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * clampedProgress, height: rect.height),
                xRadius: 10,
                yRadius: 10
            ).fill()
        }

        let stroke = isEnabled
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.escapeAmber.blended(withFraction: clampedProgress, of: .escapeGreen)?.withAlphaComponent(0.82) ?? NSColor.escapeAmber
        stroke.setStroke()
        path.lineWidth = isEnabled ? 2 : 1.5
        path.stroke()

        let fontSize: CGFloat = isEnabled ? 15 : 13
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: isEnabled ? NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.06, alpha: 1) : NSColor.escapeAmber,
            .paragraphStyle: centeredParagraphStyle
        ]
        let textRect = rect.insetBy(dx: 12, dy: 0)
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
        guard isEnabled else {
            NSSound.beep()
            return
        }
        sendAction(action, to: target)
    }

    private var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return style
    }
}

private final class WritingEscapeBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.04, alpha: 0.98).setFill()
        bounds.fill()

        let text = "THE DRAFT GATE IS ACTIVE ON ANOTHER DISPLAY"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.escapeGreen.withAlphaComponent(0.55)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

private extension NSColor {
    static let escapeInk = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.88, alpha: 1)
    static let escapePaperInk = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.10, alpha: 1)
    static let escapeMutedInk = NSColor(calibratedRed: 0.76, green: 0.75, blue: 0.68, alpha: 1)
    static let escapeGreen = NSColor(calibratedRed: 0.36, green: 0.95, blue: 0.62, alpha: 1)
    static let escapeAmber = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.32, alpha: 1)
    static let escapeRed = NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.28, alpha: 1)
}
