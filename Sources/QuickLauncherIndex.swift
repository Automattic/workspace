import Foundation
import SQLite3

enum QuickLauncherEntityKind: String, Codable, CaseIterable {
    case site
    case adminPanel = "admin_panel"
    case post
    case page
    case customPostType = "custom_post_type"
    case media
    case taxonomyTerm = "taxonomy_term"
    case guideline
    case artifact
    case skill
    case appCommand = "app_command"

    var displayName: String {
        switch self {
        case .site: return "Site"
        case .adminPanel: return "Admin"
        case .post: return "Post"
        case .page: return "Page"
        case .customPostType: return "Content"
        case .media: return "Media"
        case .taxonomyTerm: return "Term"
        case .guideline: return "Guideline"
        case .artifact: return "Artifact"
        case .skill: return "Skill"
        case .appCommand: return "Command"
        }
    }

    var systemImageName: String {
        switch self {
        case .site: return "globe"
        case .adminPanel: return "rectangle.grid.2x2"
        case .post: return "doc.text"
        case .page: return "doc.richtext"
        case .customPostType: return "square.stack.3d.up"
        case .media: return "photo"
        case .taxonomyTerm: return "tag"
        case .guideline: return "text.book.closed"
        case .artifact: return "archivebox"
        case .skill: return "sparkles"
        case .appCommand: return "command"
        }
    }
}

struct QuickLauncherEntity: Identifiable, Codable, Equatable {
    let id: String
    let siteID: Int?
    let kind: QuickLauncherEntityKind
    let remoteID: String?
    let title: String
    let subtitle: String?
    let slug: String?
    let status: String?
    let type: String?
    let restRoute: String?
    let endpoint: String?
    let adminPath: String?
    let publicURLString: String?
    let editURLString: String?
    let modifiedGMT: String?
    let parentIDs: [String]
    let searchableText: String

    var openURL: URL? {
        [editURLString, publicURLString]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap(URL.init(string:))
    }

    var displaySubtitle: String {
        let parts = [kind.displayName, status, subtitle, slug]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        return parts.joined(separator: " - ")
    }

    static func makeID(
        siteID: Int?,
        kind: QuickLauncherEntityKind,
        route: String? = nil,
        remoteID: String? = nil,
        slug: String? = nil
    ) -> String {
        [
            kind.rawValue,
            siteID.map(String.init) ?? "global",
            route ?? "",
            remoteID ?? slug ?? UUID().uuidString
        ].joined(separator: ":")
    }
}

struct QuickLauncherSyncError: Equatable {
    let siteID: Int
    let scope: String
    let message: String
}

struct QuickLauncherFetchResult {
    let entities: [QuickLauncherEntity]
    let errors: [QuickLauncherSyncError]
}

struct QuickLauncherIndexStats: Equatable {
    let siteID: Int?
    let totalEntityCount: Int
    let countsByKind: [QuickLauncherEntityKind: Int]
    let remoteCacheEntryCount: Int
    let endpointCursorCount: Int
    let lastSyncedAt: Date?
    let lastFullSyncedAt: Date?
    let lastError: String?
    let databasePath: String
    let databaseSizeBytes: Int64

    static let empty = QuickLauncherIndexStats(
        siteID: nil,
        totalEntityCount: 0,
        countsByKind: [:],
        remoteCacheEntryCount: 0,
        endpointCursorCount: 0,
        lastSyncedAt: nil,
        lastFullSyncedAt: nil,
        lastError: nil,
        databasePath: QuickLauncherIndexStore.databaseURL.path,
        databaseSizeBytes: 0
    )
}

enum QuickLauncherMenuCommandID: String, CaseIterable {
    case downloadUpdate = "menu.download_update"
    case wordpressComSettings = "menu.wordpress_com_settings"
    case accessibilitySettings = "menu.accessibility_settings"
    case quickAsk = "menu.quick_ask"
    case addSticky = "menu.stickies.add"
    case showStickies = "menu.stickies.show"
    case hideStickies = "menu.stickies.hide"
    case captureScreenshot = "menu.capture_screenshot"
    case uploadImages = "menu.upload_images"
    case useDefaultSiteForCurrentApp = "menu.app.use_default_site"
    case pinDefaultSiteToCurrentApp = "menu.app.pin_default_site"
    case removeCurrentAppSiteOverride = "menu.app.remove_site_override"
    case manageSitesInSettings = "menu.app.manage_sites"
    case toggleDictation = "menu.toggle_dictation"
    case copyReply = "menu.copy_reply"
    case openAgent = "menu.open_agent"
    case copyAgain = "menu.copy_again"
    case microphoneSystemDefault = "menu.microphone.default"
    case draftFocus = "menu.draft_focus"
    case settings = "menu.settings"
    case refreshSites = "menu.refresh_sites"
    case refreshLauncherIndex = "menu.refresh_launcher_index"
    case reindexLauncher = "menu.reindex_launcher"
    case indexingSettings = "menu.indexing_settings"
    case quit = "menu.quit"

