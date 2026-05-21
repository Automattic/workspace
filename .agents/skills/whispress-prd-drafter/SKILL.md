---
name: whispress-prd-drafter
description: Draft or update WordPress Workspace PRDs, product plans, roadmap notes, and future-development guidance for this repo. Use when the user asks for PRD work, product direction, feature scope, roadmap planning, or docs that should guide future development of the macOS WordPress Workspace app.
---

# WordPress Workspace PRD Drafter

Use this skill when creating or revising product-development docs for this repository.

## Workflow

1. Ground the doc in repo truth before writing.
   - Read `README.md`, `docs/prd.md` if it exists, `Info.plist`, `Makefile`, and the most relevant Swift files for the requested area.
   - Prefer `rg` to find flows in `Sources/AppState.swift`, `Sources/WPCOMClient.swift`, `Sources/AppDelegate.swift`, `Sources/SetupView.swift`, `Sources/SettingsView.swift`, and `Sources/WordPressAgentWindowView.swift`.
2. Align product framing with the public WordPress Workspace pages when current positioning matters.
   - Use https://wordpress.com/workspace/
   - Use https://wordpress.com/blog/2026/05/19/wordpress-workspace/
   - Date any public-source alignment notes because those pages can change.
3. Preserve core product direction.
   - WordPress Workspace is a site-first Mac app.
   - The selected WordPress.com site is the workspace context.
   - WordPress.com owns account access, site permissions, AI execution, Agent capabilities, media storage, guidelines, and skills.
   - The Mac app owns native entry points, local capture, permissions, shortcuts, upload preparation, and routing into the selected site.
4. Preserve non-goals unless the user explicitly changes them.
   - No local WordPress.com AI provider setup.
   - No local model picker.
   - No local prompt or spelling editor.
   - No separate Workspace account system.
   - No WordPress Studio replacement.
5. Write a practical living guide for an existing beta app.
   - Prefer product principles, flows, requirements, trust boundaries, metrics, test scenarios, and repo anchors.
   - Avoid greenfield ceremony unless the user asks for a strict template.

## Required Checks

- Call out the macOS support mismatch if the doc mentions compatibility: public launch copy says macOS 11 or later, while this repo's `Info.plist` currently requires 13.0.
- Make active site routing explicit for any feature that sends text, audio, images, screenshots, or Agent messages.
- Do not document unverified privacy or retention promises as external commitments.
