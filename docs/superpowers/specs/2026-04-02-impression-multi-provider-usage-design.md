# Impression — Multi-Provider Usage Monitoring (Claude Code + Codex CLI)

**Date:** 2026-04-02
**Status:** Design Complete

## Problem Statement

Impression currently monitors Claude Code usage across macOS, iPhone, iPad, and widgets. The next feature is to add Codex CLI usage without turning the app into two disconnected products.

The product goal is:
- Support both **Claude Code** and **Codex CLI**
- Let the user switch providers in-app
- Let widgets be configured per provider
- Preserve provider-specific visual identity with distinct colors and copy
- Present usage primarily as **quota progress, remaining amount, and reset time**

The delivery goal is:
- Rebuild the full Xcode project with AppleScript
- Run tests after implementation
- Inspect widget behavior and fix widget bugs found during verification
- Prepare issue / PR / merge as part of the completion workflow when repository tooling and permissions allow

## Scope

In scope:
- Provider abstraction for usage fetching and presentation
- Claude Code provider retained as the existing implementation path
- Codex CLI provider added with official-source-first discovery
- Provider-aware cache, sync, and widget configuration
- Provider-specific theme switching in app and widget surfaces
- Automated rebuild and test verification using AppleScript-driven Xcode actions

Out of scope for this design:
- A brand-new app information architecture
- Mixing Claude and Codex usage into a fake combined percentage
- Replacing existing Claude acquisition logic
- Shipping a custom backend service just for Codex usage

## Recommended Approach

Use a **unified provider architecture** with a shared UI model.

Why this approach:
- The app already has working cross-platform views and widget surfaces
- Codex data shape is likely different from Claude data shape
- Forcing provider-specific logic into the UI will create duplication and brittle widgets
- A provider layer isolates discovery, fetch, parsing, fallback, and error mapping

Alternatives considered:

1. Keep Claude as-is and bolt Codex onto side paths
   - Faster initial implementation
   - Higher long-term duplication in widgets, cache, and tests

2. Build two separate app modes with separate view models
   - Lower abstraction pressure up front
   - Creates parallel feature development forever

3. Unified provider architecture
   - Slightly larger upfront refactor
   - Best long-term maintainability and easiest widget reuse

Recommendation: **Option 3**

## Architecture

### Core Types

Add a provider layer centered on:

- `UsageProviderKind`
  - `claudeCode`
  - `codexCLI`

- `UsageProvider`
  - Resolves its own credentials or data source
  - Fetches raw usage data
  - Normalizes raw data into a shared snapshot
  - Exposes provider metadata used by the UI

- `ProviderTheme`
  - Brand colors
  - Display name
  - Accent and warning colors
  - Empty-state and error copy

- `UsageSnapshot`
  - Shared provider-agnostic presentation model
  - Includes:
    - `provider`
    - `primaryUsagePercent`
    - `primaryQuotaLabel`
    - `primaryResetAt`
    - `secondaryUsagePercent?`
    - `secondaryQuotaLabel?`
    - `secondaryResetAt?`
    - `remainingText?`
    - `fetchedAt`
    - `source`
    - `confidence`

### Provider Responsibilities

Claude provider:
- Keeps the current `/api/oauth/usage` primary path
- Keeps the current messages-header fallback path
- Maps current session and weekly values into the new snapshot

Codex provider:
- Tries official or officially-supported Codex usage sources first
- Falls back to local Codex data only if no stable official source exists
- Normalizes whatever source is found into quota-oriented snapshot fields
- If the source cannot provide a trustworthy reset time, the UI must say so explicitly instead of inventing one

### Separation of Concerns

UI layers do not inspect provider internals.

The UI only reads:
- `UsageSnapshot`
- `ProviderTheme`
- provider status metadata

This keeps:
- app screens reusable
- widget views reusable
- tests focused on normalization instead of surface-specific branching

## Data Sources And Fallback Policy

### Claude Code

Priority order:
1. `GET /api/oauth/usage`
2. `POST /v1/messages` header parsing
3. Cached local snapshot
4. Cached iCloud snapshot

### Codex CLI

Priority order:
1. Official Codex API or official Codex CLI usage interface if available
2. Officially-generated local Codex artifacts if they contain quota-progress data
3. Local cached snapshot
4. iCloud cached snapshot

