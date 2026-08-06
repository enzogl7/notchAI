# Plano — responder perguntas de múltipla escolha pela notch

Continuação da feature de permissões (commit `feat: answer Claude Code permission requests from the notch`).
Objetivo: quando o agente fizer uma pergunta com alternativas, a notch mostra a pergunta e as opções, e o clique responde o agente.

Este documento é auto-contido: dá pra executar sem o histórico da conversa que o gerou.

## Fatos medidos (não deduzir de novo)

Levantados com um hook de log (`cat | tee -a arquivo`) instalado em `~/.claude/settings.json`, contra Claude Code 2.1.222. **Foram medidos, não lidos na documentação** — deduzir errado aqui já custou uma sessão de debug.

1. **`AskUserQuestion` passa pelo hook `PermissionRequest`**, o mesmo que a feature de permissão já usa. Não precisa de hook novo, transporte novo nem segundo fluxo.

2. O `tool_input` traz a pergunta e as alternativas inteiras:

   ```json
   "tool_input": {
     "questions": [
       {
         "question": "texto da pergunta",
         "header": "Rótulo curto",
         "multiSelect": false,
         "options": [
           { "label": "Opção A", "description": "explicação" },
           { "label": "Opção B", "description": "explicação" }
         ]
       }
     ]
   }
   ```

3. **Dá pra responder a pergunta pelo hook.** Comprovado com um hook descartável que escolhia sempre a última opção: a pergunta se respondeu sozinha, sem prompt para o usuário. O formato é `behavior: "allow"` + `updatedInput` com o campo `answers`:

   ```json
   { "hookSpecificOutput": {
       "hookEventName": "PermissionRequest",
       "decision": { "behavior": "allow", "updatedInput": { /* tool_input original */ , "answers": { "<texto exato da pergunta>": "<label da opção>" } } } } }
   ```

   Não é preciso o truque de `deny` + `permissionDecisionReason`.

4. O `updatedInput` precisa ser o `tool_input` **inteiro** com `answers` acrescentado, não só o `answers`.

5. `Notification` com `agent_needs_input` só avisa — não tem controle de decisão.

6. O hook `Elicitation` (input pedido por servidor **MCP**) é um caminho diferente, com resposta `{ action, content }`. **Fora do escopo deste plano** e nunca medido.

## Decisões tomadas

| Decisão | Escolha |
|---|---|
| Modelo | Unificar em `AgentRequest` com `options: [Option]`; permissão vira o caso de duas opções |
| Escopo | Só pergunta única e de escolha única. Qualquer outra forma cai no terminal |
| Card | Lista vertical com `label` + `description` |
| Visual da permissão | Não muda: regra por forma da opção, não por tipo do pedido |

## Fases

### 1 — Modelo

- `Models/PermissionRequest.swift` → `AgentRequest`, com `options: [Option]` (`id`, `label`, `description: String?`) e `kind` (`.permission` / `.question`).
- Duas fábricas a partir do `HookEvent`.
- **Mudança necessária no `HookEvent`:** hoje `tool_input` é achatado para `[String: String]` (`EventServer.flatten`), então `questions` chega como string de JSON. Adicionar o `tool_input` cru (`Data`) ao evento — a resposta da fase 2 precisa devolver o input original inteiro. O mapa achatado continua servindo o `summary`.
- Guardar o `tool_input` cru no `AgentRequest` também, senão a resposta não consegue montar o `updatedInput`.

### 2 — Resposta

- `PermissionResponder.respond(to:choice:)`, com `choice: Option?` — `nil` significa timeout/defer.
- `ClaudeHookResponder` escolhe o formato pelo `kind`:
  - permissão → `{"decision": {"behavior": "allow"|"deny"}}`
  - pergunta → `{"decision": {"behavior": "allow", "updatedInput": <input original + answers>}}`
- A chave de `answers` é o **texto exato da pergunta**, extraído do payload. Nunca remontar a string.

### 3 — Filtro de escopo

- Remover `PermissionCenter.skippedTools` (hoje ignora `AskUserQuestion`, junto com o comentário `ponytail:`).
- Entra a regra: exatamente uma pergunta, `multiSelect == false`, com opções → vira card. Qualquer outra forma responde vazio (defer) e cai no terminal, onde dá pra digitar.
- **O defer é o padrão, o card é a exceção.** Se o filtro deixar passar uma forma que o card não desenha, a pergunta trava 60s em vez de aparecer no terminal.

### 4 — Card

- Opção **sem** `description` → pill horizontal (permissão fica idêntica ao que já existe).
- Opção **com** `description` → linha vertical clicável, com a descrição em cinza embaixo.
- Uma regra baseada na forma da opção. Sem `if isPermission` espalhado pela view.
- O painel já se dimensiona pelo conteúdo (`notchState.contentHeight`) — não voltar a introduzir constantes de altura.

### 5 — Verificação

- `scripts/fake-permission.sh` ganha um modo `question` com payload de `AskUserQuestion`.
- Depois, teste real: uma `AskUserQuestion` de verdade respondida pela notch.
- `scripts/check-summary.sh` quebra com o rename e precisa acompanhar.

## Riscos

- **Chave do `answers`**: acento ou espaço fora do lugar e a resposta é ignorada em silêncio.
- **O "Other" some**: toda `AskUserQuestion` tem um campo de texto livre implícito, e a notch não digita. É o preço da decisão de escopo, e a razão do filtro ser conservador.
- **Rename com risco**: `AgentRequest` renomeia um tipo que está funcionando em produção.
- O app precisa ser **reiniciado** a cada build pra valer — testar contra o binário antigo já enganou uma vez.

## Como medir de novo, se precisar

```bash
# instala sonda
python3 - <<'EOF'
import json, os
p = os.path.expanduser('~/.claude/settings.json')
d = json.load(open(p))
probe = {"hooks": [{"type": "command", "command": "cat | tee -a /tmp/notchai-probe.log > /dev/null"}]}
for k in ["PreToolUse", "PermissionRequest", "Elicitation", "Notification"]:
    d["hooks"].setdefault(k, []).append(probe)
json.dump(d, open(p, "w"), indent=2, sort_keys=True)
EOF
```

Depois provocar o evento e ler `/tmp/notchai-probe.log`. **Lembrar de remover a sonda ao terminar** — ela filtra por `notchai-probe.log` no `command`.

Requer modo de permissão diferente de `auto`: em `auto` o `PermissionRequest` não dispara, que é justamente o comportamento correto dele.
