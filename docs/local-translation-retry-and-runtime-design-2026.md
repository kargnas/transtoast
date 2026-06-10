# Local Translation Retry And Runtime Design 2026

This file records retry results for earlier failed models and the two-subagent design review for supporting multiple local translation runtimes cleanly.

## Retry Results

| Model | Retry Method | Result | Cause Classification |
| --- | --- | --- | --- |
| `Helsinki-NLP/opus-mt-tc-big-en-ko` | Original Transformers `MarianMTModel` + `MarianTokenizer` | Still broken | Not app harness bug; upstream model/tokenizer output is unusable for tested samples |
| `ooeoeo/opus-mt-tc-big-en-ko-ct2-float16` | Direct `source.spm` / `target.spm` + CTranslate2 | Still broken | Not app harness bug; CT2 export reproduces upstream broken outputs |
| `WindstormLabs/translate-tc-big-en-ko/lora-ct2-int8` | Direct `source.spm` / `target.spm` + CTranslate2 | Still broken | Not app harness bug; packaged CT2 reproduces upstream broken outputs |
| `harveykim/kanana-1.5-2.1b-aihub-ko-en-lora` | Transformers 4.46.3 + PEFT 0.19.1 + raw Instruction/Input/Response prompt + torch distributed patch | Runs | Earlier failure was test harness dependency/prompt mistake |
| `aufklarer/MADLAD400-3B-MT-MLX` | Official `soniqo/speech-swift` CLI `speech translate ... --to ko` | Build succeeded, runtime failed | Not model-quality result; proper Swift runtime hit MLX Swift `default metallib` load failure in this environment |

## OPUS/Marian Details

Original Transformers retry:

```text
Helsinki-NLP/opus-mt-tc-big-en-ko
The deployment failed because the database URL was missing.
=> 프로세스、403 well2.8:46ther。

Please summarize the release notes before the meeting.
=> 잘 오염 물질  잘 해충.

twice
=> 킹
```

Target prefix retry also failed:

```text
'' => 프로세스、403 well2.8:46ther。
'>>ko<< ' => ※ 과정※403 well2.8:46더
'>>kor<< ' => ※ 과정※403 well2.8:46더
'>>kor_Hang<< ' => ※ 과정※403 well2.8:46더
```

CTranslate2 direct SentencePiece retry:

```text
ooeoeo/opus-mt-tc-big-en-ko-ct2-float16
=> 프로세스、403 well2.8:46ther。
=> ☆ 좋은 오염 물질☆ 해충 ☆.
=> 칫

WindstormLabs/translate-tc-big-en-ko/lora-ct2-int8
=> 프로세스、403 well2.8:46ther。
=> ☆ 좋은 오염 물질☆ 해충 ☆.
=> 칫
```

Conclusion: this is not local hardware support failure and not just our original tokenizer call. The upstream model/tokenizer output itself is unusable on these samples; CT2 packages reproduce it.

## Kanana Details

Earlier run used the wrong prompt shape and incompatible dependency mix. The model card says raw format, not chat template:

```text
### Instruction:
{instruction}

### Input:
{input}

### Response:
```

Working retry used:

- `transformers==4.46.3`
- `peft==0.19.1`
- `kakaocorp/kanana-1.5-2.1b-base`
- raw Instruction/Input/Response prompt
- local monkey patch for `torch.distributed.tensor`

Results:

| Input | Output | Time |
| --- | --- | ---: |
| `The deployment failed because the database URL was missing.` | `데이터베이스 URL이 누락되어 배포가 실패했습니다.` | 1.670s |
| `Please summarize the release notes before the meeting.` | `회의 전에 출시 노트를 요약해 주세요.` | 0.400s |
| `twice` | `두 번이나 그랬어요.` | 0.618s |

Load: 28.34s. Peak RSS: 813.9 MB in the retry process.

Conclusion: Kanana should move from `not_run` to `runs_with_version_pins`, but it is still not a default candidate because:

- adapter license is `CC BY-NC 4.0`
- dependency matrix is fragile
- isolated word handling over-translates `twice`
- only Korean<->English scope

## MADLAD Details

Generic `mlx-lm` was the wrong runtime. Official route is `MADLADTranslation` in `soniqo/speech-swift`.

Retry command:

```bash
swift run --package-path /tmp/cctrans-madlad-test speech translate "The deployment failed because the database URL was missing." --to ko
```

Result:

```text
Build of product 'speech' complete! (48.20s)
Loading MADLAD (int4)...
Downloading int4 model...
Creating model... 70%
MLX error: Failed to load the default metallib. library not found ...
```

Conclusion: not a model-quality failure. It is a runtime/toolchain environment failure in MLX Swift. Since Python `mlx-lm` works on this machine, hardware is not broadly unsupported. MADLAD remains a separate Swift-runtime integration project, not a quick Python worker.

