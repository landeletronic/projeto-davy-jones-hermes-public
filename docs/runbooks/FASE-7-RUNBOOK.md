# FASE 7 — CI do oráculo (N2) — RUNBOOK

> **Status: CONCLUÍDA em 2026-10-18.** Suite: `PASS=99 / FAIL=0 / WARN=0` (rodando no host, via cron).
> *Números são da época; o estado atual está no `README.md`/`AGENTS.md`.*
> Escopo: o oráculo (`tests/verify_stack.sh`) passa a rodar **sozinho** e o resultado fica
> visível no **Grafana** — sem SSH. Fecha o **N2** do mapa mental ("teste automatizado + CI").
> De quebra, dois bugs reais do Grafana (existentes desde a 6.3) foram encontrados e corrigidos.

## 1. Como funciona

```
cron 04:10 (depois do backup das 03:30)          # /etc/cron.d/hermes-ci
   └─ /usr/local/bin/hermes-ci                   # = ops/bin/ci_run.sh
        ├─ bash tests/verify_stack.sh            # o oráculo (99 checks)
        ├─ ~/ci/logs/ci-<UTC>.log                # log completo (retenção 30)
        ├─ ~/ci/last-run.json                    # resumo p/ máquina (success/pass/fail/warn)
        ├─ ~/ci/last.log                         # symlink p/ o último log
        └─ ci/textfile/hermes_ci.prom            # métricas (escrita atômica: .tmp + mv)
             └─ node-exporter (textfile collector)
                  └─ Prometheus              # scrape 15s
                       └─ Grafana            # painéis "Oráculo (CI)" etc.
```

Exit code do `hermes-ci` = exit code da suíte (`0` = tudo verde).

**Métricas publicadas** (todas em `hermes_ci_*`):

| Métrica | Significado |
|---|---|
| `hermes_ci_last_run_success` | `1` = verde, `0` = vermelho |
| `hermes_ci_last_run_timestamp_seconds` | epoch da execução (o painel usa `time() - x`) |
| `hermes_ci_duration_seconds` | duração |
| `hermes_ci_checks_total` | checks executados |
| `hermes_ci_checks_failed` | checks com falha |
| `hermes_ci_checks_warned` | avisos (não derrubam o CI) |
| `hermes_ci_suite_info{sha256="…"}` | **hash da suíte que rodou** (auditoria) |

## 2. Arquivos

| Arquivo | Onde vive | Papel |
|---|---|---|
| `ops/bin/ci_run.sh` | repo → `/usr/local/bin/hermes-ci` | runner do CI |
| `ops/cron/hermes-ci.cron` | repo → `/etc/cron.d/hermes-ci` | agendamento (04:10) |
| `ops/deploy/sync-to-host.ps1` | repo (Windows) | **deploy**: espelha o repo, confere hash da suíte, permissões, reinstala runner/cron e roda o CI |
| `ci/textfile/hermes_ci.prom` | host `~/hermes-architect/ci/textfile/` | métricas (bind → node-exporter) |
| `monitoring/grafana/dashboards/hermes-lab.json` | repo | dashboard (11 painéis, 4 do CI) |

## 3. Operação (dia a dia)

```bash
# rodar o CI na hora (o mesmo que o cron faz)
ssh davy-jones-hermes '/usr/local/bin/hermes-ci --quiet'

# ver o resumo da última execução
ssh davy-jones-hermes 'cat ~/ci/last-run.json; tail -3 ~/ci/last.log'

# ver só o que falhou (se falhou)
ssh davy-jones-hermes "grep -E '^  (FAIL|WARN)' ~/ci/last.log"
```

No Windows, o caminho normal é **um comando** (edita → sincroniza → valida):

```powershell
powershell -File ops\deploy\sync-to-host.ps1          # sincroniza + roda o CI
powershell -File tests\run-tests.ps1             # roda a suíte e mostra PASS/FAIL
```

No Grafana (`https://192.168.15.231:3001`, admin / senha em `.env`), o painel
**Oráculo (CI)** no topo responde "está tudo de pé?" sem abrir terminal.

## 4. Validação (fail-first)

Teste negativo feito e registrado: trocar a suíte por uma **falsa que falha** →
`exit=1`, `last-run.json` com `success:false`, métrica `hermes_ci_last_run_success 0`
e o Prometheus servindo `0`. Restaurada a suíte real → verde.

```bash
# reproduzir (host): suíte falsa -> CI vermelho
cp tests/verify_stack.sh /tmp/verify_stack.sh.good
printf '#!/usr/bin/env bash\necho "  PASS=1  FAIL=1"\nexit 1\n' > tests/verify_stack.sh
/usr/local/bin/hermes-ci --quiet; echo "exit=$?"     # -> 1
cp /tmp/verify_stack.sh.good tests/verify_stack.sh
```

Checks da Fase 7 na suíte (9):
`hermes-ci` instalado · cron presente · `collector.textfile.directory` no compose ·
painel do CI no dashboard · **último CI verde** · CI não atrasado (<48h) ·
métrica no textfile · Prometheus expõe a série · dashboard carregado no Grafana.
Os que descrevem o **estado do próprio CI** são `WARN` (ver §5.1).

## 5. Pegadinhas (não repetir)

### 5.1 Aviso ≠ falha (e por quê)

O estado do CI é **auto-referente**: o resultado disponível durante o run é o do run
**anterior**. Se "último CI = verde" fosse `FAIL`, a suíte ficaria **travada em vermelho
para sempre** — todo run verde reportaria o vermelho do anterior. Por isso existe o helper
`warn()`: imprime `WARN`, conta em `hermes_ci_checks_warned` e **não** derruba o CI.
O que é fato estático (runner instalado, cron, permissões, painel) continua `FAIL`.

