#!/usr/bin/env bash
# Session Recap Hook — fires on SessionEnd, writes per-session recaps and
# updates a per-project Karpathy-style concept wiki in <project>/.claude/knowledge/.
#
# Override model/budget via CLAUDE_RECAP_MODEL and CLAUDE_RECAP_BUDGET.

set -u

GLOBAL_ERROR_LOG="$HOME/.claude/knowledge/_errors.log"
mkdir -p "$(dirname "$GLOBAL_ERROR_LOG")"

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$GLOBAL_ERROR_LOG"
}

# --- Recursion guard: the recap itself runs `claude -p`, which would retrigger this hook ---
if [[ -n "${CLAUDE_RECAP_RUNNING:-}" ]]; then
  exit 0
fi

# --- Read hook payload from stdin ---
HOOK_JSON=$(cat)
TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty' <<<"$HOOK_JSON")
SESSION_ID=$(jq -r '.session_id // empty' <<<"$HOOK_JSON")
CWD=$(jq -r '.cwd // empty' <<<"$HOOK_JSON")

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  log_error "no transcript at: '$TRANSCRIPT_PATH' (session=$SESSION_ID)"
  exit 0
fi
if [[ -z "$CWD" || ! -d "$CWD" ]]; then
  log_error "invalid cwd: '$CWD' (session=$SESSION_ID)"
  exit 0
fi

# --- Only operate in git repos (keeps .claude/knowledge/ out of $HOME and scratch dirs) ---
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  log_error "skip: not a git repo: $CWD (session=$SESSION_ID)"
  exit 0
fi

KNOWLEDGE_DIR="$CWD/.claude/knowledge"

# --- Meaningfulness gate: skip quick throwaway sessions ---
USER_MSGS=$(grep -c '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
TOOL_CALLS=$(grep -c '"type":"tool_use"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)

if (( USER_MSGS < 5 && TOOL_CALLS < 10 )); then
  if [[ -d "$KNOWLEDGE_DIR" ]]; then
    printf '[%s] skipped (below threshold: %s user msgs, %s tool calls, session=%s)\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$USER_MSGS" "$TOOL_CALLS" "$SESSION_ID" \
      >> "$KNOWLEDGE_DIR/log.md"
  fi
  exit 0
fi

# --- Scaffold the knowledge directory ---
mkdir -p "$KNOWLEDGE_DIR/recaps" "$KNOWLEDGE_DIR/concepts"
if [[ ! -f "$KNOWLEDGE_DIR/index.md" ]]; then
  printf '# Knowledge Index\n\n## Concepts\n\n## Recent Sessions\n' > "$KNOWLEDGE_DIR/index.md"
fi
if [[ ! -f "$KNOWLEDGE_DIR/log.md" ]]; then
  printf '# Hook Log\n\n' > "$KNOWLEDGE_DIR/log.md"
fi

# --- Load and template the ingest prompt ---
PROMPT_TEMPLATE="${CLAUDE_PLUGIN_ROOT:-}/hooks/session-recap-prompt.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  log_error "missing prompt template: $PROMPT_TEMPLATE (session=$SESSION_ID)"
  exit 0
fi

PROJECT_SLUG=$(basename "$CWD")
TIMESTAMP=$(date '+%Y-%m-%d-%H%M')
DATE_HUMAN=$(date '+%Y-%m-%d %H:%M')

PROMPT=$(awk -v tp="$TRANSCRIPT_PATH" -v kd="$KNOWLEDGE_DIR" -v ps="$PROJECT_SLUG" \
            -v ts="$TIMESTAMP" -v dh="$DATE_HUMAN" -v sid="$SESSION_ID" \
            -v um="$USER_MSGS" -v tc="$TOOL_CALLS" '
  {
    gsub(/\{\{TRANSCRIPT_PATH\}\}/, tp)
    gsub(/\{\{KNOWLEDGE_DIR\}\}/, kd)
    gsub(/\{\{PROJECT_SLUG\}\}/, ps)
    gsub(/\{\{TIMESTAMP\}\}/, ts)
    gsub(/\{\{DATE_HUMAN\}\}/, dh)
    gsub(/\{\{SESSION_ID\}\}/, sid)
    gsub(/\{\{USER_MSGS\}\}/, um)
    gsub(/\{\{TOOL_CALLS\}\}/, tc)
    print
  }
' "$PROMPT_TEMPLATE")

# --- Invoke Claude headlessly to perform the ingest ---
export CLAUDE_RECAP_RUNNING=1
MODEL="${CLAUDE_RECAP_MODEL:-claude-sonnet-4-6}"
BUDGET="${CLAUDE_RECAP_BUDGET:-1.00}"
TMP_OUT=$(mktemp -t claude-recap.XXXXXX)

cd "$KNOWLEDGE_DIR" || { log_error "cd failed: $KNOWLEDGE_DIR"; exit 0; }

if claude -p \
    --model "$MODEL" \
    --allowed-tools "Read,Write,Edit,Glob" \
    --permission-mode acceptEdits \
    --no-session-persistence \
    --max-budget-usd "$BUDGET" \
    "$PROMPT" > "$TMP_OUT" 2>&1; then
  printf '[%s] recap written (session=%s, msgs=%s, tools=%s, model=%s)\n' \
    "$DATE_HUMAN" "$SESSION_ID" "$USER_MSGS" "$TOOL_CALLS" "$MODEL" \
    >> "$KNOWLEDGE_DIR/log.md"
  rm -f "$TMP_OUT"
else
  log_error "claude -p failed (session=$SESSION_ID, cwd=$CWD): $(tail -20 "$TMP_OUT" | tr '\n' ' ')"
  rm -f "$TMP_OUT"
fi

exit 0
