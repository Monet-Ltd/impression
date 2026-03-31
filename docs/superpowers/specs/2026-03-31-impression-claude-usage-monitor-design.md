# Impression — Claude Code Usage Monitor (iPhone / iPad / Mac)

**Date:** 2026-03-31
**Status:** Design Complete

## Problem Statement

Claude Code users on Pro/Max plans have two usage limits:
- **5-hour session limit** — rolling window, resets after the window expires
- **7-day weekly limit** — rolling weekly allocation (separate buckets for Sonnet/Opus)

There is no native way to:
1. See remaining quota at a glance without opening Claude Code and running `/usage`
2. Get notified when a limit resets (so you know you can resume work)
3. Have a persistent widget on any Apple device showing real-time usage

Existing third-party tools (Claude-Usage-Tracker, ClaudeBar, claude-monitor) are all **macOS-only menu-bar apps**. None offer:
- WidgetKit desktop/home screen widgets
- iPhone or iPad support
- Precise reset-time notifications
- Cross-device sync

**Our differentiator: the first universal Apple app (iPhone + iPad + Mac) for Claude usage tracking with widgets and smart notifications on every device.**

## Solution

A universal SwiftUI app with platform-adaptive surfaces:

| Platform | Surfaces |
|----------|---------|
| **Mac** | Menu Bar icon + popover, desktop Widget (small/medium), notifications |
| **iPhone** | Home screen Widget (small/medium/lock screen), notifications, compact app view |
| **iPad** | Home screen Widget (small/medium/large/extra-large), notifications, app view |

## Authentication Constraints

**Important:** Anthropic [banned third-party apps from using Claude OAuth tokens](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/) in Feb 2026. We cannot implement an in-app OAuth login flow. However, existing apps like Claude-Usage-Tracker continue to operate by only **reading** local credentials for **read-only monitoring** (no text generation). This is a gray area; our app follows the same pattern.

**Consequence:** Token acquisition always originates from a computer running Claude Code (Mac or Linux). The app cannot create tokens itself.

## Cross-Device Architecture

Every device can operate independently. No device depends on another being online.

```
                    ┌──────────────────────┐
                    │   iCloud Sync Layer   │
                    │                      │
                    │  Keychain (token)    │◄── encrypted, auto-sync
                    │  KV Store (usage)    │◄── NSUbiquitousKeyValueStore
                    └───┬──────┬──────┬───┘
                        │      │      │
           ┌────────────▼┐ ┌──▼──────▼──────────┐
           │    macOS     │ │  iPhone / iPad      │
           │              │ │                     │
           │ Auto-read    │ │ Token Source:        │
           │ creds.json   │ │  1. iCloud Keychain  │
           │ → Keychain   │ │  2. Manual paste     │
           │ → KV Store   │ │                     │
           │              │ │ Data Source:          │
           │ Menu Bar     │ │  1. Own API fetch    │
           │ Widget       │ │  2. iCloud KV cache  │
           │ Notifications│ │                     │
           └──────────────┘ │ Widget              │
                            │ App View            │
                            │ Notifications       │
                            └─────────────────────┘
```

### Authentication by User Scenario

| User Has | Auth Method | Token Refresh |
|----------|------------|---------------|
| **Mac only** | Auto-read `~/.claude/.credentials.json` (zero-config) | Claude Code handles refresh; FileSystemMonitor re-reads |
| **Mac + iPhone/iPad** | Mac auto-reads → iCloud Keychain syncs to mobile | Mac keeps token fresh; mobile devices always current |
| **iPhone/iPad only (Linux user)** | Manual token paste: `cat ~/.claude/.credentials.json` on Linux, paste in app | User must re-paste when token expires (~24h). App shows expiry countdown + reminder notification |
| **iPhone/iPad only (no computer)** | Not our target user — Claude Code requires Mac/Linux | Onboarding explains this clearly |

### Data Sync Strategy

**Any device with a valid token fetches independently:**
1. Fetches usage data every 120s (Timer on macOS, BGAppRefreshTask on iOS)
2. Writes `UsageData` snapshot to **App Group UserDefaults** (local widget) AND **NSUbiquitousKeyValueStore** (cross-device)
3. Reads from iCloud KV store as fallback when own fetch fails

**Mac additionally:**
1. Reads `~/.claude/.credentials.json` and stores token in **iCloud Keychain** (syncs to all devices)
2. Monitors file changes with `DispatchSource.makeFileSystemObjectSource` — auto-updates on token refresh

