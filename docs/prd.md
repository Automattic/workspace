# WordPress Workspace PRD

Status: Living product and engineering guide
Last reviewed: May 21, 2026

## Summary

WordPress Workspace is a beta macOS menu bar app that turns a selected WordPress.com site into the working context for everyday Mac tasks. It gives users fast access to WordPress Agent, dictation, screenshot capture, image upload, selected-text transformation, and site switching without requiring them to rebuild their site context in a separate AI tool.

The Mac app should stay thin. WordPress.com owns authentication, site permissions, AI execution, Agent capabilities, media storage, and site-scoped guidelines. The app owns fast native entry points, local context capture, permissions, shortcuts, upload preparation, and a trustworthy bridge into the selected WordPress.com site.

## Goals

- Make a WordPress.com site feel like a workspace on the Mac, not only a place where finished work is published.
- Reduce context copy-paste by grounding Agent chat, dictation, screenshots, uploads, and rewrites in the selected site.
- Keep configuration site-scoped and shareable through WordPress.com, especially guidelines and skills.
- Make first-run setup reliable: sign-in, default site selection, permissions, shortcuts, and a successful first useful action.
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
- Native when it matters: use macOS shortcuts, menu bar access, drag and drop, screenshots, dictation, and paste flows where the browser would slow the user down.
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
- Starred sites and per-app site routing may improve repeated workflows, but the selected site remains the explicit context boundary.

### WordPress Agent

- Users can open WordPress Agent from the menu bar or a global Quick Ask shortcut.
- Agent conversations are scoped by site and agent identifier.
- Agent messages can include uploaded WordPress.com media.
- The app exposes front-end abilities, such as opening safe public URLs in the preview panel, without letting the Agent load localhost or private-network URLs.
- The preview panel should distinguish signed-out, authenticated preview, and editor modes when the selected site and URL allow it.

### Dictation and Selected Text

- Users can dictate through hold or toggle shortcuts.
- Command mode can transform selected text when selected text is available from macOS Accessibility APIs.
- The transcription request sends audio, app context, selected text when relevant, client metadata, and the selected site to the WordPress.com transcription endpoint.
- The selected site may provide a server-side `wp_guideline` skill with slug `transcribe`; the app discovers and opens that guideline rather than hosting a local prompt editor.
- Saving transcription artifacts is a user-visible setting and should route to the selected site.

### Screenshots and Image Uploads

- Users can capture a selected screenshot area through the app and then upload it to WordPress.com.
- Users can open, paste, or drag supported image files into the upload flow.
- Image import can resize images, convert HEIC/HEIF to JPEG, adjust JPEG quality, anonymize filenames, copy resulting links, and open an Agent chat.
- Uploads go to the selected site's WordPress.com media library through authenticated API calls.

### Permissions and Trust Boundaries

- The app asks for macOS permissions when they are needed: microphone for dictation, Accessibility for selected text and paste flows, and Screen Recording for screenshot capture.
- Local context collection should stay narrow: active app name, bundle identifier, window title, selected text when available, and explicitly captured screenshot or audio data.
- Cloud AI work happens through WordPress.com endpoints under the signed-in account and selected site.
- Local caches, shortcuts, site preferences, conversation metadata, and credentials must be treated as sensitive implementation details and documented carefully before public privacy copy is expanded.

### Release and Operations

- Development builds use `make` and produce `WP Workspace Dev.app` with bundle identifier `com.automattic.wpworkspace.dev`.
- Release packaging uses `Tools/manual-release.sh`, a clean working tree, a universal build, OAuth secret injection, signing, and zip creation.
- GitHub Actions release automation exists but is intentionally parked until signing, notarization, and release-channel policy are finalized.
- Buildkite can run build, signing, notarization, zip, and DMG packaging through the existing pipeline.

## UX Requirements

- First launch should guide users through welcome, WordPress.com sign-in, default site choice, Quick Ask shortcut, image upload preview, microphone permission, Accessibility permission, dictation shortcuts, test transcription, launch at login, and ready state.
- The menu bar should provide fast access to Agent chat, Quick Ask, screenshot capture, image upload, settings, setup, and status.
- Settings should group permissions, WordPress.com account/site settings, transcription, shortcuts, Agent behavior, network routing, and diagnostics without turning the app into a local AI control panel.
- Error states should name the missing prerequisite and provide the next concrete action: sign in, choose a site, grant a macOS permission, refresh sites, retry upload, or inspect network settings.
- Multi-site flows should always make the active site legible before sending audio, text, media, or Agent messages.

