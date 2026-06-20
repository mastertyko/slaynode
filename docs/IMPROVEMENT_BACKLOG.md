# SlayNode Improvement Backlog

Audit date: 2026-05-27

Baseline evidence before this audit: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed 246 XCTest tests with 0 failures.

Current verification snapshot (2026-06-20): `./script/full_verification.sh` passed 356 tests with 0 failures in the current repo state.

Status legend:
- Fixed in this pass: implemented during the audit.
- Fixed in later pass: implemented after the original audit and verified in the current repo state.
- Candidate: concrete follow-up improvement found in the current codebase.

## 100 Improvement Candidates

### Command Parsing And Detection

1. Fixed in this pass - Redact `Authorization:` style header values in command summaries so bearer tokens are not shown in the UI.
2. Fixed in this pass - Treat npm registry `_authToken` arguments as sensitive values and redact the following token.
3. Fixed in this pass - Ignore blank working-directory flag values instead of storing an empty path.
4. Fixed in this pass - Normalize quoted tilde working-directory values before expanding them.
5. Fixed in later pass - Added redaction coverage for `Cookie:`, `Set-Cookie:`, `X-Api-Key:`, and `Proxy-Authorization:` header forms, including split-header cases.
6. Fixed in later pass - Added tests for escaped spaces in `--cwd` and `--prefix` values from real shell command lines.
7. Fixed in later pass - Added parser fixtures for `npm --prefix app exec vite -- --host 127.0.0.1 --port 5173`.
8. Fixed in later pass - Added parser fixtures for `pnpm --filter web dev -- --port 3000` and workspace filter aliases.
9. Fixed in later pass - `CommandParser.firstScriptToken` now recognizes `server.tsx`-style entrypoints without relying on directory names.
10. Fixed in later pass - Expanded port inference to handle URL ports embedded inside flag values such as `--public-url=http://127.0.0.1:3000/app`, and separate URL values after port/listen flags.
11. Fixed in later pass - Added fixtures for IPv4-mapped IPv6 literals such as `[::ffff:127.0.0.1]:3000`.
12. Fixed in later pass - Added fixtures for Bun's `--hot`, `--watch`, and `bun --bun vite` command shapes.
13. Fixed in later pass - Added fixtures for Deno task commands, including `deno task dev --port 8000`.
14. Fixed in later pass - Added framework classifiers for H3/Nitro, TanStack Start, and Hono dev-server variants.
15. Candidate - Extract common command-token normalization helpers so `CommandParsing`, `ProcessClassifier`, and `ServiceHeuristics` do not drift.

### Process Discovery And Ports

16. Candidate - Share the duplicated system/tooling-process exclusion rules between `ProcessDiscovery` and `ServiceHeuristics`.
17. Fixed in later pass - Added a single fixture table for excluded tooling processes so Codex, OMX, tsserver, esbuild, and sourcekit patterns stay consistent.
18. Candidate - Add discovery tests for child promotion when a package-manager wrapper has multiple child runtimes.
19. Candidate - Add discovery tests for process trees where a child exposes a port but the parent owns the workspace.
20. Candidate - Add discovery tests for process groups where the promoted child exits between `ps` and `lsof`.
21. Candidate - Add a stable process identity that combines pid, start time, and command instead of relying only on pid and command hash.
22. Candidate - Replace Swift `hashValue` command comparison with a deterministic hash so verification remains stable across process boundaries if needed.
23. Candidate - Add per-command timeout diagnostics so process discovery can say whether `ps`, `lsof`, or cwd resolution failed.
24. Candidate - Add lsof parser fixtures for IPv6 wildcard output across current macOS versions.
25. Candidate - Add lsof parser fixtures for service names that render as `*:http-alt` instead of numeric ports.
26. Candidate - Add a bounded retry for `lsof` when it returns transient permission or race-condition failures.
27. Candidate - Add metrics for skipped process rows so malformed `ps` output is visible during debugging.
28. Candidate - Add a maximum candidate PID batch size before invoking `lsof -p` to avoid command-line length failures on busy machines.
29. Candidate - Add cancellation checks inside process enrichment after each external command completes.
30. Candidate - Add a debug-only trace mode that records why each candidate process was shown or filtered.

### Service Model And History

31. Candidate - Add a shared service-kind keyword registry to avoid keyword drift between container, brew, and process classification.
32. Candidate - Add tests for classification conflicts such as `redis-worker`, `postgres-api`, and `nginx-proxy`.
33. Candidate - Add service history pruning by age as well as count to keep SwiftData storage bounded over long use.
34. Candidate - Add tests for history migration from legacy rows with missing workspace fields.
35. Candidate - Record the last successful discovery source for each service to make UI troubleshooting easier.
36. Candidate - Add a health reason field so `watch`, `critical`, and `passive` states explain themselves consistently.
37. Candidate - Add dependency confidence scores instead of creating all workspace-shared dependencies equally.
38. Candidate - Add deterministic sorting for dependencies to keep UI snapshots and tests stable.
39. Candidate - Add a service-source display helper so process, Docker, and brew identifiers are formatted in one place.
40. Fixed in later pass - Persisted service and workspace identifiers now reject newline/tab control characters before history persistence.

### Safety And Process Control

