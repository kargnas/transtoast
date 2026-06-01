# CopyTranslator Agent Guide

## Mission

CopyTranslator is a macOS menu-bar translator. Keep the app native-feeling, fast, and operationally clear. Preserve existing translation behavior while migrating UI surfaces to Tauri 2 + Rust + Svelte.

## Project Shape

- SwiftPM app remains the production shell until the Tauri shell fully replaces it.
- Bundle identifier must stay `as.kargn.copy-translator`.
- macOS target: macOS 15+, Swift 6.2 tools.
- Keep secrets out of Git. Never commit `.env.local`, token caches, or credential-bearing logs.

## Layout

- `Sources/CopyTranslatorCore/`: platform-light translation logic, settings defaults, model registry, language handling.
- `Sources/CopyTranslator/`: current AppKit shell, menu bar app, monitors, settings, permissions, request logs.
- `Tests/CopyTranslatorTests/`: Swift tests.
- `scripts/`: build/install/package helpers and local model runtimes.
- `src/`: Svelte settings UI for the Tauri migration.
- `src-tauri/`: Rust/Tauri backend and app configuration.
- `design/`: visual reference board. Treat it as required input for UI work.
- `DESIGN.md`: durable design contract. Update it when design decisions change.

## Commands

```sh
swift test
swift build
./scripts/run-dev.zsh --show-settings
npm install
npm run check
npm run build
npm run tauri dev
cd src-tauri && cargo test
```

## Defaults And Behavior

- Default UI language: English.
- Default translation target: Korean.
- Default text provider: local Hugging Face Hy-MT2.
- OpenRouter handles non-local LLM translation and screenshot translation.
- Preserve `Cmd+C` double press and `Shift+Cmd+2` shortcuts.
- Every persisted setting is code-default plus user override:
  - persist only values different from `TranslatorSettings()`;
  - show reset control only when an override exists;
  - remove the stored override when value returns to default;
  - remove the full settings store when all values equal defaults.

## Settings Contract

The settings UI must cover current AppKit behavior before adding new behavior:

- Text Provider: `Local Model`, `OpenRouter LLM`.
- Source Language: `Auto` plus supported language list.
- Target Language: supported language list without `Auto`.
- Toast Position: bottom/top and left/right variants.
- Local Model: all built-in models plus custom models when supported.
- Local Backend Path: blank means automatic backend selection.
- Custom Models JSON: blank means default config lookup.
- OpenRouter Text Model and Vision Model.
- Permission status for keyboard and screen recording.
- Diagnostics/actions: model setup, permission panes, text test, screenshot translation, request logs, stacked toast preview.

Do not edit credentials in the settings UI. `CredentialsProvider` owns `.env.local`, app-adjacent env files, and `~/.config/copy-translator/.env`.

## Design Rules

- Before building or restructuring a screen, create a visual mockup with Codex image generation.
- Follow `DESIGN.md` and `design/` for color, spacing, typography, sidebar/grouped-row layout, and component behavior.
- Do not fake platform-owned features in web/CSS:
  - native titlebar/window controls come from Tauri/macOS;
  - native window shadow comes from the OS;
  - System Settings privacy panes stay OS-owned.
- Use SF Pro system font stack and semantic macOS-like colors.
- Use the 4 / 8 / 12 / 16 / 20 / 24 spacing scale.
- Keep groups at 8px radius or less unless native platform chrome owns the shape.
- Avoid decorative gradients, orbs, stock imagery, and marketing layouts in app surfaces.
- Use icon buttons or icon+text buttons for concrete actions.

## Layout Rules

- AppKit screens use `NSStackView` + Auto Layout. Avoid hardcoded frames except initial window rects.
- Tauri/Svelte screens use stable grid/flex dimensions. Text must not overflow controls at minimum window size.
- Keep labels and controls scannable in two-column grouped rows.
- Keep minimum settings window size large enough to show controls without clipping.

## Verification

Before claiming UI work complete:

- Run targeted unit tests for changed behavior.
- Run Swift checks when Swift behavior changes.
- Run `npm run check`, `npm run build`, and `cd src-tauri && cargo test` for Tauri/Svelte/Rust changes.
- Run the UI, capture a screenshot, crop the implemented settings surface, and compare it against `design/image.png` plus the generated mockup/reference.
- Check generated CSS for forbidden custom platform shadows (`box-shadow`) in the settings shell.
- Report any verification gap clearly.

## Git Hygiene

- Worktree may be dirty. Do not revert user changes unless explicitly asked.
- Keep diffs small and reversible.
- Add dependencies only when required by the requested stack or by an existing project rule.
- After development work is implemented and verified, create the relevant git commit before reporting completion. Do not leave completed development work uncommitted unless the user explicitly asks not to commit or the worktree contains unresolved unrelated changes that make a safe commit impossible.
- Commit messages, when requested, must follow the Lore Commit Protocol from repo history/instructions.