## Metrics

- Install to first successful sign-in.
- Sign-in success and cancellation rates.
- Default site selection success.
- Permission grant rates for microphone, Accessibility, and Screen Recording.
- Shortcut activation to recording start latency.
- Dictation completion and transcription failure rates.
- Screenshot capture and upload success rates.
- Image import completion and media upload failure rates.
- Agent message send success, response latency, and preview-open success.
- Crash-free sessions and update adoption.

## Test Scenarios

- Fresh install: sign in, select a site, grant permissions, test transcription, and open WordPress Agent.
- Dictation: hold shortcut, toggle shortcut, command mode with selected text, and no selected text fallback.
- Site routing: default site, switched Agent site, starred site ordering, and per-app site override.
- Uploads: single PNG, multiple JPEGs, HEIC conversion, filename anonymization, copy links, and open chat.
- Screenshots: permission granted, permission denied, canceled capture, and successful upload.
- Agent preview: public URL, same-site URL, authenticated preview, editor URL, and rejected local/private URL.
- Auth failures: expired token, revoked site access, missing selected site, and canceled sign-in.
- Network failures: offline, WordPress.com API error, upload timeout, and proxy bypass setting.
- Release smoke: `make`, OAuth secret injection, package verification, and transcription endpoint smoke script.

## Source Alignment Notes

These notes are dated because public marketing pages and Codex docs can change.

- As of May 21, 2026, the WordPress.com Workspace page positions the product as a beta Mac app included with WordPress.com plans, centered on site context, Agent access, dictation, screenshots, image upload, selected-text transformation, multiple sites, shared skills/guidelines, and WordPress.com permissions: https://wordpress.com/workspace/
- The May 19, 2026 launch post says Workspace brings together Agent access, voice-to-text, screenshot capture, and media upload on the Mac, and that each site can be its own workspace: https://wordpress.com/blog/2026/05/19/wordpress-workspace/
- The launch post lists system requirements as macOS 11 Big Sur or later, compatible with Intel and Apple Silicon. The current repo `Info.plist` declares `LSMinimumSystemVersion` as `13.0`; future release work should resolve whether public copy or app metadata is authoritative.
- Codex repository skills are stored under `.agents/skills`; this repo uses that location for project-specific agent workflows: https://developers.openai.com/codex/skills

## Current Repo Anchors

- Product overview and release basics: `README.md`.
- App entry and window coordination: `Sources/App.swift` and `Sources/AppDelegate.swift`.
- Central state, WordPress.com routing, dictation, Agent, and shortcuts: `Sources/AppState.swift`.
- WordPress.com API, OAuth, Agent, transcription, guidelines, media upload, and preview cookies: `Sources/WPCOMClient.swift`.
- Main user surfaces: `Sources/SetupView.swift`, `Sources/MenuBarView.swift`, `Sources/SettingsView.swift`, and `Sources/WordPressAgentWindowView.swift`.
- Media and screenshots: `Sources/ImageImportView.swift`, `Sources/ImageImportProcessor.swift`, and screenshot handling in `Sources/AppDelegate.swift`.
- Context capture and selected text: `Sources/AppContextService.swift`.
- Build and release: `Makefile`, `Tools/manual-release.sh`, `Tools/notarize.sh`, `.github/workflows/release.yml`, and `.buildkite/pipeline.yml`.

## Defaults for Future Development

- Prefer improving the site-aware workflow over adding generic AI controls.
- Keep app UI copy aligned with WordPress.com positioning unless the product direction intentionally changes.
- Treat WordPress Agent as a core pillar, not a secondary add-on.
- Treat optional features such as ElevenLabs speech, network sandbox routing, draft focus, sticky notes, and writing escape as advanced or emerging surfaces unless public positioning changes.
- When adding a feature, define which site it acts on, which permissions it needs, what leaves the Mac, and what WordPress.com endpoint or site resource owns the result.