41. Candidate - Add a dry-run API for process termination that uses `ProcessActionPreview` as the single source of truth.
42. Candidate - Make force-stop previews include whether SIGKILL targets a process group or only one pid.
43. Candidate - Add tests for permission-denied `kill` errors on process groups and child fallbacks.
44. Candidate - Add an optional longer grace period for restart actions than for simple stop actions.
45. Candidate - Add telemetry breadcrumbs for stop, force-stop, and restart outcomes without including raw commands.
46. Candidate - Add a safety warning when a process group contains processes outside the selected workspace.
47. Candidate - Add a safety warning when a process command changed and its cwd changed before termination.
48. Candidate - Add a safety warning when a process is owned by another user.
49. Candidate - Add a preview row for orphaned descendants that will be affected by group termination.
50. Candidate - Centralize `SIGTERM` and `SIGKILL` error mapping so menu and service-center errors use identical copy.

### UI And Accessibility

51. Candidate - Add keyboard shortcuts for refresh, search focus, and opening the service center.
52. Candidate - Add VoiceOver labels for service health, port badges, and destructive action buttons.
53. Candidate - Add accessibility tests for menu status text and dashboard action labels.
54. Fixed in later pass - The dashboard empty state now distinguishes discovery errors from "no services found" and active search filtering.
55. Candidate - Add visible stale-data state when refresh fails after previously showing services.
56. Candidate - Add tabular number styling to pid, port, and uptime labels for easier scanning.
57. Fixed in later pass - Long redacted command summaries now expose the full value through dashboard and preview tooltips.
58. Fixed in later pass - The command-copy action now copies the redacted command, not the raw command.
59. Candidate - Add per-workspace counts in the workspace sidebar.
60. Candidate - Add a "show hidden tooling" debug toggle for support sessions.
61. Candidate - Add a filter chip for Docker, Homebrew, and local process sources.
62. Candidate - Add a filter chip for degraded services.
63. Fixed in later pass - Service selection now falls to the nearest visible neighbor when the current selection disappears during refresh.
64. Candidate - Add UI snapshot tests for long workspace names and long command strings.
65. Candidate - Split the largest SwiftUI views into smaller view models and subviews to reduce compile-time churn.

### Build, Release, And CI

66. Fixed in later pass - The CI workflow now declares explicit read-only `contents` permissions.
67. Fixed in later pass - CI now runs `git diff --check` to catch whitespace regressions.
68. Fixed in later pass - Added an explicit CI step that runs `./debug-port-detection.sh --samples-only`.
69. Fixed in later pass - CI and release workflows now publish release metadata artifacts with version, build number, minimum macOS, and git provenance.
70. Fixed in later pass - `build.sh` now validates `SLAYNODE_VERSION` and `SLAYNODE_BUILD_NUMBER` before generating `Info.plist`.
71. Fixed in later pass - `build.sh` now XML-escapes generated Info.plist metadata values consistently, not only Sparkle metadata.
72. Fixed in later pass - `build.sh` now fails explicitly if `iconutil` does not produce `AppIcon.icns`.
73. Fixed in later pass - `build.sh --verify-only` now provides a local metadata/asset/plist preflight without rebuilding.
74. Fixed in later pass - Shell regression coverage now locks unreleased, versioned, and git-log release note extraction paths.
75. Fixed in later pass - Release note validation now refuses empty or heading-only generated notes before packaging.
76. Candidate - Add notarization retry guidance for transient Apple notarytool failures.
77. Fixed in later pass - Build preflight now requires Sparkle feed URL and ED key to be configured together or omitted together.
78. Candidate - Add a dependency update workflow for Sparkle and Sentry with a manual approval gate.

### Tests And Tooling

79. Fixed in later pass - `docs/DEVELOPMENT.md` now points to a single full local verification command.
80. Candidate - Add test helpers for building `NodeProcess` fixtures to reduce repetitive constructor boilerplate.
81. Candidate - Add parameterized tests for common process command examples instead of one-off assertions.
82. Fixed in later pass - `ShellExecutor` tests now cover timeout behavior for long-running commands and large stderr output.
83. Candidate - Add tests for `PortResolver` timeout behavior and cancellation.
84. Fixed in later pass - Sanitizer tests now verify that known secret fixtures do not survive into rendered summaries.
85. Fixed in later pass - Preview tests now assert that every destructive action surfaces at least one warning.
86. Candidate - Add tests that verify menu and service-center action ordering stays consistent.
87. Fixed in later pass - Workspace history tests now cover build folders, caches, and editor/agent hidden state directories.
88. Fixed in later pass - Added tests and normalization for Docker bind mount sources with escaped spaces, read-only mount suffixes, and missing local sources.
89. Fixed in later pass - Added tests for Homebrew services with missing, invalid, or unreadable plist paths.
90. Fixed in later pass - Added a lightweight static script that scans for `try!`, `as!`, `fatalError`, and unredacted secret fixtures.

### Documentation And Operations

91. Fixed in later pass - `docs/DEVELOPMENT.md` now links this backlog so future maintenance work has a concrete queue.
92. Fixed in later pass - Documented why full Xcode is preferred over Command Line Tools for local SwiftPM verification.
93. Fixed in later pass - Documented the difference between local ad-hoc signing, CI signing, and notarized release signing.
94. Fixed in later pass - Documented the privacy boundary for command capture and redaction.
95. Fixed in later pass - Documented the process-control safety model for stop, force stop, restart, and preview.
96. Fixed in later pass - Added troubleshooting for "no services found" with commands to inspect `ps`, `lsof`, and permissions.
97. Fixed in later pass - Added troubleshooting for stale menu-bar state after a process exits.
98. Fixed in later pass - Added a supported examples page with real Next.js, Vite, Bun, Deno, Docker, and Homebrew scenarios.
99. Fixed in later pass - Added a release checklist that mirrors `.github/workflows/release.yml` step by step.
100. Fixed in later pass - `docs/DEVELOPMENT.md` now includes a classifier checklist covering false-positive control, wrapper alignment, shared parser helpers, and required regression tests.
