# pull-backups.ps1 — cópia dos backups para o Windows

| | |
|---|---|
| Arquivo | `ops/windows/pull-backups.ps1` |
| Roda em | **Windows** (manual ou Task Scheduler) |
| Origem | `davy-jones-hermes:/home/usuario/backups/hermes-*.tar.gz` |
| Destino padrão | `\\localhost\backups\hermes-lab` (mantém os **8** mais recentes) |
| Integridade | copia para `%TEMP%` → confere **SHA-256** contra o host → só então move |

## Uso

```powershell
powershell -File ops\windows\pull-backups.ps1
powershell -File ops\windows\pull-backups.ps1 -ExtraDest 'E:\hermes-lab'   # off-site de verdade
```

`\\localhost` é a **mesma máquina** do repositório: não conta como off-site. O `-ExtraDest`
(HD externo / pasta sincronizada) é a terceira cópia.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| "Nenhum backup encontrado" | `~/backups` vazio | rodar `hermes-backup` no host |
| SHA-256 divergente | `scp` truncado | o script rejeita o arquivo; repetir |
| destino inacessível | share `\\localhost\backups` inexistente | criar a pasta (o script tenta) |
| cópia antiga repetida | filtro por `hermes-*` | conferir o padrão de nome do backup |

## Agendar

A tarefa é registrada pelo `ops/deploy/sync-to-host.ps1` (idempotente) **via `wscript.exe` +
`run-hidden.vbs`**: chamar `powershell.exe` direto numa tarefa interativa abre uma janela que rouba
o foco (o mesmo motivo do `watch-alerts.ps1`).

```powershell
# conferir a ação registrada
Get-ScheduledTask 'Hermes Lab Backup Pull' | ForEach-Object { $_.Actions[0].Execute + ' ' + $_.Actions[0].Arguments }
# provar que roda depois de mover/editar (sem janela)
Start-ScheduledTask 'Hermes Lab Backup Pull'; Get-Content "$env:USERPROFILE\hermes-backup-pull.log" -Tail 3
```

O Task Scheduler guarda o **caminho absoluto**: mover o script (ou o `run-hidden.vbs`) sem reaplicar
o deploy faz o pull parar **em silêncio**.
