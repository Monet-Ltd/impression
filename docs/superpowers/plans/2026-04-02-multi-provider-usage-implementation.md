# Multi-Provider Usage Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add provider-aware usage monitoring for both Claude Code and Codex CLI, including app switching, widget configuration, provider theming, and end-to-end rebuild/test verification.

**Architecture:** Refactor the current Claude-only flow into a provider-based model with a shared `UsageSnapshot` presentation shape, provider-aware persistence, and widget reads keyed by provider. Keep existing Claude fetch logic intact behind a `ClaudeUsageProvider`, then add a `CodexUsageProvider` that prefers official Codex usage sources and degrades explicitly when only partial local data is available.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, XcodeGen/Xcode project, XCTest, AppleScript, GitHub CLI

---

## File Structure

Planned file responsibilities:

- Modify: `Shared/Models/UsageData.swift`
  - Evolve `UsageSnapshot` into a provider-aware shared presentation model while preserving Claude parsing types.
- Create: `Shared/Models/UsageProvider.swift`
  - Define `UsageProviderKind`, provider metadata, theme, source confidence, and provider protocol.
- Create: `Shared/Services/ClaudeUsageProvider.swift`
  - Move existing Claude network fetch behavior behind a provider interface.
- Create: `Shared/Services/CodexUsageProvider.swift`
  - Implement official-source-first Codex discovery, normalization, and fallback/error behavior.
- Modify: `Shared/Services/SharedDataStore.swift`
  - Add provider-scoped reads/writes and selected-provider persistence.
- Modify: `Shared/Services/CloudSyncService.swift`
  - Add provider-scoped iCloud snapshot storage and provider-aware change observation.
- Modify: `Shared/Constants.swift`
  - Add provider-scoped storage keys, brand labels, and Codex-related discovery constants.
- Modify: `Shared/ViewModels/UsageViewModel.swift`
  - Route fetches through the selected provider, expose provider/theme metadata, and keep polling behavior.
- Modify: `ImpressionMobile/ContentView.swift`
  - Add provider switching UI and provider-aware dashboard text.
- Modify: `ImpressionWidget/UsageTimelineProvider.swift`
  - Read the provider selected for the widget instance and load the correct snapshot namespace.
- Modify: `ImpressionWidget/UsageWidgetEntryView.swift`
  - Render provider-aware title, colors, and labels.
- Create: `ImpressionTests/ProviderSelectionTests.swift`
  - Cover provider persistence and namespaced storage.
- Create: `ImpressionTests/CodexUsageProviderTests.swift`
  - Cover Codex discovery/parsing/normalization behavior.
- Modify: `ImpressionTests/UsageDataParsingTests.swift`
  - Add normalization and snapshot migration coverage.
- Create: `scripts/rebuild_xcode.applescript`
  - Drive clean rebuild/test flow through Xcode automation.

### Task 1: Introduce Provider Domain Model

**Files:**
- Create: `Shared/Models/UsageProvider.swift`
- Modify: `Shared/Models/UsageData.swift`
- Test: `ImpressionTests/UsageDataParsingTests.swift`

- [ ] **Step 1: Write the failing snapshot/provider tests**

```swift
func testEmptySnapshotDefaultsToClaudeProvider() {
    XCTAssertEqual(UsageSnapshot.empty.provider, .claudeCode)
}

func testProviderThemeMetadataIsStable() {
    XCTAssertEqual(UsageProviderKind.claudeCode.displayName, "Claude Code")
    XCTAssertEqual(UsageProviderKind.codexCLI.displayName, "Codex CLI")
}
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/UsageDataParsingTests`
Expected: FAIL because provider types and new snapshot properties do not exist yet.

- [ ] **Step 3: Add provider core types**

```swift
enum UsageProviderKind: String, Codable, CaseIterable {
    case claudeCode
    case codexCLI
}

struct ProviderTheme: Codable, Equatable {
    let name: String
    let accentHex: String
    let warningHex: String
}
```

- [ ] **Step 4: Expand the shared snapshot model**

```swift
struct UsageSnapshot: Codable, Equatable {
    let provider: UsageProviderKind
    let primaryUsagePercent: Double
    let primaryQuotaLabel: String
    let primaryResetAt: Date?
    let secondaryUsagePercent: Double?
    let secondaryQuotaLabel: String?
    let secondaryResetAt: Date?
    let remainingText: String?
    let fetchedAt: Date
    let source: FetchSource
    let confidence: SnapshotConfidence
}
```

