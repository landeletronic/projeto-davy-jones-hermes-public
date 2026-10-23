# backup_stack.sh — backup diário do lab

| | |
|---|---|
| Arquivo | `ops/bin/backup_stack.sh` |
| Instalado como | `/usr/local/bin/hermes-backup` |
| Agendamento | `ops/cron/hermes-backup.cron` → **03:30**, usuário `tlandskron` |
| Saída | `~/backups/hermes-<data>.tar.gz` (+ `backup.log`) |
| Política | retenção **14 diários + 6 mensais** |

## O que entra no artefato

- `webui.db` e `grafana.db` pela **API `.backup` do SQLite** (não `cp` de banco vivo);
- snapshots de **todas** as coleções do Qdrant (`mem0_memories`, `owui_*`);
- configs do projeto (`project-config.tgz`, 600 — leva `nginx/certs`);
- `~/.hermes` (com `sudo tar`, **excluindo caches** e `.ssh`).

## Rodar à mão

```bash
ssh davy-jones-hermes 'sudo /usr/local/bin/hermes-backup'
ssh davy-jones-hermes 'sudo /usr/local/bin/hermes-backup --prune-dry-run'   # só a retenção
```

`--prune-dry-run` tem de terminar com `RETENTION: 0` (nada fora da política). A suíte exige isso.

## Provar que presta

```bash
ssh davy-jones-hermes 'bash /home/tlandskron/hermes-architect/tools/verify_backup_restore.sh'
ssh davy-jones-hermes 'bash /home/tlandskron/hermes-architect/tools/drill_restore_clean.sh'
```

O primeiro restaura os snapshots numa coleção temporária e apaga; o segundo sobe Qdrant + OWUI
**novos** em volumes vazios e prova que uma máquina limpa volta com os dados.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| tar com erro de permissão | `~/.hermes` tem arquivo de root | o script usa `sudo tar`; rode com `sudo` |
| artefato ~150 MB | caches não excluídos | conferir `--exclude` no script |
| sem `grafana.db` | `docker run` sem `-i` (não lê stdin) | conferir o bloco do SQLite |
| `RETENTION: N` ≠ 0 | arquivos fora da política 14+6 | rodar sem `--dry-run` para podar |
| alerta "backup >48h" | cron parado | `systemctl is-active cron`; `/etc/cron.d/hermes-backup` |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

O sync instala o script + a entrada de cron. Ao criar agendamento novo: **prove disparando**
(agende a cada minuto, veja o evento, restaure o horário) — entrada em `/etc/cron.d` não roda se
o daemon `cron` não estiver ativo.
