# Other Mac Setup

Use this checklist to set up CCTrans on another Mac.

## Requirements

- macOS 15 or later.
- Xcode 26 or later.
- Swift 6.2 or later.
- `uv` for the local Hy-MT2 backend.
- GitHub CLI or plain `git` to clone the repository.

## Clone

```zsh
gh repo clone kargnas/cctrans
cd cctrans
```

## Configure Secrets

```zsh
cp .env.example .env.local
open -e .env.local
```

Fill in local secrets:

```zsh
OPENROUTER_API_KEY=...
HF_TOKEN=...
```

Do not commit `.env.local`.

## Build And Install

```zsh
./scripts/install-app.zsh --open
```

To install somewhere other than `/Applications`:

```zsh
./scripts/install-app.zsh --install-dir "$HOME/Applications" --open
```

## Permissions

Open these panes after the first install, then relaunch CCTrans:

```zsh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

CCTrans needs Input Monitoring or Accessibility for `Cmd+C` twice, and Screen Recording for screenshot context and screenshot translation.

## Package For Manual Transfer

```zsh
./scripts/package-app.zsh
```

This writes `dist/CCTrans.zip`.