**iPhone/iPad additionally:**
1. Checks iCloud Keychain first for token (from Mac sync)
2. Falls back to locally-stored manual token
3. Shows "Token expires in X hours" banner for manually-pasted tokens
4. Sends reminder notification before token expiry

**Conflict resolution:** Last-writer-wins on NSUbiquitousKeyValueStore. All devices fetch the same API data, so conflicts are harmless (same data, slightly different timestamps).

## Project Structure

```
Impression/
├── Impression.xcodeproj
│
├── Shared/                              ← Shared across all targets
│   ├── Models/
│   │   ├── UsageData.swift              — Codable model for API response
│   │   ├── Credentials.swift            — Codable model for credentials.json
│   │   └── UsageSnapshot.swift          — Lightweight Codable for iCloud KV store
│   ├── Services/
│   │   ├── UsageService.swift           — Hybrid API fetch (primary + fallback)
│   │   ├── CloudSyncService.swift       — iCloud Keychain + KV store read/write
│   │   └── NotificationScheduler.swift  — UNCalendarNotificationTrigger from resets_at
│   ├── ViewModels/
│   │   └── UsageViewModel.swift         — @Observable, platform-adaptive
│   ├── Views/
│   │   ├── UsageRingView.swift          — Reusable circular gauge (SwiftUI)
│   │   ├── UsageBarView.swift           — Reusable progress bar
│   │   └── UsageDetailView.swift        — Full detail view (shared layout)
│   └── Constants.swift                  — App Group ID, API URLs, iCloud keys
│
├── ImpressionMac/                       ← macOS-specific
│   ├── MacApp.swift                     — @main with NSApplicationDelegateAdaptor
│   ├── AppDelegate.swift                — NSStatusBar, menu bar lifecycle
│   ├── CredentialManager.swift          — Read + watch ~/.claude/.credentials.json
│   ├── MenuBarIcon.swift                — Dynamic SF Symbol with color ring
│   ├── UsagePopoverView.swift           — Popover panel
│   ├── OnboardingView.swift             — "Run claude login" guide
│   └── SettingsView.swift               — macOS settings (Preferences window)
│
├── ImpressionMobile/                    ← iOS/iPadOS-specific
│   ├── MobileApp.swift                  — @main with standard SwiftUI lifecycle
│   ├── ContentView.swift                — Main app view (usage dashboard)
│   ├── OnboardingView.swift             — Decision tree: "Sync from Mac" or "Paste Token"
│   └── SettingsView.swift               — iOS settings
│
├── ImpressionWidget/                    ← WidgetKit extension (universal)
│   ├── UsageWidget.swift                — WidgetBundle (works on all platforms)
│   ├── UsageTimelineProvider.swift      — Reads from App Group + iCloud KV store
│   ├── SmallUsageWidgetView.swift       — Dual rings (iPhone/Mac/iPad)
│   ├── MediumUsageWidgetView.swift      — Bars + details
│   ├── LargeUsageWidgetView.swift       — iPad extra detail
│   └── LockScreenWidgetView.swift       — iOS lock screen (accessory circular/rectangular)
│
└── ImpressionTests/
    ├── UsageDataParsingTests.swift
    ├── UsageServiceTests.swift
    └── ThresholdLogicTests.swift
```

## API Details

### Primary: OAuth Usage Endpoint

```
GET https://api.anthropic.com/api/oauth/usage

Headers:
  Accept: application/json
  Content-Type: application/json
  Authorization: Bearer {accessToken}
  anthropic-beta: oauth-2025-04-20
  User-Agent: Impression/1.0

Response 200:
{
  "five_hour": {
    "utilization": 42.5,          // percentage (0-100)
    "resets_at": "2026-03-31T15:30:00.000Z"  // ISO 8601
  },
  "seven_day": {
    "utilization": 15.0,
    "resets_at": "2026-04-03T08:00:00.000Z"
  },
  "seven_day_opus": {
    "utilization": 8.0,
    "resets_at": "2026-04-03T08:00:00.000Z"
  },
  "seven_day_sonnet": {
    "utilization": 3.0,
    "resets_at": "2026-04-03T08:00:00.000Z"
  }
}

Known issue: Returns 429 aggressively (GitHub issues #31021, #31637).
```

### Fallback: Messages API Header Parsing

