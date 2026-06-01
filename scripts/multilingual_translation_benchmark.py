# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "ctranslate2",
#   "huggingface_hub",
#   "llama-cpp-python",
#   "mlx-lm",
#   "psutil",
#   "sentencepiece",
#   "transformers>=4.56.0",
# ]
# ///

import argparse
import json
import os
import threading
import time
from dataclasses import dataclass
from typing import Any

import psutil


SAMPLES: list[dict[str, Any]] = [
    {
        "id": "en_word",
        "length": "word",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": "twice",
    },
    {
        "id": "en_ui_short",
        "length": "short_ui",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": "Retry download",
    },
    {
        "id": "en_technical_sentence",
        "length": "sentence",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": "The deployment failed because the database URL was missing.",
    },
    {
        "id": "en_code_log",
        "length": "technical",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": "Set DATABASE_URL before running `swift test`; otherwise the migration step exits with code 78.",
    },
    {
        "id": "en_medium_release",
        "length": "medium",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": (
            "Please summarize the release notes before the meeting, and call out any breaking "
            "changes that affect the desktop app."
        ),
    },
    {
        "id": "en_long_product",
        "length": "long",
        "source_language": "English",
        "target_language": "Korean",
        "source_code": "eng_Latn",
        "target_code": "kor_Hang",
        "text": (
            "The new offline mode keeps a local cache of recent translations so users can keep "
            "working while the network is unstable. When connectivity returns, the app syncs "
            "usage metadata without uploading the original copied text. Administrators can "
            "disable the cache from the settings file, and the change takes effect after the "
            "next launch."
        ),
    },
    {
        "id": "ja_to_ko_sentence",
        "length": "sentence",
        "source_language": "Japanese",
        "target_language": "Korean",
        "source_code": "jpn_Jpan",
        "target_code": "kor_Hang",
        "text": "ネットワークが不安定なため、翻訳を一時的に保存しました。",
    },
    {
        "id": "zh_to_ko_sentence",
        "length": "sentence",
        "source_language": "Chinese",
        "target_language": "Korean",
        "source_code": "zho_Hans",
        "target_code": "kor_Hang",
        "text": "由于数据库地址缺失，部署流程已经停止。",
    },
    {
        "id": "es_to_ko_sentence",
        "length": "sentence",
        "source_language": "Spanish",
        "target_language": "Korean",
        "source_code": "spa_Latn",
        "target_code": "kor_Hang",
        "text": "Guarda los cambios antes de cerrar la ventana de configuración.",
    },
    {
        "id": "fr_to_ko_sentence",
        "length": "sentence",
        "source_language": "French",
        "target_language": "Korean",
        "source_code": "fra_Latn",
        "target_code": "kor_Hang",
        "text": "Le raccourci clavier ne fonctionne que lorsque l'application est autorisée.",
    },
    {
        "id": "id_to_ko_sentence",
        "length": "sentence",
        "source_language": "Indonesian",
        "target_language": "Korean",
        "source_code": "ind_Latn",
        "target_code": "kor_Hang",
        "text": "Pengguna dapat mengubah bahasa target dari jendela pengaturan.",
    },
    {
        "id": "ar_to_ko_sentence",
        "length": "sentence",
        "source_language": "Arabic",
        "target_language": "Korean",
        "source_code": "arb_Arab",
        "target_code": "kor_Hang",
        "text": "تعذر حفظ الملف لأن مساحة القرص غير كافية.",
    },
    {
        "id": "ko_to_en_sentence",
        "length": "sentence",
        "source_language": "Korean",
        "target_language": "English",
        "source_code": "kor_Hang",
        "target_code": "eng_Latn",
        "text": "네트워크가 불안정해서 번역 결과를 임시로 저장했습니다.",
    },
    {
        "id": "ko_to_en_long",
        "length": "long",
        "source_language": "Korean",
        "target_language": "English",
        "source_code": "kor_Hang",
        "target_code": "eng_Latn",
        "text": (
            "새로운 오프라인 모드는 최근 번역 기록을 로컬 캐시에 저장해서 네트워크가 불안정한 "
            "상황에서도 사용자가 작업을 계속할 수 있게 합니다. 연결이 복구되면 앱은 원문 텍스트를 "
            "업로드하지 않고 사용량 메타데이터만 동기화합니다."
        ),
    },
    {
        "id": "en_to_ja_sentence",
        "length": "sentence",
        "source_language": "English",
        "target_language": "Japanese",
        "source_code": "eng_Latn",
        "target_code": "jpn_Jpan",
        "text": "The shortcut only works after accessibility permission is granted.",
    },
    {
        "id": "en_to_zh_sentence",
        "length": "sentence",
        "source_language": "English",
        "target_language": "Chinese",
        "source_code": "eng_Latn",
        "target_code": "zho_Hans",
        "text": "The shortcut only works after accessibility permission is granted.",
    },
    {
        "id": "en_to_es_sentence",
        "length": "sentence",
        "source_language": "English",
        "target_language": "Spanish",
        "source_code": "eng_Latn",
        "target_code": "spa_Latn",
        "text": "The shortcut only works after accessibility permission is granted.",
    },
]


