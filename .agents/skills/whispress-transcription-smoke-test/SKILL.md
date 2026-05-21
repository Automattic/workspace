---
name: whispress-transcription-smoke-test
description: Run or explain WordPress Workspace transcription endpoint smoke tests using the no-dependency shell script, bearer tokens, site IDs/domains, audio files, selected text, app context, proxy, envelope, and verbose curl debugging. Use when testing `/wpcom/v2/sites/{site}/ai/transcription` or diagnosing transcription endpoint failures.
---

# WordPress Workspace Transcription Smoke Test

Use this skill for direct endpoint testing of WordPress.com transcription.

## Workflow

1. Use the existing script first.
   - Script: `Tools/wpcom-transcribe.sh`
   - Endpoint: `POST /wpcom/v2/sites/{site}/ai/transcription`
   - Required: bearer token or auth header, site ID/domain, and audio file.
2. Keep it dependency-free.
   - The script is POSIX shell plus `curl`.
   - Do not add jq, Python, local OAuth flows, or extra dependencies unless the user explicitly asks.
3. Choose the narrowest invocation.
   - Dictation: `WPCOM_BEARER_TOKEN="$TOKEN" Tools/wpcom-transcribe.sh --site 123456 --file ./sample.mp3`
   - Command mode: add `--intent command --selected-text "Rewrite this."`
   - Debug REST proxy: add `--envelope`.
   - Network debugging: add `--verbose` and optional `--proxy <url>`.
   - Custom context: add `--app-context '<json>'`.
4. Protect secrets.
   - Never print token values.
   - Prefer environment variables or redacted examples.
5. Interpret failures by layer.
   - Local file and MIME detection.
   - Auth header or token scope.
   - Site ID/domain and selected-site permissions.
   - Endpoint response body and HTTP status.
   - Proxy, timeout, or WordPress.com API availability.

## Product Notes

- The app uses the same site-scoped endpoint for dictation and selected-text command mode.
- The selected site may provide a server-side `wp_guideline` skill with slug `transcribe`.
- The endpoint may create the Transcription guideline on first use.
- Saving artifacts is controlled by the `save_artifact` field in app requests.
