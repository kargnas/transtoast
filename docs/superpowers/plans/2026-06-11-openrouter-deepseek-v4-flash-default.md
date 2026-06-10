# OpenRouter DeepSeek V4 Flash Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change CCTrans's default OpenRouter text model to DeepSeek V4 Flash while keeping vision/screenshot translation on Gemini Flash Latest.

**Architecture:** Split OpenRouter text and vision defaults in Swift core, then mirror those defaults in Tauri and Svelte fallback state. Keep the catalog static and mark only DeepSeek V4 Flash as the recommended OpenRouter text option.

**Tech Stack:** Swift 6.2, Swift Testing, Rust/Tauri 2, Svelte/TypeScript, npm checks.

---

## File Structure

- `Sources/CCTransCore/TranslatorSettings.swift`: owns canonical Swift defaults and override encoding behavior.
- `Sources/CCTransCore/OpenRouterModelCatalog.swift`: owns Swift OpenRouter catalog metadata and recommended marker.
- `Tests/CCTransTests/TranslatorSettingsTests.swift`: asserts default settings behavior.
- `src-tauri/src/lib.rs`: owns Tauri settings defaults and settings UI model catalog.
- `src/lib/settings.ts`: owns Svelte fallback state for settings UI when the Tauri backend cannot load.
- `README.md`: documents the OpenRouter text and screenshot defaults.

## Task 1: Split Swift OpenRouter Defaults

**Files:**
- Modify: `Sources/CCTransCore/TranslatorSettings.swift`
- Modify: `Sources/CCTransCore/OpenRouterModelCatalog.swift`
- Test: `Tests/CCTransTests/TranslatorSettingsTests.swift`

- [ ] **Step 1: Update the default test expectation**

Change `defaultsToLocalModelAutoSourceAndKorean()` expectations to:

```swift
#expect(settings.openRouterTextModel == "deepseek/deepseek-v4-flash")
#expect(settings.openRouterVisionModel == "~google/gemini-flash-latest")
#expect(settings.favoriteOpenRouterModels == ["deepseek/deepseek-v4-flash"])
```

- [ ] **Step 2: Run the targeted Swift test and verify it fails**

Run:

```bash
swift test --filter defaultsToLocalModelAutoSourceAndKorean
```

Expected before implementation: FAIL because Swift defaults still point text/favorites to Gemini.

- [ ] **Step 3: Add split defaults in `TranslatorSettings`**

Use these constants:

```swift
public static let defaultOpenRouterTextModel = "deepseek/deepseek-v4-flash"
public static let defaultOpenRouterVisionModel = "~google/gemini-flash-latest"
public static let defaultOpenRouterModel = defaultOpenRouterTextModel
```

Set initializer and decoder fallbacks to `defaultOpenRouterTextModel` for text/favorites and `defaultOpenRouterVisionModel` for vision.

- [ ] **Step 4: Update Swift catalog recommendation**

Add/update this model:

```swift
OpenRouterModelSpec(
    id: "deepseek/deepseek-v4-flash",
    title: "DeepSeek V4 Flash",
    promptPricePerMillion: 0.0983,
    completionPricePerMillion: 0.1966,
    inputModalities: ["text"],
    releaseDate: "2026-04-24",
    contextWindow: 1_048_576,
    isReasoning: true,
    isRecommended: true
)
```

Keep Gemini in the catalog but set `isRecommended` to false.

- [ ] **Step 5: Run targeted Swift test and verify it passes**

Run:

```bash
swift test --filter defaultsToLocalModelAutoSourceAndKorean
```

Expected: PASS.

## Task 2: Align Tauri and Svelte Defaults

**Files:**
- Modify: `src-tauri/src/lib.rs`
- Modify: `src/lib/settings.ts`

- [ ] **Step 1: Update Tauri defaults**

In `default_settings()`, set:

```rust
open_router_text_model: "deepseek/deepseek-v4-flash".to_string(),
open_router_vision_model: "~google/gemini-flash-latest".to_string(),
favorite_open_router_models: vec!["deepseek/deepseek-v4-flash".to_string()],
```

- [ ] **Step 2: Update Tauri OpenRouter catalog**

In `openrouter_models()`, make DeepSeek V4 Flash recommended with the OpenRouter metadata and keep Gemini non-recommended:

```rust
openrouter_model(
    "DeepSeek V4 Flash",
    "deepseek/deepseek-v4-flash",
    Some("Recommended"),
    0.0983,
    0.1966,
    &["text"],
    "2026-04-24",
    1_048_576,
    true,
    false,
    true,
),
```

- [ ] **Step 3: Update Svelte fallback state**

In `src/lib/settings.ts`, set both `settings` and `defaults` fallback text model/favorites to DeepSeek V4 Flash while keeping vision on Gemini.

- [ ] **Step 4: Run Tauri tests**

Run:

```bash
cd src-tauri && cargo test
```

Expected: PASS.

## Task 3: Update Documentation and Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README stack row**

Document OpenRouter text default and screenshot default separately:

```markdown
| Cloud translation & vision | OpenRouter (`deepseek/deepseek-v4-flash` text default, `~google/gemini-flash-latest` screenshot default) |
```

- [ ] **Step 2: Run frontend checks**

Run:

```bash
npm run check
npm run build
```

Expected: both exit 0.

- [ ] **Step 3: Run full Swift tests**

Run:

```bash
swift test
```

Expected: exit 0.

- [ ] **Step 4: Run manual CLI surface smoke**

Run the binary if available:

```bash
dist/CCTrans.app/Contents/MacOS/CCTrans --help
```

Expected: command starts and prints supported CLI usage or exits with an app-defined help/status response. If the binary is missing, run `swift run CCTrans --help` instead.

## Commit Plan

- Commit 1: `docs: OpenRouter DeepSeek 구현 계획 추가` for this plan file.
- Commit 2: `fix: OpenRouter text 기본 모델을 DeepSeek V4 Flash로 변경` for Swift/Rust/Svelte/tests/README changes.