## Clean Runtime Architecture

Both subagents converged on the same structure: keep local models behind isolated helper processes, but replace the current Hy-MT2-only path with a runtime adapter layer.

### Core Types

```swift
public enum TextProviderID: String, Codable, CaseIterable {
    case local
    case openRouter
}

public enum LocalRuntimeKind: String, Codable, Sendable {
    case transformers
    case mlxLM
    case ctranslate2
    case llamaCPP
    case madladSwift
}

public struct LocalModelSpec: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let runtime: LocalRuntimeKind
    public let modelID: String
    public let artifactFilename: String?
    public let supportedLanguagePairs: [LanguagePair]
    public let backendScriptName: String?
    public let licenseNote: String
    public let qualityNote: String
}
```

### Proposed Files

```text
Sources/CCTransCore/Translation/
  TranslationRequest.swift
  TranslationResult.swift
  TranslationService.swift

Sources/CCTransCore/OpenRouter/
  OpenRouterTranslationClient.swift

Sources/CCTransCore/LocalTranslation/
  LocalModelRegistry.swift
  LocalRuntimeTypes.swift
  LocalRuntimeProcessClient.swift
  LocalBackendResolver.swift
  LocalTranslationErrors.swift

Sources/CCTransCore/Settings/
  TranslatorSettings.swift
  TranslatorDefaults.swift

scripts/runtimes/
  common_protocol.py
  mlx_lm_worker.py
  llama_cpp_worker.py
  ctranslate2_worker.py
  transformers_worker.py
```

### Process Protocol

Use one JSONL protocol for every local runtime.

Swift sends:

```json
{
  "id": "request-id",
  "text": "The deployment failed...",
  "source_language": "English",
  "target_language": "Korean",
  "model_id": "mlx-community/Hy-MT2-1.8B-4bit",
  "artifact_filename": null,
  "options": {}
}
```

Worker returns:

```json
{
  "id": "request-id",
  "translation": "데이터베이스 URL이 누락되어 배포가 실패했습니다.",
  "description": null
}
```

### Process Lifetime

Use a `LocalRuntimeProcessManager` actor:

- key: `(runtimeKind, modelID, artifactFilename)`
- warm persistent process
- startup timeout
- request timeout
- idle shutdown
- bounded stderr capture
- token redaction
- no silent cloud fallback

This fixes current one-shot model reload cost in `hy_mt2_translate.py`.

### Model Registry Initial Entries

| Stable ID | Runtime | Status |
| --- | --- | --- |
| `hymt2-mlx-1.8b-4bit` | `mlxLM` | default candidate |
| `hymt2-gguf-iq4-xs` | `llamaCPP` | supported fallback |
| `lfm2-koen-q4-k-m` | `llamaCPP` | experimental, license review |
| `nllb-ct2-int8` | `ctranslate2` | broad-language fallback |
| `quickmt-en-ko` | `ctranslate2` | sentence-only fallback; block short strings |
| `kanana-lora-koen` | `transformers` | non-commercial, fragile dependency pins |
| `madlad-swift-int4` | `madladSwift` | deferred, custom Swift runtime |

### Settings Migration

Replace Hy-MT2-specific settings with generic local model settings:

```swift
provider: TextProviderID = .local
localModelID: String = LocalModelRegistry.defaultTextModelID
localRuntimePathOverrides: [LocalRuntimeKind.RawValue: String] = [:]
targetLanguage: String = "Korean"
```

Keep legacy decode:

- `localHyMT2` -> `.local`
- old `hyMT2Model` -> matching `localModelID`
- old `localHyMT2BackendPath` -> `.transformers` runtime override

### Tests Needed

- `LocalModelRegistryTests`: unique IDs, default exists, runtime/script/options valid.
- `TranslatorSettingsMigrationTests`: old settings decode into new fields.
- `LocalRuntimeProcessClientTests`: command args, env token handling, JSONL parsing, timeout, crash, invalid JSON.
- `TranslationServiceRoutingTests`: local requests route by registry; OpenRouter remains unchanged.
- `LocalTranslationErrorsTests`: missing `uv`, dependency failure, model download failure, unsupported pair, timeout, worker crash.
- Gated integration tests using benchmark fixture corpus.

## Final Classification

| Model | Final Classification |
| --- | --- |
| OPUS/Marian | upstream/model package unusable for these samples; not our Mac support issue |
| Kanana | our earlier dependency/prompt mistake; now runs, but not default-worthy |
| MADLAD | our earlier generic-runtime mistake; official runtime fails due MLX Swift metallib environment/toolchain issue |
| QuickMT | model quality weakness on short strings |
| Hy-MT2 | best default; still needs regression guard for mixed-language token leakage |