- [ ] **Step 5: Preserve Claude compatibility with computed accessors**

```swift
extension UsageSnapshot {
    var sessionUtilization: Double { primaryUsagePercent }
    var sessionResetsAt: Date? { primaryResetAt }
    var weeklyUtilization: Double { secondaryUsagePercent ?? 0 }
    var weeklyResetsAt: Date? { secondaryResetAt }
}
```

- [ ] **Step 6: Run the targeted tests to verify they pass**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/UsageDataParsingTests`
Expected: PASS for the new provider metadata and snapshot default tests.

- [ ] **Step 7: Commit**

```bash
git add Shared/Models/UsageProvider.swift Shared/Models/UsageData.swift ImpressionTests/UsageDataParsingTests.swift
git commit -m "refactor: add provider-aware usage snapshot model"
```

### Task 2: Add Provider-Aware Persistence

**Files:**
- Modify: `Shared/Services/SharedDataStore.swift`
- Modify: `Shared/Services/CloudSyncService.swift`
- Modify: `Shared/Constants.swift`
- Test: `ImpressionTests/ProviderSelectionTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
func testSharedStorePersistsSelectedProvider() {
    SharedDataStore.shared.selectedProvider = .codexCLI
    XCTAssertEqual(SharedDataStore.shared.selectedProvider, .codexCLI)
}

func testSnapshotsAreNamespacedPerProvider() {
    let claude = UsageSnapshot.empty
    let codex = UsageSnapshot.empty.withProvider(.codexCLI)
    SharedDataStore.shared.writeSnapshot(claude, for: .claudeCode)
    SharedDataStore.shared.writeSnapshot(codex, for: .codexCLI)
    XCTAssertEqual(SharedDataStore.shared.readSnapshot(for: .claudeCode)?.provider, .claudeCode)
    XCTAssertEqual(SharedDataStore.shared.readSnapshot(for: .codexCLI)?.provider, .codexCLI)
}
```

- [ ] **Step 2: Run the tests to verify failure**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests`
Expected: FAIL because provider-scoped APIs and selected-provider persistence are missing.

- [ ] **Step 3: Add provider-scoped storage key helpers**

```swift
extension AppConstants {
    static func snapshotStorageKey(for provider: UsageProviderKind) -> String {
        "usageSnapshot.\(provider.rawValue)"
    }
}
```

- [ ] **Step 4: Implement namespaced local storage**

```swift
func writeSnapshot(_ snapshot: UsageSnapshot, for provider: UsageProviderKind) {
    defaults.set(try? encoder.encode(snapshot), forKey: AppConstants.snapshotStorageKey(for: provider))
}

func readSnapshot(for provider: UsageProviderKind) -> UsageSnapshot? {
    guard let data = defaults.data(forKey: AppConstants.snapshotStorageKey(for: provider)) else { return nil }
    return try? decoder.decode(UsageSnapshot.self, from: data)
}
```

- [ ] **Step 5: Implement namespaced iCloud storage and selected-provider persistence**

```swift
var selectedProvider: UsageProviderKind {
    get { UsageProviderKind(rawValue: defaults.string(forKey: "selectedProvider") ?? "") ?? .claudeCode }
    set { defaults.set(newValue.rawValue, forKey: "selectedProvider") }
}
```

- [ ] **Step 6: Run the tests to verify pass**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests`
Expected: PASS with provider-specific snapshot isolation.

- [ ] **Step 7: Commit**

```bash
git add Shared/Services/SharedDataStore.swift Shared/Services/CloudSyncService.swift Shared/Constants.swift ImpressionTests/ProviderSelectionTests.swift
git commit -m "refactor: namespace persistence by usage provider"
```

### Task 3: Wrap Existing Claude Logic In A Provider

**Files:**
- Create: `Shared/Services/ClaudeUsageProvider.swift`
- Modify: `Shared/ViewModels/UsageViewModel.swift`
- Test: `ImpressionTests/UsageDataParsingTests.swift`

- [ ] **Step 1: Write a failing Claude normalization test**

```swift
func testClaudeProviderMapsOAuthResponseToPrimaryAndSecondaryQuota() async throws {
    let provider = ClaudeUsageProvider(session: .mockingOAuthUsage(...))
    let snapshot = try await provider.fetch()
    XCTAssertEqual(snapshot.provider, .claudeCode)
    XCTAssertEqual(snapshot.primaryQuotaLabel, "Session (5h)")
    XCTAssertEqual(snapshot.secondaryQuotaLabel, "Weekly (7d)")
}
```

- [ ] **Step 2: Run the test to verify failure**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/UsageDataParsingTests/testClaudeProviderMapsOAuthResponseToPrimaryAndSecondaryQuota`
Expected: FAIL because `ClaudeUsageProvider` does not exist.

