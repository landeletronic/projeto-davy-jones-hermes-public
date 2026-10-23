# =============================================================================
# pull-backups.ps1 - puxa os backups do host Linux para o seu PC (Windows)
#
# Destino padrão: \\localhost\backups\hermes-lab
# Retenção: mantém os 8 mais recentes no destino.
#
# INTEGRIDADE: cada arquivo é copiado para %TEMP%, conferido por SHA-256 contra o
# host e só então movido para o destino - scp truncado não entra como "backup".
#
# OFF-SITE DE VERDADE: \\localhost é a MESMA máquina do repositório. Para ter uma
# terceira cópia fora do PC, passe -ExtraDest (HD externo, pasta sincronizada):
#   powershell -File ops\windows\pull-backups.ps1 -ExtraDest 'E:\hermes-lab'
#
# Rodar manualmente:  powershell -File ops\windows\pull-backups.ps1
# Agendar:            schtasks /Create /TN "Hermes Lab Backup Pull" /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\usuario\Downloads\davy-jones-hermes\ops\windows\pull-backups.ps1" /SC DAILY /ST 12:00 /F
# =============================================================================
param(
    [string]$Remote = 'davy-jones-hermes',
    [string]$RemoteDir = '/home/tlandskron/backups',
    [string]$Dest = '\\localhost\backups\hermes-lab',
    [string[]]$ExtraDest = @(),
    [int]$Keep = 8
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
}

$files = @(ssh $Remote "ls -1 $RemoteDir/hermes-*.tar.gz" 2>$null)
if ($files.Count -eq 0 -or [string]::IsNullOrWhiteSpace($files[0])) {
    Write-Error "Nenhum backup encontrado em ${Remote}:$RemoteDir"
    exit 1
}

$tmp = Join-Path $env:TEMP 'hermes-backup-pull'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$copied = 0
foreach ($f in $files) {
    $name = Split-Path $f -Leaf
    $target = Join-Path $Dest $name
    if (-not (Test-Path $target)) {
        $local = Join-Path $tmp $name
        scp "${Remote}:$f" $local
        if (-not (Test-Path $local)) { throw "scp falhou para $name" }

        # Confere antes de aceitar: um tar truncado no destino é pior que nenhum.
        $remoteHash = ((ssh $Remote "sha256sum $f" 2>$null) -join ' ').Split(' ')[0]
        $localHash = (Get-FileHash -Algorithm SHA256 -Path $local).Hash.ToLower()
        if ($remoteHash -and ($remoteHash.ToLower() -ne $localHash)) {
            Remove-Item -Force $local
            throw "SHA-256 divergente em $name (host=$remoteHash local=$localHash) - cópia descartada"
        }
        Move-Item -Force $local $target
        Write-Host "copiado e conferido: $name"
        $copied++
    }

    # Destinos extras (off-site): mesma verificação, retenção própria.
    foreach ($d in $ExtraDest) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
        $t2 = Join-Path $d $name
        if (-not (Test-Path $t2)) {
            Copy-Item -Path $target -Destination $t2 -Force
            $h1 = (Get-FileHash -Algorithm SHA256 -Path $target).Hash
            $h2 = (Get-FileHash -Algorithm SHA256 -Path $t2).Hash
            if ($h1 -ne $h2) { throw "cópia off-site corrompida: $t2" }
            Write-Host "off-site: $t2"
        }
        Get-ChildItem $d -Filter 'hermes-*.tar.gz' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Keep |
            Remove-Item -Force
    }
}

Get-ChildItem $Dest -Filter 'hermes-*.tar.gz' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $Keep |
    Remove-Item -Force

$total = @(Get-ChildItem $Dest -Filter 'hermes-*.tar.gz').Count
Write-Host "OK: $copied novo(s), $total no destino ($Dest)"
if ($ExtraDest.Count -gt 0) {
    Write-Host "Off-site: $($ExtraDest -join ', ')"
} else {
    Write-Warning "Sem -ExtraDest: a cópia está só neste PC (\\localhost). Para off-site de verdade, aponte para um HD externo ou pasta sincronizada."
}
