# Lab davy-jones-hermes

Lab de IA **100% local** (sem internet) para um escritório de advocacia pequeno: chat com
memória de longo prazo por usuário e **RAG jurídica com citação** — rodando num único host
com GPU de 8 GB.

- **Open WebUI** (HTTPS) para o escritório: login e-mail+senha; cada pessoa só vê a própria memória.
- **Hermes gateway** orquestra o agente; modelo `qwen3:4b-64k` no Ollama (GPU ROCm).
- **mem0** guarda fatos por usuário (`user_id` = e-mail) no **Qdrant**; a RAG usa o mesmo Qdrant
  (coleções `owui_*`, embeddings `bge-m3`, extração Docling).
- **nginx** termina o TLS na LAN; **Prometheus + Grafana** mostram o estado; **backup diário**
  com prova de restore; **CI** roda o oráculo todo dia.

> Este diretório é o **repositório de trabalho** (compartilhado por SMB). O host executa uma
> cópia sincronizada em `/home/tlandskron/hermes-architect` — é essa cópia que o cron usa.

## Estado atual (2026-10-21)

| Item | Estado |
|---|---|
| Containers | 12, todos `healthy` |
| Oráculo | `tests/verify_stack.sh` — **166 checks**, CI diário 04:10 |
| Alertas | **9 regras** no grupo `lab` (Prometheus) + painel `hermes-alerts` + notificação no Windows |
| Backup | diário 03:30, retenção **14 diários + 6 mensais**, `webui.db` + `grafana.db` + snapshots, **restore provado** (inclusive em ambiente limpo) |
| TLS | autoassinado até **2029-01-20**, alerta aos 30 dias, renovação em 1 comando |
| Modelos | `qwen3:4b-64k` com KV `q4_0`: 100% na GPU e residente junto do `bge-m3` |
| Qdrant | **v1.19.2** (upgrade por degrau, provado em cópia do volume) |
| Pendente | P3 restante: citação verificável, retenção LGPD, auditoria leve, off-site real |

Backlog completo e evidências: **`docs/reports/RELATORIO-LACUNAS.md`**.

## Uso rápido

```powershell
# suíte completa (Windows -> host, é o oráculo)
powershell -File tests\run-tests.ps1

# deploy (espelha o repo, instala cron/scripts e roda o CI)
powershell -File ops\deploy\sync-to-host.ps1
```

```bash
# no host
bash tests/verify_stack.sh                 # suíte
/usr/local/bin/hermes-ci --quiet           # o mesmo que o cron das 04:10
bash tools/drill_restore_clean.sh          # prova de restore em ambiente limpo
mem0-maintenance --dry-run                 # higiene da memória (sem apagar)
bash tools/make_tls_cert.sh --force --reload   # renovar o certificado
```

## Endereços (LAN)

| Serviço | URL |
|---|---|
| Open WebUI | `https://192.168.15.231` |
| Grafana | `https://192.168.15.231:3001` |
| Hermes API | `http://127.0.0.1:8642` **só no host / rede interna** (bloqueada na LAN) |
| Dashboard | `http://192.168.15.231:9119` |

`:80` redireciona para HTTPS; `:3000` (OWUI) e `:6333`/`:11434` (Qdrant/Ollama) ficam fora da LAN.
O certificado é autoassinado — o navegador avisa "não confiável" até você confiar nele.

## Rotinas automáticas

| Quando | O quê |
|---|---|
| 03:00 | `mem0-maintenance` — dedup/teto da memória |
| 03:20 | `tls-cert-metrics` — validade do certificado |
| 03:30 | `hermes-backup` — banco + configs + snapshots do Qdrant |
| 04:10 | `hermes-ci` — o oráculo; publica métricas e logs |
| a cada 30 min | `ops/windows/watch-alerts.ps1` (Windows, tarefa **"Hermes Lab Alerts"**) — toast/balão + `~/hermes-alerts.log` |
| 12:00 | `ops/windows/pull-backups.ps1` (Windows, tarefa **"Hermes Lab Backup Pull"**) — cópia para `\\localhost\backups` |

## Documentos

A raiz do repositório é **código e configuração**: `AGENTS.md` (regras), `README.md`,
`docker-compose.yml`, `ops/`, `tools/`, `tests/`, `monitoring/`, `nginx/`, `searxng/`,
`hermes-data/`. O conhecimento vive em `docs/`, por assunto:

| Onde | Para quê |
|---|---|
| **`AGENTS.md`** | **regras do projeto** — leia antes de mexer; invariantes, deploy e armadilhas |
| **`docs/README.md`** | índice da documentação (comece por aqui) |
| `docs/ai-memory.md` | memória consolidada: diretrizes, o que deu certo, o que deu problema |
| `docs/architecture/` | como o lab é feito e por quê (retratos do host, decisões de desenho) |
| `docs/runbooks/` | como cada fase foi construída e como operar/consertar (números são da época) |
| `docs/runbooks/TROUBLESHOOTING.md` | **algo quebrou?** triagem por sintoma — comece por aqui |
| `docs/runbooks/servicos/` | um card por container: verificar, reiniciar, falhas comuns, backup |
| `docs/runbooks/scripts/` | um card por script de `ops/` + índice dos scripts de `tools/` |
| `docs/plans/` | planos originais (mem0/RAG, trilha paralela do ChatGPT) |
| `docs/reports/` | relatórios de Estado: lacunas de endurecimento (#1–#10), relatório técnico |
| `docs/learning/` | trilha de aprendizado (N0–N5) e onde o lab está nela |
| `archive/` | **fora do git**: ebook, PDFs antigos e exports de sessão (podem conter segredo) |

## Regra de ouro

Uma mudança por vez, **oráculo antes e depois**. Bug corrigido = **check novo** em
`tests/verify_stack.sh`. Mexeu em `tests/`, compose ou configs? **Sincronize** — o cron valida
a cópia do host, não a pasta do Windows.
