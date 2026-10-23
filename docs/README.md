# docs/ — índice do conhecimento do lab

A raiz do repositório é **código e configuração**. Aqui fica o que explica, decide, ensina e
conserta. **Todo documento desta árvore está listado abaixo** — a suíte falha se um `.md` de
`docs/` não aparecer neste índice.

## Como entrar no projeto

1. **`AGENTS.md`** (raiz) — regras, invariantes, deploy e armadilhas. Manda em tudo.
2. **`ai-memory.md`** — o que já deu certo, o que já deu problema e por quê.
3. **`runbooks/TROUBLESHOOTING.md`** — algo quebrou? comece aqui, por sintoma.
4. **`reports/RELATORIO-LACUNAS.md`** — o que ainda falta endurecer, com evidência.

## Operação: conserto e diagnóstico

| Documento | Use quando |
|---|---|
| [`runbooks/TROUBLESHOOTING.md`](runbooks/TROUBLESHOOTING.md) | triagem por sintoma (chat, memória, RAG, alertas, backup, CI) |
| [`runbooks/servicos/`](runbooks/servicos/) | um container específico está fora, lento ou com dados errados |
| [`runbooks/scripts/`](runbooks/scripts/) | um script agendado/de deploy falhou, ou você precisa rodá-lo à mão |

### Um card por serviço (12 containers)

| Serviço | O que é |
|---|---|
| [`runbooks/servicos/open-webui.md`](runbooks/servicos/open-webui.md) | chat + RAG (UI) |
| [`runbooks/servicos/hermes-agent.md`](runbooks/servicos/hermes-agent.md) | gateway OpenAI-compatible + memória |
| [`runbooks/servicos/hermes-dashboard.md`](runbooks/servicos/hermes-dashboard.md) | painel interno (`:9119`) |
| [`runbooks/servicos/ollama.md`](runbooks/servicos/ollama.md) | modelos (chat + embeddings) |
| [`runbooks/servicos/qdrant.md`](runbooks/servicos/qdrant.md) | banco vetorial (mem0 + RAG) |
| [`runbooks/servicos/docling.md`](runbooks/servicos/docling.md) | conversão de documentos |
| [`runbooks/servicos/searxng.md`](runbooks/servicos/searxng.md) | meta-busca (desligada no chat) |
| [`runbooks/servicos/nginx.md`](runbooks/servicos/nginx.md) | TLS e proxy (é o que a LAN vê) |
| [`runbooks/servicos/prometheus.md`](runbooks/servicos/prometheus.md) | coleta + regras de alerta |
| [`runbooks/servicos/node-exporter.md`](runbooks/servicos/node-exporter.md) | métricas do host + textfile |
| [`runbooks/servicos/cadvisor.md`](runbooks/servicos/cadvisor.md) | métricas por container |
| [`runbooks/servicos/grafana.md`](runbooks/servicos/grafana.md) | dashboards (`:3001` via nginx) |
| [`runbooks/servicos/samba.md`](runbooks/servicos/samba.md) | share `documentos` (serviço de host, não container) |

### Um card por script de `ops/` (o que roda sozinho)

| Script | Quando roda |
|---|---|
| [`runbooks/scripts/backup_stack.md`](runbooks/scripts/backup_stack.md) | 03:30 — backup diário (retenção 14+6) |
| [`runbooks/scripts/mem0_maintenance.md`](runbooks/scripts/mem0_maintenance.md) | 03:00 — dedup/teto da memória |
| [`runbooks/scripts/tls_cert_metrics.md`](runbooks/scripts/tls_cert_metrics.md) | 03:20 — validade do certificado |
| [`runbooks/scripts/ci_run.md`](runbooks/scripts/ci_run.md) | 04:10 — o oráculo agendado |
| [`runbooks/scripts/docker-firewall.md`](runbooks/scripts/docker-firewall.md) | a cada start do Docker (DOCKER-USER) |
| [`runbooks/scripts/ufw-lab.md`](runbooks/scripts/ufw-lab.md) | no deploy (portas de INPUT) |
| [`runbooks/scripts/sync-to-host.md`](runbooks/scripts/sync-to-host.md) | sob demanda (Windows → host) |
| [`runbooks/scripts/watch-alerts.md`](runbooks/scripts/watch-alerts.md) | a cada 30 min (Windows) |
| [`runbooks/scripts/pull-backups.md`](runbooks/scripts/pull-backups.md) | diário (Windows → cópia local) |
| [`runbooks/scripts/rag_ingest.md`](runbooks/scripts/rag_ingest.md) | a cada 15 min (share de documentos → RAG) |
| [`runbooks/scripts/questoes.md`](runbooks/scripts/questoes.md) | a cada 30 min (provas/gabaritos → banco de questões) |
| [`runbooks/scripts/tools.md`](runbooks/scripts/tools.md) | índice dos scripts de `tools/` (sob demanda) |
| [`runbooks/scripts/make-public-repo.md`](runbooks/scripts/make-public-repo.md) | sob demanda (gera/publica o espelho público sanitizado) |
| [`runbooks/scripts/inventario-proxmox.md`](runbooks/scripts/inventario-proxmox.md) | sob demanda (inventário de hardware do servidor físico, disparado do Windows) |

