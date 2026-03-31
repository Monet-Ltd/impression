# Impression

Native Apple app for monitoring Claude Code usage limits in real-time. Track your 5-hour session and 7-day weekly quotas with desktop/home screen widgets and smart notifications — on iPhone, iPad, and Mac.

## Why Impression?

Claude Code users on Pro/Max plans have session and weekly usage limits, but there's no easy way to check them without running `/usage` inside Claude Code. Existing tools are macOS-only menu bar apps with no widgets.

**Impression is the first universal Apple app** with:
- WidgetKit widgets on every platform (home screen, desktop, lock screen)
- Smart notifications that fire exactly when your limits reset
- Cross-device sync via iCloud

## Features

### Mac
- **Menu Bar** — Color-coded icon showing session usage at a glance
- **Popover** — Detailed view with session, weekly, Opus, and Sonnet breakdowns
- **Desktop Widget** — Small (dual rings) and Medium (progress bars) sizes
- **Zero-config** — Automatically reads `~/.claude/.credentials.json`

### iPhone & iPad
- **Home Screen Widgets** — Small, Medium, Large sizes
- **Lock Screen Widgets** — Circular gauge and rectangular bar
- **Smart Notifications** — "Session reset!" exactly when `resets_at` arrives
- **iCloud Sync** — Token syncs from Mac automatically, or paste manually for Linux users

### Cross-Device
- Usage data syncs via `NSUbiquitousKeyValueStore` (~10-20s)
- Token syncs via iCloud Keychain (encrypted)
- Every device fetches independently — no dependency on another device being online

## Screenshots

> *Coming soon after first Xcode build*

## How It Gets Your Data

Impression uses a **hybrid API strategy** to handle Anthropic's aggressive rate limiting:

1. **Primary:** `GET /api/oauth/usage` — free, returns utilization % and reset timestamps
2. **Fallback:** `POST /v1/messages` with `max_tokens=1` — parses rate-limit headers (costs ~$0.26/year)

The OAuth token is read from Claude Code's local credentials file. Impression only performs **read-only monitoring** — it never generates text or uses your quota.

## Setup

### Prerequisites
- macOS 14+ (Sonoma), iOS 17+, iPadOS 17+
- Xcode 16+
- Apple Developer account (for iCloud + Keychain entitlements)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build

```bash
# Clone
git clone git@github.com:Monet-Ltd/impression.git
cd impression

# Set your Development Team ID in project.yml
# Look for DEVELOPMENT_TEAM: "" and fill in your team ID

# Generate Xcode project
xcodegen generate

# Open in Xcode
open Impression.xcodeproj
```

Select the **ImpressionMac** scheme to build the macOS menu bar app, or **ImpressionMobile** for iOS/iPad.

### Authentication

**Mac (zero-config):**
Just make sure you're logged into Claude Code (`claude login`). Impression auto-detects the token.

**iPhone/iPad (with Mac):**
Install Impression on both devices with the same iCloud account. Token syncs automatically.

**iPhone/iPad (Linux user):**
```bash
cat ~/.claude/.credentials.json
```
Copy the entire JSON output and paste it in the app's onboarding flow.

## Project Structure

```
Impression/
├── Shared/                  # Cross-platform code
│   ├── Models/              # UsageData, Credentials
│   ├── Services/            # UsageService, CloudSync, Notifications
│   ├── ViewModels/          # UsageViewModel
│   └── Views/               # UsageRingView, UsageBarView, UsageDetailView
├── ImpressionMac/           # macOS menu bar app
├── ImpressionMobile/        # iOS/iPad app
├── ImpressionWidget/        # WidgetKit extension (universal)
├── ImpressionTests/         # Unit tests
└── project.yml              # XcodeGen configuration
```

## Tech Stack

- **Swift 6** + **SwiftUI**
- **WidgetKit** — Home screen, desktop, and lock screen widgets
- **UserNotifications** — Scheduled reset alerts and threshold warnings
- **iCloud Keychain** — Encrypted cross-device token sync
- **NSUbiquitousKeyValueStore** — Cross-device usage data sync
- **Zero third-party dependencies**

## Known Limitations

- The `/api/oauth/usage` endpoint is **undocumented** and may change without notice
- Anthropic [banned third-party OAuth usage](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/) in Feb 2026. Impression only reads local credentials for read-only monitoring (same approach as [Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) and similar tools)
- iOS manual token paste expires in ~24h; the app reminds you to refresh
- WidgetKit has a minimum ~5 minute refresh interval (system-throttled)

## License

MIT
