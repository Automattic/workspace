---
name: whispress-agent-ux-consistency-check
description: Review WordPress Workspace Agent, site picker, conversation history, Quick Ask, QuickLauncher, settings, and sidebar UX for consistency with the repo's plain, explicit, site-scoped interaction patterns. Use when changing Agent UI, site switching, starred/all-sites behavior, conversation pagination, or settings copy.
---

# WordPress Workspace Agent UX Consistency Check

Use this skill for recurring Agent and workspace UI patterns.

## Workflow

1. Inspect the relevant UI and state.
   - Common files: `Sources/WordPressAgentWindowView.swift`, `Sources/WordPressAgentUtilityOverlayView.swift`, `Sources/MenuBarView.swift`, `Sources/SettingsView.swift`, and `Sources/AppState.swift`.
   - Search with `rg -n "Starred|All Sites|Load previous|QuickLauncher|@|settings|shortcut|conversation|site" Sources`.
2. Preserve site-scoped clarity.
   - Make the active selected site visible before sending text, audio, images, screenshots, or Agent messages.
   - Prefer explicit site switching over hidden "last site" behavior.
   - Use Starred and All Sites as plain labels.
3. Prefer calm, explicit controls.
   - Avoid hidden auto-loading when a visible action is clearer.
   - Use "Load previous conversations" for paging older history.
   - Persist state users mentally own: starred sites, sidebar sections, collapse state, and cached lists.
   - Keep buttons and settings copy straightforward rather than clever.
4. Keep settings explanatory.
   - Toggles should say what changes when enabled, especially for artifacts, indexing, debug behavior, permissions, and setup reruns.
5. Review failure and empty states.
   - Empty, loading, signed-out, no-site, no-results, and permission-denied states should be specific and actionable.

## Output

- Lead with UX inconsistencies and behavioral risks.
- Include file and line references.
- Separate product-language suggestions from implementation bugs.
