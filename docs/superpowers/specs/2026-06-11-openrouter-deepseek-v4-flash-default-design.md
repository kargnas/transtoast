# OpenRouter DeepSeek V4 Flash Default Design

## Goal

Change CCTrans's default OpenRouter text translation model from `~google/gemini-flash-latest` to `deepseek/deepseek-v4-flash`.

Keep screenshot and vision translation on `~google/gemini-flash-latest` because DeepSeek V4 Flash is text-only. This preserves the existing screenshot translation surface while making ordinary OpenRouter text translation cheaper and faster by default.

## Current State

- `TranslatorSettings.defaultOpenRouterModel` drives both OpenRouter text and vision defaults in Swift.
- Tauri has a separate `default_settings()` copy for settings UI and preview actions.
- Svelte has `fallbackState` with the same OpenRouter defaults for frontend fallback rendering.
- OpenRouter catalog entries currently mark Gemini Flash Latest as recommended.
- Tests assert Gemini as both text and vision defaults.
- README documents Gemini as the OpenRouter screenshot default.

## Selected Design

Use separate default constants:

- `defaultOpenRouterTextModel = "deepseek/deepseek-v4-flash"`
- `defaultOpenRouterVisionModel = "~google/gemini-flash-latest"`

`TranslatorSettings.defaultOpenRouterModel` may remain as a compatibility alias for the text default if needed by existing call sites, but new default assignments should be explicit about text vs vision.

## Behavior

- New installs and users with no OpenRouter override get DeepSeek V4 Flash for text translation when they choose OpenRouter LLM.
- New installs and users with no OpenRouter vision override continue using Gemini Flash Latest for screenshot translation.
- Existing users with stored `openRouterTextModel` or `openRouterVisionModel` overrides keep their saved values because settings persist only non-default overrides.
- `favoriteOpenRouterModels` defaults to include the text default. Users can still favorite/select Gemini manually from the catalog.

## Catalog/UI

- Add or update catalog entry for `deepseek/deepseek-v4-flash` as "DeepSeek V4 Flash".
- Mark DeepSeek V4 Flash as recommended.
- Remove the recommended flag from Gemini Flash Latest, while keeping it in the list for vision/manual use.
- Use OpenRouter's public model page values:
  - Input price: $0.0983 / 1M tokens
  - Output price: $0.1966 / 1M tokens
  - Context window: 1,048,576 tokens
  - Release date: 2026-04-24
  - Modalities: text

## Verification

- Swift tests should confirm text default is DeepSeek V4 Flash and vision default remains Gemini Flash Latest.
- Tauri/Rust tests should confirm settings defaults and reset behavior use the split defaults.
- Svelte check/build should pass after fallback state updates.
- Manual CLI smoke should run the app binary with `--provider openrouter --openrouter-text-model deepseek/deepseek-v4-flash --translate-text-once` only if an OpenRouter key is available; otherwise verify the command construction/settings surface without sending a live request.

## Out of Scope

- Do not change the app-wide default provider; local Hy-MT2 remains default.
- Do not change screenshot translation away from Gemini.
- Do not add model-routing fallback logic.
