import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let quickLauncherKeyboardPageStep = 6

struct WordPressAgentUtilityOverlayView: View {
    @EnvironmentObject var appState: AppState

    let onSubmit: (String) -> Void
    let onSaveSticky: (String, Int) -> Bool
    let onDismiss: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var draftMessage = ""
    @State private var pendingImageURLs: [URL] = []
    @State private var composerTextHeight: CGFloat = 22
    @State private var isLauncherActive = false
    @State private var launcherQuery = ""
    @State private var highlightedLauncherIndex = 0
    @FocusState private var isPromptFocused: Bool

    private var selectedConversation: WordPressAgentConversation? {
        appState.selectedWordPressAgentConversation
    }

    private var activeSiteID: Int? {
        appState.selectedWordPressComSiteID
    }

    private var activeSite: WPCOMSite? {
        appState.selectedWordPressComSite
    }

    private var siteTitle: String {
        activeSite.map(Self.compactSiteLabel(for:)) ?? "Choose your site"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !pendingImageURLs.isEmpty {
                UtilityOverlayAttachmentStrip(fileURLs: pendingImageURLs) { url in
                    pendingImageURLs.removeAll { $0 == url }
                }
            }

            composerTextView

            if isLauncherActive {
                quickLauncher
            }

            toolbar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.067, green: 0.467, blue: 0.800).opacity(0.72), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: UtilityOverlayHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onAppear {
            requestPromptFocus()
            updateLauncherState(for: draftMessage)
        }
        .onChange(of: isComposerDisabled) { isDisabled in
            if !isDisabled {
                requestPromptFocus()
            }
        }
        .onChange(of: draftMessage) { value in
            updateLauncherState(for: value)
        }
        .onChange(of: appState.quickLauncherResults) { _ in
            clampHighlightedLauncherIndex()
        }
        .onPreferenceChange(UtilityOverlayHeightPreferenceKey.self) { height in
            onHeightChange(max(96, height))
        }
        .onExitCommand {
            if isLauncherActive {
                closeLauncher()
            } else {
                onDismiss()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                selectImages()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLauncherActive ? .tertiary : .secondary)
            .help("Add images")
            .disabled(isComposerDisabled || isLauncherActive)

            Button {
                appState.showWordPressAgentWindow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .medium))
                    Text(siteTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: 160, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLauncherActive ? .tertiary : .secondary)
            .help("Open WordPress Agent")
            .disabled(isLauncherActive)

            Spacer(minLength: 8)

            if selectedConversation?.isSending == true || appState.isTranscribing {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .help("Working")
            }

            Button {
                saveDraftAsSticky()
            } label: {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSaveSticky ? .secondary : .tertiary)
            .help("Save as sticky note")
            .disabled(!canSaveSticky)