- [ ] **Step 3: Move Claude fetch logic into a provider**

```swift
struct ClaudeUsageProvider: UsageProvider {
    let kind: UsageProviderKind = .claudeCode

    func fetch(using token: String) async throws -> UsageSnapshot {
        // keep existing oauth + message-header logic and map to shared fields
    }
}
```

- [ ] **Step 4: Update the view model to call the selected provider**

```swift
private func provider(for kind: UsageProviderKind) -> any UsageProvider {
    switch kind {
    case .claudeCode: claudeProvider
    case .codexCLI: codexProvider
    }
}
```

- [ ] **Step 5: Run the targeted tests**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/UsageDataParsingTests`
Expected: PASS for Claude provider normalization coverage.

- [ ] **Step 6: Commit**

```bash
git add Shared/Services/ClaudeUsageProvider.swift Shared/ViewModels/UsageViewModel.swift ImpressionTests/UsageDataParsingTests.swift
git commit -m "refactor: move Claude usage fetch into provider"
```

### Task 4: Implement Codex Provider Discovery And Normalization

**Files:**
- Create: `Shared/Services/CodexUsageProvider.swift`
- Modify: `Shared/Constants.swift`
- Test: `ImpressionTests/CodexUsageProviderTests.swift`

- [ ] **Step 1: Write failing Codex provider tests**

```swift
func testCodexProviderPrefersOfficialSourceWhenAvailable() async throws {
    let provider = CodexUsageProvider(discovery: .mock(officialUsage: .sample))
    let snapshot = try await provider.fetch()
    XCTAssertEqual(snapshot.provider, .codexCLI)
    XCTAssertEqual(snapshot.confidence, .official)
}

func testCodexProviderFallsBackToLocalSource() async throws {
    let provider = CodexUsageProvider(discovery: .mock(localUsage: .sample))
    let snapshot = try await provider.fetch()
    XCTAssertEqual(snapshot.confidence, .localFallback)
}
```

- [ ] **Step 2: Run the tests to verify failure**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/CodexUsageProviderTests`
Expected: FAIL because Codex provider/discovery types are missing.

- [ ] **Step 3: Add Codex discovery constants and shell/file discovery helpers**

```swift
enum CodexDiscoveryPath {
    static let binary = "/Users/minghsuan/.nvm/versions/node/v20.19.0/bin/codex"
    static let homeDirectory = NSHomeDirectory() + "/.codex"
}
```

- [ ] **Step 4: Implement official-first Codex provider**

```swift
struct CodexUsageProvider: UsageProvider {
    func fetch(using token: String?) async throws -> UsageSnapshot {
        if let official = try await readOfficialUsage() { return normalize(official, confidence: .official) }
        if let local = try readLocalUsage() { return normalize(local, confidence: .localFallback) }
        throw CodexUsageError.noSupportedSource
    }
}
```

- [ ] **Step 5: Ensure normalization stays quota-oriented**

```swift
private func normalize(_ usage: CodexUsageSample, confidence: SnapshotConfidence) -> UsageSnapshot {
    UsageSnapshot(
        provider: .codexCLI,
        primaryUsagePercent: usage.primaryPercent,
        primaryQuotaLabel: usage.primaryLabel,
        primaryResetAt: usage.primaryResetAt,
        secondaryUsagePercent: usage.secondaryPercent,
        secondaryQuotaLabel: usage.secondaryLabel,
        secondaryResetAt: usage.secondaryResetAt,
        remainingText: usage.remainingText,
        fetchedAt: .now,
        source: usage.source,
        confidence: confidence
    )
}
```

- [ ] **Step 6: Run Codex provider tests**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/CodexUsageProviderTests`
Expected: PASS for official-source-first and local fallback behavior.

- [ ] **Step 7: Commit**

```bash
git add Shared/Services/CodexUsageProvider.swift Shared/Constants.swift ImpressionTests/CodexUsageProviderTests.swift
git commit -m "feat: add codex usage provider discovery"
```

### Task 5: Add Provider Switching To The App

**Files:**
- Modify: `Shared/ViewModels/UsageViewModel.swift`
- Modify: `ImpressionMobile/ContentView.swift`
- Modify: `ImpressionMac/SettingsView.swift`
- Test: `ImpressionTests/ProviderSelectionTests.swift`

- [ ] **Step 1: Write failing provider-switch UI/view model tests**

```swift
func testSelectingCodexUpdatesPersistedProvider() {
    let viewModel = UsageViewModel()
    viewModel.selectProvider(.codexCLI)
    XCTAssertEqual(viewModel.selectedProvider, .codexCLI)
}
```

- [ ] **Step 2: Run the targeted test**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests/testSelectingCodexUpdatesPersistedProvider`
Expected: FAIL because provider selection APIs are missing.

