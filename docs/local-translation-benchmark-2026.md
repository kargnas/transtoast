# Local Translation Benchmark 2026

Goal: find local translation models that are light and fast enough for CCTrans, with Korean target quality that is not bad.

Scope note: Hugging Face and GitHub returned many 2026 translation uploads, most of them near-duplicate fine-tunes or exports of the same few families. This benchmark tracks by family and tests one representative per meaningfully different runtime/model family, per the "do not test similar ones" constraint.

Updated: 2026-05-31 18:55 UTC.

## Current Pick

`mlx-community/Hy-MT2-1.8B-4bit` remains the best local candidate after warm-cache retest.

- Warm load: 0.75s
- Peak RSS: 1508 MB
- Inference: 0.079-0.171s on the three sample inputs
- Quality: best overall, with correct `release notes` and `twice`

Good alternatives:

- `gyung/lfm2-1.2b-koen-mt-v8-rl-10k-merged-GGUF` Q4_K_M: strong 2026 GitHub/HF candidate, fast and correct, but license needs review.
- `unsloth/Hy-MT2-1.8B-GGUF` IQ4_XS: good llama.cpp route, correct outputs, slightly slower than MLX on sentences.
- `quickmt/quickmt-en-ko`: fastest/lightest viable model, but failed the isolated short-word test.

## Tested Results

| Model | Runtime | Load | Peak RSS | Inference | Quality | Verdict |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `mlx-community/Hy-MT2-1.8B-4bit` warm | MLX Apple Silicon | 0.75s | 1508 MB | 0.079-0.171s | High | Best pick |
| `gyung/lfm2-1.2b-koen-mt-v8-rl-10k-merged-GGUF` Q4_K_M | llama.cpp CPU | 0.32s | 1566 MB | 0.070-0.201s | High | Strong, license review needed |
| `unsloth/Hy-MT2-1.8B-GGUF` IQ4_XS | llama.cpp CPU | 0.18s | 1414 MB | 0.083-0.609s | High | Good llama.cpp option |
| `quickmt/quickmt-en-ko` | CTranslate2 CPU | 0.16s | 1243 MB | 0.022-0.032s | Medium-high | Very fast, but short word failure |
| `Timteamteem/CTranslate2-nllb-200-int8` | CTranslate2 CPU int8 | 0.74s | 1554 MB | 0.055-0.210s | Medium | Fast, slightly awkward |
| `mlx-community/HY-MT1.5-1.8B-4bit` | MLX Apple Silicon | 102.93s first run | 1867 MB | 0.083-0.677s | Medium-high | OK, worse terminology than Hy-MT2 |
| `mlx-community/Hy-MT2-1.8B-4bit` cold | MLX Apple Silicon | 97.93s first run | 2383 MB | 0.078-0.329s | High | Cold download/load run |
| `mlx-community/translategemma-4b-it-4bit_immersive-translate` | MLX Apple Silicon | 202.10s first run | 5151 MB | 0.187-0.747s | Medium | Reject: too heavy, `twice` wrong |
| `WindstormLabs/translate-tc-big-en-ko/lora-ct2-int8` | CTranslate2 CPU int8 | 0.09s | 764 MB | 0.018-0.050s | Fail | Reject: unusable output |
| `ooeoeo/opus-mt-tc-big-en-ko-ct2-float16` | CTranslate2 CPU | 0.25s | 1618 MB | 0.027-0.054s | Fail | Reject: unusable output |
| `R4kSo1997/opus-mt-en-ko-onnx-int8` | ONNX Runtime int8 | 75.52s | 1308 MB | 0.023-0.042s | Fail | Reject: unusable output |
| `harveykim/gemma-3-1b-aihub-ko-en-lora` | Transformers + PEFT | 194.39s | 2573 MB | 0.534-4.908s | Fail | Reject: prompt-following failure |
| `harveykim/kanana-1.5-2.1b-aihub-ko-en-lora` | Transformers + PEFT | 28.34s retry | 814 MB | 0.400-1.670s | Medium-high | Retry runs with pinned deps; not default due license/runtime fragility |
| `aufklarer/MADLAD400-3B-MT-MLX` int4 | official Swift runtime attempted | failed | n/a | n/a | Not run | `speech` builds, then MLX Swift metallib load fails |

## Sample Outputs

Input: `The deployment failed because the database URL was missing.`

- Hy-MT2 MLX warm: `데이터베이스 URL이 누락되어 배포가 실패했습니다.`
- LFM2 GGUF Q4_K_M: `데이터베이스 URL이 누락되어 배포가 실패했습니다.`
- Hy-MT2 GGUF IQ4_XS: `데이터베이스 URL이 누락되어 배포가 실패했습니다.`
- QuickMT: `데이터베이스 URL이 누락되어 배포가 실패했습니다.`
- NLLB CTranslate2: `배포는 데이터베이스 URL가 없어서 실패했습니다.`
- TranslateGemma MLX 4bit: `배포가 실패한 이유는 데이터베이스 URL이 누락되었기 때문입니다.`
- OPUS/Windstorm variants: `프로세스、403 well2.8:46ther。`

