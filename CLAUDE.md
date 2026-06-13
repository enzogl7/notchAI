# CLAUDE.md

Guia para o Claude Code trabalhar neste repositório. Mantenha-o atualizado conforme o projeto evolui pelas fases do roadmap.

## O que é o NotchAI

App **open source para macOS** que monitora e gerencia **agentes de IA de desenvolvimento** (Claude Code, Codex CLI, Gemini CLI, OpenCode, Ollama e ferramentas futuras) a partir da **notch** e da **barra de menus**.

O foco não é apenas a interface visual na notch — é ser um **centro de monitoramento, observabilidade e interação** com os agentes em execução: quais estão ativos, há quanto tempo, em qual projeto, em que estado (trabalhando, esperando input, pedindo permissão), consumo de recursos e histórico — e **responder ao agente direto da notch** (aprovar/negar permissões, responder perguntas, revisar planos) sem trocar de janela. A notch é a camada de apresentação (estilo Dynamic Island); o valor está no monitoramento e na interação.

Inspiração/referência: **Vibe Island** (vibeisland.app) — app nativo macOS que monitora 16+ agentes pela Dynamic Island e permite aprovar permissões, responder perguntas e revisar planos a partir da notch. O NotchAI persegue esse mesmo norte, em código aberto.

## Stack

- **Linguagem:** Swift 5.0
- **UI:** SwiftUI
- **Plataforma:** macOS (deployment target **26.3**)
- **Projeto:** `NotchAI.xcodeproj` (sem dependências externas / SPM até o momento)

## Build, run e testes

```bash
# Build
xcodebuild -project NotchAI.xcodeproj -scheme NotchAI -configuration Debug build

# Testes (unit + UI)
xcodebuild -project NotchAI.xcodeproj -scheme NotchAI -destination 'platform=macOS' test
```

No dia a dia, abrir no Xcode (`open NotchAI.xcodeproj`) e rodar com `Cmd+R` costuma ser mais prático.

> **App Sandbox está desativado** de propósito. O `ProcessMonitorService` executa `Process()` (`pgrep`), o que o sandbox bloqueia. Não reative a capability App Sandbox sem antes resolver o monitoramento de processos por outra via — isso quebra a funcionalidade principal.

## Arquitetura (MVVM simplificado)

Separação por responsabilidade. Ao criar arquivos novos, respeite estas pastas:

```text
NotchAI/
├── Views/       # SwiftUI — apenas apresentação
├── Models/      # structs de dados (Agent, ...)
├── Managers/    # estado observável / ViewModels (@MainActor, ObservableObject)
├── Services/    # acesso ao SO e a recursos externos (processos, Ollama, APIs)
└── Assets.xcassets/
```

Fluxo atual (orientado a polling): `AgentMonitor` (Manager) faz polling via `ProcessMonitorService` (Service) e publica `[Agent]` (Model); `ContentView` (barra de menus) e `NotchView` (notch) observam o monitor. A janela da notch é gerenciada pelo `NotchWindowController`, com o estado colapsado/expandido em `NotchState`.

> **Pivô planejado (Fase 5):** sair de *polling de presença* para *eventos empurrados* pelos agentes. O Claude Code dispara hooks (`PreToolUse`, `Notification`, `Stop`, ...) configuráveis em `~/.claude/settings.json`; o app passa a hospedar um servidor IPC local que recebe esses eventos em tempo real (e, no caso de permissão, devolve a decisão do usuário ao agente). O `pgrep` permanece como fallback para agentes sem hooks.

### Componentes atuais

Dados / monitoramento:
- **`Models/Agent.swift`** — agente declarativo: `{ name, processName, icon, isRunning }`. Lista em `Agent.builtIn`, sem índices hardcoded. ✅ Fase 1.
- **`Models/AgentSession.swift`** — sessão de um agente: `{ id (sessionId), agentName, projectPath, gitBranch, state, lastActivity }` + enum `SessionState` (`working` / `waitingForInput` / `waitingForPermission` / `idle`). ✅ Fase 4.
- **`Services/ProcessMonitorService.swift`** — verifica presença via `pgrep -x <nome>`. Já foi `ps aux`, trocado por `pgrep` por performance. Mantenha leve.
- **`Services/ClaudeSessionService.swift`** — lê os transcripts JSONL em `~/.claude/projects/`; deriva a sessão (cwd/branch a partir do prefixo de 64KB do arquivo, estado a partir do mtime). Janela ativa de 600s; `working` <15s, `waitingForInput` <120s, `idle` além disso. Sem hooks ainda — `waitingForPermission` fica para as Fases 5/6. ✅ Fase 4.
- **`Managers/AgentMonitor.swift`** — `@MainActor ObservableObject`. Polling a cada 2s com `Timer`; roda `pgrep` + leitura de sessões fora da main actor e publica `[Agent]` e `[AgentSession]`. Expõe `activeCount`.