- [ ] **Step 3: Add provider selection APIs to the view model**

```swift
var selectedProvider: UsageProviderKind

func selectProvider(_ provider: UsageProviderKind) {
    selectedProvider = provider
    dataStore.selectedProvider = provider
    Task { await fetchOnce() }
}
```

- [ ] **Step 4: Add segmented provider switching in app UI**

```swift
Picker("Provider", selection: $selectedProvider) {
    ForEach(UsageProviderKind.allCases, id: \.self) { provider in
        Text(provider.displayName).tag(provider)
    }
}
.pickerStyle(.segmented)
```

- [ ] **Step 5: Run focused tests and a build**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests`
Expected: PASS

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionMobile`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Shared/ViewModels/UsageViewModel.swift ImpressionMobile/ContentView.swift ImpressionMac/SettingsView.swift ImpressionTests/ProviderSelectionTests.swift
git commit -m "feat: add provider switching to app surfaces"
```

### Task 6: Add Provider Themes To App And Widget Views

**Files:**
- Modify: `Shared/Models/UsageProvider.swift`
- Modify: `ImpressionMobile/ContentView.swift`
- Modify: `ImpressionWidget/UsageWidgetEntryView.swift`
- Test: `ImpressionTests/ProviderSelectionTests.swift`

- [ ] **Step 1: Write failing theme tests**

```swift
func testCodexThemeUsesDistinctBrandName() {
    XCTAssertEqual(UsageProviderKind.codexCLI.theme.name, "Codex")
}
```

- [ ] **Step 2: Run the targeted test**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests/testCodexThemeUsesDistinctBrandName`
Expected: FAIL because theme metadata is incomplete.

- [ ] **Step 3: Add provider theme metadata**

```swift
extension UsageProviderKind {
    var theme: ProviderTheme {
        switch self {
        case .claudeCode: ProviderTheme(name: "Claude", accentHex: "#D97757", warningHex: "#D94841")
        case .codexCLI: ProviderTheme(name: "Codex", accentHex: "#0F766E", warningHex: "#115E59")
        }
    }
}
```

- [ ] **Step 4: Bind views to provider theme instead of fixed labels**

```swift
Text(viewModel.selectedProvider.displayName)
    .foregroundStyle(viewModel.theme.accentColor)
```

- [ ] **Step 5: Run tests and build widget target**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests`
Expected: PASS

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionWidgetMac`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/UsageProvider.swift ImpressionMobile/ContentView.swift ImpressionWidget/UsageWidgetEntryView.swift ImpressionTests/ProviderSelectionTests.swift
git commit -m "feat: add provider themes for app and widgets"
```

### Task 7: Make Widget Reads Provider-Aware

**Files:**
- Modify: `ImpressionWidget/UsageTimelineProvider.swift`
- Modify: `ImpressionWidget/UsageWidget.swift`
- Modify: `Shared/Services/SharedDataStore.swift`
- Test: `ImpressionTests/ProviderSelectionTests.swift`

- [ ] **Step 1: Write failing widget namespace tests**

```swift
func testWidgetLoadsSelectedProviderSnapshot() {
    let provider = UsageProviderKind.codexCLI
    let snapshot = UsageSnapshot.empty.withProvider(provider)
    SharedDataStore.shared.writeSnapshot(snapshot, for: provider)
    XCTAssertEqual(SharedDataStore.shared.readSnapshot(for: provider)?.provider, .codexCLI)
}
```

- [ ] **Step 2: Run the test to verify failure or missing widget configuration support**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac -only-testing:ImpressionTests/ProviderSelectionTests/testWidgetLoadsSelectedProviderSnapshot`
Expected: FAIL until provider-specific widget reading is wired through.

- [ ] **Step 3: Add widget provider configuration**

```swift
struct UsageWidgetConfiguration: Codable, Equatable {
    let provider: UsageProviderKind
}
```

- [ ] **Step 4: Update timeline provider to read the correct namespace**

