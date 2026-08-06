# CLAUDE.md

Guia para o Claude Code trabalhar neste repositório.

## O que é o NotchAI

App **open source para macOS** que monitora e gerencia **agentes de IA de desenvolvimento** (Claude Code, Codex CLI, Gemini CLI, OpenCode) a partir da **notch** e da **barra de menus**.

O foco é ser um **centro de monitoramento, observabilidade e interação** com os agentes em execução: quais estão ativos, em qual projeto, em que estado (trabalhando, esperando input, pedindo permissão) — e **responder ao agente direto da notch** (aprovar/negar permissões, escolher alternativas de uma pergunta) sem trocar de janela. A notch é a camada de apresentação (estilo Dynamic Island); o valor está no monitoramento e na interação.

## Stack

- **Linguagem:** Swift 5.0
- **UI:** SwiftUI
- **Plataforma:** macOS (deployment target **26.3**)
- **Projeto:** `NotchAI.xcodeproj` (sem dependências externas / SPM)

## Build e testes

```bash
xcodebuild -project NotchAI.xcodeproj -scheme NotchAI -configuration Debug build
xcodebuild -project NotchAI.xcodeproj -scheme NotchAI -destination 'platform=macOS' test
```

No dia a dia, `open NotchAI.xcodeproj` e `Cmd+R` é mais prático.

> **App Sandbox está desativado** de propósito. O `ProcessMonitorService` executa `pgrep` via `Process()`, o que o sandbox bloqueia. Não reative sem antes resolver o monitoramento de processos por outra via.

## Arquitetura (MVVM simplificado)

```text
NotchAI/
├── Views/       # SwiftUI — apenas apresentação
├── Models/      # structs de dados
├── Managers/    # estado observável / ViewModels (@MainActor, ObservableObject)
├── Services/    # acesso ao SO e recursos externos
└── Assets.xcassets/
```

Fluxo de dados: `AgentMonitor` (Manager) recebe eventos em tempo real do `EventServer` e faz polling via `ProcessMonitorService` como fallback; publica `[Agent]` e `[AgentSession]`; `ContentView` e `NotchView` observam o monitor. A janela da notch é gerenciada pelo `NotchWindowController`, com estado colapsado/expandido em `NotchState`.

O Claude Code dispara hooks (`PreToolUse`, `PostToolUse`, `Stop`, `Notification`) configurados em `~/.claude/settings.json`; o `EventServer` recebe esses eventos na porta 7749 em tempo real. O `pgrep` permanece como fallback para agentes sem hooks.

### Componentes

**Dados / monitoramento:**

- **`Models/Agent.swift`** — agente declarativo: `{ name, processName, icon, isRunning }`. Lista em `Agent.builtIn`, sem índices hardcoded.
- **`Models/AgentSession.swift`** — sessão de um agente: `{ id (sessionId), agentName, projectPath, gitBranch, state, lastActivity }` + enum `SessionState` (`working` / `waitingForInput` / `waitingForPermission` / `idle`).
- **`Services/ProcessMonitorService.swift`** — verifica presença via `pgrep -x <nome>`. Mantenha leve.
- **`Services/ClaudeSessionService.swift`** — lê os transcripts JSONL em `~/.claude/projects/`; deriva a sessão (cwd/branch a partir do prefixo de 64KB do arquivo, estado a partir do mtime). Janela ativa de 600s; `working` <15s, `waitingForInput` <120s, `idle` além disso.
- **`Services/EventServer.swift`** — servidor HTTP local TCP na porta 7749; recebe eventos de hooks do Claude Code e entrega ao `AgentMonitor` via closure `onEvent`.
- **`Services/HookInstaller.swift`** — instala/remove os hooks no `~/.claude/settings.json` (com backup automático) na primeira execução; expõe `areInstalled`, `install()` e `remove()`.
- **`Managers/AgentMonitor.swift`** — `@MainActor ObservableObject`. Polling a cada 2s; inicia o `EventServer` e o `HookInstaller` no `startMonitoring()`; aplica `waitingForPermission` em tempo real via `pendingPermissions` quando recebe `PreToolUse`.

