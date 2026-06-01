# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "ctranslate2",
#   "huggingface_hub",
#   "llama-cpp-python",
#   "mlx-lm",
#   "peft",
#   "psutil",
#   "sentencepiece",
#   "torch",
#   "transformers>=4.56.0",
# ]
# ///

import argparse
import json
import os
import threading
import time
from dataclasses import dataclass
from typing import Callable

import psutil


DEFAULT_INPUTS = [
    "The deployment failed because the database URL was missing.",
    "Please summarize the release notes before the meeting.",
    "twice",
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


def benchmark_ctranslate2_nllb(model_id: str, texts: list[str]) -> dict:
    import ctranslate2
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer

    download_start = time.perf_counter()
    path = snapshot_download(model_id)
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(path, src_lang="eng_Latn")
    translator = ctranslate2.Translator(path, device="cpu", compute_type="int8")
    load_seconds = time.perf_counter() - load_start

    outputs = []
    for text in texts:
        started = time.perf_counter()
        tokens = tokenizer.convert_ids_to_tokens(tokenizer.encode(text))
        translated = translator.translate_batch(
            [tokens],
            target_prefix=[["kor_Hang"]],
            beam_size=1,
            max_decoding_length=128,
        )
        output_tokens = translated[0].hypotheses[0]
        output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
        output = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": model_id,
        "runtime": "ctranslate2-cpu-int8",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def benchmark_ctranslate2_marian(model_id: str, texts: list[str]) -> dict:
    import ctranslate2
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer

    download_start = time.perf_counter()
    path = snapshot_download(model_id)
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(path)
    translator = ctranslate2.Translator(path, device="cpu")
    load_seconds = time.perf_counter() - load_start

    outputs = []
    for text in texts:
        started = time.perf_counter()
        tokens = tokenizer.convert_ids_to_tokens(tokenizer.encode(text))
        translated = translator.translate_batch([tokens], beam_size=1, max_decoding_length=128)
        output_tokens = translated[0].hypotheses[0]
        output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
        output = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": model_id,
        "runtime": "ctranslate2-cpu",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def benchmark_quickmt_ctranslate2(model_id: str, texts: list[str]) -> dict:
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

    outputs = []
    for text in texts:
        started = time.perf_counter()
        tokens = source_tokenizer.encode(text, out_type=str) + ["</s>"]
        translated = translator.translate_batch(
            [tokens],
            beam_size=1,
            max_decoding_length=128,
            disable_unk=True,
        )
        output = target_tokenizer.decode(translated[0].hypotheses[0]).strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": model_id,
        "runtime": "quickmt-ctranslate2-cpu",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def benchmark_mlx_lm(model_id: str, texts: list[str]) -> dict:
    from mlx_lm import generate, load

    load_start = time.perf_counter()
    model, tokenizer = load(model_id)
    load_seconds = time.perf_counter() - load_start

    outputs = []
    for text in texts:
        prompt = f"Translate the following text into Korean. Only output the translated result.\n\n{text}"
        try:
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": prompt}],
                add_generation_prompt=True,
                tokenize=False,
            )
        except Exception:
            pass
        started = time.perf_counter()
        output = generate(model, tokenizer, prompt=prompt, max_tokens=128, verbose=False).strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": model_id,
        "runtime": "mlx-lm",
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def benchmark_llama_cpp_gguf(model_id: str, filename: str, prompt_style: str, texts: list[str]) -> dict:
    from huggingface_hub import hf_hub_download
    from llama_cpp import Llama

    download_start = time.perf_counter()
    path = hf_hub_download(model_id, filename)
    download_seconds = time.perf_counter() - download_start

    load_start = time.perf_counter()
    model = Llama(model_path=path, n_ctx=4096, n_threads=4, verbose=False)
    load_seconds = time.perf_counter() - load_start

    outputs = []
    for text in texts:
        if prompt_style == "lfm2-koen":
            prompt = (
                "<|im_start|>system\n"
                "Translate the following text to Korean.<|im_end|>\n"
                "<|im_start|>user\n"
                f"{text}<|im_end|>\n"
                "<|im_start|>assistant\n"
            )
            stop = ["<|im_end|>"]
        else:
            prompt = f"Translate the following text into Korean. Only output the translated result.\n\n{text}\n"
            stop = ["</s>"]

        started = time.perf_counter()
        response = model(prompt, max_tokens=128, temperature=0.0, stop=stop)
        output = response["choices"][0]["text"].strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": f"{model_id}/{filename}",
        "runtime": "llama.cpp-cpu",
        "download_seconds": round(download_seconds, 2),
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def benchmark_gemma_lora(model_id: str, base_model: str, texts: list[str]) -> dict:
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    token = os.environ.get("HF_TOKEN")
    load_start = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(model_id, token=token)
    model = AutoModelForCausalLM.from_pretrained(
        base_model,
        dtype=torch.bfloat16,
        device_map="auto",
        token=token,
    )
    model = PeftModel.from_pretrained(model, model_id, token=token)
    model.eval()
    load_seconds = time.perf_counter() - load_start

    outputs = []
    for text in texts:
        prompt = f"Translate English to Korean. Output only Korean.\nEnglish: {text}\nKorean:"
        try:
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": prompt}],
                add_generation_prompt=True,
                tokenize=False,
            )
        except Exception:
            pass
        inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
        started = time.perf_counter()
        with torch.no_grad():
            generated = model.generate(**inputs, max_new_tokens=128, do_sample=False)
        completion = generated[0][inputs["input_ids"].shape[-1] :]
        output = tokenizer.decode(completion, skip_special_tokens=True).strip()
        outputs.append({"input": text, "translation": output, "seconds": round(time.perf_counter() - started, 3)})

    return {
        "model": model_id,
        "base_model": base_model,
        "runtime": "transformers-peft",
        "load_seconds": round(load_seconds, 2),
        "results": outputs,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--case",
        required=True,
        choices=["nllb-ct2", "marian-ct2", "quickmt-ct2", "hy-mt15-mlx", "llama-gguf", "gemma3-lora"],
    )
    parser.add_argument("--model", required=True)
    parser.add_argument("--base-model")
    parser.add_argument("--filename")
    parser.add_argument("--prompt-style", default="generic")
    parser.add_argument("--output")
    args = parser.parse_args()

    sampler = MemorySampler(psutil.Process(os.getpid()))
    cases: dict[str, Callable[[], dict]] = {
        "nllb-ct2": lambda: benchmark_ctranslate2_nllb(args.model, DEFAULT_INPUTS),
        "marian-ct2": lambda: benchmark_ctranslate2_marian(args.model, DEFAULT_INPUTS),
        "quickmt-ct2": lambda: benchmark_quickmt_ctranslate2(args.model, DEFAULT_INPUTS),
        "hy-mt15-mlx": lambda: benchmark_mlx_lm(args.model, DEFAULT_INPUTS),
        "llama-gguf": lambda: benchmark_llama_cpp_gguf(
            args.model,
            args.filename or "",
            args.prompt_style,
            DEFAULT_INPUTS,
        ),
        "gemma3-lora": lambda: benchmark_gemma_lora(args.model, args.base_model or "google/gemma-3-1b-it", DEFAULT_INPUTS),
    }

    sampler.start()
    try:
        result = cases[args.case]()
    finally:
        sampler.stop()

    result["peak_rss_mb"] = round(sampler.peak_rss / 1024 / 1024, 1)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as file:
            file.write(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
