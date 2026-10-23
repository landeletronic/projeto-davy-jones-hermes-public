# Relatório de lacunas — endurecimento do lab

> Originado da revisão do lab em 2026-10-19/20. Cada item fechado virou **check no oráculo**
> (`tests/verify_stack.sh`), como manda o `AGENTS.md` §1. Este arquivo é o registro que faltava:
> antes ele só existia na conversa.
>
> **Estado:** **10 de 10 fechados** (#4 incluído) · P3 quase todo fechado.
> Suíte na última verificação: `PASS=151 / FAIL=0 / WARN=0`.

## Os 10 itens

| # | Lacuna | Risco | Status |
|---|---|---|---|
| 1 | Nada notificava alerta | Falha silenciosa: disco/backup/CI quebrados sem ninguém saber | ✅ 2026-10-20 |
| 2 | Backup existia só no host (script + cron manuais) | Rebuild perderia o backup | ✅ 2026-10-20 |
| 3 | Firewall aplicado à mão | Regras não voltam num rebuild/restart | ✅ 2026-10-20 |
| 4 | API do gateway na LAN + `shell` sem sandbox | Usuário do chat executa comando no container (que tem `docker.sock`) | ✅ 2026-10-20 |
| 5 | `Up` ≠ vivo (healthcheck `none` passava) | Container "up" sem responder | ✅ 2026-10-20 |
| 6 | Logs do Docker sem rotação | Disco enche aos poucos | ✅ 2026-10-20 |
| 7 | mem0 sem retenção/consolidação | Coleção só cresce; memória velha/repetida para sempre | ✅ 2026-10-20 |
| 8 | Raciocínio vazando no caminho não-stream | Resposta com "pensamento" no lugar do texto | ✅ 2026-10-20 (mitigado + teste) |
| 9 | Restore só testado dentro da stack viva | Não se sabia se uma máquina vazia volta | ✅ 2026-10-20 |
| 10 | Certificado TLS sem renovação nem monitoramento | HTTPS quebraria em 2029 sem aviso | ✅ 2026-10-20 |

## Detalhe dos fechados

### #1 — Alertas
- 9 regras no grupo `lab` (`monitoring/alert-rules.yml`): alvo fora do ar, disco >85%, backup
  >48 h, métrica de backup ausente, **TLS <30 dias / expirado**, **manutenção do mem0 >48 h**,
  CI vermelho e CI atrasado.
- Painel **`hermes-alerts`** no Grafana; notificação local no Windows
  (`ops/windows/watch-alerts.ps1`, a cada 30 min, log em `~/hermes-alerts.log`).
- **Alerta disparado = WARN na suíte**, nunca FAIL (estado do ambiente ≠ regressão de código).
- Regra descoberta no caminho: **Prometheus não relê `alert-rules.yml` sozinho** (só start/SIGHUP)
  → o deploy manda HUP e a suíte compara as regras carregadas com o arquivo.

### #2 — Backup versionado
- `ops/bin/backup_stack.sh` + `ops/cron/hermes-backup.cron` no repositório, instalados pelo
  `sync-to-host.ps1`; artefato com `webui.db`, snapshots de **todas** as coleções, configs e
  manifest; retenção 7/8; métricas `hermes_backup_*`.
- Retrato do `nginx/certs` também vai no `project-config.tgz` (o artefato é `600`).

### #3 — Firewall versionado
- `ops/bin/ufw-lab.sh` (idempotente, **sem** `ufw reset`) + `ops/bin/docker-firewall.sh` e
  `ops/systemd/docker-firewall.service` (`DOCKER-USER` com `PartOf=docker.service`): libera
  22/80/443/3001/8642/9119 e derruba 6333/11434 para a LAN.
- Bug de então: a lista de portas com rótulo de espaço (`Nginx HTTP`) virava duas regras e
  abortava o `set -e` → separador `|`.

### #5 — Healthchecks de verdade
- `node-exporter` (wget `--spider /metrics`) e `hermes-dashboard` (curl `/api/health`) ganharam
  healthcheck; a suíte passou a exigir **`healthy` em 12/12** e não aceita mais `none`.

### #6 — Rotação de logs
- `ops/docker/daemon.json` (json-file 10 MB × 3) instalado em `/etc/docker/daemon.json`; o sync só
  reinicia o Docker quando o hash muda; `--force-recreate` aplicado uma vez aos 12 containers.
- A suíte exige `max-size` em todo container em execução.

### #7 — Higiene do mem0
- `ops/bin/mem0_maintenance.py` (cron 03:00): dedup exato `(user_id, hash)`, dedup por cosseno
  ≥ 0.97, teto de 2000/usuário e TTL **opcional** (`MEM0_RETENTION_DAYS`, default **0** —
  apagar memória é decisão do escritório).
- Publica `hermes_mem0_*`; alerta `LabMem0MaintenanceLate`; 4 checks (script, cron, métrica,
  **zero duplicatas exatas**). Já removeu duplicata real em produção.

### #8 — Raciocínio fora do texto
- Diagnóstico: o gateway separa `content`/`reasoning_content` **nos dois caminhos** (SSE e
  não-stream) e o OWUI repassa igual. O vazamento era o **modelo** escrevendo o pensamento sem
  tags como resposta (1 em 3 execuções a `temperature: 0.7`).
- Mitigação: `temperature: 0.3`; o smoke de RAG **falha** se o raciocínio aparecer no `content`
  ou houver `<think>`. Limite conhecido: texto não marcado é irrecuperável por parser.

### #9 — Restore em ambiente limpo
- `tools/drill_restore_clean.sh`: sobe **Qdrant e OWUI novos** (volumes vazios, portas
  16333/13000 no loopback), restaura os snapshots e o `webui.db`, confere usuários/modelo/
  conexão Hermes e derruba tudo. **11/11 PASS**.
- Prova os **dados**; instalar SO/Docker/ufw/cron/GPU continua sendo o rebuild manual.
- Armadilha encontrada: `docker cp` de SQLite por cima de container já iniciado deixa WAL velho
  → "database disk image is malformed". A solução é semear o volume **antes** do 1º boot.

### #10 — Renovação TLS
- `tools/make_tls_cert.sh` agora **renova** (`--force`, `--renew-if-days`, `--days`, `--ip`,
  `--reload`), guarda o par antigo e **confere o fingerprint servido** pelo nginx.
- `ops/bin/tls_cert_metrics.sh` (cron 03:20) publica `hermes_tls_cert_days_left`; alertas
  `LabTLSCertExpiring` (<30 d) e `LabTLSCertExpired` (<0).
- 9 checks: validade, SAN, IP atual na SAN, fingerprint arquivo×nginx, métrica, instalação e
  renovação provada em **diretório isolado** (gera, não sobrescreve sem `--force`, guarda o par).
- Renovação é **manual de propósito**: autoassinado renovado faz o navegador avisar de novo.

## #4 — fechado em 2026-10-20 (e o que continua valendo como risco)

O que estava errado:
- `ufw` "liberava" **8642** — regra **inócua e enganosa**: porta publicada pelo Docker entra por
  `FORWARD/DOCKER-USER`, nunca pelo `INPUT` do ufw. A API **estava** alcançável da LAN.
- `hermes-agent` montava **`/var/run/docker.sock`** e **`~/.ssh`**, e a ferramenta `shell` roda
  **local** no container (`terminal.backend: local`): um pedido no chat (ou injeção de prompt)
  valia **root no host** e acesso às chaves.
- `sandbox.type: docker` com imagem `runtime:latest` era **fachada**: nenhum container de sandbox
  jamais subiu, e a tag flutuante não é resolvível com o lab offline.

O que foi feito:
1. **8642 bloqueada na LAN** no `DOCKER-USER` (`ops/bin/docker-firewall.sh`); o ufw **removeu** a
   regra antiga. Loopback e a rede interna do OWUI continuam funcionando (provado: a suíte checa
   `/health` em `localhost:8642`; do Windows a porta dá timeout).
2. **`docker.sock` e `~/.ssh` removidos** do container do gateway (mounts agora: `/workspace` e
   `/opt/data`); recriado, gateway `200` e mem0 ativo.
3. Checks novos: sem `docker.sock`, sem `~/.ssh`, 8642 ausente do ufw, 8642 bloqueada no
   `DOCKER-USER`, API viva no loopback.

Risco residual (aceito e explícito): **usuário autenticado** no OWUI ainda pode pedir comandos ao
agente, e eles rodam **dentro** do `hermes-agent`, com `/workspace` (repo) e `/opt/data` (config e
`.env`) graváveis. Isso é "shell do dono do chat", não escalada para o host. Para reduzir mais:
`terminal.backend: docker` com imagem **pinada por digest** e sem bind-mounts, `shell` fora de
`tools.enabled`, ou allowlist de comandos. A chave da API segue **estática** (não rotacionada —
sem exposição de rede, a rotação não pagaria o risco de quebrar a conexão do OWUI).

## P3 — backlog restante

| Item | Nota |
|---|---|
| ~~Modelos ociosos na GPU~~ | ✅ **2026-10-20** — KV `q4_0`: 5,6 GB, **100% GPU**, ~62 tok/s (era 31 com 13% na CPU); chat + `bge-m3` residentes, **sem swap**. Checks na suíte |
| ~~Base de teste `Teste raciocinio`~~ | ✅ **2026-10-20** — removida (`tools/cleanup_owui_test_kb.py`): 0 knowledge, 0 órfã em `knowledge_file`, 0 pontos em `owui_knowledge` |
| ~~Upgrade do Qdrant~~ | ✅ **2026-10-20** — 1.15.2 → **1.16.3 → 1.19.2** (degrau obrigatório), provado em cópia por `tools/verify_qdrant_upgrade.sh --via`; drill 11/11 e smoke RAG verdes |
| ~~`grafana_data` no backup~~ | ✅ **2026-10-20** — `grafana.db` via `.backup` do SQLite; suíte valida presença e integridade |
| ~~Backup off-site~~ | 🟡 **parcial** — `pull-backups.ps1` confere **SHA-256** e aceita `-ExtraDest` (HD externo). O destino segue `\\localhost` até alguém apontar um HD/pasta externa: a ferramenta avisa |
| Citação verificável | 🟡 **parcial (2026-10-20)** — o smoke exige `[1]` e que **todo número afirmado** exista no texto das fontes (teste negativo feito: 99 meses/75% reprovam). Falta o filtro em **produção** (o OWUI não valida sozinho) e a checagem de afirmação sem número |
| Retenção/expurgo LGPD | TTL do mem0 existe e está **desligado**; falta a política do escritório |
| Auditoria leve | quem perguntou o quê |

## Como reconferir

```bash
ssh davy-jones-hermes '/usr/local/bin/hermes-ci --quiet'     # PASS/FAIL/WARN
ssh davy-jones-hermes 'mem0-maintenance --dry-run'
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tools/drill_restore_clean.sh'
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tools/verify_backup_restore.sh'
```
