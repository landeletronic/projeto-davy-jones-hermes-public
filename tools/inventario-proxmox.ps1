#Requires -Version 5.1
<#
.SYNOPSIS
    Inventario de hardware do servidor fisico (Proxmox), disparado do Windows.

.DESCRIPTION
    Envia tools/inventario_hardware.sh ao host por base64 (o ssh do PowerShell 5.1
    mangla aspas), executa (root ou `sudo -n`) e grava o Markdown em
    docs/architecture/INVENTARIO-HARDWARE-PROXMOX.md.

    Somente leitura: nao instala nada e nao altera nada no host. O coletor viaja num
    temporario /tmp/.inventario<pid>.sh (mais a saida em .md), removido por um trap ao
    final - inclusive quando o coletor falha. A saida volta em base64 para o console
    nao estragar travessoes/acentos.

    Sem chave cadastrada o ssh pede a senha (a primeira tentativa e sem BatchMode).

.EXAMPLE
    powershell -File tools\inventario-proxmox.ps1

.EXAMPLE
    powershell -File tools\inventario-proxmox.ps1 -DryRun

.EXAMPLE
    powershell -File tools\inventario-proxmox.ps1 -Target root@192.168.15.221 -OutFile C:\temp\inventario.md
#>
[CmdletBinding()]
param(
    [string]$Target = 'root@192.168.15.221',
    [string]$OutFile = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$raiz    = Split-Path -Parent $PSScriptRoot
$coletor = Join-Path $PSScriptRoot 'inventario_hardware.sh'
if (-not $OutFile) { $OutFile = Join-Path $raiz 'docs\architecture\INVENTARIO-HARDWARE-PROXMOX.md' }

if (-not (Test-Path -LiteralPath $coletor)) {
    Write-Host "ERRO: coletor ausente: $coletor" -ForegroundColor Red
    exit 1
}

function Invoke-Remote {
    param([string]$Command, [switch]$Batch)

    $sshArgs = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
    if ($Batch) { $sshArgs += @('-o', 'BatchMode=yes') }
    $sshArgs += $Target
    $sshArgs += $Command

    $errFile = [System.IO.Path]::GetTempFileName()
    # ssh que falha escreve no stderr; com ErrorActionPreference=Stop o PS 5.1
    # transforma isso em NativeCommandError e o tratamento nunca roda.
    $ErrorActionPreference = 'Continue'
    $linhas = & ssh @sshArgs 2> $errFile
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    $erro = ''
    if (Test-Path -LiteralPath $errFile) {
        $erro = [System.IO.File]::ReadAllText($errFile)
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Code = $code
        Out  = ($linhas -join "`n")
        Err  = $erro
    }
}

# 1. coletor -> base64 (texto puro, sem aspas que o ssh mangla)
$b64Coletor = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($coletor))

# 2. runner remoto. Regras: NENHUMA aspa dupla aqui dentro (o PowerShell 5.1 mangla
#    aspas ao passar um argumento grande para o ssh) e UMA LINHA SO (quebra de linha
#    em argumento de comando e fragil no CreateProcess do Windows). O payload vai uma
#    vez (base64 do coletor, ~21 KB): duas camadas davam ~28 KB e estouravam o limite
#    de 32 KB do CreateProcess no Windows.
#    Sem PIPESTATUS: assim nao depende de o shell do root ser bash.
$runner = @'
set -u; f=/tmp/.inventario$$.sh; o=/tmp/.inventario$$.md; trap 'rm -f $f $o' EXIT; echo __B64__ | base64 -d > $f || { echo ERRO_AO_DECODIFICAR_O_COLETOR >&2; exit 3; }; bash -n $f || { echo SINTAXE_FALHOU_no_coletor >&2; exit 2; }; if [ $(id -u) -eq 0 ]; then bash $f > $o; rc=$?; else sudo -n bash $f > $o; rc=$?; fi; base64 -w0 < $o; exit $rc
'@
$runner = $runner.Trim()
$runner = $runner.Replace('__B64__', $b64Coletor)

$comando = $runner

# 3. executa
Write-Host "[1/3] conectando em $Target ..."
$r = Invoke-Remote -Command $comando -Batch

if ($r.Code -eq 255 -and $r.Err -match 'Permission denied|publickey|no such identity') {
    Write-Host '      sem chave cadastrada; o ssh vai pedir a senha do root ...'
    $r = Invoke-Remote -Command $comando
}

if ($r.Code -ne 0) {
    Write-Host "[2/3] FALHOU (ssh/coletor exit $($r.Code))" -ForegroundColor Red
    if ($r.Err) { Write-Host $r.Err.Trim() -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Dicas:' -ForegroundColor Yellow
    Write-Host '  - cadastrar a chave (uma vez):'
    Write-Host '      type $env:USERPROFILE\.ssh\pve-lab.pub | ssh root@192.168.15.221 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"'
    Write-Host '  - o host precisa de pciutils (lspci) e de dmidecode; ambos vem com o Proxmox VE'
    exit $r.Code
}

# 4. decodifica
$b64Out = ($r.Out -replace '\s', '')
if (-not $b64Out) {
    Write-Host '[2/3] o host nao devolveu nada' -ForegroundColor Red
    if ($r.Err) { Write-Host $r.Err.Trim() }
    exit 1
}

try {
    $texto = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64Out))
} catch {
    Write-Host "[2/3] saida do host nao e base64 valido: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($texto -notmatch '(?m)^# Inventario de hardware') {
    Write-Host '[2/3] saida inesperada: nao comeca com o titulo do inventario' -ForegroundColor Red
    exit 1
}

# 5. invariante: numero de serie/UUID/asset tag nunca sai do coletor
if ($texto -match '(?m)^\s*(Serial Number|UUID|Asset Tag):\s*(?!\(omitido\))\S') {
    Write-Host '[2/3] o coletor devolveu identificador unico NAO mascarado; nada foi gravado' -ForegroundColor Red
    exit 1
}

if ($texto -match 'systemd-detect-virt = (kvm|qemu|vmware|microsoft|xen|oracle)') {
    Write-Warning 'este host e uma VM: placa-mae/fonte/gabinete so aparecem no servidor fisico (Proxmox)'
}

# 6. grava
if (-not $texto.EndsWith("`n")) { $texto += "`n" }
$linhasTexto = ($texto -split "`n").Count

if ($DryRun) {
    Write-Host "[2/3] -DryRun: nada gravado ($linhasTexto linhas). Documento:"
    Write-Host ''
    Write-Host $texto
    exit 0
}

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutFile, $texto, $utf8)

Write-Host "[2/3] gravado: $OutFile ($linhasTexto linhas, $($texto.Length) caracteres)"

# 7. resume na tela o que o usuario pediu
$resumo = @()
$dentro = $false
foreach ($l in ($texto -split "`n")) {
    if ($l -match '^## Resumo') { $dentro = $true; continue }
    if ($dentro -and $l -match '^## ') { break }
    if ($dentro -and $l.Trim()) { $resumo += $l }
}
if ($resumo.Count -gt 0) {
    Write-Host "[3/3] resumo do que foi encontrado:"
    $resumo | ForEach-Object { Write-Host "  $_" }
}
exit 0
