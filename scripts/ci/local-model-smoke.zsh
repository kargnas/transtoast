#!/usr/bin/env zsh
# CI smoke test for bundled local translation models. Runs the real app binary
# (--translate-text-once) so the test exercises the exact TranslationService ->
# `uv run <backend script>` path users hit, instead of a synthetic harness.
#
# Pass criteria per request: exit 0, non-empty output, output contains Hangul
# (the fixed target language is Korean), and wall time within budget.
set -euo pipefail
zmodload zsh/datetime

MODEL_ID="${1:?usage: local-model-smoke.zsh <local-model-id>}"
BINARY="${CCTRANS_BINARY:-.build/debug/CCTrans}"
# Request #1 may download the model from Hugging Face and load it cold, so it
# gets its own budget; later requests measure the warm path users feel.
COLD_BUDGET="${MODEL_CI_COLD_BUDGET:-900}"
WARM_BUDGET="${MODEL_CI_WARM_BUDGET:-120}"

# Mirrors docs/local-translation-benchmark-2026.md sample shapes: a plain
# statement, an imperative, and a sentence with "twice" (the terminology spot
# where weaker models slipped in the benchmark).
typeset -a SAMPLES
SAMPLES=(
  "The deployment failed because the database URL was missing."
  "Please summarize the release notes before the meeting."
  "Press the button twice to confirm."
)

if [[ ! -x "$BINARY" ]]; then
  print -u2 "Binary not found or not executable: $BINARY (run 'swift build' first)"
  exit 2
fi

STDERR_LOG="${TMPDIR:-/tmp}/local-model-smoke-stderr.log"
typeset -a ROWS
FAILED=0
INDEX=0

print "Smoke testing local model: $MODEL_ID"
for SAMPLE in "${SAMPLES[@]}"; do
  (( INDEX += 1 ))
  if (( INDEX == 1 )); then
    PHASE="cold"
    BUDGET=$COLD_BUDGET
  else
    PHASE="warm"
    BUDGET=$WARM_BUDGET
  fi

  START=$EPOCHREALTIME
  set +e
  OUTPUT=$("$BINARY" --translate-text-once "$SAMPLE" \
    --local-model "$MODEL_ID" \
    --source-language English \
    --target-language Korean 2>"$STDERR_LOG")
  RC=$?
  set -e
  ELAPSED=$(( EPOCHREALTIME - START ))
  ELAPSED_FMT=$(printf '%.1f' "$ELAPSED")

  STATUS="ok"
  if (( RC != 0 )); then
    STATUS="error (rc=$RC)"
  elif [[ -z "${OUTPUT//[[:space:]]/}" ]]; then
    STATUS="empty output"
  elif ! print -r -- "$OUTPUT" | LC_ALL=en_US.UTF-8 grep -qE '[가-힣]'; then
    STATUS="no Hangul in output"
  elif (( ELAPSED > BUDGET )); then
    STATUS="over budget (${ELAPSED_FMT}s > ${BUDGET}s)"
  fi

  FIRST_LINE="${OUTPUT%%$'\n'*}"
  if [[ "$STATUS" == "ok" ]]; then
    print "PASS [$PHASE ${ELAPSED_FMT}s/${BUDGET}s] $SAMPLE -> $FIRST_LINE"
  else
    FAILED=1
    print -u2 "FAIL [$PHASE ${ELAPSED_FMT}s/${BUDGET}s] $SAMPLE -> $STATUS"
    print -u2 -- "--- stdout ---"
    print -r -u2 -- "$OUTPUT"
    print -u2 -- "--- stderr ---"
    cat "$STDERR_LOG" >&2
  fi
  ROWS+=("| $PHASE | ${ELAPSED_FMT}s / ${BUDGET}s | $STATUS | $SAMPLE | ${FIRST_LINE//|/\\|} |")
done

SUMMARY="### Local model smoke: \`$MODEL_ID\`

| Phase | Time / Budget | Status | Input | Output (first line) |
|---|---:|---|---|---|
${(F)ROWS}
"
print -r -- "$SUMMARY"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  print -r -- "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"
fi

exit $FAILED
