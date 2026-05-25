# CopyTranslator Agent Notes

## Project Shape

- This is a SwiftPM-first macOS menu bar app.
- The app bundle identifier must stay `as.kargn.copy-translator`.
- Keep secrets in local environment files only. Do not commit `.env.local`, token caches, or generated logs that contain credentials.

## Commands

```zsh
swift test
swift build
./scripts/run-dev.zsh
./scripts/build-app.zsh
```

## Implementation Rules

- Keep the default UI language English.
- Keep the default translation target Korean unless the user asks for another default.
- Keep Hugging Face Hy-MT2 as the default text translation provider.
- Use OpenRouter for non-Hy-MT2 LLM translation and screenshot translation.
- Preserve the `Cmd+C` double-press and `Shift+Cmd+2` shortcuts when changing shortcut code.