```swift
private func loadBestSnapshot(for provider: UsageProviderKind) -> UsageSnapshot {
    if let local = dataStore.readSnapshot(for: provider) { return local }
    if let cloud = cloudSync.readSnapshot(for: provider) { return cloud }
    return .empty.withProvider(provider)
}
```

- [ ] **Step 5: Build and verify widget target**

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionWidgetMac`
Expected: BUILD SUCCEEDED

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionMobile`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add ImpressionWidget/UsageTimelineProvider.swift ImpressionWidget/UsageWidget.swift Shared/Services/SharedDataStore.swift ImpressionTests/ProviderSelectionTests.swift
git commit -m "feat: make widget timeline provider-aware"
```

### Task 8: Add AppleScript Rebuild Automation

**Files:**
- Create: `scripts/rebuild_xcode.applescript`
- Modify: `README.md`
- Test: manual script run

- [ ] **Step 1: Write the AppleScript automation file**

```applescript
tell application "Xcode"
    activate
    open POSIX file "/Users/minghsuan/Documents/Impression/Impression.xcodeproj"
    delay 2
    tell workspace document 1
        set active scheme to scheme "ImpressionMac"
    end tell
end tell
```

- [ ] **Step 2: Add clean/build/test automation steps**

```applescript
tell application "System Events"
    tell process "Xcode"
        keystroke "k" using {command down, shift down}
        delay 1
        keystroke "b" using {command down}
    end tell
end tell
```

- [ ] **Step 3: Run the script manually**

Run: `osascript scripts/rebuild_xcode.applescript`
Expected: Xcode opens the project, performs clean build, and leaves the target workspace active.

- [ ] **Step 4: Document the script**

```markdown
`osascript scripts/rebuild_xcode.applescript` rebuilds the project through Xcode UI automation before final verification.
```

- [ ] **Step 5: Commit**

```bash
git add scripts/rebuild_xcode.applescript README.md
git commit -m "chore: add applescript xcode rebuild automation"
```

### Task 9: Full Verification, Review, And GitHub Workflow

**Files:**
- Modify: any files needed for bug fixes discovered during verification
- Create: issue / PR metadata as needed

- [ ] **Step 1: Run the full AppleScript-driven rebuild**

Run: `osascript scripts/rebuild_xcode.applescript`
Expected: Xcode completes clean rebuild without blocking errors.

- [ ] **Step 2: Run full automated tests**

Run: `xcodebuild test -project Impression.xcodeproj -scheme ImpressionMac`
Expected: TEST SUCCEEDED

- [ ] **Step 3: Build widget targets and inspect for regressions**

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionWidgetMac`
Expected: BUILD SUCCEEDED

Run: `xcodebuild build -project Impression.xcodeproj -scheme ImpressionMobile`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Fix any widget or provider regressions found and rerun verification**

```bash
git add <fixed files>
git commit -m "fix: resolve provider or widget verification regressions"
```

- [ ] **Step 5: Run code review**

Run: `codex review --help`
Expected: Confirm review command usage, then run the appropriate non-interactive review command against the current branch or diff.

- [ ] **Step 6: Create issue and PR if GitHub tooling is available**

Run: `gh issue create --title "Add Codex CLI provider to Impression" --body-file /tmp/impression-issue.md`
Expected: issue URL output

Run: `gh pr create --title "Add multi-provider usage monitoring" --body-file /tmp/impression-pr.md`
Expected: PR URL output

- [ ] **Step 7: Merge if branch protections and permissions allow**

Run: `gh pr merge --squash --delete-branch`
Expected: merge confirmation

- [ ] **Step 8: Final closeout**

```bash
git status --short
git log --oneline -5
```

Expected: clean working tree or only intentional post-merge state.

## Self-Review

Spec coverage:
- Provider abstraction is covered in Tasks 1, 3, and 4.
- Provider-aware persistence and widget isolation are covered in Tasks 2 and 7.
- App switching and theme changes are covered in Tasks 5 and 6.
- AppleScript rebuild, testing, widget verification, review, issue, PR, and merge are covered in Tasks 8 and 9.

Placeholder scan:
- The plan avoids `TODO`, `TBD`, and vague "handle this later" instructions.
- Every task includes concrete files, commands, and expected outputs.

Type consistency:
- `UsageProviderKind`, `ProviderTheme`, `UsageSnapshot`, `ClaudeUsageProvider`, and `CodexUsageProvider` are introduced before later tasks rely on them.
