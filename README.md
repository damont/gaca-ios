# GACA for iPhone

The iPhone client for gaca-api, next to [`gaca`](https://github.com/damont/gaca) (the API and installer) and [`gaca-android`](https://github.com/damont/gaca-android). It covers
everything the Android app does (Chat, Today, Inbox, Artifacts, Skills, Settings) and adds
the redesigned chat described in [`docs/chat-design.md`](https://github.com/damont/gaca/blob/main/docs/chat-design.md) in the gaca repo.

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

### Signing and sideloading

Nobody's team or signing setup is checked in. A fresh clone builds for the simulator as-is.
To put it on your own iPhone, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
(git ignores it) and set:

| Setting | What |
|---|---|
| `DEVELOPMENT_TEAM` | Your Apple Team ID (developer.apple.com/account › Membership details) |
| `PRODUCT_BUNDLE_IDENTIFIER` | Must be unique to you, e.g. `com.yourname.gaca` |
| `CODE_SIGN_ENTITLEMENTS` + `GACA_PUSH_ENABLED` | Push is on by default and needs a paid developer team. With a free Apple ID, set `Gaca/Resources/Basic.entitlements` and `NO` (the app then runs without notifications) |

Then pick your iPhone in Xcode and press Run. Apps signed with a free Apple ID expire after 7
days. Rebuild to renew.

Push notifications go straight from gaca-api to Apple (APNs). The server needs an APNs key
from the team that signed the app, and `GACA_APNS_TOPIC` must equal the bundle id. Debug builds register their token as `sandbox`, release builds as `production`. See
gaca-api's `.env.example` for the `GACA_APNS_*` settings. A build without push works
normally and doesn't ask for notification permission.

## Push notifications: the secrets involved

Alerts always show in the app when you open it. For them to buzz your phone, the **server** sends each one to Apple
(APNs) itself, so these pieces have to line up. Only the key is secret.

| piece | what it is | where it goes |
|---|---|---|
| Apple Developer team | the paid account that signs the app; its **Team ID** (10 characters, Membership page) | `project.yml` → `DEVELOPMENT_TEAM`; also given to the server |
| Bundle id | `dev.monts.gaca` unless you change it; the app needs the **Push Notifications** capability | the server's `GACA_APNS_TOPIC` must be exactly this |
| APNs key | a `.p8` file from developer.apple.com → Keys, with *Apple Push Notifications service* ticked. **Apple lets you download it once**, so keep it safe | on the server only, never in this repo or the app |
| Key ID | the 10-character id shown next to that key | given to the server |

On the server run `gaca-api push ios` (it asks for the `.p8` file, Key ID, Team ID and bundle id), or answer the installer's push
question. The server stores the key in `~/.config/gaca/secrets/` with owner-only permissions. `gaca-api push status` shows what is on.
The key must belong to the same team that signed the app: if you use someone else's build, you can pair and see alerts but cannot
push to it. Debug builds register as APNs `sandbox` and release builds as `production`; the server handles both.

More in the [gaca README](https://github.com/damont/gaca#push-notifications-optional).

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

## License

Apache License 2.0 (see [`LICENSE`](LICENSE)). Copyright 2026 David Monts. Report security problems privately: see [`SECURITY.md`](SECURITY.md).
