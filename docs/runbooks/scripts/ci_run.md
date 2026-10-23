# ci_run.sh — o oráculo agendado

| | |
|---|---|
| Arquivo | `ops/bin/ci_run.sh` |
| Instalado como | `/usr/local/bin/hermes-ci` |
| Agendamento | `ops/cron/hermes-ci.cron` → **04:10** (40 min depois do backup) |
| Log | `~/ci/logs/ci-<UTC>.log`, `~/ci/last.log`, `~/ci/last-run.json` |
| Métricas | `hermes_ci_*` no textfile → node-exporter → Prometheus → Grafana |

## Rodar à mão

```bash
ssh davy-jones-hermes '/usr/local/bin/hermes-ci'            # log completo
ssh davy-jones-hermes '/usr/local/bin/hermes-ci --quiet'    # só a última linha
```

Exit code = exit code da suíte (`0` = tudo verde). Histórico: `KEEP_LOGS=30`.

## O que ele faz

1. executa `tests/verify_stack.sh` no host (a **cópia sincronizada**, não o seu Windows);
2. grava o log e um resumo legível por máquina (`last-run.json`);
3. publica `hermes_ci_*` no `ci/textfile`.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| FAIL no CI e verde rodando à mão | você rodou o repo do Windows; o CI usa o sincronizado | `sync-to-host.ps1` |
| estado do CI em WARN na suíte | auto-referente: lê o run anterior | rodar de novo |
| `hermes_ci_*` ausente | falhou antes de publicar | ver `~/ci/last.log` |
| CI lento (126 s) | swap de modelo do Ollama | não é regressão |
| cron não dispara | daemon `cron` inativo | `systemctl enable --now cron` |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

Instala `/usr/local/bin/hermes-ci` e `/etc/cron.d/hermes-ci`.
