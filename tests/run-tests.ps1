# Executa a suite de regressao do lab no host (Windows -> host via ssh).
#
# Uso:  powershell -File tests/run-tests.ps1 [host]
#       (host padrao: davy-jones-hermes)
#
# Transporte: scp do arquivo + execucao remota.
#
# Historico: ate 2026-10-23 este runner mandava a suite inteira em base64 numa UNICA linha de
# `ssh`. Com 230 checks o argumento passou do limite de ~32k da linha de comando do Windows e o
# runner morreu com "Falha na execucao do programa 'ssh.exe': O nome do arquivo ou a extensao e
# muito grande" - sem sequer conectar. O base64 tambem inflava o payload em 33%.
# scp nao tem esse limite e mantem o arquivo byte a byte; o `tr -d '\r'` continua protegendo
# contra final de linha CRLF do Windows.

param([string]$Target = 'davy-jones-hermes')

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'verify_stack.sh'
if (-not (Test-Path $script)) { Write-Error "nao encontrei $script"; exit 2 }

$remote = '/tmp/verify_stack.sh'

Write-Host ">> enviando $script para ${Target}:$remote" -ForegroundColor Cyan
scp $script "${Target}:${remote}"
if ($LASTEXITCODE -ne 0) {
  Write-Error "scp falhou (exit $LASTEXITCODE) - host inacessivel? (lab desligado e a causa comum)"
  exit $LASTEXITCODE
}

# O comando remoto usa SO aspas simples: o PowerShell 5.1 mangla aspas duplas embutidas.
Write-Host ">> executando a suite no host" -ForegroundColor Cyan
ssh $Target "tr -d '\r' < $remote > /tmp/vs.sh && chmod +x /tmp/vs.sh && bash /tmp/vs.sh"
exit $LASTEXITCODE