```
POST https://api.anthropic.com/v1/messages

Headers:
  Authorization: Bearer {accessToken}
  anthropic-version: 2023-06-01
  anthropic-beta: oauth-2025-04-20
  User-Agent: Impression/1.0
  Content-Type: application/json

Body:
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 1,
  "messages": [{ "role": "user", "content": "." }]
}

Response headers to parse:
  anthropic-ratelimit-unified-5h-utilization: 0.425    // 0.0 - 1.0 scale
  anthropic-ratelimit-unified-7d-utilization: 0.15

Trade-off: ~2 tokens per call (~$0.000001). At 720 calls/day, yearly cost ~$0.26.
Note: No resets_at in headers; use last cached value from primary endpoint.
```

### Fetch Strategy (per-platform)

```
          ┌─── macOS ───────────────────────────────────────┐
          │ Timer (every 120s, always running in menu bar)  │
          │   → Try GET /api/oauth/usage                    │
          │   → 429? Fallback to POST /v1/messages headers  │
          │   → Write to: App Group + iCloud KV + Keychain  │
          │   → Trigger: WidgetCenter.reloadTimelines()     │
          │   → Schedule: NotificationScheduler(resets_at)  │
          └─────────────────────────────────────────────────┘

          ┌─── iOS/iPadOS ─────────────────────────────────┐
          │ Foreground: Timer (every 120s while app is open)│
          │ Background: BGAppRefreshTask (system-scheduled) │
          │   → Read token from iCloud Keychain             │
          │   → Same fetch strategy as macOS                │
          │   → Write to: App Group + iCloud KV             │
          │   → Trigger: WidgetCenter.reloadTimelines()     │
          │   → Schedule: NotificationScheduler(resets_at)  │
          │                                                 │
          │ Widget Timeline: reads App Group + iCloud KV    │
          │   → Fallback chain: local App Group → iCloud KV │
          └─────────────────────────────────────────────────┘
```

### Credential Source

```
macOS reads from: ~/.claude/.credentials.json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "sk-ant-ort01-...",
    "expiresAt": 1711929600000,     // Unix ms
    "scopes": ["user:profile", ...]
  }
}

macOS then stores accessToken in iCloud Keychain:
  Service: "com.impression.claude-token"
  Account: "default"
  Sync: kSecAttrSynchronizable = true

iOS/iPad reads from iCloud Keychain (auto-synced).
```

## Credential UX (Every Device Works Independently)

### macOS Flow
| State | What User Sees | What Happens |
|-------|---------------|-------------|
| Fresh install, Claude Code logged in | Usage appears immediately | Auto-reads credentials.json → syncs to iCloud Keychain |
| Claude Code not logged in | Onboarding: "Run `claude login` in Terminal" | FileSystemMonitor waits for file creation |
| Token expires | Transparent | Claude Code refreshes → FileSystemMonitor re-reads → re-syncs |

### iPhone/iPad Flow (with Mac)
| State | What User Sees | What Happens |
|-------|---------------|-------------|
| Mac app synced | Usage appears immediately | Reads token from iCloud Keychain, fetches independently |
| Waiting for sync | "Syncing from Mac..." with spinner | Polls iCloud Keychain every 5s until token arrives |

### iPhone/iPad Flow (without Mac — e.g., Linux user)
| State | What User Sees | What Happens |
|-------|---------------|-------------|
| First launch | Onboarding with 2 options: "Sync from Mac" or "Paste Token" | Clear choice based on user's setup |
| Paste token | Step-by-step guide: `cat ~/.claude/.credentials.json` → copy accessToken → paste | Token stored in local Keychain |
| Token active | Usage works normally + banner: "Token expires in 23h" | Countdown to expiry |
| Token nearing expiry (2h) | Push notification: "Token expires soon — refresh in Terminal" | Reminder to re-paste |
| Token expired | Alert: "Token expired" + one-tap to paste new token | Quick re-auth flow |

### Onboarding Decision Tree (iPhone/iPad)

```
App Launch → "How do you use Claude Code?"
    │
    ├── "On my Mac" → "Great! Install Impression on Mac too — your token will sync automatically via iCloud"
    │                   [Waiting for iCloud Keychain...]
    │
    └── "On Linux / other" → "Paste your token"
                               Step 1: "Run this in your terminal:"
                                        cat ~/.claude/.credentials.json
                               Step 2: "Copy the ENTIRE JSON output and paste it below:"
                                        [  Paste JSON Here  ]
                                        (App parses accessToken + expiresAt automatically)
                               Step 3: "Connected! ✓ Token expires in ~24h. We'll remind you to refresh."
```

**Design principle:** Every device is a first-class citizen. Mac offers the best experience (zero-config + auto-refresh), but iPhone/iPad without Mac is fully functional with a simple paste flow.

## Widget Design