Input: `Please summarize the release notes before the meeting.`

- Hy-MT2 MLX warm: `회의 전에 릴리스 노트를 요약해 주세요.`
- LFM2 GGUF Q4_K_M: `회의 전에 릴리스 노트를 요약해 주십시오.`
- Hy-MT2 GGUF IQ4_XS: `회의 전에 릴리스 노트를 요약해 주세요.`
- QuickMT: `회의 전에 릴리스 정보를 요약하십시오.`
- NLLB CTranslate2: `회의 전에 발표 메모를 요약해 주세요.`
- TranslateGemma MLX 4bit: `회의 전에 릴리스 노트 내용을 요약해주세요.`
- OPUS/Windstorm variants: `잘 오염 물질  잘 해충.`

Input: `twice`

- Hy-MT2 MLX warm: `두 번`
- LFM2 GGUF Q4_K_M: `두 번`
- Hy-MT2 GGUF IQ4_XS: `두 번`
- QuickMT: `두번 째`
- NLLB CTranslate2: `두 번`
- TranslateGemma MLX 4bit: `트와이스`
- OPUS/Windstorm variants: `킹`

## Candidate Families Seen

- Hy-MT1.5: 2026 multilingual MT family. Tested `mlx-community/HY-MT1.5-1.8B-4bit`.
- Hy-MT2: 2026 Tencent MT2 family. Tested MLX 4-bit and GGUF IQ4_XS; skipped 7B GGUF as same family and heavier.
- LFM2 Korean-English MT: GitHub project created 2026-01-03. Tested `gyung/...Q4_K_M.gguf`.
- NLLB exports: Tested `Timteamteem/CTranslate2-nllb-200-int8`.
- QuickMT: Tested `quickmt/quickmt-en-ko` direct CTranslate2 path.
- TranslateGemma: Tested `mlx-community/translategemma-4b-it-4bit_immersive-translate`.
- Gemma/Kanana ko/en LoRA: Gemma tested and rejected; Kanana retry runs with pinned Transformers/PEFT and raw prompt, but remains non-default due CC-BY-NC license and short-word over-translation.
- MADLAD400 exports: MLX int4 attempted; generic `mlx-lm` failed. Official Swift CLI build succeeded but MLX Swift metallib load failed on this host. ONNX sibling exists but is same 3B family and not lighter than current winners.
- Marian/OPUS 2026 packages: Tested ONNX, CT2, and Windstorm/WindyWord int8 representatives; rejected.
- Murasaki-project: 2026 GitHub ACGN-specialized translation project; not a light general English-to-Korean candidate for this app.
- Large/older GGUF translation models updated in 2026: `tensorblock/nayohan_llama3-8b-it-translation-sharegpt-en-ko-GGUF`, `tensorblock/kwoncho_Llama-3.2-3B-KO-EN-Translation-GGUF`, and `TARARARAK/gpt-oss-20b-*` were seen. They were either created before 2026, much heavier than the tested winners, or wrong-direction KO-EN only.
- GitHub notebooks/evaluation repos: `songhahyun/seq2seq-transformer`, `estincelle/Translator_models_experiments_english--korean`, and `minovermax/ko-entity-fidelity` were found, but they are training/evaluation artifacts rather than app-ready local model weights.

## Sources Checked

- https://huggingface.co/quickmt/quickmt-en-ko
- https://huggingface.co/aufklarer/MADLAD400-3B-MT-MLX
- https://huggingface.co/unsloth/Hy-MT2-1.8B-GGUF
- https://huggingface.co/gyung/lfm2-1.2b-koen-mt-v8-rl-10k-merged-GGUF
- https://github.com/gyunggyung/LFM2-KoEn-Tuning
- https://huggingface.co/WindstormLabs/translate-tc-big-en-ko
- https://huggingface.co/tonythethompson/madlad400-3b-mt-onnx
- https://github.com/soundstarrain/Murasaki-project
- https://api.github.com/search/repositories?q=translation+korean+model+created:%3E2025-01-01
- https://api.github.com/search/repositories?q=en-ko+translation+model+created:%3E2025-01-01
- https://api.github.com/search/repositories?q=ko-en+translation+model+created:%3E2025-01-01

Raw data: `docs/local-translation-benchmark-2026.json`.

Retry analysis: `docs/local-translation-retry-and-runtime-design-2026.md` and `docs/local-translation-retry-2026.json`.
