#!/usr/bin/env bash
# Compila o Models/PermissionRequest.swift de verdade e roda asserts sobre o `summary`.
#   ./scripts/check-summary.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'EOF'
import Foundation

func make(_ tool: String, _ input: [String: String]) -> PermissionRequest {
    PermissionRequest(id: "t", agentName: "Claude", sessionId: "s",
                      projectPath: "/Users/x/Projetos/NotchAI", toolName: tool,
                      toolInput: input, receivedAt: Date())
}

assert(make("Bash", ["command": "rm -rf /tmp/x", "description": "limpa"]).summary == "rm -rf /tmp/x")
assert(make("Write", ["file_path": "/a/b.swift", "content": "x"]).summary == "/a/b.swift")
assert(make("WebFetch", ["url": "https://x.dev", "prompt": "p"]).summary == "https://x.dev")
assert(make("Grep", ["pattern": "foo", "path": "/a"]).summary == "foo")
assert(make("mcp__srv__do", ["zeta": "1", "alpha": "2"]).summary == "alpha: 2")
assert(make("Weird", [:]).summary == "Weird")
assert(make("Bash", ["command": "echo  a\n  b"]).summary == "echo a b")

let long = make("Bash", ["command": String(repeating: "x", count: 300)]).summary
assert(long.count == 160 && long.hasSuffix("…"), long)
assert(make("Bash", [:]).projectName == "NotchAI")

print("ok")
EOF

swiftc -o "$WORK/check" "$ROOT/NotchAI/Models/PermissionRequest.swift" "$WORK/main.swift"
"$WORK/check"
