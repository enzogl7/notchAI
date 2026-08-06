#!/usr/bin/env bash
# Compila Models/AgentRequest.swift de verdade e roda asserts sobre `summary`,
# o filtro de perguntas de múltipla escolha e o payload de resposta ao hook.
#   ./scripts/check-summary.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'EOF'
import Foundation

func event(_ tool: String, _ input: [String: Any]) -> HookEvent {
    HookEvent(
        hookType: "PermissionRequest",
        requestId: "t",
        sessionId: "s",
        toolName: tool,
        toolInput: input.compactMapValues { $0 as? String },
        rawToolInput: try? JSONSerialization.data(withJSONObject: input),
        cwd: "/Users/x/Projetos/NotchAI",
        permissionMode: "default",
        notificationType: nil,
        transcriptPath: nil
    )
}

func make(_ tool: String, _ input: [String: Any]) -> AgentRequest {
    AgentRequest(event: event(tool, input))
}

// summary
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

// permissão: sempre duas opções sem descrição
let permission = make("Bash", ["command": "ls"])
assert(permission.options.map(\.id) == ["deny", "allow"])
assert(permission.options.allSatisfy { $0.description == nil })

// pergunta dentro do escopo: uma pergunta, escolha única, com opções
func question(_ questions: [[String: Any]]) -> AgentRequest {
    make("AskUserQuestion", ["questions": questions])
}

let single: [String: Any] = [
    "question": "Qual abordagem?",
    "header": "Abordagem",
    "multiSelect": false,
    "options": [
        ["label": "Opção A", "description": "explica A"],
        ["label": "Opção B"]
    ]
]

let ask = question([single])
assert(ask.summary == "Qual abordagem?")
assert(ask.options.map(\.label) == ["Opção A", "Opção B"])
assert(ask.options[0].description == "explica A")
assert(ask.options[1].description == nil)

// fora do escopo → sem opções, o PermissionCenter defere pro terminal
var multi = single
multi["multiSelect"] = true
assert(question([multi]).options.isEmpty)
assert(question([single, single]).options.isEmpty)
assert(question([]).options.isEmpty)

var noOptions = single
noOptions["options"] = []
assert(question([noOptions]).options.isEmpty)

var badOption = single
badOption["options"] = [["description": "sem label"]]
assert(question([badOption]).options.isEmpty)

// payload
assert(ClaudeHookResponder.payload(for: permission, choice: nil) == nil)

let allowed = ClaudeHookResponder.payload(for: permission, choice: permission.options[1])!
assert(allowed == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#, allowed)

let denied = ClaudeHookResponder.payload(for: permission, choice: permission.options[0])!
assert(denied.contains(#""behavior":"deny""#), denied)

let answer = ClaudeHookResponder.payload(for: ask, choice: ask.options[0])!
let decoded = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as! [String: Any]
let decision = (decoded["hookSpecificOutput"] as! [String: Any])["decision"] as! [String: Any]
assert(decision["behavior"] as! String == "allow")

let updated = decision["updatedInput"] as! [String: Any]
assert(updated["answers"] as! [String: String] == ["Qual abordagem?": "Opção A"])
assert((updated["questions"] as! [[String: Any]]).count == 1, "updatedInput precisa levar o tool_input inteiro")

print("ok")
EOF

swiftc -o "$WORK/check" \
  "$ROOT/NotchAI/Models/AgentRequest.swift" \
  "$ROOT/NotchAI/Services/EventServer.swift" \
  "$ROOT/NotchAI/Services/PermissionResponder.swift" \
  "$WORK/main.swift"
"$WORK/check"