Apresentação:
- **`NotchAIApp.swift`** — `@main`. Monta o `MenuBarExtra` (estilo `.window`) com a contagem `🧠 N` no label. ✅ Fase 2.
- **`AppDelegate.swift`** — ponto de entrada AppKit: cria o estado compartilhado, inicia o monitoramento e ancora o painel da notch.
- **`Views/ContentView.swift`** — conteúdo do `MenuBarExtra`: lista de agentes com status 🟢/🔴 e botão de sair.
- **`Views/NotchView.swift`** — UI na notch (Dynamic Island). Colapsada: `🧠` + contagem; expandida no hover: sessões ativas do Claude (projeto + branch + estado colorido) e a lista de agentes por presença. ✅ Fases 3–4.
- **`Managers/NotchState.swift`** — estado de apresentação da notch (`isExpanded`, `topInset`), compartilhado entre view e controller.
- **`Services/NotchWindowController.swift`** — cria e posiciona o `NSPanel` borderless ancorado na notch; redimensiona entre colapsado/expandido. ⚠️ Sensível, duas armadilhas já resolvidas:
  - **Crash (SIGABRT):** os comentários no arquivo documentam crashes ao animar o frame da janela via AppKit — não reintroduza; a suavidade fica por conta da animação do *conteúdo* SwiftUI.
  - **Flicker infinito no hover:** o hover é detectado por **posição do mouse** (timer 10Hz testando `panel.frame.contains(NSEvent.mouseLocation)`), **não** por `.onHover` do SwiftUI. Como o painel se redimensiona, o `.onHover` entrava em loop expande↔colapsa: o `setFrame` reconstrói as tracking areas e dispara `mouseExited`/`mouseEntered` espúrios com o cursor parado. Não volte a usar `.onHover` neste painel.
- **`Services/NotchScreen.swift`** — geometria da notch a partir do `NSScreen`: `hasNotch`, `notchWidth`, `notchTopInset`, etc.

## Princípios (toda decisão arquitetural deve priorizar)

1. **Simplicidade** — código direto, fácil de contribuir (open source).
2. **Performance e baixo consumo de recursos** — é um app que roda o tempo todo em background. Evite polling caro, prefira o mais leve (`pgrep` > `ps aux`).
3. **Experiência nativa de macOS** — SwiftUI idiomático, MenuBarExtra, comportamento na notch como Dynamic Island.
4. **Facilidade de contribuição** — adicionar um novo agente deve ser trivial (config declarativa, sem editar índices ou lógica espalhada).

## Convenções de código

- Swift idiomático e SwiftUI declarativo, seguindo o estilo já presente nos arquivos.
- Estado mutável compartilhado em Managers `@MainActor` / `ObservableObject`; Views não acessam Services diretamente.
- Toda chamada a `Process()` / SO fica em `Services/`, nunca em Views ou Models.
- Evite acoplar lógica a índices de array (ver dívida técnica no `AgentMonitor`); prefira modelar dados que se descrevem sozinhos.
- **Não adicione comentários no código gerado pelo Claude.** Escreva código autoexplicativo (nomes claros, funções pequenas); deixe o código falar por si. Comentários só quando o usuário pedir explicitamente.

## Roadmap

O trabalho segue por fases. Ao implementar, prefira avançar a fase atual sem antecipar complexidade das seguintes.

Status: **Fases 1–3 concluídas** (base declarativa, MenuBarExtra, UI na notch). O foco agora é o salto de *monitor de presença* para *centro de interação* — daí a reordenação das fases a partir da 4. **Fases 4 e 5 destravam todo o resto.**

Concluído:
- **Fase 1 — Base ✅:** `Agent` declarativo `{ name, processName, icon, isRunning }`, sem índices hardcoded; agentes cadastrados em `Agent.builtIn`.
- **Fase 2 — Menu Bar ✅:** `MenuBarExtra` (sem janela tradicional) com contagem de ativos (`🧠 N`).
- **Fase 3 — Notch ✅:** painel ancorado na notch, expansão no hover, visual Dynamic Island.
- **Fase 4 — Estado real do agente ✅:** sessões do Claude lidas dos transcripts JSONL (`ClaudeSessionService`) — projeto/branch, última atividade e estado por mtime; refletido na notch com cor por estado. Pendências deixadas para depois: tempo de **início** da sessão, consumo de **tokens** (Fase 9) e `waitingForPermission` real (precisa de hooks — Fase 5/6). O estado atual é heurístico (baseado em tempo desde a última escrita).

A fazer (ordem sugerida):
- **Fase 5 — Canal de eventos (fundação):** `EventServer` em `Services/` (HTTP local ou Unix socket) + instalador que escreve os hooks no `~/.claude/settings.json` na primeira execução (com backup e opção de remover). O estado passa a ser *empurrado* em tempo real; `pgrep` vira fallback.
- **Fase 6 — Aprovação de permissão na notch (recurso-âncora):** hook `PreToolUse` bloqueia, envia o pedido ao app, a notch mostra ferramenta + argumentos com Aprovar/Negar, e o app devolve a decisão (`allow`/`deny`) ao agente.
- **Fase 7 — Perguntas e review de plano:** mesmo canal — campo de texto para responder perguntas do agente; render de Markdown para revisar planos antes de aprovar.
- **Fase 8 — Pular pro terminal:** mapear sessão → tty → janela do terminal (via PID/tty) e focar com AppleScript/Accessibility (iTerm2, Terminal.app, Ghostty…). Começar com 1–2 terminais.
- **Fase 9 — Uso/quota e som:** tokens consumidos a partir dos JSONL (abordagem estilo `ccusage`); alertas sonoros (8-bit) configuráveis.
- **Fase 10 — Histórico:** tempo total de uso, agentes mais usados, estatísticas diárias/semanais (persistência).
- **Fase 11 — Ollama:** modelos carregados, consumo de RAM, quantidade de modelos ativos.
- **Fase 12 — Agentes adicionais e SSH remoto:** ampliar a lista de agentes; relay em servidor remoto monitorado via túnel SSH.

Integração futura com APIs dos provedores de IA segue prevista, posterior às fases acima.

## Agentes monitorados (processos)

| Agente     | Processo (`pgrep -x`) |
|------------|-----------------------|
| Claude     | `claude`              |
| Codex      | `codex`               |
| Gemini     | `gemini`              |
| OpenCode   | `opencode`            |

Ollama entra na Fase 11 com monitoramento próprio (modelos/RAM), não apenas presença de processo.
