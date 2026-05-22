# WordPress Workspace PRD

Status: Living product and engineering guide
Last reviewed: May 22, 2026

## Summary

WordPress Workspace is a beta macOS menu bar app that turns a selected WordPress.com site into the working context for everyday Mac tasks. It gives users fast access to WordPress Agent, dictation, screenshot capture, image upload, selected-text transformation, and site switching without requiring them to rebuild their site context in a separate AI tool.

The broader goal is to make WordPress usable as a personal cloud: a place where notes, media, drafts, guidelines, site knowledge, and Agent work can live under the user's account and site permissions. Workspace is one native gateway into that cloud and should grow as an all-in-one utility suite that offers WordPress-backed alternatives to everyday Mac workflows where a site-aware, cloud-owned result is useful.

The Mac app should stay thin. WordPress.com owns authentication, site permissions, AI execution, Agent capabilities, media storage, and site-scoped guidelines. The app owns fast native entry points, local context capture, permissions, shortcuts, upload preparation, local launcher indexing, and a trustworthy bridge into the selected WordPress.com site.

## Goals

- Make a WordPress.com site feel like a workspace on the Mac, not only a place where finished work is published.
- Use WordPress as the user's personal cloud, with Workspace as one gateway for bringing Mac work into that cloud.
- Reduce context copy-paste by grounding Agent chat, dictation, screenshots, uploads, and rewrites in the selected site.
- Build toward a practical utility suite, not a single-purpose dictation or chat app.
- Keep configuration site-scoped and shareable through WordPress.com, especially guidelines and skills.
- Make first-run setup reliable: sign-in, default site selection, permissions, shortcuts, and a successful first useful action.
- Make repeated work fast by indexing trusted site and app actions locally for QuickLauncher.
- Preserve user trust by making site boundaries, local capture, uploads, and cloud processing explicit in product behavior and docs.
- Keep release operations understandable while signing, notarization, and distribution policy continue to mature.

## Non-Goals

- Do not add local AI provider setup, local API key entry for WordPress.com AI, model pickers, prompt editors, or spelling editors to the Mac app.
- Do not create a separate Workspace account system or subscription layer.
- Do not make Workspace a generic chatbot that starts from an empty conversation.
- Do not replace WordPress Studio or become a local WordPress development tool.
- Do not bypass WordPress.com account, site, role, or team permission boundaries.
- Do not imply the Agent knows a whole business unless that knowledge exists in the selected WordPress.com context.

## Product Principles

- Site first: the selected WordPress.com site is the workspace context. Changing sites changes the context.
- WordPress-native by default: use WordPress archetypes and plugin-provided capabilities when possible, including posts, media, terms, guidelines, artifacts, skills, site roles, and site permissions.
- Native when it matters: do not try to make all of WordPress native. Provide native bridges where the Mac adds leverage, especially media, screenshots, quick notes, dictation, selected text, shortcuts, and paste flows.
- Configuration belongs on WordPress.com: shared guidelines, skills, permissions, and AI behavior should be managed where teams can audit and reuse them.
- User actions should be inspectable: captures, uploads, and selected-text transformations should have clear initiation, failure, and completion states.
- Keep the app honest about beta scope: frequent changes are expected, but core trust boundaries should not drift silently.

## Users

- Site owner: runs a blog, business, store, newsletter, portfolio, or documentation site and wants faster drafting, uploading, and site-aware help.
- Editor or contributor: works inside an existing site's voice and permissions and needs help rewriting, dictating, or preparing content.
- Multi-site operator: manages several WordPress.com sites and needs each site to behave as a separate context.
- Team member with scoped access: should only receive context and capabilities allowed by the account and site permission model.
- Support or product builder: uses Workspace internally to inspect flows, test guidelines, and validate WordPress Agent behavior.

## Functional Requirements

### Account and Site Context

- Users sign in with WordPress.com OAuth through the native app.
- The app fetches WordPress.com sites available to the Agent and augments them with site metadata when possible.
- Users choose a default site for new chats, uploads, screenshots, and dictation.
- Users can switch sites inside WordPress Agent when work belongs elsewhere.
- The active site should never be guessed silently. The whole-app selected site persists until the user explicitly switches it, while site-bound apps or actions may deliberately move the current site as part of an explicit user handoff.
- Starred sites, all-sites browsing, remembered collapse state, and per-app site routing should make repeated workflows fast without hiding the active context boundary.

### QuickLauncher and Local Indexing

- Typing `@` in Quick Ask opens QuickLauncher when it is enabled.
- QuickLauncher can search local app commands, site switching, WordPress content, media, taxonomy terms, guidelines, artifacts, skills, and admin panels.
- The app stores launcher entities, remote cache rows, endpoint cursors, recent opens, and sync state in `Workspace.sqlite` under Application Support.
- Launcher indexing should be site-aware, support manual refresh and full reindex, and prefer incremental refreshes when safe.
- Launcher results may open a detached WordPress Agent preview for WordPress content or execute a local app command.

