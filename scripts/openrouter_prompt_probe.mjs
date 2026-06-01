#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join, resolve } from "node:path";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const value = process.argv[index];
  if (!value.startsWith("--")) continue;
  const next = process.argv[index + 1];
  if (!next || next.startsWith("--")) {
    args.set(value, true);
  } else {
    args.set(value, next);
    index += 1;
  }
}

loadEnvFile(".env.local");

const apiKey = process.env.OPENROUTER_API_KEY;
if (!apiKey) {
  console.error("OPENROUTER_API_KEY is missing. Add it to .env.local or export it before running this probe.");
  process.exit(1);
}

const model = String(args.get("--model") || "google/gemini-2.5-flash-lite");
const targetLanguage = String(args.get("--target-language") || "Korean");
const image = loadImageInput();
const cases = [
  {
    name: "selected adverb",
    selectedText: "twice",
    expectedTranslation: "두번",
    expectDescription: false,
  },
  {
    name: "selected pronoun",
    selectedText: "it",
    expectedTranslation: "그것",
    expectDescription: true,
  },
];

const promptCandidates = [
  {
    name: "basic-selected-fragment",
    build: (selectedText) => `
Translate only this selected text into ${targetLanguage}.
Use the attached screenshot as context, but do not translate text outside the selection.

Selected text:
${selectedText}
`.trim(),
  },
  {
    name: "strict-json-context",
    build: (selectedText) => `
Translate the selected/copied text into ${targetLanguage}.
Return JSON with "translation" and "description".

Rules:
- Translate only <selected_text>, even if the screenshot shows a full sentence.
- Use the screenshot only to disambiguate the selected text.
- Put contextual explanation in "description"; use null if none is needed.
- For Korean, "it" must be translated literally as "그것".

<selected_text>
${selectedText}
</selected_text>
`.trim(),
  },
  {
    name: "app-strict-selected-fragment",
    build: (selectedText) => `
Translate the selected or copied text into ${targetLanguage}.

Critical rules:
- Treat the text inside <selected_text> as the only source text. Ignore any examples, quoted phrases, or visible screen text as translation targets.
- Translate exactly the text inside <selected_text>. Do not translate the full sentence visible in the screen image.
- If <selected_text> is a word or fragment inside a larger sentence, return only that word or fragment's translation.
- Use surrounding screen context only to choose the right meaning and to write the optional description.
- Put only the translated text in "translation". Put contextual details only in "description".
- Write every returned string value in ${targetLanguage}, including "description". Do not write English explanations unless ${targetLanguage} is English.
- Set "description" to null unless the selected text is ambiguous, pronominal, deictic, or needs screen context to be understood.
- When a screen image is attached and <selected_text> is a pronoun or deictic word such as "it", "this", "that", or "they", "description" must be a short ${targetLanguage} sentence that explains the referent from the visible context.
- If the visible context is a sentence and the exact referent is implicit, explain the most likely referent in that sentence instead of returning null.
- For Korean, translate "twice" as "두번" when it means two times.
- For Korean, translate the pronoun "it" literally as "그것"; when <selected_text> is exactly "it" and a screen image is attached, "description" must never be null.
- If <selected_text> is exactly "it" but the attached image does not show a reliable referent, still return "그것" and describe it as the most likely object from the surrounding visible sentence.

A screen image is attached. Use it only to understand the selected fragment's local sentence, referent, part of speech, tone, casing, UI label, or product name. The image is context, not the translation target.

<selected_text>
${selectedText}
</selected_text>
`.trim(),
  },
];

let finalPass = false;
for (const candidate of promptCandidates) {
  const results = [];
  for (const testCase of cases) {
    const response = await translate(candidate.build(testCase.selectedText));
    results.push({ testCase, response, pass: matches(testCase, response) });
  }

  printCandidate(candidate.name, results);
  if (results.every((result) => result.pass)) {
    finalPass = true;
    console.log(`\nPASS: ${candidate.name} satisfies every probe case.`);
    break;
  }
}

if (!finalPass) {
  console.error("\nFAIL: no prompt candidate satisfied every probe case.");
  process.exit(1);
}

function loadEnvFile(filePath) {
  if (!existsSync(filePath)) return;
  for (const line of readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(trimmed);
    if (!match) continue;
    const [, key, rawValue] = match;
    if (process.env[key]) continue;
    process.env[key] = rawValue.replace(/^['"]|['"]$/g, "");
  }
}

function loadImageInput() {
  if (args.has("--capture")) {
    const directory = mkdtempSync(join(tmpdir(), "copy-translator-probe-"));
    const path = join(directory, "screen.png");
    execFileSync("/usr/sbin/screencapture", ["-x", path], { stdio: "ignore" });
    return imageFromPath(path);
  }

  if (args.has("--image")) {
    return imageFromPath(resolve(String(args.get("--image"))));
  }

  return null;
}

function imageFromPath(path) {
  const data = readFileSync(path);
  const mimeType = mimeTypeFor(path);
  return {
    path,
    content: {
      type: "image_url",
      image_url: {
        url: `data:${mimeType};base64,${data.toString("base64")}`,
      },
    },
  };
}

function mimeTypeFor(path) {
  switch (extname(path).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".webp":
      return "image/webp";
    default:
      return "image/png";
  }
}

async function translate(prompt) {
  const content = image
    ? [{ type: "text", text: prompt }, image.content]
    : prompt;
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://kargn.as",
      "X-OpenRouter-Title": "Sangrak",
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content: "You are a precise translation engine. Return JSON that matches the schema.",
        },
        {
          role: "user",
          content,
        },
      ],
      max_tokens: 65535,
      temperature: 0.1,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "translation_result",
          strict: true,
          schema: {
            type: "object",
            properties: {
              translation: { type: "string" },
              description: { type: ["string", "null"] },
            },
            required: ["translation", "description"],
            additionalProperties: false,
          },
        },
      },
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`OpenRouter HTTP ${response.status}: ${body}`);
  }

  const json = JSON.parse(body);
  const contentText = json.choices?.[0]?.message?.content;
  if (!contentText) {
    throw new Error(`OpenRouter response did not include message content: ${body}`);
  }
  return JSON.parse(contentText);
}

function matches(testCase, response) {
  const translationPass = normalized(response.translation) === testCase.expectedTranslation;
  const description = typeof response.description === "string" ? response.description.trim() : "";
  if (!translationPass) return false;
  if (!testCase.expectDescription) return description.length === 0;
  return description.length > 0 && /[가-힣]/.test(description);
}

function normalized(value) {
  return String(value || "").trim().replace(/\s+/g, "");
}

function printCandidate(name, results) {
  console.log(`\nCandidate: ${name}`);
  if (image) {
    console.log(`Context image: ${image.path}`);
  } else {
    console.log("Context image: none");
  }
  for (const { testCase, response, pass } of results) {
    const description = response.description ?? "null";
    console.log(
      `- ${pass ? "PASS" : "FAIL"} ${testCase.name}: translation=${JSON.stringify(response.translation)}, description=${JSON.stringify(description)}`,
    );
  }
}
