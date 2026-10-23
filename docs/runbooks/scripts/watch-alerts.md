# watch-alerts.ps1 — notificação de alertas no Windows

| | |
|---|---|
| Arquivo | `ops/windows/watch-alerts.ps1` |
| Roda em | **Windows** (Task Scheduler "Hermes Lab Alerts", a cada 30 min) |
| Lançador | `ops/windows/run-hidden.vbs` via `wscript.exe` — **sem janela** (ver abaixo) |
| Consulta | Prometheus no host, via SSH |
| Aviso | toast **"Hermes Lab"** → fallback balão da bandeja; **sempre** grava em `~/hermes-alerts.log` |
| Estado | `%TEMP%\hermes-alerts-state.json` (dedupe de 6 h) |

## Por que existe o `run-hidden.vbs`

A tarefa roda na **sessão do usuário** (`InteractiveToken`). Chamar `powershell.exe` direto faz o
Windows abrir o console por ~1 s (até ~7 s quando notifica) a cada 30 min — isso **rouba o foco** e
engole o que a pessoa está digitando (reclamação real de 2026-10-22). O `run-hidden.vbs` é um host
gráfico (sem console) que chama o PowerShell com `Run(cmd, 0, False)`: janela zero, sem esperar.

O toast tem AUMID próprio (`Hermes.Lab.Alerts`, registrado em
`HKCU\SOFTWARE\Classes\AppUserModelId\Hermes.Lab.Alerts` com `DisplayName = Hermes Lab`) — sem isso
ele aparecia rotulado como "Windows PowerShell".

Três desfechos, todos notificados (o dedupe de 6 h vale para os dois primeiros):

| Prometheus responde | Efeito |
|---|---|
| 0 alertas disparados | registra `ok` no log, sem notificação (limpa o estado) |
| ≥1 alerta disparado | toast/balão com os nomes |
| **não responde** | toast/balão `PrometheusSemResposta(critical)` e sai com código 2 — monitoração cega não pode ser silenciosa |

## Uso

```powershell
powershell -File ops\windows\watch-alerts.ps1          # normal, silencioso se ok
powershell -File ops\windows\watch-alerts.ps1 -Test    # força um alerta de teste
```

Deduplicação: o **mesmo** conjunto de alertas não repete por 6 h; se o conjunto mudar
(entrou alerta novo), notifica na hora.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| Nenhum aviso nunca | Task Scheduler aponta caminho antigo | `schtasks /change /tn "Hermes Lab Alerts" /TR "<caminho novo>"` |
| **Janela do console piscando** a cada 30 min | a tarefa foi registrada chamando `powershell.exe` direto | `powershell -File ops\deploy\sync-to-host.ps1` (reaplica o `wscript` + `run-hidden.vbs`) |
| Toast aparece como "Windows PowerShell" | AUMID padrão do processo | o script re-registra `Hermes.Lab.Alerts` em `HKCU` a cada execução; se persistir, rodar com `-Test` e conferir o log (`toast falhou: …`) |
| Toast não aparece | `ToastNotificationManager` indisponível na sessão | é best-effort: o log e o balão continuam |
| Acentos quebrados no script | `.ps1` sem BOM UTF-8 (PS 5.1 lê como ANSI) | salvar como **UTF-8 com BOM** |
| "ok" repetido no log e alerta real existe | consulta não chega ao Prometheus | testar o `ssh` usado pelo script |

## Agendar / mover

O registro é **idempotente no deploy** (`ops/deploy/sync-to-host.ps1`): se a tarefa existe, ele
troca só a ação para `wscript.exe … run-hidden.vbs`; se não existe, cria com o gatilho certo.

```powershell
# conferir
Get-ScheduledTask 'Hermes Lab Alerts' | ForEach-Object { $_.Actions[0].Execute + ' ' + $_.Actions[0].Arguments }
# provar que roda depois de mover/editar (não abre janela)
Start-ScheduledTask 'Hermes Lab Alerts'; Get-Content "$env:USERPROFILE\hermes-alerts.log" -Tail 1
```

O Task Scheduler guarda o **caminho absoluto**: mover o script (ou o `run-hidden.vbs`) sem
reaplicar o deploy faz o alerta parar **em silêncio**.