### WordPress Agent

- Users can open WordPress Agent from the menu bar or a global Quick Ask shortcut.
- Agent conversations are scoped by site and agent identifier.
- Conversation history should be explicit and predictable: show current cached/recent conversations first, refresh when the Agent window regains focus or the app relaunches, and use a visible "Load previous conversations" control for paging older history.
- Agent messages can include uploaded WordPress.com media.
- The app exposes front-end abilities, such as opening safe public URLs in the preview panel, without letting the Agent load localhost or private-network URLs.
- The preview panel should distinguish signed-out, authenticated preview, and editor modes when the selected site and URL allow it.
- Preview UI should display the requested user-facing URL, not private effective preview URLs, frame nonces, or other bootstrap details.
- Preview routing may vary across simple WordPress.com, Jetpack, and Atomic sites, so preview/auth handling should stay site-aware.
- Preview surfaces need a clear loading or preparation state while authentication cookies, preview nonces, and editor/preview mode URLs resolve.

### Dictation and Selected Text

- Users can dictate through hold or toggle shortcuts.
- Command mode can transform selected text when selected text is available from macOS Accessibility APIs.
- The transcription request sends audio, app context, selected text when relevant, client metadata, and the selected site to the WordPress.com transcription endpoint.
- The app posts multipart audio to `/wpcom/v2/sites/{site}/ai/transcription`; the endpoint should stay useful for app smoke tests and other authenticated clients, not only this UI.
- The selected site may provide a server-side `wp_guideline` skill with slug `transcribe`; the app discovers that guideline on launch and site switch, caches the result when available, and opens it from settings rather than hosting a local prompt editor.
- If the `transcribe` guideline does not exist, the WordPress.com transcription endpoint may create it as a WordPress Guideline skill on first use so every connected app can share the same spelling, cleanup, formatting, and style rules for that site.
- Saving transcription artifacts is a user-visible setting, should default off unless deliberately changed, should route to the selected site, and should create WordPress Guideline artifacts rather than app-private records.

### Screenshots and Image Uploads

- Users can capture a selected screenshot area through the app and then upload it to WordPress.com.
- Users can open, paste, or drag supported image files into the upload flow.
- Image import can resize images, convert HEIC/HEIF to JPEG, adjust JPEG quality, anonymize filenames, copy resulting links, and open an Agent chat.
- Uploads go to the selected site's WordPress.com media library through authenticated API calls.
- Screenshot and image upload should move toward a CleanShot-like sharing loop: capture or import, upload to WordPress.com media, get a shareable link back immediately, and copy or hand that link to Agent without extra ceremony.

### Permissions and Trust Boundaries

- The app asks for macOS permissions when they are needed: microphone for dictation, Accessibility for selected text and paste flows, and Screen Recording for screenshot capture.
- Local context collection should stay narrow: active app name, bundle identifier, window title, selected text when available, and explicitly captured screenshot or audio data.
- Cloud AI work happens through WordPress.com endpoints under the signed-in account and selected site.
- Local caches, `Workspace.sqlite`, shortcuts, site preferences, conversation metadata, and credentials must be treated as sensitive implementation details and documented carefully before public privacy copy is expanded.

### Release and Operations

- Development builds use `make` and produce `WP Workspace Dev.app` with bundle identifier `com.automattic.wpworkspace.dev`.
- Release packaging uses `Tools/manual-release.sh`, a clean working tree, a universal build, OAuth secret injection, signing, and zip creation.
- GitHub Actions release automation exists but is intentionally parked until signing, notarization, and release-channel policy are finalized.
- Creating the GitHub Release triggers the Buildkite production build. After the build completes, the release owner downloads the artifact from Buildkite and attaches it to the GitHub Release unless automation has been explicitly changed.
- Publishing a new release can surface the update badge in the app for existing users, so version, notes, and artifact readiness should be confirmed before the release becomes public.

## UX Requirements

- First launch should guide users through welcome, WordPress.com sign-in, default site choice, Quick Ask shortcut, image upload preview, microphone permission, Accessibility permission, dictation shortcuts, test transcription, launch at login, and ready state.
- The menu bar should provide fast access to Agent chat, Quick Ask, screenshot capture, image upload, settings, setup, status, and launcher indexing commands.
- Settings should group permissions, WordPress.com account/site settings, transcription, shortcuts, QuickLauncher indexing, Agent behavior, network routing, and diagnostics without turning the app into a local AI control panel.
- Settings controls should use plain labels and short explanatory text, especially for toggles that enable persistence, artifacts, indexing, debug behavior, or setup reruns.
- Error states should name the missing prerequisite and provide the next concrete action: sign in, choose a site, grant a macOS permission, refresh sites, retry upload, or inspect network settings.
- Multi-site flows should always make the active site legible before sending audio, text, media, or Agent messages.