### 5.2 Dashboards: permissões de leitura (bug real, encontrado na 7)

O Grafana roda como **uid 472** (`grafana`) e lê `./monitoring` por bind-mount. O umask do
host criava diretórios **700** → o file provider falhava:

```
level=error msg="failed to walk provisioned dashboards" error="open /var/lib/grafana/dashboards: permission denied"
```

Efeito prático: **o dashboard não existia no Grafana** (e o healthcheck respondia ok, então
ninguém percebia). Correção (`ops/deploy/sync-to-host.ps1` agora força isso):

```bash
chmod -R a+rX /home/usuario/hermes-architect/monitoring    # dirs 755, arquivos 644 (não toca nginx/certs)
```

### 5.3 Senha do admin do Grafana (bug real, encontrado na 7)

`GF_SECURITY_ADMIN_PASSWORD` **só vale na primeira criação do admin** no volume — depois
disso o valor do `.env` é ignorado. Resultado: a senha documentada não entrava.

```bash
# resetar para o valor do .env (só passa a valer depois de REINICIAR o container)
PW=$(grep -h '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2)
docker exec -u 0 grafana grafana cli --homepath /usr/share/grafana admin reset-admin-password "$PW"
docker restart grafana

# conferir (2 formas: hash do banco e HTTP)
curl -s -u "admin:$PW" http://<ip-do-container>:3000/api/user -o /dev/null -w '%{http_code}\n'   # 200
```

A suíte agora **testa o login de verdade** (`/api/user` = 200) — se a senha divergir, o CI fica vermelho.

### 5.4 Brute-force do Grafana é persistente

5 logins errados bloqueiam o usuário — e o bloqueio **sobrevive a restart** (tabela
`login_attempt` no `grafana.db`). Sintoma: `401` com
`too many consecutive incorrect login attempts for user - login for user temporarily blocked`.

```bash
docker stop grafana
docker cp grafana:/var/lib/grafana/grafana.db /tmp/g.db
python3 -c "import sqlite3;c=sqlite3.connect('/tmp/g.db');print(c.execute('select count(*) from login_attempt').fetchone());c.execute('delete from login_attempt');c.commit()"
docker cp /tmp/g.db grafana:/var/lib/grafana/grafana.db
docker exec -u 0 grafana sh -c 'chown 472:472 /var/lib/grafana/grafana.db; chmod 640 /var/lib/grafana/grafana.db'
docker start grafana
```

> **Pegadinha dentro da pegadinha:** `docker cp` de **volta** no `grafana.db` deixa o arquivo
> com o uid do host (`1000`) → o SQLite do container não abre (`unable to open database file (14)`)
> e o Grafana entra em crash-loop. **Sempre** `chown 472:472` depois do `cp` (ou faça o
> `chown` por um container auxiliar com o volume montado).

Na suíte, o login é **uma** tentativa por execução — nunca mais que isso.

### 5.5 `bge-m3` com a GPU ocupada
O Ollama **serializa** modelos: se um `qwen3` estiver residente, a chamada de embedding espera
o *swap* (medido no host: **63-90 s**). O check tinha `--max-time 30` → falso negativo.
Agora: `--max-time 120` + 1 retentativa. Se um dia falhar de novo, verifique
`docker exec ollama ollama ps` antes de culpar o bge-m3.

### 5.6 O agendador não existia (bug real, encontrado na 7)

O pacote **`cron` não estava instalado** no host: `dpkg -l cron` → `un`, `systemctl status cron`
→ *unit not found*. As entradas em `/etc/cron.d` (backup 03:30 **desde a 6.4** e CI 04:10)
existiam, a suíte passava (ela checava o **arquivo**) e **nada rodava** — nem o backup diário.
Os artefatos de backup que existiam tinham sido gerados à mão.

```bash
# corrigir (uma vez)
sudo apt-get install -y cron
sudo systemctl enable --now cron
systemctl is-active cron && systemctl is-enabled cron      # active / enabled

# provar de ponta a ponta: agendar a cada minuto e ver disparar
BEFORE=$(stat -c %Y ~/ci/last-run.json)
sudo cp /etc/cron.d/hermes-ci /root/hermes-ci.orig
printf '* * * * * usuario /usr/local/bin/hermes-ci --quiet >> /home/usuario/ci/cron.log 2>&1\n' | sudo tee /etc/cron.d/hermes-ci
# ... esperar ~1-2 min e conferir: ~/ci/cron.log + `CRON[...]` no /var/log/syslog
sudo cp /root/hermes-ci.orig /etc/cron.d/hermes-ci         # restaurar o horário real
```

A suíte agora checa **o daemon** (`is-active` + `is-enabled`), não só o arquivo.

## 6. Estado da Fase 7

- **`cron` instalado, ativo e habilitado no boot** (antes: entradas em `/etc/cron.d` sem daemon
  → backup e CI nunca rodavam). Provado disparando os dois via cron de verdade.
- `hermes-ci` instalado (`/usr/local/bin/hermes-ci`, 755) + cron `/etc/cron.d/hermes-ci` (04:10).
- 7 métricas no Prometheus/Grafana; dashboard com 4 painéis novos (11 no total).
- Grafana: permissões corrigidas, senha do admin alinhada ao `.env` (login testado no CI).
- Suíte: 88 → **99 checks** (`WARN=0`), incluindo as regressões do Grafana e do CI.
- Pendências que ficaram visíveis: incluir o volume `grafana_data` no backup (opcional);
  os demais itens seguem os já registrados na Fase 6 (verificação de citação, retenção/LGPD,
  backup off-site, upgrade do Qdrant).