            Button {
                appState.toggleRecordingForWordPressAgentUtilityOverlay()
            } label: {
                Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(dictationControlColor)
            .help(appState.isRecording ? "Stop recording" : "Dictate")
            .disabled(isLauncherActive || activeSiteID == nil || appState.isTranscribing)

            Button {
                sendDraftMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSendMessage ? AgentPalette.primaryActionIcon : AgentPalette.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(canSendMessage ? AgentPalette.primaryActionFill : AgentPalette.disabledControl)
                    )
            }
            .buttonStyle(.plain)
            .help("Send")
            .disabled(!canSendMessage)
        }
    }

    private var canSendMessage: Bool {
        (Self.containsNonWhitespace(draftMessage) || !pendingImageURLs.isEmpty)
        && !isLauncherActive
        && !isComposerDisabled
    }

    private var dictationControlColor: Color {
        if isLauncherActive {
            return Color(nsColor: .tertiaryLabelColor)
        }
        return appState.isRecording ? .red : Color(nsColor: .secondaryLabelColor)
    }

    private var canSaveSticky: Bool {
        Self.containsNonWhitespace(draftMessage)
        && !isLauncherActive
        && activeSiteID != nil
        && !isComposerDisabled
    }

    private var isComposerDisabled: Bool {
        activeSiteID == nil
            || selectedConversation?.isSending == true
            || appState.isTranscribing
    }

    private var composerTextView: some View {
        ZStack(alignment: .topLeading) {
            AgentComposerTextView(
                text: $draftMessage,
                isFocused: Binding(
                    get: { isPromptFocused },
                    set: { isPromptFocused = $0 }
                ),
                height: $composerTextHeight,
                fontSize: 15,
                minimumHeight: 22,
                maximumHeight: 160,
                isDisabled: isComposerDisabled,
                onShiftSubmit: saveDraftAsSticky,
                onCommand: handleComposerCommand,
                onSubmit: sendDraftMessage
            )
            .frame(height: composerTextHeight)

            if draftMessage.isEmpty {
                Text("Ask WordPress Agent")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    private var quickLauncher: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.7)

            if appState.quickLauncherResults.isEmpty {
                HStack(spacing: 8) {
                    if appState.isQuickLauncherIndexing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(appState.isQuickLauncherIndexing ? "Indexing site..." : "No matching items")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                .padding(.horizontal, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(appState.quickLauncherResults.enumerated()), id: \.element.id) { index, entity in
                                QuickLauncherRow(
                                    entity: entity,
                                    isHighlighted: index == highlightedLauncherIndex
                                ) {
                                    openLauncherEntity(entity)
                                }
                                .id(entity.id)
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 286)
                    .onChange(of: highlightedLauncherIndex) { index in
                        guard index >= 0,
                              index < appState.quickLauncherResults.count else {
                            return
                        }
                        proxy.scrollTo(appState.quickLauncherResults[index].id, anchor: .center)
                    }
                }
            }

            if let message = appState.quickLauncherStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.top, 2)
    }

    private func sendDraftMessage() {
        guard canSendMessage, !isLauncherActive else { return }
        let message = draftMessage
        let attachments = pendingImageURLs
        draftMessage = ""
        pendingImageURLs = []
        guard let conversationID = appState.submitWordPressAgentComposerMessage(
            message,
            attachments: attachments,
            siteID: activeSiteID,
            startsNewConversation: true
        ) else {
            draftMessage = message
            pendingImageURLs = attachments
            return
        }

        onSubmit(conversationID)
    }

    private func updateLauncherState(for value: String) {
        guard appState.quickLauncherEnabled else {
            if isLauncherActive {
                closeLauncher()
            }
            return
        }
        guard let query = launcherQuery(from: value), activeSiteID != nil || !appState.wordpressComSites.isEmpty else {
            if isLauncherActive {
                closeLauncher()
            }
            return
        }

        let wasActive = isLauncherActive
        let didChangeQuery = launcherQuery != query
        isLauncherActive = true
        launcherQuery = query
        if !wasActive || didChangeQuery {
            highlightedLauncherIndex = 0
        }
        if !wasActive {
            appState.prepareQuickLauncher(query: query)
        } else {
            appState.updateQuickLauncherSearch(query)
        }
        clampHighlightedLauncherIndex()
    }

    private func launcherQuery(from value: String) -> String? {
        let trimmedPrefix = value.drop(while: { $0.isWhitespace && !$0.isNewline })
        guard trimmedPrefix.first == "@" else { return nil }
        let query = trimmedPrefix.dropFirst()
        guard !query.contains(where: { $0.isNewline }) else { return nil }
        return String(query).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleComposerCommand(_ command: AgentComposerCommand) -> Bool {
        guard isLauncherActive else { return false }
        switch command {
        case .submit:
            openHighlightedLauncherEntity()
            return true
        case .moveUp:
            guard !appState.quickLauncherResults.isEmpty else { return true }
            highlightedLauncherIndex = max(0, highlightedLauncherIndex - 1)
            return true
        case .moveDown:
            guard !appState.quickLauncherResults.isEmpty else { return true }
            highlightedLauncherIndex = min(appState.quickLauncherResults.count - 1, highlightedLauncherIndex + 1)
            return true
        case .pageUp:
            guard !appState.quickLauncherResults.isEmpty else { return true }
            highlightedLauncherIndex = max(0, highlightedLauncherIndex - quickLauncherKeyboardPageStep)
            return true
        case .pageDown:
            guard !appState.quickLauncherResults.isEmpty else { return true }
            highlightedLauncherIndex = min(
                appState.quickLauncherResults.count - 1,
                highlightedLauncherIndex + quickLauncherKeyboardPageStep
            )
            return true
        case .cancel:
            closeLauncher()
            return true
        }
    }

    private func openHighlightedLauncherEntity() {
        guard highlightedLauncherIndex >= 0,
              highlightedLauncherIndex < appState.quickLauncherResults.count else {
            return
        }
        openLauncherEntity(appState.quickLauncherResults[highlightedLauncherIndex])
    }

    private func openLauncherEntity(_ entity: QuickLauncherEntity) {
        appState.openQuickLauncherEntity(entity)
        draftMessage = ""
        pendingImageURLs = []
        onDismiss()
    }

    private func closeLauncher() {
        isLauncherActive = false
        launcherQuery = ""
        highlightedLauncherIndex = 0
        if draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
            draftMessage = ""
        }
        requestPromptFocus()
    }

    private func clampHighlightedLauncherIndex() {
        let count = appState.quickLauncherResults.count
        if count == 0 {
            highlightedLauncherIndex = 0
        } else {
            highlightedLauncherIndex = min(max(0, highlightedLauncherIndex), count - 1)
        }
    }

    private func saveDraftAsSticky() {
        guard canSaveSticky, let activeSiteID else { return }
        let message = draftMessage
        guard onSaveSticky(message, activeSiteID) else { return }
        draftMessage = ""
        pendingImageURLs = []
    }

    private static func containsNonWhitespace(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace && !$0.isNewline }
    }

    private static func compactSiteLabel(for site: WPCOMSite) -> String {
        let candidates: [String?] = [site.slug, site.url.map(Self.strippedSiteURL), site.displayName]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, trimmed.localizedCaseInsensitiveCompare("Site Title") != .orderedSame {
                return trimmed
            }
        }
        return "\(site.id)"
    }

    private static func strippedSiteURL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func requestPromptFocus() {
        isPromptFocused = true
        DispatchQueue.main.async {
            isPromptFocused = true
        }
    }

    private func selectImages() {
        guard !isComposerDisabled, !isLauncherActive else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }

        var existingURLs = Set(pendingImageURLs)
        for url in panel.urls where existingURLs.insert(url).inserted {
            pendingImageURLs.append(url)
        }
        isPromptFocused = true
    }
}

private struct UtilityOverlayHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 96

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct QuickLauncherRow: View {
    let entity: QuickLauncherEntity
    let isHighlighted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: entity.kind.systemImageName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isHighlighted ? AgentPalette.primaryActionIcon : .secondary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(entity.displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if entity.kind == .site {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHighlighted ? AgentPalette.primaryActionFill.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct UtilityOverlayAttachmentStrip: View {
    let fileURLs: [URL]
    let onRemove: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileURLs, id: \.self) { url in
                    UtilityOverlayAttachmentPill(fileURL: url) {
                        onRemove(url)
                    }
                }
            }
        }
        .frame(height: 34)
    }
}

private struct UtilityOverlayAttachmentPill: View {
    let fileURL: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            Text(fileURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.leading, 5)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AgentPalette.softControl)
        )
    }
}