Rules:
- Do not fabricate provider parity if Codex cannot expose the same granularity as Claude
- Prefer explicit source labeling over false precision
- Treat unofficial local parsing as lower confidence than official sources

## App Behavior

### Provider Switching

The main app adds a provider selector:
- `Claude Code`
- `Codex CLI`

Switching provider updates:
- headline labels
- usage rings and bars
- reset countdown copy
- source labels
- brand colors
- provider-specific onboarding or error guidance

The layout remains structurally consistent across providers to avoid maintaining two separate products.

### Settings And Onboarding

Claude setup remains aligned with the current token and credential flow.

Codex setup adds provider-specific status:
- official source available
- local source fallback in use
- no supported Codex usage source found

If Codex cannot expose quota progress yet, the UI should fail honestly with actionable messaging rather than showing misleading zeros.

## Widget Behavior

Widgets are configured **per widget instance**.

That means a user can place:
- one Claude widget
- one Codex widget
- multiple widgets with different provider selections

Widget configuration stores provider kind alongside existing widget data. The timeline provider reads the correct provider namespace and renders the shared widget layout using the matching provider theme.

This avoids:
- global widget coupling to the app’s current provider
- accidental data overwrite between providers

## Persistence And Sync

Persistence becomes provider-aware.

Required changes:
- local App Group storage keys namespaced by provider
- iCloud KV store keys namespaced by provider
- provider selection stored separately from snapshot data
- widget configuration stores provider kind explicitly

Example key strategy:
- `usageSnapshot.claudeCode`
- `usageSnapshot.codexCLI`
- `selectedProvider`

This prevents Claude and Codex snapshots from overwriting each other.

## Error Handling

Errors must remain provider-specific and user-readable.

Claude examples:
- token expired
- credentials not found
- primary endpoint rate-limited, fallback active

Codex examples:
- official usage source unavailable
- no local Codex usage data found
- unsupported Codex data format
- usage source found but reset time unavailable

The UI should map these to provider-specific guidance instead of exposing raw parse or transport failures.

## Testing Strategy

### Unit Tests

Add or update tests for:
- provider normalization into shared `UsageSnapshot`
- Claude regression coverage for current parsing and fallback behavior
- Codex discovery and parsing behavior
- provider-aware cache key selection
- provider selection persistence

### UI / ViewModel Tests

Cover:
- switching providers updates labels, theme, and data source
- empty states and degraded states render the correct provider-specific messaging
- widgets read the right provider snapshot

### Widget Verification

Widget verification is part of done criteria.

Minimum bar:
- widget extension builds cleanly
- provider selection does not break widget timeline reads
- no provider cross-talk in widget storage

If widget regressions are found during verification, they are fixed before completion.

## Rebuild And Verification Workflow

Implementation is not complete until rebuild and verification run end to end.

Verification workflow:
1. Rebuild the project using AppleScript to drive Xcode
2. Run automated tests for the project or affected schemes
3. Inspect widget build behavior and fix any widget-specific defects found
4. Re-run build and tests after fixes

AppleScript is used to automate the rebuild path through Xcode so the verification matches the actual local development flow, not just raw `xcodebuild`.

## Issue, PR, And Merge Workflow

After implementation and verification:
- create or update an issue summarizing the feature and verification scope
- create a PR with implementation notes and test evidence
- merge once the branch is in a valid state and repository permissions allow it

If GitHub CLI or repository protections block automation:
- prepare the issue body
- prepare the PR body
- document the exact blocking step

The implementation is still expected to produce ready-to-submit artifacts, not vague instructions.

## Implementation Shape

Expected code changes are centered on:
- `Shared/Models`
- `Shared/Services`
- `Shared/ViewModels`
- `Shared/Constants.swift`
- widget provider configuration and timeline read path
- app settings and provider selector surfaces

The refactor should preserve existing Claude behavior while making Codex integration additive.

## Success Criteria

The feature is successful when:
- the app can switch between Claude Code and Codex CLI
- each provider uses its own theme and copy
- widgets can be configured per provider
- Claude remains functional after the refactor
- Codex uses the best available official source first, then a documented fallback path if needed
- the project rebuilds successfully through AppleScript-driven Xcode automation
- tests pass after implementation
- widget-specific bugs discovered during verification are fixed before closeout
