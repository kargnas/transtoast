# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "mlx-lm>=0.29.0",
# ]
# ///

import json
import sys
from typing import Any


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        text = str(payload["text"]).strip()
        source_language = str(payload.get("source_language") or "Auto").strip()
        target_language = str(payload.get("target_language") or "Korean").strip()
        model_id = str(payload.get("model_id") or "mlx-community/Hy-MT2-1.8B-4bit").strip()
        prompt = str(payload.get("prompt") or "").strip() or (
            f"Translate the following {source_language} text into {target_language}.\n"
            "Only output the translated result without any additional explanation:\n\n"
            f"{text}"
        )
        if not text:
            raise ValueError("No text was provided.")

        translation = translate(model_id=model_id, prompt=prompt)
        print(json.dumps({"translation": translation}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        return 1


def translate(model_id: str, prompt: str) -> str:
    from mlx_lm import generate, load

    model, tokenizer = load(model_id)
    formatted_prompt = format_prompt(tokenizer=tokenizer, prompt=prompt)
    output = generate(
        model,
        tokenizer,
        prompt=formatted_prompt,
        max_tokens=2048,
        verbose=False,
    )
    return clean_output(prompt=formatted_prompt, output=output)


def format_prompt(tokenizer: Any, prompt: str) -> str:
    messages = [{"role": "user", "content": prompt}]
    apply_chat_template = getattr(tokenizer, "apply_chat_template", None)
    if apply_chat_template is None:
        return prompt

    try:
        return apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False,
        )
    except Exception:
        return prompt


def clean_output(prompt: str, output: str) -> str:
    cleaned = output.strip()
    if cleaned.startswith(prompt):
        cleaned = cleaned[len(prompt) :].strip()
    return cleaned


if __name__ == "__main__":
    raise SystemExit(main())
