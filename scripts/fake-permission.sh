#!/usr/bin/env bash
# Simula um hook do Claude Code contra o EventServer do NotchAI.
#   ./scripts/fake-permission.sh                      -> PermissionRequest (fica pendurado até você decidir na notch)
#   ./scripts/fake-permission.sh question             -> AskUserQuestion de mentira, com alternativas
#   ./scripts/fake-permission.sh PreToolUse           -> hook fire-and-forget (responde na hora)
#   ./scripts/fake-permission.sh PermissionRequest 5  -> desiste depois de 5s
set -u

HOOK="${1:-PermissionRequest}"
MAX_TIME="${2:-0}"

if [ "$HOOK" = "question" ]; then
  HOOK="PermissionRequest"
  TOOL_NAME="AskUserQuestion"
  TOOL_INPUT='{
    "questions": [
      {
        "question": "Qual abordagem seguir para o cache?",
        "header": "Cache",
        "multiSelect": false,
        "options": [
          { "label": "lru_cache", "description": "Uma linha, sem dependência nova" },
          { "label": "Redis", "description": "Compartilhado entre processos, precisa de infra" },
          { "label": "Nenhum", "description": "Medir antes de otimizar" }
        ]
      }
    ]
  }'
else
  TOOL_NAME="Bash"
  TOOL_INPUT='{
    "command": "rm -rf /tmp/notchai-fake",
    "description": "Pedido de permissão de mentira"
  }'
fi

payload() {
  cat <<JSON
{
  "session_id": "fake-session-$$",
  "transcript_path": "$HOME/.claude/projects/fake/fake.jsonl",
  "cwd": "$PWD",
  "permission_mode": "default",
  "hook_event_name": "$HOOK",
  "tool_name": "$TOOL_NAME",
  "tool_use_id": "toolu_fake_$$",
  "tool_input": $TOOL_INPUT
}
JSON
}

echo "→ POST /NotchAI/v2/$HOOK  ($TOOL_NAME, tool_use_id: toolu_fake_$$)"
START=$(date +%s)

payload | curl -sf -X POST "http://127.0.0.1:7749/NotchAI/v2/$HOOK" \
  -H 'Content-Type: application/json' \
  --max-time "$MAX_TIME" \
  -d @- > /tmp/notchai-fake-response.txt
STATUS=$?

ELAPSED=$(( $(date +%s) - START ))

if [ $STATUS -ne 0 ]; then
  echo "✗ curl falhou (código $STATUS) depois de ${ELAPSED}s — NotchAI está rodando?"
  exit $STATUS
fi

echo "← respondeu em ${ELAPSED}s:"
if [ -s /tmp/notchai-fake-response.txt ]; then
  cat /tmp/notchai-fake-response.txt
  echo
else
  echo "(corpo vazio = defer, o Claude cairia no prompt do terminal)"
fi