@dataclass
class MemorySampler:
    process: psutil.Process
    peak_rss: int = 0
    running: bool = False
    thread: threading.Thread | None = None

    def start(self) -> None:
        self.running = True
        self.thread = threading.Thread(target=self._poll, daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.running = False
        if self.thread:
            self.thread.join()

    def _poll(self) -> None:
        while self.running:
            self.peak_rss = max(self.peak_rss, self.process.memory_info().rss)
            time.sleep(0.02)


def max_tokens_for(sample: dict[str, Any]) -> int:
    if sample["length"] == "long":
        return 512
    if sample["length"] in {"medium", "technical"}:
        return 256
    return 128


def prompt_for(sample: dict[str, Any]) -> str:
    return (
        f"Translate the following text from {sample['source_language']} to {sample['target_language']}. "
        "Return only the translated text. Preserve product names, file paths, commands, placeholders, and numbers.\n\n"
        f"{sample['text']}"
    )


def metadata_for(sample: dict[str, Any], translation: str, seconds: float) -> dict[str, Any]:
    return {
        "id": sample["id"],
        "length": sample["length"],
        "source_language": sample["source_language"],
        "target_language": sample["target_language"],
        "input_chars": len(sample["text"]),
        "input": sample["text"],
        "translation": translation,
        "seconds": round(seconds, 3),
    }


def supported_samples(case: str) -> list[dict[str, Any]]:
    if case in {"quickmt-ct2"}:
        return [
            sample for sample in SAMPLES
            if sample["source_language"] == "English" and sample["target_language"] == "Korean"
        ]
    if case in {"lfm2-gguf"}:
        return [
            sample for sample in SAMPLES
            if {sample["source_language"], sample["target_language"]} == {"English", "Korean"}
        ]
    return SAMPLES


def benchmark_hymt2_mlx(model_id: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    from mlx_lm import generate, load

    load_start = time.perf_counter()
    model, tokenizer = load(model_id)
    load_seconds = time.perf_counter() - load_start

    results = []
    for sample in samples:
        prompt = prompt_for(sample)
        try:
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": prompt}],
                add_generation_prompt=True,
                tokenize=False,
            )
        except Exception:
            pass

        started = time.perf_counter()
        translation = generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens_for(sample),
            verbose=False,
        ).strip()
        results.append(metadata_for(sample, translation, time.perf_counter() - started))

    return {
        "case": "hymt2-mlx",
        "model": model_id,
        "runtime": "mlx-lm",
        "load_seconds": round(load_seconds, 2),
        "results": results,
    }