**Apresentação:**

- **`NotchAIApp.swift`** — `@main`. Monta o `MenuBarExtra` (estilo `.window`) com a contagem `🧠 N` no label.
- **`AppDelegate.swift`** — ponto de entrada AppKit: cria o estado compartilhado, inicia o monitoramento e ancora o painel da notch.
- **`Views/ContentView.swift`** — conteúdo do `MenuBarExtra`: lista de agentes com status 🟢/🔴 e botão de sair.
- **`Views/NotchView.swift`** — UI na notch (Dynamic Island). Colapsada é **invisível**: a caixa preta tem exatamente o tamanho da notch, escondida atrás do recorte físico. Expandida no hover: sessões ativas do Claude (projeto + branch + estado colorido) e os agentes numa linha horizontal. O conteúdo fica sempre montado em largura fixa e é **recortado pela caixa** (`.clipShape`) — não use transição/delay próprios pra revelá-lo, foi assim que o fundo e o conteúdo saíam de fase.
- **`Managers/NotchState.swift`** — estado de apresentação da notch (`isExpanded`, `topInset`, `notchWidth`), compartilhado entre view e controller.
- **`Services/NotchWindowController.swift`** — cria e posiciona o `NSPanel` borderless ancorado na notch. ⚠️ Sensível, três armadilhas já resolvidas:
  - **Crash (SIGABRT):** não anime o frame da janela via AppKit; a suavidade fica por conta da animação do *conteúdo* SwiftUI.
  - **Flicker infinito no hover:** o hover é detectado por **posição do mouse** (timer 10Hz), **não** por `.onHover` do SwiftUI. O `.onHover` entrava em loop expande↔colapsa porque o `setFrame` reconstrói as tracking areas e dispara `mouseExited`/`mouseEntered` espúrios. Não volte a usar `.onHover` neste painel.
  - **O painel não redimensiona no hover:** ele vive permanentemente no tamanho expandido; `setFrame` só em mudança de tela ou de nº de sessões. O alvo do hover é o `notchRect` (+6pt) quando colapsado e o `panel.frame` quando expandido, com dwell de 0.3s pra abrir e 0.2s pra fechar. `ignoresMouseEvents` acompanha `isExpanded`, senão o painel invisível rouba clique da barra de menus.
- **`Services/NotchScreen.swift`** — geometria da notch a partir do `NSScreen`: `hasNotch`, `notchWidth`, `notchTopInset`, `notchRect`, `isFullScreenActive` (heurística de `visibleFrame`, **ainda não verificada** com app real em fullscreen). Sem tela com notch (ex.: clamshell com monitor externo), o painel some — `targetScreen` não tem fallback.

## Princípios

1. **Simplicidade** — código direto, fácil de contribuir (open source).
2. **Performance e baixo consumo** — app que roda o tempo todo em background. Prefira o mais leve (`pgrep` > `ps aux`).
3. **Experiência nativa de macOS** — SwiftUI idiomático, MenuBarExtra, comportamento na notch como Dynamic Island.
4. **Facilidade de contribuição** — adicionar um novo agente deve ser trivial (config declarativa, sem editar índices ou lógica espalhada).

## Convenções de código

- Swift idiomático e SwiftUI declarativo, seguindo o estilo já presente nos arquivos.
- Estado mutável compartilhado em Managers `@MainActor` / `ObservableObject`; Views não acessam Services diretamente.
- Toda chamada a `Process()` / SO fica em `Services/`, nunca em Views ou Models.
- Evite acoplar lógica a índices de array; prefira modelar dados que se descrevem sozinhos.
- **Não adicione comentários no código gerado pelo Claude.** Escreva código autoexplicativo; comentários só quando o usuário pedir explicitamente.

## Agentes monitorados

| Agente     | Processo (`pgrep -x`) |
|------------|-----------------------|
| Claude     | `claude`              |
| Codex      | `codex`               |
| Gemini     | `gemini`              |
| OpenCode   | `opencode`            |