    static let microphoneDevicePrefix = "menu.microphone.device:"
}

struct QuickLauncherMenuCommand: Equatable {
    let id: String
    let title: String
    let menuPath: String
    let aliases: [String]

    init(
        id: QuickLauncherMenuCommandID,
        title: String,
        menuPath: String,
        aliases: [String] = []
    ) {
        self.init(id: id.rawValue, title: title, menuPath: menuPath, aliases: aliases)
    }

    init(
        id: String,
        title: String,
        menuPath: String,
        aliases: [String] = []
    ) {
        self.id = id
        self.title = title
        self.menuPath = menuPath
        self.aliases = aliases
    }

    var entity: QuickLauncherEntity {
        let searchableText = ([title, menuPath, "command", "menu", "menubar"] + aliases)
            .joined(separator: " ")
        return QuickLauncherEntity(
            id: QuickLauncherEntity.makeID(
                siteID: nil,
                kind: .appCommand,
                route: "menu",
                remoteID: id
            ),
            siteID: nil,
            kind: .appCommand,
            remoteID: id,
            title: title,
            subtitle: menuPath,
            slug: nil,
            status: nil,
            type: "menu_command",
            restRoute: nil,
            endpoint: nil,
            adminPath: nil,
            publicURLString: nil,
            editURLString: nil,
            modifiedGMT: nil,
            parentIDs: [],
            searchableText: searchableText
        )
    }
}

final class QuickLauncherIndexStore: @unchecked Sendable {
    private struct IndexedEntity {
        let entity: QuickLauncherEntity
        let openCount: Int
        let openedAt: TimeInterval
    }

    private let queue = DispatchQueue(label: "com.automattic.wpworkspace.quicklauncher.index")
    private var database: OpaquePointer?
    private var hasFTS = false

    init() {
        queue.sync {
            openDatabase()
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func replaceSites(_ sites: [WPCOMSite]) {
        let entities = sites.map(Self.entity(for:))
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            deletePrivacyExcludedEntities()
            deleteEntities(whereClause: "kind = ?", bindings: [.text(QuickLauncherEntityKind.site.rawValue)])
            for entity in entities {
                insert(entity)
            }
            commitTransaction()
        }
    }

    func cachedWordPressComSites() -> [WPCOMSite]? {
        queue.sync {
            guard let sites = cachedRemoteJSON(
                [WPCOMSite].self,
                scope: Self.globalCacheScope,
                siteID: Self.globalCacheSiteID,
                namespace: Self.wpcomCacheNamespace,
                key: Self.wpcomSitesCacheKey
            ) else {
                return nil
            }

            var seenSiteIDs = Set<Int>()
            return sites.filter { site in
                site.id > 0 && seenSiteIDs.insert(site.id).inserted
            }
        }
    }

    func replaceCachedWordPressComSites(_ sites: [WPCOMSite]) {
        queue.sync {
            guard database != nil else { return }
            if sites.isEmpty {
                deleteRemoteCache(
                    scope: Self.globalCacheScope,
                    siteID: Self.globalCacheSiteID,
                    namespace: Self.wpcomCacheNamespace,
                    key: Self.wpcomSitesCacheKey
                )
            } else {
                upsertRemoteCacheJSON(
                    sites,
                    scope: Self.globalCacheScope,
                    siteID: Self.globalCacheSiteID,
                    namespace: Self.wpcomCacheNamespace,
                    key: Self.wpcomSitesCacheKey,
                    sourceURL: "https://public-api.wordpress.com/wpcom/v2/ai/agent/dolly/sites"
                )
            }
        }
    }

    func cachedWordPressComUser() -> WPCOMUser? {
        queue.sync {
            cachedRemoteJSON(
                WPCOMUser.self,
                scope: Self.globalCacheScope,
                siteID: Self.globalCacheSiteID,
                namespace: Self.wpcomCacheNamespace,
                key: Self.wpcomUserCacheKey
            )
        }
    }

    func replaceCachedWordPressComUser(_ user: WPCOMUser?) {
        queue.sync {
            guard database != nil else { return }
            guard let user else {
                deleteRemoteCache(
                    scope: Self.globalCacheScope,
                    siteID: Self.globalCacheSiteID,
                    namespace: Self.wpcomCacheNamespace,
                    key: Self.wpcomUserCacheKey
                )
                return
            }

            upsertRemoteCacheJSON(
                user,
                scope: Self.globalCacheScope,
                siteID: Self.globalCacheSiteID,
                namespace: Self.wpcomCacheNamespace,
                key: Self.wpcomUserCacheKey,
                sourceURL: "https://public-api.wordpress.com/rest/v1.1/me"
            )
        }
    }

    func replaceSiteContent(siteID: Int, entities: [QuickLauncherEntity], errors: [QuickLauncherSyncError]) {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            deletePrivacyExcludedEntities()
            deleteEntities(
                whereClause: "site_id = ? AND kind != ?",
                bindings: [.int(siteID), .text(QuickLauncherEntityKind.site.rawValue)]
            )
            for entity in entities where entity.kind != .site {
                insert(entity)
            }
            recordSyncState(siteID: siteID, scope: "site", errorMessage: errors.first?.message)
            recordSyncState(siteID: siteID, scope: "site-full", errorMessage: errors.first?.message)
            for error in errors {
                recordSyncState(siteID: error.siteID, scope: error.scope, errorMessage: error.message)
            }
            commitTransaction()
        }
    }

