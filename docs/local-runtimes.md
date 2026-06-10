# Local Translation Runtimes

CCTrans now treats local translators as registry entries instead of hard-coding Hy-MT2.

## Built-In Model IDs

- `hymt2-mlx-1.8b-4bit`: default local model. Uses `scripts/runtimes/mlx_lm_translate.py`.
- `hymt2-transformers-1.8b`: legacy Transformers backend, included in first-run comparison.
- `hymt2-transformers-30b`: supported by the legacy backend, but excluded from first-run comparison because it is too heavy.
- `hymt2-gguf-iq4-xs`, `lfm2-koen-q4-k-m`, `nllb-ct2-int8`, `quickmt-en-ko`, `kanana-lora-koen`, and `madlad-swift-int4`: tracked candidates from the benchmark notes. They stay visible in the registry, but need an adapter or custom backend before normal use.

## First-Run Setup UI

The first-run **Local Model Setup** window starts with prior benchmark evidence, not a blank test runner.

- Top controls choose source and target language.
- The main table lists tested local model families with runtime, quality, speed/memory, language coverage, status, and notes.
- The right panel explains the selected row and calls out license or runtime constraints.
- The sample preview tabs show saved short, medium, and long outputs from previous tests.
- **Run Fresh Test** runs the current language pair on this Mac only after the user has seen the prior comparison.

Status values are intentionally explicit:

- `Recommended`: best current default.
- `Supported`: runnable fallback.
- `Heavy`: available but not suitable for first-run default.
- `Planned adapter`: benchmarked candidate, adapter not wired yet.
- `Fragile deps`: worked only with constrained dependencies or license concerns.
- `Runtime issue`: package/runtime failed before quality could be judged.
- `Rejected`: retry showed unusable output.

## Backend Protocol

Backends are one-shot JSON processes. The app runs:

```zsh
uv run /path/to/backend.py
```

stdin:

```json
{
  "text": "The deployment failed.",
  "prompt": "Translate ...",
  "source_language": "English",
  "target_language": "Korean",
  "local_model_id": "hymt2-mlx-1.8b-4bit",
  "model_id": "mlx-community/Hy-MT2-1.8B-4bit",
  "runtime": "mlx-lm",
  "artifact_name": "",
  "hf_token": ""
}
```

stdout on success:

```json
{"translation": "배포가 실패했습니다."}
```

stdout on failure:

```json
{"error": "failure reason"}
```

## Custom Models

Custom models live in:

```zsh
~/.config/cctrans/local-models.json
```

Create a template:

```zsh
uv run scripts/local_model_setup.py --write-template
```

Then set `customBackendPath` to a backend that follows the protocol above. The app can also use another config path through Settings or:

```zsh
swift run CCTrans --list-local-models --custom-local-models /path/to/local-models.json
```

The app does not automatically execute `setupCommand`; it records the command so a setup flow can present it explicitly before installing new model dependencies.
