import Foundation

enum WordPressAgentPreviewViewMode: String, Equatable, Hashable, Identifiable {
    case signedOut
    case preview
    case edit

    var id: String { rawValue }

    var usesAuthenticatedSession: Bool {
        self != .signedOut
    }
}

struct WordPressAgentPreviewModeURLs: Equatable {
    let signedOutURL: URL
    let signedInURL: URL?
    let editURL: URL?

    var availableModes: [WordPressAgentPreviewViewMode] {
        var modes: [WordPressAgentPreviewViewMode] = [.signedOut]
        if signedInURL != nil {
            modes.append(.preview)
        }
        if editURL != nil {
            modes.append(.edit)
        }
        return modes
    }

    func url(for mode: WordPressAgentPreviewViewMode) -> URL? {
        switch mode {
        case .signedOut:
            return signedOutURL
        case .preview:
            return signedInURL
        case .edit:
            return editURL
        }
    }
}

private struct WordPressAgentPreviewPostURLs: Equatable {
    let signedOutURL: URL
    let signedInURL: URL
    let editURL: URL
}

enum WordPressAgentPreviewURLResolver {
    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if hasExplicitScheme(trimmed) {
            candidate = trimmed
        } else if trimmed.hasPrefix("//") {
            candidate = "https:\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }
        guard let url = URLComponents(string: candidate)?.url else {
            return nil
        }

        return isPreviewable(url) ? securePreviewLoadURL(for: url) : nil
    }

