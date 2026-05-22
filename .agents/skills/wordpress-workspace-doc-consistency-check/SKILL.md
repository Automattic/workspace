---
name: wordpress-workspace-doc-consistency-check
description: Review WordPress Workspace README, PRD, release notes, public copy, and product documentation for consistency with this repo and the current WordPress Workspace positioning. Use when editing docs, checking copy drift, or reviewing product claims for this macOS app.
---

# WordPress Workspace Doc Consistency Check

Use this skill to review documentation and product copy for drift.

## Workflow

1. Identify the docs or copy being changed.
   - Common targets: `README.md`, `docs/prd.md`, release notes, app copy, website copy, and skill docs under `.agents/skills`.
2. Compare claims against repo facts.
   - Use `Info.plist` for bundle IDs, version, URL scheme, minimum macOS version, and permission strings.
   - Use `Makefile`, `Tools/manual-release.sh`, `.github/workflows/release.yml`, and `.buildkite/pipeline.yml` for build and release claims.
   - Use `Sources/WPCOMClient.swift` for WordPress.com endpoints and integration behavior.
   - Use `Sources/QuickLauncherIndex.swift` for `Workspace.sqlite`, launcher entities, cached remote rows, recent opens, and indexing stats.
   - Use `Sources/AppState.swift`, `Sources/AppDelegate.swift`, and UI files for user-facing flows.
3. Check product vocabulary.
   - Prefer "WordPress Workspace" or "WP Workspace" only where the app already uses the shorter product name.
   - Use the current product name in new public and repo-facing docs.
   - Describe the product as site-first and WordPress.com-aware.
   - Say "selected site" when explaining context boundaries.
   - Prefer WordPress archetypes such as posts, media, terms, guidelines, artifacts, skills, site roles, and plugin-provided capabilities over parallel app-only concepts.
   - Use plain UI labels such as "Starred", "All Sites", and "Load previous conversations" when describing the Agent sidebar.
   - Keep WordPress Studio positioned as local site development, not daily live-site workspace work.
4. Check non-goals and trust boundaries.
   - Do not imply local model/provider configuration exists for WordPress.com AI.
   - Do not imply the app bypasses WordPress.com permissions.
   - Distinguish local capture from data sent to WordPress.com.
   - Do not expose effective preview URLs, frame nonces, or private preview bootstrap details in user-facing copy.
5. Return findings first when reviewing.
   - Include file and line references when possible.
   - Separate factual mismatches from tone or clarity suggestions.

## Known Alignment Points

- Public Workspace positioning emphasizes beta status, inclusion with WordPress.com plans during beta, Agent access, dictation, screenshots, image upload, selected-text transformation, multiple sites, guidelines, skills, and WordPress.com permissions.
- The repo currently requires macOS 13.0 in `Info.plist`; public launch copy says macOS 11 or later.
- GitHub Actions release automation is parked; Buildkite is the production build path for release artifacts.
- Current builds link SQLite through `Makefile` and store local launcher/cache data in `Workspace.sqlite`.
- Transcription smoke tests should use `Tools/wpcom-transcribe.sh` before inventing new endpoint tooling.
- Do not claim in-app telemetry exists. Current external product signal is limited mostly to WordPress.com OAuth sign-in counts plus manual QA and release feedback.