    func mergeSiteContent(siteID: Int, entities: [QuickLauncherEntity], errors: [QuickLauncherSyncError]) {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            deletePrivacyExcludedEntities()
            for entity in entities where entity.kind != .site {
                insert(entity)
            }
            recordSyncState(siteID: siteID, scope: "site", errorMessage: errors.first?.message)
            for error in errors {
                recordSyncState(siteID: error.siteID, scope: error.scope, errorMessage: error.message)
            }
            commitTransaction()
        }
    }

    func removePrivacyExcludedEntities() {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            deletePrivacyExcludedEntities()
            commitTransaction()
        }
    }

    func upsertEntities(_ entities: [QuickLauncherEntity]) {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            for entity in entities {
                insert(entity)
            }
            commitTransaction()
        }
    }

    func replaceAppCommands(_ entities: [QuickLauncherEntity]) {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            deleteEntities(whereClause: "kind = ?", bindings: [.text(QuickLauncherEntityKind.appCommand.rawValue)])
            for entity in entities where entity.kind == .appCommand {
                insert(entity)
            }
            commitTransaction()
        }
    }

    func search(query: String, activeSiteID: Int?, limit: Int = 50) -> [QuickLauncherEntity] {
        queue.sync {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = trimmedQuery.isEmpty
                ? scopedEntities(activeSiteID: activeSiteID, limit: 500)
                : searchEntities(query: trimmedQuery, activeSiteID: activeSiteID, limit: 500)

            return candidates
                .sorted {
                    rank($0, query: trimmedQuery, activeSiteID: activeSiteID)
                    > rank($1, query: trimmedQuery, activeSiteID: activeSiteID)
                }
                .prefix(limit)
                .map(\.entity)
        }
    }

    func recordOpen(entityID: String) {
        queue.sync {
            guard let database else { return }
            let sql = """
            INSERT INTO recent_opens(entity_id, opened_at, open_count)
            VALUES(?, ?, 1)
            ON CONFLICT(entity_id) DO UPDATE SET
                opened_at = excluded.opened_at,
                open_count = recent_opens.open_count + 1
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            bind(.text(entityID), to: statement, index: 1)
            bind(.double(Date().timeIntervalSince1970), to: statement, index: 2)
            sqlite3_step(statement)
        }
    }

    func isSiteFresh(siteID: Int, maxAge: TimeInterval, scope: String = "site") -> Bool {
        queue.sync {
            guard let database else { return false }
            let sql = "SELECT last_synced_at FROM sync_state WHERE site_id = ? AND scope = ? LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(statement) }
            bind(.int(siteID), to: statement, index: 1)
            bind(.text(scope), to: statement, index: 2)
            guard sqlite3_step(statement) == SQLITE_ROW else { return false }
            let lastSyncedAt = sqlite3_column_double(statement, 0)
            return Date().timeIntervalSince1970 - lastSyncedAt < maxAge
        }
    }

    func latestModifiedByEndpoint(siteID: Int) -> [String: String] {
        queue.sync {
            guard let database else { return [:] }
            let sql = """
            SELECT endpoint, MAX(modified_gmt)
            FROM entities
            WHERE site_id = ?
              AND endpoint IS NOT NULL
              AND modified_gmt IS NOT NULL
              AND modified_gmt != ''
            GROUP BY endpoint
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
            defer { sqlite3_finalize(statement) }
            bind(.int(siteID), to: statement, index: 1)

            var values: [String: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let endpoint = textColumn(statement, 0),
                      let modifiedGMT = textColumn(statement, 1) else {
                    continue
                }
                values[endpoint] = modifiedGMT
            }
            return values
        }
    }

    func indexedSiteIDs() -> Set<Int> {
        queue.sync {
            guard let database else { return [] }
            let sql = "SELECT DISTINCT site_id FROM sync_state WHERE scope = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(.text("site"), to: statement, index: 1)

            var siteIDs = Set<Int>()
            while sqlite3_step(statement) == SQLITE_ROW {
                siteIDs.insert(Int(sqlite3_column_int64(statement, 0)))
            }
            return siteIDs
        }
    }

    func stats(siteID: Int?) -> QuickLauncherIndexStats {
        queue.sync {
            guard database != nil else { return .empty }
            let countsByKind = entityCounts(siteID: siteID)
            let totalEntityCount = countsByKind.values.reduce(0, +)
            return QuickLauncherIndexStats(
                siteID: siteID,
                totalEntityCount: totalEntityCount,
                countsByKind: countsByKind,
                remoteCacheEntryCount: remoteCacheEntryCount(siteID: siteID),
                endpointCursorCount: endpointCursorCount(siteID: siteID),
                lastSyncedAt: syncState(siteID: siteID, scope: "site").lastSyncedAt,
                lastFullSyncedAt: syncState(siteID: siteID, scope: "site-full").lastSyncedAt,
                lastError: syncState(siteID: siteID, scope: "site").lastError,
                databasePath: Self.databaseURL.path,
                databaseSizeBytes: Self.databaseSizeBytes()
            )
        }
    }

    func clearAll() {
        queue.sync {
            guard database != nil else { return }
            beginTransaction()
            execute("DELETE FROM entity_fts")
            execute("DELETE FROM entities")
            execute("DELETE FROM sync_state")
            execute("DELETE FROM recent_opens")
            execute("DELETE FROM remote_cache")
            commitTransaction()
        }
    }

    private func openDatabase() {
        let url = Self.databaseURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &openedDatabase, flags, nil) == SQLITE_OK else {
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            database = nil
            return
        }

        database = openedDatabase
        execute("PRAGMA foreign_keys = ON")
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        createSchema()
    }

    static var databaseURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Workspace.sqlite")
    }

    private static var applicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "WP Workspace"
        return appSupport.appendingPathComponent(appName, isDirectory: true)
    }

    private func createSchema() {
        execute("""
        CREATE TABLE IF NOT EXISTS entities (
            id TEXT PRIMARY KEY,
            site_id INTEGER,
            kind TEXT NOT NULL,
            remote_id TEXT,
            title TEXT NOT NULL,
            subtitle TEXT,
            slug TEXT,
            status TEXT,
            type TEXT,
            rest_route TEXT,
            endpoint TEXT,
            admin_path TEXT,
            public_url TEXT,
            edit_url TEXT,
            modified_gmt TEXT,
            parent_ids TEXT,
            searchable_text TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS entities_site_kind_idx ON entities(site_id, kind)")
        execute("CREATE INDEX IF NOT EXISTS entities_kind_idx ON entities(kind)")
        hasFTS = execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS entity_fts
        USING fts5(id UNINDEXED, searchable_text, title, slug, kind, type, tokenize = 'unicode61')
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS sync_state (
            site_id INTEGER NOT NULL,
            scope TEXT NOT NULL,
            last_synced_at REAL NOT NULL,
            last_error TEXT,
            PRIMARY KEY(site_id, scope)
        )
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS recent_opens (
            entity_id TEXT PRIMARY KEY,
            opened_at REAL NOT NULL,
            open_count INTEGER NOT NULL DEFAULT 1
        )
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS remote_cache (
            scope TEXT NOT NULL,
            site_id INTEGER NOT NULL DEFAULT 0,
            namespace TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            content_type TEXT NOT NULL DEFAULT 'application/json',
            payload TEXT NOT NULL,
            fetched_at REAL NOT NULL,
            expires_at REAL,
            last_modified TEXT,
            etag TEXT,
            source_url TEXT,
            privacy_level TEXT NOT NULL DEFAULT 'private',
            PRIMARY KEY(scope, site_id, namespace, cache_key)
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS remote_cache_site_idx ON remote_cache(site_id, namespace)")
        execute("CREATE INDEX IF NOT EXISTS remote_cache_fetched_idx ON remote_cache(fetched_at)")
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let database else { return false }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        return result == SQLITE_OK
    }

    private func beginTransaction() {
        execute("BEGIN IMMEDIATE TRANSACTION")
    }

    private func commitTransaction() {
        execute("COMMIT TRANSACTION")
    }

    private func deleteEntities(whereClause: String, bindings: [SQLiteBinding]) {
        guard database != nil else { return }
        if hasFTS {
            let ftsSQL = "DELETE FROM entity_fts WHERE id IN (SELECT id FROM entities WHERE \(whereClause))"
            executePrepared(ftsSQL, bindings: bindings)
        }
        let entitySQL = "DELETE FROM entities WHERE \(whereClause)"
        executePrepared(entitySQL, bindings: bindings)
    }

    private func deletePrivacyExcludedEntities() {
        let exactValues = Self.privacyExcludedEntityIdentifiers
        let placeholders = Array(repeating: "?", count: exactValues.count).joined(separator: ", ")
        let whereClause = """
        kind != ?
        AND (
            lower(COALESCE(type, '')) GLOB ?
            OR lower(COALESCE(slug, '')) GLOB ?
            OR lower(COALESCE(remote_id, '')) GLOB ?
            OR lower(COALESCE(endpoint, '')) GLOB ?
            OR lower(COALESCE(rest_route, '')) GLOB ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(type, '')) IN (\(placeholders))
            OR lower(COALESCE(slug, '')) IN (\(placeholders))
            OR lower(COALESCE(endpoint, '')) IN (\(placeholders))
            OR lower(COALESCE(rest_route, '')) IN (\(placeholders))
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
            OR lower(COALESCE(admin_path, '')) LIKE ?
        )
        """
        let exactBindings = exactValues.map(SQLiteBinding.text)
        let bindings: [SQLiteBinding] =
            [
                .text(QuickLauncherEntityKind.appCommand.rawValue),
                .text("jp_pay_*"),
                .text("jp_pay_*"),
                .text("post-type-jp_pay_*"),
                .text("wp/v2/jp_pay_*"),
                .text("/wp/v2/jp_pay_*"),
                .text("%post_type=jp_pay_%")
            ]
            + exactBindings
            + exactBindings
            + exactBindings.map { binding in
                if case .text(let value) = binding {
                    return .text("wp/v2/\(value)")
                }
                return binding
            }
            + exactBindings.map { binding in
                if case .text(let value) = binding {
                    return .text("/wp/v2/\(value)")
                }
                return binding
            }
            + [
                .text("%post_type=feedback%"),
                .text("%post_type=form_response%"),
                .text("%post_type=form_responses%"),
                .text("%post_type=form-response%"),
                .text("%post_type=form-responses%"),
                .text("%post_type=wpforms_entries%")
            ]
        deleteEntities(whereClause: whereClause, bindings: bindings)
    }

    private func executePrepared(_ sql: String, bindings: [SQLiteBinding]) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        for (index, binding) in bindings.enumerated() {
            bind(binding, to: statement, index: Int32(index + 1))
        }
        sqlite3_step(statement)
    }

    private func upsertRemoteCacheJSON<T: Encodable>(
        _ value: T,
        scope: String,
        siteID: Int,
        namespace: String,
        key: String,
        sourceURL: String?,
        privacyLevel: String = "private"
    ) {
        guard let data = try? JSONEncoder().encode(value),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }

        let sql = """
        INSERT OR REPLACE INTO remote_cache(
            scope, site_id, namespace, cache_key, content_type, payload, fetched_at,
            expires_at, last_modified, etag, source_url, privacy_level
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        executePrepared(sql, bindings: [
            .text(scope),
            .int(siteID),
            .text(namespace),
            .text(key),
            .text("application/json"),
            .text(payload),
            .double(Date().timeIntervalSince1970),
            .null,
            .null,
            .null,
            sourceURL.map(SQLiteBinding.text) ?? .null,
            .text(privacyLevel)
        ])
    }

    private func cachedRemoteJSON<T: Decodable>(
        _ type: T.Type,
        scope: String,
        siteID: Int,
        namespace: String,
        key: String
    ) -> T? {
        guard let database else { return nil }
        let sql = """
        SELECT payload
        FROM remote_cache
        WHERE scope = ?
          AND site_id = ?
          AND namespace = ?
          AND cache_key = ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(.text(scope), to: statement, index: 1)
        bind(.int(siteID), to: statement, index: 2)
        bind(.text(namespace), to: statement, index: 3)
        bind(.text(key), to: statement, index: 4)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = textColumn(statement, 0),
              let data = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func deleteRemoteCache(scope: String, siteID: Int, namespace: String, key: String) {
        executePrepared(
            """
            DELETE FROM remote_cache
            WHERE scope = ?
              AND site_id = ?
              AND namespace = ?
              AND cache_key = ?
            """,
            bindings: [
                .text(scope),
                .int(siteID),
                .text(namespace),
                .text(key)
            ]
        )
    }

    private func entityCounts(siteID: Int?) -> [QuickLauncherEntityKind: Int] {
        guard let database else { return [:] }
        let filter = siteID == nil ? "" : "WHERE site_id = ?"
        let sql = "SELECT kind, COUNT(*) FROM entities \(filter) GROUP BY kind"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        if let siteID {
            bind(.int(siteID), to: statement, index: 1)
        }

        var counts: [QuickLauncherEntityKind: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawKind = textColumn(statement, 0),
                  let kind = QuickLauncherEntityKind(rawValue: rawKind) else {
                continue
            }
            counts[kind] = Int(sqlite3_column_int64(statement, 1))
        }
        return counts
    }

    private func remoteCacheEntryCount(siteID: Int?) -> Int {
        guard let database else { return 0 }
        let sql: String
        let bindings: [SQLiteBinding]
        if let siteID {
            sql = "SELECT COUNT(*) FROM remote_cache WHERE site_id IN (?, ?)"
            bindings = [.int(Self.globalCacheSiteID), .int(siteID)]
        } else {
            sql = "SELECT COUNT(*) FROM remote_cache"
            bindings = []
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        for (index, binding) in bindings.enumerated() {
            bind(binding, to: statement, index: Int32(index + 1))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func endpointCursorCount(siteID: Int?) -> Int {
        guard let database else { return 0 }
        let filter = siteID == nil ? "" : "AND site_id = ?"
        let sql = """
        SELECT COUNT(DISTINCT endpoint)
        FROM entities
        WHERE endpoint IS NOT NULL
          AND modified_gmt IS NOT NULL
          AND modified_gmt != ''
          \(filter)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        if let siteID {
            bind(.int(siteID), to: statement, index: 1)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func syncState(siteID: Int?, scope: String) -> (lastSyncedAt: Date?, lastError: String?) {
        guard let database,
              let siteID else {
            return (nil, nil)
        }
        let sql = "SELECT last_synced_at, last_error FROM sync_state WHERE site_id = ? AND scope = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_finalize(statement) }
        bind(.int(siteID), to: statement, index: 1)
        bind(.text(scope), to: statement, index: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { return (nil, nil) }

        let timestamp = sqlite3_column_double(statement, 0)
        let lastSyncedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        return (lastSyncedAt, textColumn(statement, 1))
    }

    private func insert(_ entity: QuickLauncherEntity) {
        guard let database else { return }
        let sql = """
        INSERT OR REPLACE INTO entities(
            id, site_id, kind, remote_id, title, subtitle, slug, status, type,
            rest_route, endpoint, admin_path, public_url, edit_url, modified_gmt,
            parent_ids, searchable_text, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        let bindings: [SQLiteBinding] = [
            .text(entity.id),
            entity.siteID.map(SQLiteBinding.int) ?? .null,
            .text(entity.kind.rawValue),
            entity.remoteID.map(SQLiteBinding.text) ?? .null,
            .text(entity.title),
            entity.subtitle.map(SQLiteBinding.text) ?? .null,
            entity.slug.map(SQLiteBinding.text) ?? .null,
            entity.status.map(SQLiteBinding.text) ?? .null,
            entity.type.map(SQLiteBinding.text) ?? .null,
            entity.restRoute.map(SQLiteBinding.text) ?? .null,
            entity.endpoint.map(SQLiteBinding.text) ?? .null,
            entity.adminPath.map(SQLiteBinding.text) ?? .null,
            entity.publicURLString.map(SQLiteBinding.text) ?? .null,
            entity.editURLString.map(SQLiteBinding.text) ?? .null,
            entity.modifiedGMT.map(SQLiteBinding.text) ?? .null,
            .text(entity.parentIDs.joined(separator: ",")),
            .text(entity.searchableText),
            .double(Date().timeIntervalSince1970)
        ]
        for (index, binding) in bindings.enumerated() {
            bind(binding, to: statement, index: Int32(index + 1))
        }
        sqlite3_step(statement)

        guard hasFTS else { return }
        executePrepared("DELETE FROM entity_fts WHERE id = ?", bindings: [.text(entity.id)])
        let ftsSQL = "INSERT INTO entity_fts(id, searchable_text, title, slug, kind, type) VALUES (?, ?, ?, ?, ?, ?)"
        executePrepared(ftsSQL, bindings: [
            .text(entity.id),
            .text(entity.searchableText),
            .text(entity.title),
            .text(entity.slug ?? ""),
            .text(entity.kind.rawValue),
            .text(entity.type ?? "")
        ])
    }

    private func recordSyncState(siteID: Int, scope: String, errorMessage: String?) {
        guard let database else { return }
        let sql = """
        INSERT INTO sync_state(site_id, scope, last_synced_at, last_error)
        VALUES(?, ?, ?, ?)
        ON CONFLICT(site_id, scope) DO UPDATE SET
            last_synced_at = excluded.last_synced_at,
            last_error = excluded.last_error
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(.int(siteID), to: statement, index: 1)
        bind(.text(scope), to: statement, index: 2)
        bind(.double(Date().timeIntervalSince1970), to: statement, index: 3)
        bind(errorMessage.map(SQLiteBinding.text) ?? .null, to: statement, index: 4)
        sqlite3_step(statement)
    }

    private func scopedEntities(activeSiteID: Int?, limit: Int) -> [IndexedEntity] {
        let sql = """
        SELECT e.id, e.site_id, e.kind, e.remote_id, e.title, e.subtitle, e.slug, e.status,
               e.type, e.rest_route, e.endpoint, e.admin_path, e.public_url, e.edit_url,
               e.modified_gmt, e.parent_ids, e.searchable_text,
               COALESCE(r.open_count, 0), COALESCE(r.opened_at, 0)
        FROM entities e
        LEFT JOIN recent_opens r ON r.entity_id = e.id
        WHERE (? IS NULL AND (e.kind = ? OR e.kind = ?))
           OR (? IS NOT NULL AND (e.site_id = ? OR e.kind = ?))
        LIMIT ?
        """
        return loadEntities(sql: sql, bindings: [
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            .text(QuickLauncherEntityKind.site.rawValue),
            .text(QuickLauncherEntityKind.appCommand.rawValue),
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            .text(QuickLauncherEntityKind.appCommand.rawValue),
            .int(limit)
        ])
    }

    private func searchEntities(query: String, activeSiteID: Int?, limit: Int) -> [IndexedEntity] {
        if hasFTS,
           let ftsQuery = Self.ftsQuery(from: query) {
            let sql = """
            SELECT e.id, e.site_id, e.kind, e.remote_id, e.title, e.subtitle, e.slug, e.status,
                   e.type, e.rest_route, e.endpoint, e.admin_path, e.public_url, e.edit_url,
                   e.modified_gmt, e.parent_ids, e.searchable_text,
                   COALESCE(r.open_count, 0), COALESCE(r.opened_at, 0)
            FROM entity_fts f
            JOIN entities e ON e.id = f.id
            LEFT JOIN recent_opens r ON r.entity_id = e.id
            WHERE entity_fts MATCH ?
              AND ((? IS NULL AND (e.kind = ? OR e.kind = ?))
                   OR (? IS NOT NULL AND (e.site_id = ? OR e.kind = ?)))
            LIMIT ?
            """
            let results = loadEntities(sql: sql, bindings: [
                .text(ftsQuery),
                activeSiteID.map(SQLiteBinding.int) ?? .null,
                .text(QuickLauncherEntityKind.site.rawValue),
                .text(QuickLauncherEntityKind.appCommand.rawValue),
                activeSiteID.map(SQLiteBinding.int) ?? .null,
                activeSiteID.map(SQLiteBinding.int) ?? .null,
                .text(QuickLauncherEntityKind.appCommand.rawValue),
                .int(limit)
            ])
            if !results.isEmpty {
                return results
            }
        }

        let likeQuery = "%\(query.lowercased())%"
        let sql = """
        SELECT e.id, e.site_id, e.kind, e.remote_id, e.title, e.subtitle, e.slug, e.status,
               e.type, e.rest_route, e.endpoint, e.admin_path, e.public_url, e.edit_url,
               e.modified_gmt, e.parent_ids, e.searchable_text,
               COALESCE(r.open_count, 0), COALESCE(r.opened_at, 0)
        FROM entities e
        LEFT JOIN recent_opens r ON r.entity_id = e.id
        WHERE (lower(e.searchable_text) LIKE ? OR lower(e.title) LIKE ? OR lower(COALESCE(e.slug, '')) LIKE ?)
          AND ((? IS NULL AND (e.kind = ? OR e.kind = ?))
               OR (? IS NOT NULL AND (e.site_id = ? OR e.kind = ?)))
        LIMIT ?
        """
        return loadEntities(sql: sql, bindings: [
            .text(likeQuery),
            .text(likeQuery),
            .text(likeQuery),
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            .text(QuickLauncherEntityKind.site.rawValue),
            .text(QuickLauncherEntityKind.appCommand.rawValue),
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            activeSiteID.map(SQLiteBinding.int) ?? .null,
            .text(QuickLauncherEntityKind.appCommand.rawValue),
            .int(limit)
        ])
    }

    private func loadEntities(sql: String, bindings: [SQLiteBinding]) -> [IndexedEntity] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, binding) in bindings.enumerated() {
            bind(binding, to: statement, index: Int32(index + 1))
        }

        var entities: [IndexedEntity] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entity = entity(from: statement) else { continue }
            let openCount = Int(sqlite3_column_int(statement, 17))
            let openedAt = sqlite3_column_double(statement, 18)
            entities.append(IndexedEntity(entity: entity, openCount: openCount, openedAt: openedAt))
        }
        return entities
    }

    private func entity(from statement: OpaquePointer?) -> QuickLauncherEntity? {
        guard let id = textColumn(statement, 0),
              let rawKind = textColumn(statement, 2),
              let kind = QuickLauncherEntityKind(rawValue: rawKind),
              let title = textColumn(statement, 4),
              let searchableText = textColumn(statement, 16) else {
            return nil
        }

        let siteID: Int?
        if sqlite3_column_type(statement, 1) == SQLITE_NULL {
            siteID = nil
        } else {
            siteID = Int(sqlite3_column_int(statement, 1))
        }

        let parentIDs = (textColumn(statement, 15) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }

        return QuickLauncherEntity(
            id: id,
            siteID: siteID,
            kind: kind,
            remoteID: textColumn(statement, 3),
            title: title,
            subtitle: textColumn(statement, 5),
            slug: textColumn(statement, 6),
            status: textColumn(statement, 7),
            type: textColumn(statement, 8),
            restRoute: textColumn(statement, 9),
            endpoint: textColumn(statement, 10),
            adminPath: textColumn(statement, 11),
            publicURLString: textColumn(statement, 12),
            editURLString: textColumn(statement, 13),
            modifiedGMT: textColumn(statement, 14),
            parentIDs: parentIDs,
            searchableText: searchableText
        )
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func bind(_ binding: SQLiteBinding, to statement: OpaquePointer?, index: Int32) {
        switch binding {
        case .null:
            sqlite3_bind_null(statement, index)
        case .int(let value):
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case .double(let value):
            sqlite3_bind_double(statement, index, value)
        case .text(let value):
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        }
    }

    private func rank(_ indexed: IndexedEntity, query: String, activeSiteID: Int?) -> Double {
        let entity = indexed.entity
        let normalizedQuery = Self.normalized(query)
        let normalizedTitle = Self.normalized(entity.title)
        let normalizedSlug = Self.normalized(entity.slug ?? "")
        let normalizedSearchableText = Self.normalized(entity.searchableText)
        let isCurrentSite = activeSiteID != nil && entity.siteID == activeSiteID

        var score = Self.launcherPriorityScore(for: entity.kind)
        if isCurrentSite, entity.kind != .site {
            score += 300
        }

        if !normalizedQuery.isEmpty {
            if normalizedTitle == normalizedQuery {
                score += 1_000
            } else if normalizedTitle.hasPrefix(normalizedQuery) {
                score += 700
            } else if normalizedTitle.contains(normalizedQuery) {
                score += 420
            }

            if normalizedSlug == normalizedQuery {
                score += 650
            } else if normalizedSlug.hasPrefix(normalizedQuery) {
                score += 460
            } else if normalizedSearchableText.contains(normalizedQuery) {
                score += 120
            }
        }

        score += min(Double(indexed.openCount) * 30, 210)
        if indexed.openedAt > 0 {
            let age = max(0, Date().timeIntervalSince1970 - indexed.openedAt)
            score += max(0, 140 - age / 86_400 * 10)
        }

        if let modified = entity.modifiedGMT,
           let date = Self.date(from: modified) {
            let age = max(0, Date().timeIntervalSince(date))
            score += max(0, 70 - age / 86_400 * 2)
        }

        return score
    }

    private static func launcherPriorityScore(for kind: QuickLauncherEntityKind) -> Double {
        switch kind {
        case .appCommand, .adminPanel:
            return 70_000
        case .site:
            return 60_000
        case .guideline, .skill, .artifact:
            return 50_000
        case .page:
            return 40_000
        case .post:
            return 30_000
        case .media:
            return 20_000
        case .customPostType, .taxonomyTerm:
            return 10_000
        }
    }

    private static func entity(for site: WPCOMSite) -> QuickLauncherEntity {
        let urlString = site.url ?? site.slug.map { "https://\($0)" }
        let searchableText = [
            site.displayName,
            site.slug,
            site.url,
            "\(site.id)",
            "site"
        ].compactMap { $0 }.joined(separator: " ")
        return QuickLauncherEntity(
            id: QuickLauncherEntity.makeID(siteID: site.id, kind: .site, remoteID: "\(site.id)"),
            siteID: site.id,
            kind: .site,
            remoteID: "\(site.id)",
            title: site.displayName,
            subtitle: siteDomainDisplayText(site),
            slug: site.slug,
            status: nil,
            type: "site",
            restRoute: nil,
            endpoint: nil,
            adminPath: nil,
            publicURLString: urlString,
            editURLString: nil,
            modifiedGMT: nil,
            parentIDs: [],
            searchableText: searchableText
        )
    }

    private static func siteDomainDisplayText(_ site: WPCOMSite) -> String {
        site.slug ?? site.url?.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "\(site.id)"
    }

    private static func ftsQuery(from query: String) -> String? {
        let tokens = normalized(query)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func databaseSizeBytes() -> Int64 {
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm"
        ]
        return paths.reduce(Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
                .int64Value ?? 0
            return total + size
        }
    }

    private static let privacyExcludedEntityIdentifiers = [
        "feedback",
        "feedbacks",
        "form_response",
        "form_responses",
        "form-response",
        "form-responses",
        "form_entry",
        "form_entries",
        "form-entry",
        "form-entries",
        "wpforms_entry",
        "wpforms_entries",
        "ninja_forms_submission",
        "ninja-forms-submission"
    ]

    private static let globalCacheScope = "global"
    private static let globalCacheSiteID = 0
    private static let wpcomCacheNamespace = "wpcom"
    private static let wpcomSitesCacheKey = "sites"
    private static let wpcomUserCacheKey = "current_user"
}

private enum SQLiteBinding {
    case null
    case int(Int)
    case double(Double)
    case text(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