def benchmark_nllb_ct2(model_id: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    import ctranslate2
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer

    download_start = time.perf_counter()
    path = snapshot_download(model_id)
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(path)
    translator = ctranslate2.Translator(path, device="cpu", compute_type="int8")
    load_seconds = time.perf_counter() - load_start

    results = []
    for sample in samples:
        tokenizer.src_lang = sample["source_code"]
        started = time.perf_counter()
        tokens = tokenizer.convert_ids_to_tokens(tokenizer.encode(sample["text"]))
        translated = translator.translate_batch(
            [tokens],
            target_prefix=[[sample["target_code"]]],
            beam_size=1,
            max_decoding_length=max_tokens_for(sample),
        )
        output_tokens = translated[0].hypotheses[0]
        output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
        translation = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
        results.append(metadata_for(sample, translation, time.perf_counter() - started))

    return {
        "case": "nllb-ct2",
        "model": model_id,
        "runtime": "ctranslate2-cpu-int8",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": results,
    }


def benchmark_quickmt_ct2(model_id: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    import ctranslate2
    import sentencepiece
    from huggingface_hub import snapshot_download

    download_start = time.perf_counter()
    path = snapshot_download(model_id, ignore_patterns=["eole-model/*", "eole_model/*"])
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    translator = ctranslate2.Translator(path, device="cpu", inter_threads=1, intra_threads=0)
    source_tokenizer = sentencepiece.SentencePieceProcessor(model_file=os.path.join(path, "src.spm.model"))
    target_tokenizer = sentencepiece.SentencePieceProcessor(model_file=os.path.join(path, "tgt.spm.model"))
    load_seconds = time.perf_counter() - load_start

    results = []
    for sample in samples:
        started = time.perf_counter()
        tokens = source_tokenizer.encode(sample["text"], out_type=str) + ["</s>"]
        translated = translator.translate_batch(
            [tokens],
            beam_size=1,
            max_decoding_length=max_tokens_for(sample),
            disable_unk=True,
        )
        translation = target_tokenizer.decode(translated[0].hypotheses[0]).strip()
        results.append(metadata_for(sample, translation, time.perf_counter() - started))

    return {
        "case": "quickmt-ct2",
        "model": model_id,
        "runtime": "quickmt-ctranslate2-cpu",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": results,
    }


def benchmark_lfm2_gguf(model_id: str, filename: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    from huggingface_hub import hf_hub_download
    from llama_cpp import Llama

    download_start = time.perf_counter()
    path = hf_hub_download(model_id, filename)
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    model = Llama(model_path=path, n_ctx=4096, n_threads=4, verbose=False)
    load_seconds = time.perf_counter() - load_start

    results = []
    for sample in samples:
        prompt = (
            "<|im_start|>system\n"
            f"Translate the following text to {sample['target_language']}.<|im_end|>\n"
            "<|im_start|>user\n"
            f"{sample['text']}<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
        started = time.perf_counter()
        response = model(
            prompt,
            max_tokens=max_tokens_for(sample),
            temperature=0.0,
            stop=["<|im_end|>"],
        )
        translation = response["choices"][0]["text"].strip()
        results.append(metadata_for(sample, translation, time.perf_counter() - started))

    return {
        "case": "lfm2-gguf",
        "model": f"{model_id}/{filename}",
        "runtime": "llama.cpp-cpu",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True, choices=["hymt2-mlx", "nllb-ct2", "quickmt-ct2", "lfm2-gguf"])
    parser.add_argument("--output")
    args = parser.parse_args()

    sampler = MemorySampler(psutil.Process(os.getpid()))
    samples = supported_samples(args.case)
    sampler.start()
    try:
        if args.case == "hymt2-mlx":
            result = benchmark_hymt2_mlx("mlx-community/Hy-MT2-1.8B-4bit", samples)
        elif args.case == "nllb-ct2":
            result = benchmark_nllb_ct2("Timteamteem/CTranslate2-nllb-200-int8", samples)
        elif args.case == "quickmt-ct2":
            result = benchmark_quickmt_ct2("quickmt/quickmt-en-ko", samples)
        else:
            result = benchmark_lfm2_gguf(
                "gyung/lfm2-1.2b-koen-mt-v8-rl-10k-merged-GGUF",
                "lfm2-1.2b-koen-mt-v8-rl-10k-merged-Q4_K_M.gguf",
                samples,
            )
    finally:
        sampler.stop()

    result["peak_rss_mb"] = round(sampler.peak_rss / 1024 / 1024, 1)
    result["sample_count"] = len(result["results"])
    result["created_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as file:
            file.write(output + "\n")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