### iPhone Home Screen — Small (systemSmall)

```
┌───────────────────┐
│                   │
│    ╭─── 42% ───╮  │  ← Outer ring: 5h session
│    │  ╭ 15% ╮  │  │  ← Inner ring: 7d weekly
│    │  ╰─────╯  │  │
│    ╰───────────╯  │
│                   │
│  Session  2h 15m  │  ← Time until reset
│  Weekly   3d 5h   │
└───────────────────┘
```

### iPhone Home Screen — Medium (systemMedium)

```
┌─────────────────────────────────────────┐
│  Impression                    ◉ 42%    │
│                                         │
│  Session (5h)    ████████░░░░░  42%     │
│  Resets in 2h 15m                       │
│                                         │
│  Weekly (7d)     ██░░░░░░░░░░░  15%     │
│  Resets in 3d 5h                        │
│                                         │
│  Opus   █░░░░  8%    Sonnet ░░░░░  3%  │
└─────────────────────────────────────────┘
```

### iPhone Lock Screen — Circular (accessoryCircular)

```
  ╭─────╮
  │ 42% │  ← Session % with ring
  ╰─────╯
```

### iPhone Lock Screen — Rectangular (accessoryRectangular)

```
┌─────────────────┐
│ Session    42%   │
│ ████████░░░░░░  │
│ Weekly     15%   │
└─────────────────┘
```

### iPad Widget — Large (systemLarge)

```
┌─────────────────────────────────────────┐
│  Impression                             │
│                                         │
│     ╭─── 42% ───╮    ╭─── 15% ───╮     │
│     │  Session   │    │  Weekly    │     │
│     ╰───────────╯    ╰───────────╯     │
│     Resets: 2h 15m    Resets: 3d 5h     │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  Opus (7d)     ████░░░░░░░░░░░░  8%    │
│  Sonnet (7d)   █░░░░░░░░░░░░░░░  3%   │
│                                         │
│  Last updated: 2 min ago               │
└─────────────────────────────────────────┘
```

### macOS Desktop Widget

Same as iPhone small/medium layouts. Desktop widgets use the same WidgetKit code.

### Color Coding (all platforms)

| Utilization | Color | Meaning |
|------------|-------|---------|
| 0-60% | Green | Healthy |
| 60-80% | Yellow | Watch it |
| 80-95% | Orange | Running low |
| 95-100% | Red | Almost depleted |

## Menu Bar Design (macOS only)

### Icon States

| State | Icon | Color |
|-------|------|-------|
| 0-60% session | Circular gauge SF Symbol | Green tint |
| 60-80% | Same | Yellow tint |
| 80-95% | Same | Orange tint |
| 95-100% | `exclamationmark.circle.fill` | Red tint |
| API error | `wifi.exclamationmark` | Gray |
| No credentials | `person.crop.circle.badge.questionmark` | Gray |

### Popover Panel (click to open)

Shows:
- Session usage: ring + percentage + reset countdown
- Weekly usage: ring + percentage + reset countdown
- Opus weekly: bar + percentage
- Sonnet weekly: bar + percentage
- Last updated: relative timestamp
- Settings gear icon (bottom right)

## Notification Design

### Notification Types (all platforms)

| ID | Event | Title | Body | Trigger |
|----|-------|-------|------|---------|
| `session-reset` | 5h window resets | Session 額度已重置 | Claude Code 可以繼續使用了 | `UNCalendarNotificationTrigger(resets_at)` |
| `weekly-reset` | 7d window resets | Weekly 額度已重置 | 新的一週額度已開始 | `UNCalendarNotificationTrigger(resets_at)` |
| `session-80` | Session hits 80% | Session 已用 80% | 預估剩餘約 1 小時 | Threshold check |
| `session-95` | Session hits 95% | Session 即將耗盡 | {time} 後重置 | Threshold check |

### Scheduling Logic

```swift
func scheduleResetNotification(type: String, resetsAt: Date) {
    let content = UNMutableNotificationContent()
    content.title = type == "session" ? "Session 額度已重置" : "Weekly 額度已重置"
    content.body = "Claude Code 可以繼續使用了"
    content.sound = .default

    let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: resetsAt
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

    // Same ID replaces previous — safe to call repeatedly
    let request = UNNotificationRequest(
        identifier: "\(type)-reset",
        content: content,
        trigger: trigger
    )
    UNUserNotificationCenter.current().add(request)
}
```

## iOS App View (iPhone/iPad)

Since iOS doesn't have a menu bar, the app itself shows a simple dashboard:

