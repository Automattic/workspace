import AppKit

struct ArchiveTimeSlipContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let siteName: String?
    let siteURL: String?

    init(snapshot: AppSelectionSnapshot?, site: WPCOMSite?) {
        appName = snapshot?.appName
        bundleIdentifier = snapshot?.bundleIdentifier
        windowTitle = snapshot?.windowTitle
        selectedText = snapshot?.selectedText
        siteName = site?.displayName
        siteURL = site?.url
    }

    var appDisplayName: String {
        trimmed(appName) ?? "UNKNOWN APPLICATION"
    }

    var windowDisplayName: String {
        trimmed(windowTitle) ?? "UNTITLED WINDOW"
    }

    var siteDisplayName: String {
        trimmed(siteName) ?? "UNMAPPED WORDPRESS SITE"
    }

    var siteDisplayURL: String {
        trimmed(siteURL) ?? "NO PUBLIC URL SIGNAL"
    }

    var selectedTextPreview: String? {
        guard let selectedText = trimmed(selectedText) else { return nil }
        let collapsed = selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard collapsed.count > 220 else { return collapsed }
        return String(collapsed.prefix(220)) + "..."
    }

    var selectedTextByteCount: Int {
        selectedText?.utf8.count ?? 0
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue?.isEmpty == false ? trimmedValue : nil
    }
}

final class ArchiveTimeSlipOverlayManager {
    private var overlayWindows: [NSPanel] = []
    private var dismissWorkItem: DispatchWorkItem?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let duration: TimeInterval = 24

    var isShowing: Bool {
        !overlayWindows.isEmpty
    }

    func show(context: ArchiveTimeSlipContext) {
        dismiss(animated: false)

        let startedAt = Date()
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens

        overlayWindows = screens.enumerated().map { index, screen in
            let panel = makeOverlayPanel(for: screen)
            let overlayView = ArchiveTimeSlipOverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                context: context,
                screenIndex: index,
                screenCount: screens.count,
                duration: duration,
                startedAt: startedAt
            )
            panel.contentView = overlayView
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            return panel
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            overlayWindows.forEach { $0.animator().alphaValue = 1 }
        }

        installEscapeMonitors()
        scheduleDismiss()
    }

    func dismiss(animated: Bool = true) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        removeEscapeMonitors()

        let windows = overlayWindows
        overlayWindows = []
        guard !windows.isEmpty else { return }

        let closeWindows = {
            windows.forEach { window in
                window.contentView = nil
                window.close()
            }
        }

        guard animated else {
            closeWindows()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            closeWindows()
        }
    }

    private func makeOverlayPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func installEscapeMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.keyDown]
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
            }
        }
    }

    private func removeEscapeMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func scheduleDismiss() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

private final class ArchiveTimeSlipOverlayView: NSView {
    private struct FloatingFragment {
        let text: String
        let xRatio: CGFloat
        let yRatio: CGFloat
        let size: CGFloat
        let speed: CGFloat
        let phase: CGFloat
    }

