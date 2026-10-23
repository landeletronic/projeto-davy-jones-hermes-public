# mem0_maintenance.py — higiene da memória de longo prazo

| | |
|---|---|
| Arquivo | `ops/bin/mem0_maintenance.py` |
| Instalado como | `/usr/local/bin/mem0-maintenance` |
| Agendamento | `ops/cron/mem0-maintenance.cron` → **03:00** (antes do backup) |
| Fala com | Qdrant por REST (stdlib) — **não** depende do venv do Hermes |
| Métricas | `hermes_mem0_*` no textfile |

## O que faz, em ordem

1. **dedup exato** — mesmo `(user_id, hash)`, mantém o mais recente;
2. **dedup near** — cosseno ≥ `MEM0_DEDUP_SIM` (0.97) no mesmo usuário;
3. **teto** — acima de `MEM0_MAX_PER_USER` (2000), remove os mais antigos por `updated_at`;
4. **TTL** — `MEM0_RETENTION_DAYS` > 0 remove o que não é tocado há N dias.
   **Default 0 = desligado**: apagar memória é decisão do escritório (LGPD/sigilo).

## Rodar à mão

```bash
ssh davy-jones-hermes 'mem0-maintenance --dry-run'   # relatório, não apaga
ssh davy-jones-hermes 'mem0-maintenance'             # aplica
```

O `--dry-run` é a forma de conferir antes de qualquer mudança de parâmetro.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| `connection refused` no 6333 | Qdrant fora | [`../servicos/qdrant.md`](../servicos/qdrant.md) |
| memória sumiu além do esperado | TTL ligado sem querer | conferir `MEM0_RETENTION_DAYS` na linha do cron |
| memória duplicada continua | o job não roda (cron inativo) | `systemctl is-active cron`; ver `~/backups/mem0-maintenance.log` |
| alerta "manutenção >48h" | job parado | rodar à mão e investigar o log |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

Instala o script + `/etc/cron.d/mem0-maintenance`. Requer `python3` no host (stdlib apenas).
