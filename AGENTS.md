# FMO Companion Agent Guide

This file is the repository entry point for AI-assisted development. `CLAUDE.md` points to this file so Codex, Claude Code, and other agents share one source of truth.

## Language Preferences

| Setting | Language |
|---|---|
| Conversation | 中文 |
| Documentation | 中文 |
| Code identifiers | English |
| Code comments | 中文或英文均可，但仅在解释“为什么”时添加 |

## Project Summary

FMO Companion is a native iOS companion app for FMO (NFM Over Internet) hardware. It uses only documented interfaces and user-authorized services:

- Bonjour/mDNS and the documented local GEO WebSocket API.
- The strictly allowlisted, user-authorized local read-only status API described by ADR-0005.
- Public FMO V4 APRS frames and standard APRS-IS behavior.
- The documented APRS remote-control format.
- The user-authorized, strictly read-only local QSO list/detail contract fixed by ADR-0007, plus user-exported QSO archives when explicitly chosen.
- A separately authenticated HTTPS API for the user's own FMO server.

The app must not perform runtime packet sniffing or rely on firmware reverse engineering, private-key extraction, undocumented audio frames, or impersonating an FMO device. The ADR-0005 status client and ADR-0007 QSO client are limited to sanitized, typed, read-only behavior observed in the official UI; they must never expose generic management commands, secrets, write operations, backup/restore triggers, or `/audio`.

## Documentation Map

All agents must use these paths. Update this table when documentation moves.

| Purpose | Path |
|---|---|
| Session entry point | `docs/project-brief.md` |
| Product requirements | `docs/spec/product-spec.md` |
| Technical requirements | `docs/spec/technical-spec.md` |
| Architecture overview | `docs/architecture/overview.md` |
| Module documentation | `docs/architecture/modules/` |
| UI design system | `docs/design/ui-design-system.md` |
| Prototype coverage matrix | `docs/design/prototype-coverage-matrix.md` |
| Prototype implementation guide | `docs/design/prototype-implementation-guide.md` |
| ADR index | `docs/adr/README.md` |
| Implementation plans | `docs/plans/` |
| FMO protocol references | `docs/references/` |
| Interactive HTML prototype | `prototype/` |
| Loom project skills | `.claude/skills/` |
| Loom project agents | `.claude/agents/` |
| Codex skill mirror | `.agents/skills` → `.claude/skills` |

## Session Start Protocol

At the beginning of a development session:

1. Read `AGENTS.md` and `docs/project-brief.md`.
2. Read only the specification, ADR, module document, and plan relevant to the task.
3. Run `bash .claude/scripts/drift-check-hook.sh` as a quick freshness check.
4. Inspect `git status --short --branch`; preserve unrelated user changes.
5. State any documentation drift or scope uncertainty, then continue unless it materially changes the requested outcome.

## Development Rules

- Target iOS 26 or later and use SwiftUI with Swift Concurrency.
- Prefer current iOS 26 APIs directly. Do not add availability branches or compatibility shims for older iOS releases unless the deployment policy is explicitly changed.
- Prefer Apple frameworks before adding dependencies: Network, CoreLocation, MapKit, CryptoKit, SwiftData, UserNotifications, WebKit, LocalAuthentication.
- Treat all network and location operations as asynchronous and cancellation-aware.
- Keep protocol parsing and cryptographic verification independent from UI code.
- Use dependency injection through protocols for network, location, clock, storage, and APRS transports.
- Never log APRS PASSCODEs, remote-control secrets, bearer tokens, precise location, or synchronized/exported QSO contents in production logs.
- Store secrets only in Keychain. Do not put secrets in source, UserDefaults, test fixtures, screenshots, or documentation.
- Do not weaken certificate, signature, replay-window, or CRL validation to make tests pass.
- Use localized user-facing strings; do not hard-code visible copy deep in service layers.
- When implementing UI or a workflow represented in `prototype/`, read `docs/design/ui-design-system.md`, `docs/design/prototype-coverage-matrix.md`, and `docs/design/prototype-implementation-guide.md`; preserve the confirmed navigation and interaction hierarchy while replacing every browser simulation with typed Swift state and real injected services.
- New behavior requires unit tests. User journeys or permissions behavior that cannot be unit tested should have focused UI/integration coverage and a documented manual check.
- Never claim background execution occurs at exact periodic intervals; iOS scheduling is system-controlled.

## Planned Source Layout

```text
FMOc/
├── App/
├── Features/
│   ├── Device/
│   ├── Location/
│   ├── APRS/
│   ├── RemoteControl/
│   ├── QSO/
│   ├── Server/
│   └── Settings/
├── Core/
│   ├── Networking/
│   ├── Persistence/
│   ├── Security/
│   └── Diagnostics/
├── Models/
└── Resources/
```

Do not create all directories preemptively. Add them as the first real type in each area is implemented, then update module documentation.

## Verification

For normal code changes, run the narrowest relevant tests first, then the full suite when risk warrants it. Use a generic destination for the baseline build:

```bash
xcodebuild \
  -project FMOc.xcodeproj \
  -scheme FMOc \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath /tmp/FMOcDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Tests require a concrete installed simulator. Find an available device with `xcrun simctl list devices available`, then run:

```bash
xcodebuild \
  -project FMOc.xcodeproj \
  -scheme FMOc \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -configuration Debug \
  -derivedDataPath /tmp/FMOcDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

If no compatible simulator runtime is installed, report the missing runtime instead of changing deployment targets to hide the issue.

## Documentation Workflow (Loom)

This repository was bootstrapped using the structure and project-local assets from [The-Last-Humans/loom](https://github.com/The-Last-Humans/loom). Loom is not a runtime dependency.

After a change:

1. Decide whether requirements, architecture, public module APIs, dependencies, security rules, or conventions changed.
2. If yes, update the corresponding document and its `last-reviewed` date in the same change.
3. Add an ADR for a consequential, hard-to-reverse decision; do not create ADRs for routine implementation details.
4. Update `docs/project-brief.md` at the end of a meaningful development session.
5. Run the `doc-drift-check` and `syncing-docs-with-code` workflows before a PR.

Loom templates mention the optional Superpowers plugin. If it is unavailable, use the host agent's native planning, testing, review, and delegation tools; missing Superpowers is not a blocker.

## Git Conventions

| Setting | Value |
|---|---|
| Branching model | GitHub Flow |
| Main branch | `main` |
| Branch naming | `<type>/<short-description>` |
| Commit format | Conventional Commits: `<type>: <description>` |
| Merge strategy | Squash merge |

Branch prefixes: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`.

- Do not push or open a PR unless the user asks.
- Keep commits atomic and do not mix unrelated user changes.
- Never commit signing credentials, provisioning profiles, private keys, APRS secrets, server tokens, or precise-location exports.

## Source-of-Truth Order

When information conflicts, use this order:

1. Current user request.
2. Accepted ADRs.
3. Product and technical specifications.
4. Architecture/module documentation.
5. Active implementation plan.
6. Existing code and tests.

If code intentionally departs from accepted documentation, update the documentation or record a superseding ADR in the same unit of work.
