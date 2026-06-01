# Local Translation Multilingual Benchmark 2026

This expands the local model benchmark beyond the original three English-to-Korean samples. It tests multiple source/target languages, short UI strings, technical text, medium release-note text, and long product text.

Raw data: `docs/local-translation-multilingual-2026.json`.

## Coverage

Language pairs tested:

- Arabic -> Korean
- Chinese -> Korean
- English -> Chinese
- English -> Japanese
- English -> Korean
- English -> Spanish
- French -> Korean
- Indonesian -> Korean
- Japanese -> Korean
- Korean -> English
- Spanish -> Korean

Lengths/types tested:

- `word`
- `short_ui`
- `sentence`
- `technical`
- `medium`
- `long`

## Summary

| Model | Scope | Samples | Load | Peak RSS | Inference | Verdict |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `mlx-community/Hy-MT2-1.8B-4bit` | multilingual | 17 | 1.09s | 1308 MB | 0.127-0.566s | Best multilingual candidate |
| `Timteamteem/CTranslate2-nllb-200-int8` | multilingual | 17 | 0.72s | 1522 MB | 0.074-1.054s | Broad fallback only |
| `gyung/lfm2-1.2b-koen-mt-v8-rl-10k-merged-GGUF` Q4_K_M | en<->ko | 8 | 8.04s | 1609 MB | 0.243-1.117s | Strong en/ko, license review needed |
| `quickmt/quickmt-en-ko` | en->ko | 6 | 0.17s | 1094 MB | 0.021-0.108s | Fast but unsafe as default |

## Model Notes

### Hy-MT2 MLX

Best overall. It handled English, Japanese, Chinese, Spanish, French, Indonesian, Arabic, Korean, and English-to-Japanese/Chinese/Spanish in one model with low latency.

Good outputs:

- `twice` -> `두 번`
- `Retry download` -> `다시 다운로드 시도`
- Japanese -> Korean: `네트워크가 불안정하기 때문에, 번역을 일시적으로 저장했습니다.`
- Korean -> English long sample was fluent and preserved the metadata/privacy point.

Issues:

- English -> Korean medium sample leaked a Chinese token: `任何`.
- Arabic -> Korean was understandable but grammatically awkward.
- English -> Chinese used a generic access-permission phrase instead of precise accessibility-permission wording.

### NLLB CTranslate2

Useful when broad language coverage is needed, but Korean quality is weaker than Hy-MT2.

Issues:

- `release notes` -> `발표 메모`
- `swift test` -> `swift 테스트`
- Long output was understandable but stiff and awkward.

### LFM2-KoEn GGUF

Strong for English<->Korean only. It handled short words and long text well.

Issues:

- `migration step` became `이동 단계`, which is weak for software context.
- `usage metadata` became `user data` in one long sample.
- License is LFM Open License; review before integration.

### QuickMT

Fastest and lowest-memory in this expanded run, but short text makes it unsafe as a default.

Failures:

- `twice` -> `두번 째`
- `Retry download` -> `다운로드 다운로드 Slot`

It is acceptable only for straightforward longer English-to-Korean sentence translation, or after separate short-text routing.

## Recommendation

Keep `mlx-community/Hy-MT2-1.8B-4bit` as the local default candidate. It has the best multilingual quality/speed balance. Add regression samples for:

- short UI text
- isolated words
- code/log strings
- Arabic/French/Indonesian/Japanese/Chinese -> Korean
- Korean -> English

Use NLLB only as a broad fallback. Consider LFM2 only for English<->Korean after license review. Do not use QuickMT as default unless short-string handling is fixed.
