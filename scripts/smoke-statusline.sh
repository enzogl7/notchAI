#!/usr/bin/env bash
set -euo pipefail

URL="http://127.0.0.1:7749/NotchAI/v3/StatusLine"
now=$(date +%s)

post() {
    curl -sf -m 2 -X POST "$URL" -H 'Content-Type: application/json' -d "$1" >/dev/null
    echo "→ $2"
    read -r -p "  confirma na barra de menus? [enter] " _
}

post "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":68,\"resets_at\":$((now + 7200))},\"seven_day\":{\"used_percentage\":41,\"resets_at\":$((now + 400000))}}}" \
    "esperado: 🧠 N · 68%  (notch expandida: 5h 68%, 7d 41%)"

post '{"session_id":"abc"}' \
    "esperado: 🧠 N sem percentual (payload sem rate_limits)"

post "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":91,\"resets_at\":$((now - 60))}}}" \
    "esperado: 🧠 N sem percentual (resets_at no passado, valor descartado)"

echo "ok"
