---
name: whispress-preview-routing-debug
description: Debug WordPress Workspace Agent preview, edit-mode, authentication, proxy, and URL-routing behavior across simple WordPress.com, Jetpack, and Atomic sites. Use when preview panels load blank pages, show the wrong URL, leak effective preview URLs, fail authentication, or behave differently by site type.
---

# WordPress Workspace Preview Routing Debug

Use this skill for preview/auth/editor-mode problems in the WordPress Agent window or detached preview.

## Workflow

1. Ground the report in the current code path.
   - Inspect `Sources/WordPressAgentPreviewURLResolver.swift`, `Sources/WordPressAgentWindowView.swift`, `Sources/WPCOMClient.swift`, and relevant `Sources/AppState.swift` preview methods.
   - Search with `rg -n "preview|frame_nonce|jetpack_frame_nonce|unmapped|Atomic|cookie|requested|effective|private|proxy" Sources`.
2. Preserve the preview trust rules.
   - Show the requested user-facing URL in UI.
   - Do not expose effective preview URLs, frame nonces, auth bootstrap URLs, or private preview details.
   - Reject localhost and private-network URLs.
3. Check site type and mode.
   - Simple WordPress.com, Jetpack, and Atomic sites can require different preview URL, unmapped-host, nonce, cookie, or read-access handling.
   - Distinguish signed-out view, authenticated preview, and editor mode.
4. Reproduce with focused signals.
   - Prefer app logs, existing preview loading states, and targeted code inspection before inventing shell-only repros.
   - Verify loading/preparation states, navigation updates, requested-vs-effective URL display, and mode switch behavior.
5. Keep comments where behavior is non-obvious.
   - Proxy bypass, cookie bootstrap, nonce handling, and URL rewriting deserve concise code comments when changed.

## Output

- Lead with the failing route or trust boundary.
- Include file references and the specific site/mode assumptions.
- Recommend tests for public URL, same-site URL, preview URL, editor URL, internal navigation, and rejected private URL.
