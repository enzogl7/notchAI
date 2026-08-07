# Plano — mostrar o limite de uso do agente na notch

Objetivo: mostrar quanto resta da cota de uso do usuário, com dado **real** do provedor, no menu bar e na notch expandida.

Este documento é auto-contido: dá pra executar sem o histórico da conversa que o gerou.

## Fatos medidos (não deduzir de novo)

Levantados contra Claude Code 2.1.221 (binário em `/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`) e OpenCode 1.17.15.

1. **Não existe fonte local de quota em disco.** `~/.claude.json` não guarda nada de uso/limite (as chaves `passes*` são referral, não cota). Os transcripts em `~/.claude/projects/*/*.jsonl` não têm `rateLimits`, `rate_limit`, nem aviso de "usage limit"/"resets at" — zero ocorrências.

2. **O JSON da statusline carrega a cota.** Documentado no help embutido do próprio binário:

   ```jsonc
   "rate_limits": {
     "five_hour": { "used_percentage": number, "resets_at": number },  // opcional
     "seven_day": { "used_percentage": number, "resets_at": number }   // opcional
   }
   ```

   `used_percentage` é 0–100. `resets_at` é epoch em **segundos**. Ambos os blocos são opcionais e podem estar ausentes. Esse JSON chega no **stdin** do comando configurado em `statusLine` no `~/.claude/settings.json`.

2b. **A statusline só roda no CLI do terminal — o app desktop não a executa.** Medido em 2026-08-07 contra Claude Code 2.1.223 e Claude.app: com o comando instrumentado pra logar cada execução, uma sessão `claude` no terminal registrou execução; o app desktop, reiniciado *depois* da instalação da chave, não registrou nenhuma em horas de uso. Também não há `used_percentage` em disco: o app deixa só `rate_limit_info` (`status`, `resetsAt`, `rateLimitType`, **sem percentual**) em `~/Library/Application Support/Claude/local-agent-mode-sessions/*/audit.jsonl`. Consequência: **este feature só entrega dado pra quem usa o CLI**. Decisão de 2026-08-07: aceitar essa limitação. Cobrir o app desktop exige o fato 3.

3. **Existe `/api/oauth/usage`** no binário, com os mesmos campos. **Descartado**: exige ler a credencial OAuth do Keychain (a ACL é ligada à assinatura do binário — cada rebuild do NotchAI dispara novo prompt), e é endpoint interno não documentado. A statusline entrega o mesmo dado de graça.

4. **A cota é por conta, não por sessão.** Três sessões do Claude reportam o mesmo `used_percentage`.

5. **`EventServer` roteia pelo último segmento do path** (`POST /Stop` → `hookType: "Stop"`). Um `POST /StatusLine` já entra sem tocar no parser HTTP.

6. **Os outros agentes não são variações do mesmo widget:**

   | Agente | Fonte | Unidade | Situação |
   |---|---|---|---|
   | Claude | statusline `rate_limits` (push, oficial) | % de 5h e 7d + `resets_at` | **v1** |
   | Codex | `~/.codex/sessions/*.jsonl` (pull, formato interno) | % restante 5h e semanal | fase futura |
   | OpenCode | SQLite `~/.local/share/opencode/opencode.db`, tabela `message`, colunas `cost` e `tokens_*` | **$ acumulado — não há limite** | fora da v1 |
   | Gemini | nada local conhecido; só `/stats` na sessão | requests/dia (1000/1500/2000), reset meia-noite PT | **descartado** |

   OpenCode é multi-provider/BYO-key: não existe "% do plano". Gemini exigiria o app contar requisições sozinho (e 1 prompt ≠ 1 request) — seria estimativa, que é justamente o que este plano recusa.

7. **Codex e Gemini não estão instalados nesta máquina** (`which` não encontra). O formato do JSONL do Codex precisa ser verificado in loco antes da fase futura.

## Decisões travadas

