# Mac App Store Release Plan

Status: **plan only — nothing submitted yet.** This documents what a Mac App
Store (MAS) build of CCTrans requires, what breaks under the mandatory App
Sandbox, and the exact submission pipeline. Direct distribution (DMG + brew +
Sparkle) stays the primary channel; MAS would be a second, reduced variant.

## TL;DR

The current app cannot ship to MAS as-is. Four things must change, in order of
pain:

| # | Today | MAS requirement | Plan |
|---|---|---|---|
| 1 | Sparkle self-update | Self-updating is forbidden; the store owns updates | Strip Sparkle from the MAS build (`MAS_BUILD` compile flag) |
| 2 | `NSEvent.addGlobalMonitorForEvents(.keyDown)` watches Cmd+C in other apps | Sandboxed apps do not receive global keyDown events; Input Monitoring is effectively unavailable to MAS apps | Use the existing `PasteboardMonitor` (polling, sandbox-safe) as the only double-copy trigger in the MAS build |
| 3 | Local Hy-MT2 models run through an external Python/uv backend process | Spawned processes inherit the sandbox; the backend, its venv, and HF caches live outside the container and die | MAS v1 ships OpenRouter-only; embedding a runtime inside the bundle is a separate, later project |
| 4 | No sandbox at all (Developer ID + hardened runtime only) | `com.apple.security.app-sandbox` entitlement is mandatory, on the main app and every nested binary (Tauri helper included) | New entitlements files + `build-mas.zsh` signing path |

Already MAS-compatible, no change needed:

- `Shift+Cmd+2` hotkey — Carbon `RegisterEventHotKey` works sandboxed.
- Screenshot translation — ScreenCaptureKit works sandboxed behind the Screen
  Recording permission prompt.
- OpenRouter networking — just needs the `network.client` entitlement.
- GitHub star prompt — `GitHubStarPromptPolicy` already detects the MAS
  receipt/sandbox and disables itself.
- LSUIElement menu-bar-only apps are allowed on MAS (review notes must tell
  the reviewer where the UI lives).

## 1. Accounts, certificates, identifiers

Apple Developer Program membership already exists (Developer ID signing runs
in CI). Additionally needed, all from the same account:

1. **Certificates** (Xcode → Settings → Accounts, or developer.apple.com):
   - `Apple Distribution` — signs the .app for MAS.
   - `Mac Installer Distribution` — signs the .pkg uploaded to App Store
     Connect. Neither exists in the current keychain/CI; Developer ID certs
     cannot be reused for MAS.
2. **App ID**: register `as.kargn.cctrans` explicitly (and
   `as.kargn.cctrans.tauri-helper` for the nested helper) with the App Sandbox
   capability.
3. **Provisioning profile**: type "Mac App Store", tied to the App ID and the
   Apple Distribution cert. Must be embedded as
   `Contents/embedded.provisionprofile` — direct distribution never needed
   this, so `build-app.zsh` has no support for it today.
4. **App Store Connect**: create the app record on bundle id
   `as.kargn.cctrans`. The name "CCTrans" must be unique store-wide.

## 2. Sandbox entitlements

Main app (`scripts/mas/CCTrans.entitlements`, new):

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
```

Notes:

- Screen Recording and Notifications are TCC prompts, not entitlements;
  nothing to declare beyond using the APIs.
- No file-access entitlements needed: settings, logs, and overrides under
  Application Support move into the sandbox container automatically
  (`~/Library/Containers/as.kargn.cctrans/...`). First MAS launch starts with
  fresh settings — acceptable, no migration planned.
- Tauri helper gets its own copy of the same two entitlements. It is launched
  via `NSWorkspace` as a separate app, so it cannot use
  `com.apple.security.inherit`; it must be a fully sandboxed app itself.
  Tauri 2 documents this path officially (App Store distribution guide).
- The WKWebView/Tauri runtime may additionally need
  `com.apple.security.files.user-selected.read-only` only if a file picker is
  ever exposed; today it is not.

## 3. Code changes (behind a `MAS_BUILD` compile flag)

`swift build -Xswiftc -DMAS_BUILD` plus `#if !MAS_BUILD` around:

1. **Sparkle**: `SPUStandardUpdaterController`, the "Check for Updates..."
   menu item, and the `Sparkle` import in `AppDelegate`. SwiftPM still links
   the package; the framework simply must not be embedded or referenced at
   runtime in the MAS bundle (build script omits `Sparkle.framework` and the
   `SUFeedURL`/`SUPublicEDKey` Info.plist keys).
2. **KeyboardMonitor**: do not start it; rely on `PasteboardMonitor`'s
   same-text-copied-twice detection (already implemented and tested) as the
   double-copy trigger. Menu copy still works, which the keyboard path never
   covered anyway.
3. **Local model provider**: hide `localHyMT2` from the provider/model UI and
   default to OpenRouter. Reuse `hasCompletedLocalModelSelection` semantics so
   the first-run local-model setup window never appears.
4. **Permission helper**: the Input Monitoring / Accessibility sections do not
   apply; only Screen Recording remains.

## 4. Build + package pipeline (`scripts/build-mas.zsh`, new)

Mirror `build-app.zsh`, with these differences:

1. `swift build -c release -Xswiftc -DMAS_BUILD`.
2. No Sparkle embedding, no rpath for it, no feed keys in Info.plist.
3. Embed the Mac App Store provisioning profile at
   `Contents/embedded.provisionprofile` (helper app gets its own).
4. Sign inside-out with `Apple Distribution`, passing the entitlements file at
   every `codesign` call (helper first, then the outer app). Hardened runtime
   is a Developer ID concept; for MAS the sandbox entitlement is what matters.
5. Build the installer package:

   ```sh
   productbuild --component dist-mas/CCTrans.app /Applications \
     --sign "3rd Party Mac Developer Installer: <name> (<team>)" \
     dist-mas/CCTrans.pkg
   ```

6. Validate locally before upload:

   ```sh
   codesign -dvv --entitlements - dist-mas/CCTrans.app   # sandbox=true everywhere
   xcrun stapler validate ...   # not needed: MAS pkgs are NOT notarized
   ```

   MAS uploads skip notarization entirely; App Review replaces it.

## 5. Upload and review

1. Upload the .pkg with the **Transporter** app (or `xcrun altool`'s
   replacement, the App Store Connect API / `fastlane deliver`; classic
   `altool --upload-app` is discontinued).
2. App Store Connect metadata:
   - Screenshots: 1280×800 / 1440×900 / 2560×1600 / 2880×1800 only.
   - Privacy policy URL (required) + privacy "nutrition label". CCTrans
     stores the OpenRouter key locally and sends translated text to
     OpenRouter — declare "data not collected by the developer" only if that
     stays true; otherwise declare third-party processing.
   - Category (Productivity or Utilities), free pricing, export compliance
     (uses only standard HTTPS → exempt).
3. **Review notes are critical** for this app:
   - It is LSUIElement: tell the reviewer the app lives in the menu bar and
     how to trigger a translation (copy the same text twice).
   - Explain the Screen Recording prompt (screenshot translation) — missing
     justification is a common 2.5.x rejection.
   - Provide a throwaway OpenRouter API key for the reviewer, or a demo mode;
     a translator that does nothing without a paid key risks a 2.1 "minimum
     functionality" rejection. **Decide before submission.**
4. TestFlight for macOS works for beta builds from the same .pkg pipeline if
   a staged rollout is wanted.

## 6. Known review risks

| Guideline | Risk | Mitigation |
|---|---|---|
| 2.4.5 App Sandbox | Any nested binary without the sandbox entitlement fails ingest automatically | Entitlements on app + helper + every executable |
| 2.5.2 downloaded code | Local model runtime downloads and runs code | Excluded from MAS v1 entirely |
| 2.1 minimum functionality | App is inert without an API key | Reviewer demo key in review notes |
| 5.1.1 permission purpose | Screen Recording without clear reason | Purpose explained in-app before prompting + review notes |
| 4.x design / discoverability | Menu-bar-only app "looks broken" | Review notes + first-launch onboarding window already exists |

## 7. Open decisions before any submission

1. MAS v1 feature cut confirmed as OpenRouter-only + pasteboard trigger only?
2. Free, or paid/IAP? (Free assumed throughout this plan.)
3. Reviewer access: demo key vs. limited built-in demo quota.
4. Whether the MAS variant is worth maintaining at all next to the
   self-updating direct build — every release doubles QA surface.
