# CLAUDE.md

Guia para o Claude Code trabalhar neste repositório. Mantenha-o atualizado conforme o projeto evolui pelas fases do roadmap.

## O que é o NotchAI

App **open source para macOS** que monitora e gerencia **agentes de IA de desenvolvimento** (Claude Code, Codex CLI, Gemini CLI, OpenCode, Ollama e ferramentas futuras) a partir da **notch** e da **barra de menus**.

O foco não é apenas a interface visual na notch — é ser um **centro de monitoramento e observabilidade** dos agentes em execução: quais estão ativos, há quanto tempo, em qual projeto, consumo de recursos e histórico. A notch é a camada de apresentação (estilo Dynamic Island); o valor está no monitoramento.

Inspiração: Vibe Notch — mas com escopo bem mais amplo que exibição visual.

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

Fluxo atual: `ContentView` → observa `AgentMonitor` (Manager) → consulta `ProcessMonitorService` (Service) → atualiza `[Agent]` (Model).

### Componentes atuais

- **`Models/Agent.swift`** — representa um agente. Hoje: `name`, `isRunning`. Ver refatoração planejada na Fase 1.
- **`Services/ProcessMonitorService.swift`** — verifica processos ativos via `pgrep -x <nome>`. Já foi `ps aux`, trocado por `pgrep` por performance. Mantenha leve.
- **`Managers/AgentMonitor.swift`** — `@MainActor ObservableObject`. Faz polling a cada 2s com `Timer` e atualiza os agentes. A lista de agentes está hardcoded e os índices (`agents[0]`...) estão acoplados — alvo da Fase 1.
- **`Views/ContentView.swift`** — lista os agentes com status 🟢/🔴 numa janela fixa. Será substituída por MenuBarExtra (Fase 2) e UI na notch (Fase 3).

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

## Roadmap

O trabalho segue por fases. Ao implementar, prefira avançar a fase atual sem antecipar complexidade das seguintes.

- **Fase 1 — Base:** refatorar `Agent` para `{ name, processName, icon, isRunning }`, eliminar duplicação e os índices hardcoded no `AgentMonitor`; cadastrar agentes de forma declarativa.
- **Fase 2 — Menu Bar:** virar `MenuBarExtra`, sem janela tradicional; mostrar contagem de agentes ativos (ex.: `🧠 2`).
- **Fase 3 — Notch:** UI ancorada na notch, expansão no hover, animações suaves, visual Dynamic Island.
- **Fase 4 — Info avançada:** por agente — tempo de execução, projeto/diretório de trabalho, estado atual, última atividade.
- **Fase 5 — Histórico:** tempo total de uso, agentes mais usados, estatísticas diárias/semanais (persistência).
- **Fase 6 — Ollama:** modelos carregados, consumo de RAM, quantidade de modelos ativos.

Integração futura com APIs dos provedores de IA está prevista, posterior às fases acima.

## Agentes monitorados (processos)

| Agente     | Processo (`pgrep -x`) |
|------------|-----------------------|
| Claude     | `claude`              |
| Codex      | `codex`               |
| Gemini     | `gemini`              |
| OpenCode   | `opencode`            |

Ollama entra na Fase 6 com monitoramento próprio (modelos/RAM), não apenas presença de processo.