    private let context: ArchiveTimeSlipContext
    private let screenIndex: Int
    private let screenCount: Int
    private let duration: TimeInterval
    private let startedAt: Date
    private let fragments: [FloatingFragment]
    private var animationTimer: Timer?

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        context: ArchiveTimeSlipContext,
        screenIndex: Int,
        screenCount: Int,
        duration: TimeInterval,
        startedAt: Date
    ) {
        self.context = context
        self.screenIndex = screenIndex
        self.screenCount = screenCount
        self.duration = duration
        self.startedAt = startedAt
        self.fragments = Self.makeFragments(context: context, screenIndex: screenIndex)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        startAnimating()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let elapsed = Date().timeIntervalSince(startedAt)
        drawTintWash(elapsed: elapsed)
        drawPhosphorMask()
        drawScanlines(elapsed: elapsed)
        drawFloatingFragments(elapsed: elapsed)
        drawTerminal(elapsed: elapsed)
        drawRecoveredSelection(elapsed: elapsed)
        drawVignette()
        drawCurvedGlass()
        drawGlitchSweep(elapsed: elapsed)
    }

    private func startAnimating() {
        animationTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func drawTintWash(elapsed: TimeInterval) {
        NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.06, alpha: 0.34).setFill()
        bounds.fill()

        let pulse = CGFloat((sin(elapsed * 1.6) + 1) / 2)
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.32, alpha: 0.08 + 0.05 * pulse).setFill()
        bounds.fill()

        let amber = NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.34, alpha: 0.06)
        let green = NSColor(calibratedRed: 0.18, green: 0.85, blue: 0.52, alpha: 0.12)
        NSGradient(colors: [green, amber, .clear])?.draw(in: bounds, angle: 18)
    }

    private func drawPhosphorMask() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        for x in stride(from: CGFloat(0), through: bounds.width, by: 3) {
            let alpha: CGFloat
            switch Int(x) % 9 {
            case 0:
                alpha = 0.025
                NSColor(calibratedRed: 1, green: 0.2, blue: 0.16, alpha: alpha).setFill()
            case 3:
                alpha = 0.035
                NSColor(calibratedRed: 0.25, green: 1, blue: 0.34, alpha: alpha).setFill()
            default:
                alpha = 0.024
                NSColor(calibratedRed: 0.22, green: 0.42, blue: 1, alpha: alpha).setFill()
            }
            NSRect(x: x, y: 0, width: 1, height: bounds.height).fill()
        }
        context.restoreGState()
    }

    private func drawScanlines(elapsed: TimeInterval) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        for y in stride(from: CGFloat(0), through: bounds.height, by: 4) {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }

        let jitter = CGFloat((sin(elapsed * 18) + 1) / 2)
        NSColor.white.withAlphaComponent(0.035).setFill()
        for y in stride(from: jitter * 2, through: bounds.height, by: 16) {
            NSRect(x: 0, y: y, width: bounds.width, height: 0.7).fill()
        }
    }

    private func drawFloatingFragments(elapsed: TimeInterval) {
        let attributes = fragmentAttributes
        for fragment in fragments {
            let drift = sin(CGFloat(elapsed) * fragment.speed + fragment.phase) * 18
            let x = bounds.width * fragment.xRatio + drift
            let y = bounds.height * fragment.yRatio + cos(CGFloat(elapsed) * fragment.speed + fragment.phase) * 10
            let alpha = 0.18 + 0.16 * CGFloat((sin(elapsed * 1.8 + Double(fragment.phase)) + 1) / 2)
            var resolvedAttributes = attributes
            resolvedAttributes[.font] = NSFont.monospacedSystemFont(ofSize: fragment.size, weight: .medium)
            resolvedAttributes[.foregroundColor] = NSColor(calibratedRed: 0.63, green: 1, blue: 0.72, alpha: alpha)
            fragment.text.draw(at: NSPoint(x: x, y: y), withAttributes: resolvedAttributes)
        }
    }

    private func drawTerminal(elapsed: TimeInterval) {
        let panelWidth = min(max(bounds.width * 0.52, 520), 780)
        let panelHeight: CGFloat = 276
        let panel = NSRect(x: 42, y: 42, width: panelWidth, height: panelHeight)

        drawPanelBackground(panel)

        let titleAttributes = textAttributes(size: 24, weight: .heavy, color: .crtGreen)
        "ARCHIVE TIME SLIP: 2004".draw(at: NSPoint(x: panel.minX + 22, y: panel.minY + 20), withAttributes: titleAttributes)

        let subtitleAttributes = textAttributes(size: 12, weight: .semibold, color: .crtAmber)
        let title = "WP WORKSPACE TEMPORAL RECOVERY CONSOLE"
        title.draw(at: NSPoint(x: panel.minX + 24, y: panel.minY + 54), withAttributes: subtitleAttributes)

        let bodyAttributes = textAttributes(size: 13, weight: .medium, color: .crtGreen)
        let visibleLineCount = min(bootLines.count, max(1, Int(elapsed * 3.4)))
        var y = panel.minY + 86
        for line in bootLines.prefix(visibleLineCount) {
            line.draw(at: NSPoint(x: panel.minX + 24, y: y), withAttributes: bodyAttributes)
            y += 22
        }

        let remaining = max(0, Int(ceil(duration - elapsed)))
        let footer = "ESC TO BAIL   AUTO-RETURN IN \(remaining)S   SCREEN \(screenIndex + 1)/\(screenCount)"
        footer.draw(
            at: NSPoint(x: panel.minX + 24, y: panel.maxY - 34),
            withAttributes: textAttributes(size: 11, weight: .bold, color: .crtDimGreen)
        )
    }

    private func drawRecoveredSelection(elapsed: TimeInterval) {
        guard let selectedTextPreview = context.selectedTextPreview else { return }

        let panelWidth = min(max(bounds.width * 0.34, 360), 520)
        let panelHeight: CGFloat = 196
        let panel = NSRect(
            x: bounds.maxX - panelWidth - 46,
            y: max(72, bounds.height * 0.42),
            width: panelWidth,
            height: panelHeight
        )

        drawPanelBackground(panel, alpha: 0.44)

        "RECOVERED DRAFT FRAGMENT".draw(
            at: NSPoint(x: panel.minX + 18, y: panel.minY + 18),
            withAttributes: textAttributes(size: 13, weight: .heavy, color: .crtAmber)
        )
        "AX SELECTED TEXT CAPTURED".draw(
            at: NSPoint(x: panel.minX + 18, y: panel.minY + 42),
            withAttributes: textAttributes(size: 11, weight: .semibold, color: .crtDimGreen)
        )

        let flicker = CGFloat((sin(elapsed * 12) + 1) / 2)
        let bodyColor = NSColor(calibratedRed: 0.72, green: 1, blue: 0.78, alpha: 0.74 + flicker * 0.14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: bodyColor,
            .paragraphStyle: paragraph
        ]
        selectedTextPreview.draw(
            in: NSRect(x: panel.minX + 18, y: panel.minY + 70, width: panel.width - 36, height: panel.height - 88),
            withAttributes: bodyAttributes
        )
    }

    private func drawPanelBackground(_ rect: NSRect, alpha: CGFloat = 0.5) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(alpha).setFill()
        path.fill()
        NSColor(calibratedRed: 0.32, green: 1, blue: 0.52, alpha: 0.42).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawVignette() {
        guard let gradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0),
            NSColor.black.withAlphaComponent(0.64)
        ]) else {
            return
        }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        gradient.draw(
            fromCenter: center,
            radius: min(bounds.width, bounds.height) * 0.18,
            toCenter: center,
            radius: max(bounds.width, bounds.height) * 0.74,
            options: []
        )
    }

    private func drawCurvedGlass() {
        let outer = NSBezierPath(rect: bounds)
        let innerRect = bounds.insetBy(dx: 16, dy: 16)
        let inner = NSBezierPath(roundedRect: innerRect, xRadius: 42, yRadius: 42)
        outer.append(inner)
        outer.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        outer.fill()

        NSColor.white.withAlphaComponent(0.12).setStroke()
        inner.lineWidth = 2
        inner.stroke()

        NSColor(calibratedRed: 0.36, green: 1, blue: 0.57, alpha: 0.16).setStroke()
        let glow = NSBezierPath(roundedRect: innerRect.insetBy(dx: 11, dy: 11), xRadius: 34, yRadius: 34)
        glow.lineWidth = 1
        glow.stroke()
    }

    private func drawGlitchSweep(elapsed: TimeInterval) {
        let sweepY = CGFloat((elapsed / 2.4).truncatingRemainder(dividingBy: 1)) * bounds.height
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: 0, y: sweepY, width: bounds.width, height: 5).fill()

        if Int(elapsed * 5) % 9 == 0 {
            NSColor(calibratedRed: 0.3, green: 1, blue: 0.65, alpha: 0.09).setFill()
            let y = CGFloat((sin(elapsed * 11) + 1) / 2) * bounds.height
            NSRect(x: 0, y: y, width: bounds.width, height: 24).fill()
        }
    }

    private var bootLines: [String] {
        [
            "BOOTING BLOGOSPHERE MEMORY MAP...",
            "TEMPORAL LOCK ACQUIRED: \(context.appDisplayName)",
            "WINDOW SIGNAL: \(context.windowDisplayName)",
            "BUNDLE TRACE: \(context.bundleIdentifier ?? "UNKNOWN BUNDLE")",
            "SITE ANCHOR: \(context.siteDisplayName)",
            "SITE URL: \(context.siteDisplayURL)",
            "SELECTED TEXT: \(context.selectedTextByteCount) BYTES RECOVERED",
            "PERMALINK FORMAT: QUESTIONABLE",
            "RESTORING INDEX.PHP?p=42...",
            "THE FIRST KEY IS PROBABLY IN A DRAFT"
        ]
    }

    private var fragmentAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.crtGreen
        ]
    }

    private func textAttributes(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
    }

    private static func makeFragments(context: ArchiveTimeSlipContext, screenIndex: Int) -> [FloatingFragment] {
        let labels = [
            "index.php?p=42",
            "/wp-admin/post.php",
            "DRAFT AUTOSAVE",
            "RSS 2.0 SIGNAL",
            "PINGBACK ENABLED",
            "FIRST POST",
            "BLOGROLL ONLINE",
            "COMMENTS: OPEN",
            "SLUG FIELD UNSTABLE",
            context.siteDisplayName.uppercased()
        ]

        return labels.enumerated().map { index, text in
            let seed = CGFloat(index + 1 + screenIndex * 7)
            return FloatingFragment(
                text: text,
                xRatio: 0.12 + CGFloat((index * 23) % 74) / 100,
                yRatio: 0.18 + CGFloat((index * 31) % 68) / 100,
                size: 11 + CGFloat(index % 5),
                speed: 0.38 + seed.truncatingRemainder(dividingBy: 5) * 0.08,
                phase: seed * 1.37
            )
        }
    }
}

private extension NSColor {
    static let crtGreen = NSColor(calibratedRed: 0.54, green: 1, blue: 0.65, alpha: 0.92)
    static let crtDimGreen = NSColor(calibratedRed: 0.4, green: 0.82, blue: 0.5, alpha: 0.78)
    static let crtAmber = NSColor(calibratedRed: 1, green: 0.76, blue: 0.38, alpha: 0.9)
}
