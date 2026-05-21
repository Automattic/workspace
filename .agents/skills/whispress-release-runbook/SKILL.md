---
name: whispress-release-runbook
description: Guide WordPress Workspace build, packaging, signing, notarization, OAuth secret injection, release checks, and release documentation for this repo. Use when the user asks to build, package, sign, notarize, publish, smoke test, or explain release operations.
---

# WordPress Workspace Release Runbook

Use this skill for release, packaging, and build-operation work in this repository.

## Before Acting

- Check `git status --short --branch`.
- Do not overwrite unrelated local changes.
- Confirm whether the user wants a development build, local release package, notarized package, or published GitHub Release.
- Do not expose OAuth secrets or paste secret values into logs, docs, or commit messages.

## Development Build

- Default command: `make`
- Default output: `build/WP Workspace Dev.app`
- Default bundle identifier: `com.automattic.wpworkspace.dev`
- Use `make run` only when the user wants to launch the app locally.

## OAuth Secret Handling

- `Info.plist` contains the WordPress.com OAuth client ID.
- The OAuth client secret is not committed.
- Local builds can inject it with:
  - `WPCOM_OAUTH_CLIENT_SECRET="$WPCOM_CLIENT_SECRET" make CODESIGN_IDENTITY=-`
  - `make CODESIGN_IDENTITY=- WPCOM_OAUTH_CLIENT_SECRET_FILE=.wpcom-oauth-client-secret`
- Treat the app secret as inspectable native-app credential material, not a server-grade secret.

## Manual Release

- Main script: `Tools/manual-release.sh`
- Default package path: `build/WPWorkspace-<version>.zip`
- The script expects a clean working tree unless `--allow-dirty` is explicitly chosen.
- The script uses `Info.plist` for `CFBundleShortVersionString` and creates or reuses tag `v<version>` when publishing.
- Publishing requires `gh` and uploads the zip to GitHub Releases.

## CI and Notarization

- `Makefile` owns direct `swiftc` compilation, resource copying, secret injection, code signing, zip, DMG, and notarization targets.
- `Tools/notarize.sh` handles notarization and stapling.
- `.github/workflows/release.yml` is intentionally disabled behind manual dispatch.
- `.buildkite/pipeline.yml` runs build, signing, notarization, and artifact collection on the mac queue.

## Smoke Test

- Transcription endpoint script: `Tools/wpcom-transcribe.sh`
- It requires a bearer token, site, and audio file.
- It posts multipart audio to `/wpcom/v2/sites/{site}/ai/transcription`.

## Verification

- For docs-only changes, do not run `make` unless the user asks.
- For build changes, prefer `make` or the narrowest relevant target.
- For release changes, verify scripts with shellcheck-style reading and dry-run reasoning when secrets or publishing are unavailable.