## Signals and Observability

- Do not describe or add product telemetry as an existing capability. The app does not currently gather in-app metrics.
- The main external usage signal currently available is WordPress.com OAuth sign-in count.
- Use manual QA, endpoint smoke tests, release feedback, GitHub issues, and support reports to evaluate readiness until explicit analytics work is designed and approved.
- Before adding telemetry, define the user-visible purpose, privacy boundary, opt-in or disclosure model, retention, and whether the signal belongs in the Mac app or WordPress.com.

## Test Scenarios

- Fresh install: sign in, select a site, grant permissions, test transcription, and open WordPress Agent.
- Dictation: hold shortcut, toggle shortcut, command mode with selected text, and no selected text fallback.
- Site routing: default site, switched Agent site, Starred section, All Sites section, persisted collapse state, and per-app site override.
- Agent history: cached history on launch, refresh on focus return, and explicit "Load previous conversations" pagination.
- Uploads: single PNG, multiple JPEGs, HEIC conversion, filename anonymization, copy links, and open chat.
- Screenshots: permission granted, permission denied, canceled capture, and successful upload.
- Agent preview: public URL, same-site URL, authenticated preview, editor URL, preview/edit mode switching, internal navigation updates, requested URL display, private nonce redaction, loading state, simple site, Jetpack site, Atomic site, and rejected local/private URL.
- QuickLauncher: `@` activation, empty search, command execution, site switch, content preview, incremental refresh, full reindex, disabled state, and corrupt or missing `Workspace.sqlite`.
- Auth failures: expired token, revoked site access, missing selected site, and canceled sign-in.
- Network failures: offline, WordPress.com API error, upload timeout, and proxy bypass setting.
- Release smoke: `make`, SQLite linking, OAuth secret injection, package verification, and no-dependency transcription endpoint smoke script.

## Source Alignment Notes

These notes are dated because public marketing pages and Codex docs can change.

- As of May 21, 2026, the WordPress.com Workspace page positions the product as a beta Mac app included with WordPress.com plans, centered on site context, Agent access, dictation, screenshots, image upload, selected-text transformation, multiple sites, shared skills/guidelines, and WordPress.com permissions: https://wordpress.com/workspace/
- The May 19, 2026 launch post says Workspace brings together Agent access, voice-to-text, screenshot capture, and media upload on the Mac, and that each site can be its own workspace: https://wordpress.com/blog/2026/05/19/wordpress-workspace/
- The launch post lists system requirements as macOS 11 Big Sur or later, compatible with Intel and Apple Silicon. The current repo `Info.plist` declares `LSMinimumSystemVersion` as `13.0`; future release work should resolve whether public copy or app metadata is authoritative.
- Codex repository skills are stored under `.agents/skills`; this repo uses that location for project-specific agent workflows: https://developers.openai.com/codex/skills
- As of the May 21, 2026 rebase onto `origin/main`, this repo includes `Workspace.sqlite` and QuickLauncher indexing for app commands, sites, WordPress content, guidelines, artifacts, skills, admin panels, and local remote-cache rows.

## Current Repo Anchors

- Product overview and release basics: `README.md`.
- App entry and window coordination: `Sources/App.swift` and `Sources/AppDelegate.swift`.
- Central state, WordPress.com routing, dictation, Agent, and shortcuts: `Sources/AppState.swift`.
- WordPress.com API, OAuth, Agent, transcription, guidelines, media upload, and preview cookies: `Sources/WPCOMClient.swift`.
- QuickLauncher entities, SQLite persistence, remote cache rows, recent opens, and indexing stats: `Sources/QuickLauncherIndex.swift`.
- Main user surfaces: `Sources/SetupView.swift`, `Sources/MenuBarView.swift`, `Sources/SettingsView.swift`, and `Sources/WordPressAgentWindowView.swift`.
- Media and screenshots: `Sources/ImageImportView.swift`, `Sources/ImageImportProcessor.swift`, and screenshot handling in `Sources/AppDelegate.swift`.
- Context capture and selected text: `Sources/AppContextService.swift`.
- Build and release: `Makefile`, `Tools/manual-release.sh`, `Tools/notarize.sh`, `.github/workflows/release.yml`, and `.buildkite/pipeline.yml`.

## Defaults for Future Development

- Prefer improving the site-aware workflow over adding generic AI controls.
- Keep app UI copy aligned with WordPress.com positioning unless the product direction intentionally changes.
- Treat WordPress Agent as a core pillar, not a secondary add-on.
- Treat QuickLauncher as a current native workspace surface. Treat optional features such as ElevenLabs speech, network sandbox routing, draft focus, sticky notes, and writing escape as advanced or emerging surfaces unless public positioning changes.
- When adding a feature, define which site it acts on, which permissions it needs, what leaves the Mac, and what WordPress.com endpoint or site resource owns the result.
