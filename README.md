# GACA for iPhone

The iPhone client for gaca-api, next to `gaca` (API and web) and `gaca-android`. It covers
everything the Android app does (Chat, Today, Inbox, Artifacts, Skills, Settings) and adds
the redesigned chat described in `gaca/gaca-planning/chat/design.md`.

**A thin client by design.** The app keeps no logic or data of its own. Labels, previews,
activity summaries, resolved artifact links, data rows and the artifact page wrapper all
come from gaca-api, so every client shows the same thing. If the app needs something new,
change the API rather than computing it here.

## Build

Requirements: Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate            # after adding/removing files or changing project.yml
open Gaca.xcodeproj
```

Command line:

```bash
xcodebuild -project Gaca.xcodeproj -scheme Gaca \
  -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

## Configuration

There's no sign-in and no built-in server address. On first launch the app pairs with a
server: run `gaca-api pair` on the server, then scan the QR code it shows (or tap its
`gaca://setup` link, or type the address and code). Settings › Disconnect makes the server
forget this phone. Plain-http addresses are accepted only in debug builds.

| What | Where |
|---|---|
| Signing team (real devices, push) | `project.yml` → `DEVELOPMENT_TEAM` (29PC3482HK) |
| Bundle id | `dev.monts.gaca` (same as Android). gaca-api's `GACA_APNS_TOPIC` must match |

Push notifications go straight from gaca-api to Apple (APNs). Debug builds register their
token as `sandbox`, release builds as `production`. See gaca-api's `.env.example` for the
`GACA_APNS_*` settings.

## Testing against a local API with a fake agent

`tools/fake_hermes.py` stands in for a Hermes gateway. It produces tool activity, streamed
replies, failures and artifact links, so the full chat flow can be tested without a real
agent:

```bash
uv run --project ../gaca/gaca-api python tools/fake_hermes.py --port 18642
```

`tools/e2e.sh` starts a throwaway gaca-api and the fake agent, pairs with the server using
`gaca-api pair`, seeds data, and runs the UI tests (including the pairing screen) against them.

## Layout

- `Gaca/App`: entry point, push handling, tabs, navigation
- `Gaca/Core`: API client, wire models, SSE event stream, Keychain/settings
- `Gaca/Design`: palette and shared components
- `Gaca/Features/*`: one folder per area (Pairing, Chat, Today, Inbox, Artifacts, Skills, Crew, Settings)
- `GacaTests`: unit tests; `GacaUITests`: end-to-end tests against a local API
