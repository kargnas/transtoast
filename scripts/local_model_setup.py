# /// script
# requires-python = ">=3.12"
# ///

import argparse
import json
from pathlib import Path


DEFAULT_PATH = Path.home() / ".config" / "copy-translator" / "local-models.json"


TEMPLATE = [
    {
        "id": "my-custom-translator",
        "title": "My Custom Translator",
        "runtime": "custom-process",
        "modelID": "vendor/model-name",
        "artifactName": None,
        "supportedSourceLanguages": ["English", "Korean"],
        "supportedTargetLanguages": ["Korean", "English"],
        "qualityNote": "Describe where this model works well.",
        "licenseNote": "Add license or usage constraint.",
        "isRecommended": False,
        "includeInFirstRunBenchmark": False,
        "customBackendPath": "/absolute/path/to/my_backend.py",
        "setupCommand": ["uv", "run", "/absolute/path/to/setup_model.py"],
    }
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--print-template", action="store_true")
    parser.add_argument("--write-template", action="store_true")
    args = parser.parse_args()

    data = json.dumps(TEMPLATE, ensure_ascii=False, indent=2)
    if args.print_template:
        print(data)
        return 0

    if args.write_template:
        args.path.parent.mkdir(parents=True, exist_ok=True)
        if args.path.exists():
            raise SystemExit(f"{args.path} already exists; move it before writing a template.")
        args.path.write_text(data + "\n", encoding="utf-8")
        print(args.path)
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