    static func panelURL(forPossiblyBare url: URL) -> URL? {
        if isPreviewable(url) {
            return securePreviewLoadURL(for: url)
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
    }

    static func previewURL(forPossiblyBare url: URL) -> URL? {
        if let previewURL = previewURL(for: url) {
            return previewURL
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
    }

    static func defaultOpenURL(forPossiblyBare url: URL) -> URL? {
        if isPreviewable(url) {
            return securePreviewLoadURL(for: url)
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
    }

    static func panelURL(for url: URL) -> URL? {
        guard isPreviewable(url) else { return nil }
        if postID(fromAdminPostURL: url) != nil {
            return url
        }
        return rewrittenWordPressPostQueryURL(for: url) ?? url
    }

    static func signedOutURL(for url: URL) -> URL? {
        isPreviewable(url) ? securePreviewLoadURL(for: url) : nil
    }

    static func previewURL(for url: URL) -> URL? {
        guard isPreviewable(url) else { return nil }
        return rewrittenWordPressAdminPostURL(for: url)
            ?? rewrittenWordPressPostQueryURL(for: url)
            ?? url
    }

    static func previewURL(for url: URL, sitePreviewOptions: WPCOMSitePreviewOptions?) -> URL? {
        guard var previewURL = previewURL(for: url),
              hasPreviewQuery(previewURL),
              let sitePreviewOptions else {
            return previewURL(for: url)
        }

        // WordPress.com preview frames are usually served from the site's
        // unmapped URL, even when the agent gave us a mapped-domain link. Apply
        // that host rewrite before appending the frame nonce so simple
        // WordPress.com and Jetpack/Atomic previews both enter the authenticated
        // preview shell instead of the public post route.
        previewURL = unmappedURL(for: previewURL, unmappedURLString: sitePreviewOptions.unmappedURL) ?? previewURL
        previewURL = addingFrameNonceIfNeeded(to: previewURL, frameNonce: sitePreviewOptions.frameNonce) ?? previewURL
        return previewURL
    }

    static func isPreviewable(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host?.isEmpty == false else {
            return false
        }

        return true
    }

    static func isLocalOrPrivateNetworkURL(_ url: URL) -> Bool {
        guard let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased(),
              !host.isEmpty else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }

        if let octets = ipv4Octets(from: host) {
            return isLocalOrPrivateIPv4(octets)
        }

        return isLocalOrPrivateIPv6(host)
    }

    static func previewModeURLs(for url: URL, site: WPCOMSite?) -> WordPressAgentPreviewModeURLs? {
        guard isPreviewable(url) else { return nil }

        let loadURL = securePreviewLoadURL(for: url)
        let isSameSite = isSameSiteURL(loadURL, site: site)
        if isSameSite, let postURLs = adminPostPreviewModeURLs(for: loadURL) {
            return WordPressAgentPreviewModeURLs(
                signedOutURL: postURLs.signedOutURL,
                signedInURL: postURLs.signedInURL,
                editURL: postURLs.editURL
            )
        }

        return WordPressAgentPreviewModeURLs(
            signedOutURL: loadURL,
            signedInURL: isSameSite ? loadURL : nil,
            editURL: isSameSite ? postQueryEditURL(for: loadURL) : nil
        )
    }

    private static func adminPostPreviewModeURLs(for url: URL) -> WordPressAgentPreviewPostURLs? {
        guard isPreviewable(url) else { return nil }

        if let postID = postID(fromAdminPostURL: url),
           let signedOutURL = signedOutPostURL(for: url, postID: postID),
           let signedInURL = rewrittenWordPressAdminPostURL(for: url),
           let editURL = adminPostEditURL(for: url, postID: postID) {
            return WordPressAgentPreviewPostURLs(
                signedOutURL: securePreviewLoadURL(for: signedOutURL),
                signedInURL: securePreviewLoadURL(for: signedInURL),
                editURL: securePreviewLoadURL(for: editURL)
            )
        }

        return nil
    }

    private static func postQueryEditURL(for url: URL) -> URL? {
        guard isPreviewable(url) else { return nil }

        if let postID = postID(fromWordPressPostQueryURL: url),
           let editURL = adminPostEditURL(for: url, postID: postID) {
            return securePreviewLoadURL(for: editURL)
        }

        return nil
    }

    static func viewMode(for url: URL) -> WordPressAgentPreviewViewMode? {
        if postID(fromAdminPostURL: url) != nil {
            return .edit
        }
        if postID(fromWordPressPostQueryURL: url) != nil {
            return hasPreviewQuery(url) ? .preview : .signedOut
        }
        return nil
    }

    static func isSameSiteURL(_ url: URL, site: WPCOMSite?) -> Bool {
        guard let host = normalizedComparableHost(url.host),
              let site,
              !siteHosts(for: site).isEmpty else {
            return false
        }

        return siteHosts(for: site).contains(host)
    }

    private static func siteHosts(for site: WPCOMSite) -> Set<String> {
        let candidates = [
            site.url,
            site.slug,
            site.slug.map { "https://\($0)" }
        ]

        return Set(candidates.compactMap { candidate in
            guard let candidate else { return nil }
            if let host = URLComponents(string: candidate)?.host {
                return normalizedComparableHost(host)
            }
            return normalizedComparableHost(candidate)
        })
    }

    private static func normalizedComparableHost(_ host: String?) -> String? {
        guard var host = host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespacesAndNewlines)).lowercased(),
              !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    private static func securePreviewLoadURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http",
              let host = normalizedComparableHost(components.host),
              isWordPressComHost(host) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private static func isWordPressComHost(_ host: String) -> Bool {
        host == "wordpress.com" || host.hasSuffix(".wordpress.com")
    }

    private static func signedOutPostURL(for url: URL, postID: String) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var signedOutComponents = URLComponents()
        signedOutComponents.scheme = components.scheme
        signedOutComponents.host = components.host
        signedOutComponents.port = components.port
        signedOutComponents.path = "/"
        signedOutComponents.queryItems = [
            URLQueryItem(name: "p", value: postID)
        ]
        return signedOutComponents.url
    }

    private static func rewrittenWordPressAdminPostURL(for url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let postID = postID(fromAdminPostComponents: components) else {
            return nil
        }

        var rewrittenComponents = URLComponents()
        rewrittenComponents.scheme = components.scheme
        rewrittenComponents.host = components.host
        rewrittenComponents.port = components.port
        rewrittenComponents.path = "/"
        rewrittenComponents.queryItems = [
            URLQueryItem(name: "p", value: postID),
            URLQueryItem(name: "preview", value: "true")
        ]

        return rewrittenComponents.url
    }

    private static func rewrittenWordPressPostQueryURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard postID(fromWordPressPostQueryItems: queryItems) != nil,
              !queryItems.contains(where: { $0.name == "preview" }) else {
            return nil
        }

        components.queryItems = queryItems + [URLQueryItem(name: "preview", value: "true")]
        return components.url
    }

    private static func signedOutWordPressPostQueryURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              postID(fromWordPressPostQueryItems: components.queryItems ?? []) != nil else {
            return nil
        }

        let publicQueryItems = (components.queryItems ?? []).filter { item in
            !sensitivePreviewQueryItemNames.contains(item.name.lowercased())
        }
        components.queryItems = publicQueryItems.isEmpty ? nil : publicQueryItems
        return components.url
    }

    private static func postID(fromAdminPostURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return postID(fromAdminPostComponents: components)
    }

    private static func postID(fromAdminPostComponents components: URLComponents) -> String? {
        guard components.path.lowercased() == "/wp-admin/post.php" else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "post" })?.value.flatMap(normalizedPostID)
    }

    private static func postID(fromWordPressPostQueryURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return postID(fromWordPressPostQueryItems: components.queryItems ?? [])
    }

    private static func postID(fromWordPressPostQueryItems queryItems: [URLQueryItem]) -> String? {
        queryItems
            .first { ["p", "page_id", "attachment_id"].contains($0.name) }?
            .value
            .flatMap(normalizedPostID)
    }

    private static func normalizedPostID(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue.allSatisfy(\.isNumber) else {
            return nil
        }
        return trimmedValue
    }

    private static func adminPostEditURL(for url: URL, postID: String) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var editComponents = URLComponents()
        editComponents.scheme = components.scheme
        editComponents.host = components.host
        editComponents.port = components.port
        editComponents.path = "/wp-admin/post.php"
        editComponents.queryItems = [
            URLQueryItem(name: "post", value: postID),
            URLQueryItem(name: "action", value: "edit")
        ]
        return editComponents.url
    }

    private static func hasPreviewQuery(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        return components.queryItems?.contains(where: { $0.name == "preview" }) == true
    }

    private static let sensitivePreviewQueryItemNames: Set<String> = [
        "preview",
        "frame-nonce",
        "nonce",
        "_wpnonce"
    ]

    private static func unmappedURL(for url: URL, unmappedURLString: String?) -> URL? {
        guard let unmappedURLString,
              let unmappedURL = URL(string: unmappedURLString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = unmappedURL.scheme
        components.host = unmappedURL.host
        components.port = unmappedURL.port
        return components.url
    }

    private static func addingFrameNonceIfNeeded(to url: URL, frameNonce: String?) -> URL? {
        guard let frameNonce,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "frame-nonce" }) else {
            return url
        }

        components.queryItems = queryItems + [URLQueryItem(name: "frame-nonce", value: frameNonce)]
        return components.url
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
            options: .regularExpression
        ) != nil
    }

    private static func ipv4Octets(from host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        let octets = parts.compactMap { part -> Int? in
            guard let value = Int(part), (0...255).contains(value) else {
                return nil
            }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    private static func isLocalOrPrivateIPv4(_ octets: [Int]) -> Bool {
        let first = octets[0]
        let second = octets[1]

        return first == 0
            || first == 10
            || first == 127
            || (first == 100 && (64...127).contains(second))
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 198 && (18...19).contains(second))
    }

    private static func isLocalOrPrivateIPv6(_ host: String) -> Bool {
        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return true
        }

        if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80") {
            return true
        }

        if host.hasPrefix("::ffff:") {
            let ipv4Host = String(host.dropFirst("::ffff:".count))
            if let octets = ipv4Octets(from: ipv4Host) {
                return isLocalOrPrivateIPv4(octets)
            }
        }

        return false
    }
}