| # | Decisão | Por quê |
|---|---|---|
| 1 | Fonte: `statusLine` → `POST localhost:7749/StatusLine` | Dado real e oficial, sem credencial e sem endpoint interno |
| 2 | Transporte: closure `onStatusLine` separada; `HookEvent` intocado | `HookEvent` descreve hook; não ganha campos `nil` em 100% dos casos reais |
| 3 | `enum AgentQuota { case window(...); case spend(...); case none }` | Unidades por agente são incompatíveis (% vs. $) |
| 4 | `Agent.quota: AgentQuota?` | Cardinalidade certa: uma cota por agente (fato 4) |
| 5 | `🧠 2 · 68%` sempre no menu bar; detalhe na notch expandida | A notch colapsada é invisível por design — aviso que só aparece no hover não avisa |
| 6 | Persistir em `UserDefaults`; descartar quando `now > resets_at` | Push é reativo: sem atividade, sem dado. `resets_at` permite descartar com certeza, não com chute |
| 7 | `HookInstaller` **encadeia** a statusLine existente, silencioso | `statusLine` é slot único; sobrescrever quebra o setup de quem já tem uma |
| 8 | Verificação por script de smoke com `curl` | Os test targets foram removidos em `df25ab4`; e o que quebra é o transporte, não a função pura |

## Fases

### 1. Transporte

`Services/EventServer.swift`:

- `struct StatusLinePayload { let fiveHour: Window?; let sevenDay: Window? }`, com `struct Window { let usedPercentage: Double; let resetsAt: Date }`.
- `var onStatusLine: ((StatusLinePayload) -> Void)?`.
- Em `process(_:on:)`, antes do `decode` de hook: se o path for `StatusLine`, decodifica o payload, chama `onStatusLine` e responde vazio (não é conexão adiada — só o `PermissionRequest` difere).

Ambos os blocos são opcionais; payload sem `rate_limits` é válido e significa "sem dado".

### 2. Instalação

`Services/HookInstaller.swift` passa a gerenciar também a chave `statusLine` do `~/.claude/settings.json` (o backup automático já existe: `settings.notchai-backup.json`).

- Comando instalado: lê o stdin uma vez, dispara o `POST` para `localhost:7749/StatusLine` **em background (fire-and-forget)** e repassa o mesmo stdin para o comando original, devolvendo o stdout dele.
- Sem statusLine anterior: instala só o POST e não imprime nada.
- **`remove()` restaura o comando original** em vez de apagar a chave. O `remove()` de hoje só remove — isso precisa mudar.
- Guardar o comando original no `settings.json` do NotchAI (ou no backup) para conseguir restaurar.

> ⚠️ O comando roda **a cada render da statusline**. Se o `curl` bloquear, você adiciona latência ao terminal de todos os usuários. É a única parte que, feita errado, piora a vida de quem instalou.

### 3. Modelo

- `Models/AgentQuota.swift`: o enum. O caso `.spend` existe como forma e **nada o popula na v1** — sem leitor de SQLite, sem layout próprio.
- `Models/Agent.swift`: `var quota: AgentQuota?`.
- `Managers/AgentMonitor.swift`: liga `eventServer.onStatusLine`, aplica no agente "Claude", persiste em `UserDefaults` e restaura no `startMonitoring()`. Ao ler (do disco ou da memória), descarta janela cujo `resetsAt` já passou.

### 4. UI

- `NotchAIApp.swift`: label do `MenuBarExtra` vira `🧠 N · P%` com o `used_percentage` da janela de 5h. **Sem dado, volta a ser `🧠 N`** — nunca mostrar `0%` nem `—`, que o usuário lê como "estou zerado".
- `Views/NotchView.swift`: bloco na área expandida com 5h e 7d, percentual e tempo restante até o reset, mais a hora da última leitura.
- **Não encostar em `NotchWindowController.swift`.** O CLAUDE.md marca esse arquivo como sensível (três armadilhas já resolvidas) e nada aqui exige mexer nele.

### 5. Smoke

Script no repo que faz `POST` em `:7749/StatusLine` com três payloads e confere o resultado no menu bar:

1. `rate_limits` completo (5h e 7d) → label mostra o percentual;
2. payload sem `rate_limits` → label volta a `🧠 N`;
3. `resets_at` no passado → valor descartado, label sem percentual.

## Fora de escopo

- Codex, Gemini e o `.spend` do OpenCode.
- Múltiplas contas/organizações — o modelo assume uma.
- Atualização com sessão parada: o canal é reativo por natureza. A notch mostra a hora da última leitura em vez de fingir tempo real.
- Qualquer indicador na notch colapsada.
