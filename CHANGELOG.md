# Changelog

All notable changes to SlayNode will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2026-04-18

### Added

- Tahoe-native main window built around `NavigationSplitView`, toolbar search, inspector, and workspace-scoped secondary windows
- Unified local service domain for processes, Docker containers, and Homebrew Services
- Actor-based discovery orchestration and source-specific control providers
- SwiftData-backed history for recent workspaces, action history, and scene restoration
- App Intents, Spotlight indexing hooks, local notification plumbing, and richer menu bar integration
- New tests for provider logic, command redaction, port parsing, and the extracted dashboard support layer

### Changed

- Raised the minimum OS requirement to `macOS 26.0`
- Repositioned SlayNode from Node-focused runtime utility to a first-class local service control room
- Rebuilt the main UX around native macOS 26 patterns instead of custom window chrome
- Replaced primary destructive copy like `Slay` with clearer actions such as `Stop`, `Force Stop`, and `Restart`
- Tightened process heuristics so tooling daemons and non-service noise are filtered out more aggressively
- Redacted known secret-bearing command arguments before they are shown in the UI

### Fixed

- Search and filtering now operate on a normalized service index instead of ad hoc runtime strings
- Hidden or low-value utility processes no longer dominate the main dashboard
- Commands and summaries shown in the UI avoid leaking common API keys and token flags
- Recent workspace history no longer reintroduces detached `/` roots into the primary sidebar

## [1.0] - 2026-04-11

### Added

- Window-first runtime dashboard with richer list/detail layout
- Integrated Settings and About surfaces inside the main app experience
- Dedicated SlayNode menu bar glyph generated from the same brand system as the app icon
- Official `script/build_and_run.sh` workflow for local build, run, logs, and verification

### Changed

- Repositioned the app from a menu bar-first utility to a desktop control surface for local runtimes
- Improved runtime naming, workspace inference, and process-role presentation in the UI
- Normalized branding to `SlayNode` across bundle metadata, build scripts, release tooling, and docs
- Rebuilt the icon pipeline around `generate-icons.swift` as the source of truth
- Aligned the public release line on `v1.0` and automated GitHub releases from `main`

### Fixed

- Settings and About now feel like part of the same product instead of detached popups
- Local builds no longer present Sparkle update flows when release metadata is incomplete
- Wrapper processes such as `npm run dev` inherit more useful identities from their child runtimes

## [1.2.0] - 2025-10-12

### Added

- Threading modernization using Swift concurrency and async/await
- Unified process parsing and standardized error handling
- Improved port detection, logging, and process-role classification

### Fixed

- MainActor warnings, timer memory leaks, race conditions, and parser robustness issues

## [1.1.x] - Previous Versions

### Core Features

- Menu bar integration with popover interface
- Real-time Node.js process detection
- One-click process termination
- Port number detection and display
- Project name inference