## Construção: como cada fase foi feita

| Documento | Conteúdo |
|---|---|
| [`runbooks/FASE-5bcd-RUNBOOK.md`](runbooks/FASE-5bcd-RUNBOOK.md) | endurecimento 5b/5c/5d |
| [`runbooks/FASE-6-RUNBOOK.md`](runbooks/FASE-6-RUNBOOK.md) | higiene e retenção |
| [`runbooks/FASE-7-RUNBOOK.md`](runbooks/FASE-7-RUNBOOK.md) | CI do oráculo + métricas |
| [`runbooks/AI-MEMORY-WINDOWS-RUNBOOK.md`](runbooks/AI-MEMORY-WINDOWS-RUNBOOK.md) | ai-memory no Windows/OpenCode |

## Arquitetura, planos e relatórios

| Documento | Conteúdo |
|---|---|
| [`architecture/DIRETORIOS-HOST-MEDUSA-2026-10-20.md`](architecture/DIRETORIOS-HOST-MEDUSA-2026-10-20.md) | retrato do host e mapeamento de diretórios (base da reestruturação) |
| [`architecture/INVENTARIO-HARDWARE-PROXMOX.md`](architecture/INVENTARIO-HARDWARE-PROXMOX.md) | inventário de hardware do **servidor físico** (placa-mãe, CPU, GPU, USB, portas) — gerado por `tools/inventario-proxmox.ps1` |
| [`plans/PLANO-IMPLEMENTACAO-MEM0.md`](plans/PLANO-IMPLEMENTACAO-MEM0.md) | plano original do mem0/RAG |
| [`plans/DAVY-JONES-GPT-CONTEXTO-CONTINUIDADE.md`](plans/DAVY-JONES-GPT-CONTEXTO-CONTINUIDADE.md) | trilha paralela do ChatGPT (intenção, não inventário) |
| [`plans/tarefas_mentais_davy-jones-hermas.md`](plans/tarefas_mentais_davy-jones-hermas.md) | rascunho do usuário para o **eixo de estudos** (em andamento) |
| [`plans/DESENHO-INBOX-DOCUMENTS.md`](plans/DESENHO-INBOX-DOCUMENTS.md) | inbox `documents/` (share SMB no host) + ingestão na RAG — árvore criada, SMB pendente |
| [`plans/BANCO-DE-QUESTOES.md`](plans/BANCO-DE-QUESTOES.md) | banco de questões (Fase 5 do eixo): medições, decisões, desenho e limites |
| [`reports/RELATORIO-LACUNAS.md`](reports/RELATORIO-LACUNAS.md) | backlog de endurecimento #1–#10 com status |
| [`reports/RELATORIO-TECNICO-DAVY-JONES-GPT.md`](reports/RELATORIO-TECNICO-DAVY-JONES-GPT.md) | relatório técnico da trilha paralela |

## Aprendizado e memória

| Documento | Conteúdo |
|---|---|
| [`learning/MAPA-MENTAL.md`](learning/MAPA-MENTAL.md) | trilha N0–N5 de estudo do stack |
| [`ai-memory.md`](ai-memory.md) | memória consolidada das conversas (diretrizes, acertos, problemas) |

## Regras de convivência

- **Dois padrões de nome**, de propósito:
  - documentos de assunto/fase (este índice, runbooks de fase, relatórios, planos):
    **MAIÚSCULAS, sem espaço** — o `scp` e o shell do host agradecem;
  - cards de **serviço** e de **script**: minúsculas, **iguais ao nome do container/script**
    (`servicos/open-webui.md`, `scripts/backup_stack.md`) — é o que permite a suíte exigir
    1:1 entre container/script e card.
- Caminho citado em `.md` tem de existir: a suíte transforma link morto em FAIL (URL não conta).
- Todo `.md` começa com um título `#`.
- O que sai da árvore ativa mas não deve ser apagado vai para `archive/` (fora do git, **não**
  vai para o host — export de sessão pode conter segredo).
