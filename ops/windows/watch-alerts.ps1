# =============================================================================
# watch-alerts.ps1 — avisa no Windows quando o lab tem alerta disparado.
#
# O lab é 100% offline: não há e-mail/Slack/Telegram. Esta é a notificação
# ativa — consulta o Prometheus (dentro do container, via SSH) a cada execução:
#   - >0 alertas em ALERTS{alertstate="firing"}  -> toast/balão + log
#   - nenhum                                      -> registra "ok" no log
#   - Prometheus sem resposta                     -> avisa (a monitoração está cega)
#
# Deduplicação: o mesmo conjunto de alertas não repete por 6 h; se o conjunto
# mudar (alerta novo), notifica na hora. Estado em %TEMP%\hermes-alerts-state.json
#
# Uso:
#   powershell -File ops\windows\watch-alerts.ps1            (uso normal, silencioso se ok)
#   powershell -File ops\windows\watch-alerts.ps1 -Test      (força uma notificação)
#
# Agendada via wscript (run-hidden.vbs) para abrir ZERO janelas: um console a cada
# 30 min roubava o foco de quem estava digitando (aconteceu em 2026-10-22).
#
# Agendar (a cada 30 min) — feito pelo ops\deploy\sync-to-host.ps1:
#   wscript.exe //nologo <caminho>\ops\windows\run-hidden.vbs watch-alerts.ps1
# Remover: schtasks /Delete /TN "Hermes Lab Alerts" /F
# =============================================================================
param(
    [string]$Remote = 'davy-jones-hermes',
    [switch]$Test,
    [int]$RepeatAfterHours = 6
)

$ErrorActionPreference = 'Stop'
$log   = Join-Path $env:USERPROFILE 'hermes-alerts.log'
$state = Join-Path $env:TEMP 'hermes-alerts-state.json'
# AUMID próprio: sem isto o Windows rotula o toast como "Windows PowerShell" (o
# AUMID padrão era o do powershell.exe). Registrado por usuário, idempotente.
$Aumid = 'Hermes.Lab.Alerts'

function Write-Log([string]$m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -Path $log -Encoding UTF8
}

function Show-Notification([string]$title, [string]$body) {
    # 1) toast (WinRT) — funciona sem módulo extra
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $t.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($t.CreateTextNode($title)) | Out-Null
        $texts.Item(1).AppendChild($t.CreateTextNode($body)) | Out-Null
        # Registro do AUMID (HKCU, por usuário): é o que faz o toast aparecer como
        # "Hermes Lab" e não como "Windows PowerShell". Falhou? o toast ainda sai.
        try {
            $chave = "HKCU:\SOFTWARE\Classes\AppUserModelId\$Aumid"
            if (-not (Test-Path $chave)) { New-Item -Path $chave -Force | Out-Null }
            Set-ItemProperty -Path $chave -Name DisplayName -Value 'Hermes Lab' -ErrorAction SilentlyContinue
        } catch { }
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Aumid).Show(
            [Windows.UI.Notifications.ToastNotification]::new($t))
        return
    } catch {
        Write-Log "toast falhou: $($_.Exception.Message)"
    }
    # 2) fallback: balão da bandeja (sempre funciona em sessão interativa)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Warning
        $ni.Visible = $true
        $ni.ShowBalloonTip(10000, $title, $body, [System.Windows.Forms.ToolTipIcon]::Warning)
        Start-Sleep -Seconds 6
        $ni.Dispose()
    } catch {
        Write-Log "balão falhou: $($_.Exception.Message)"
    }
}

function Get-NamesHash([string]$names) {
    $sha = [Security.Cryptography.SHA256]::Create()
    return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($names))).Replace('-', '')
}

function Test-Notify([string]$hash) {
    if (Test-Path $state) {
        try {
            $s = Get-Content $state -Raw | ConvertFrom-Json
            $age = ((Get-Date) - [datetime]$s.at).TotalHours
            if ($s.hash -eq $hash -and $age -lt $RepeatAfterHours) { return $false }
        } catch { }
    }
    return $true
}

function Save-Notified([string]$hash, [string]$names) {
    @{ hash = $hash; at = (Get-Date).ToString('o'); names = $names } |
        ConvertTo-Json | Set-Content $state -Encoding UTF8
}

$query = 'ALERTS%7Balertstate%3D%22firing%22%7D'
# BatchMode + ConnectTimeout: numa tarefa agendada não existe ninguém para
# digitar senha de chave; sem isto, host fora do ar deixaria a task pendurada.
# EAP=Stop (no topo) transforma stderr de comando nativo em EXCEÇÃO: com o host
# fora do ar o ssh escreve no stderr e o script morria antes de chegar ao
# "sem resposta" - foi assim que a queda de 2026-10-22 passou em silêncio.
$raw = $null
$sshRc = 1
$ErrorActionPreference = 'Continue'
try {
    $raw = ssh -o BatchMode=yes -o ConnectTimeout=10 $Remote "docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=$query'" 2>$null
    $sshRc = $LASTEXITCODE
} catch {
    $raw = $null
}
$ErrorActionPreference = 'Stop'
if ($sshRc -ne 0) { $raw = $null }
if (-not $raw) {
    # Sem o Prometheus TUDO fica cego: nenhum alerta do lab chega. Isto TEM de avisar.
    # Antes só gravava no log e saía com 2: em 2026-10-22 a monitoração ficou 4 h fora
    # (host desligado e o prometheus não voltou) e ninguém foi avisado.
    $names = 'PrometheusSemResposta(critical)'
    $hash = Get-NamesHash $names
    if (Test-Notify $hash) {
        Show-Notification 'Hermes Lab: monitoracao fora do ar' 'O Prometheus nao respondeu (host desligado? ssh?). Os alertas do lab estao cegos.'
        Save-Notified $hash $names
        Write-Log "NOTIFICADO: $names"
    } else {
        Write-Log "ERRO (suprimido por <$RepeatAfterHours h): sem resposta do Prometheus"
    }
    exit 2
}

$alerts = @(($raw | ConvertFrom-Json).data.result)
if ($Test) {
    $alerts = @([pscustomobject]@{ metric = [pscustomobject]@{ alertname = 'TesteManual'; severity = 'warning' } })
}

if ($alerts.Count -eq 0) {
    Write-Log 'ok: nenhum alerta disparado'
    if (Test-Path $state) { Remove-Item $state -Force -ErrorAction SilentlyContinue }
    exit 0
}

$names = ($alerts | ForEach-Object { "$($_.metric.alertname)($($_.metric.severity))" } | Sort-Object -Unique) -join ', '
$hash = Get-NamesHash $names

if (Test-Notify $hash) {
    $title = "Hermes Lab: $($alerts.Count) alerta(s) disparado(s)"
    Show-Notification $title $names
    Save-Notified $hash $names
    Write-Log "NOTIFICADO: $names"
} else {
    Write-Log "disparado (suprimido por <$RepeatAfterHours h): $names"
}
exit 0