```
┌─────────────────────────────────────────┐
│  Impression                    ⚙️       │
│                                         │
│     ╭─── 42% ───╮                       │
│     │  Session   │    Resets in 2h 15m  │
│     ╰───────────╯                       │
│                                         │
│     ╭─── 15% ───╮                       │
│     │  Weekly    │    Resets in 3d 5h   │
│     ╰───────────╯                       │
│                                         │
│  ─────────────────────────────────────  │
│  Opus (7d)     ████░░░░░░░░░  8%       │
│  Sonnet (7d)   █░░░░░░░░░░░░  3%      │
│                                         │
│  Updated 2 min ago        Refresh ↻    │
└─────────────────────────────────────────┘
```

The app is intentionally minimal — most users will interact via widgets and notifications, not the app itself.

## Settings (all platforms)

| Setting | Default | Options |
|---------|---------|---------|
| Refresh interval | 120 seconds | 60 / 120 / 300 seconds |
| Session warning threshold | 80% | 50-95% slider |
| Critical threshold | 95% | 80-100% slider |
| Notification: reset alerts | ON | Toggle |
| Notification: threshold alerts | ON | Toggle |
| Launch at login (macOS only) | OFF | Toggle |
| Show in Dock (macOS only) | OFF | Toggle (LSUIElement) |
| Manual token entry (iOS/iPad) | Visible in onboarding + Settings | Paste Token flow with expiry tracking |
| Token expiry reminder | ON | Notification 2h before manually-pasted token expires |

Settings sync via NSUbiquitousKeyValueStore across devices.

## Error Handling

| Error | Platform | Behavior |
|-------|----------|----------|
| 429 from /api/oauth/usage | All | Silent fallback to Messages API headers |
| 429 from Messages API | All | Exponential backoff: 2→4→8→16 min (cap). Show cached data with "Updated X min ago" |
| Network offline | All | Show cached data. Resume polling on reconnect. |
| Token expired | macOS | Claude Code auto-refreshes; FileSystemMonitor re-reads |
| Token expired | iOS/iPad (with Mac) | Mac auto-refreshes → iCloud Keychain syncs new token |
| Token expired | iOS/iPad (no Mac) | Alert: "Token expired" + quick re-paste flow + notification reminder 2h before expiry |
| credentials.json missing | macOS | Onboarding: "Run `claude login`" |
| iCloud Keychain empty | iOS/iPad | Onboarding decision tree: "Sync from Mac" or "Paste Token" |
| iCloud KV store stale | iOS/iPad | Fetch independently using synced token |
| Invalid JSON | All | Log error. Continue showing cached data. |

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI (universal, platform-adaptive)
- **Minimum OS:** macOS 14.0 (Sonoma), iOS 17.0, iPadOS 17.0
- **Frameworks:** WidgetKit, UserNotifications, BackgroundTasks (iOS), Security (Keychain), Foundation
- **Dependencies:** Zero third-party dependencies
- **Distribution:**
  - macOS: Non-sandboxed (needs ~/.claude/ access), Developer ID signed, Homebrew + GitHub Releases
  - iOS/iPad: App Store (sandboxed, iCloud Keychain for token access)
- **Entitlements:** iCloud (key-value store + keychain sharing), App Groups, Push Notifications, Background Modes (fetch) for iOS
- **Build:** Xcode 16+
- **Note:** macOS non-sandboxed apps CAN use iCloud Keychain with the keychain-access-groups entitlement and a provisioning profile. This requires Apple Developer Program membership.

## Testing Strategy

- **Unit tests:** UsageData parsing (both API response formats), credential parsing, threshold logic, iCloud snapshot serialization
- **Integration tests:** Mock URLProtocol for API call sequences (200, 429, fallback), iCloud KV store mock
- **Widget snapshot tests:** SwiftUI previews for all widget states across all sizes
- **Cross-device:** Manual test: Mac syncs token → iPhone picks up → widget shows data
- **Notification:** Manual test: verify notification fires at exact resets_at time

## Build Sequence

1. **Shared models + UsageService** — API integration, parsing, both fetch paths
2. **macOS menu bar + popover** — credential reading, timer, UI
3. **WidgetKit extension** — timeline provider, all widget sizes
4. **Notifications** — scheduler, threshold checks
5. **iCloud sync** — Keychain + KV store, cross-device flow
6. **iOS/iPad app** — dashboard view, background refresh, onboarding
7. **Lock screen widgets** — accessory circular/rectangular
8. **Polish** — error states, settings, launch-at-login
