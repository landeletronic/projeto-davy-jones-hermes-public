# Executa a suíte de regressão do lab no host (Windows -> host via ssh).
#
# Uso:  powershell -File tests/run-tests.ps1 [host]
#       (host padrão: davy-jones-hermes)
#
# Envia o script em base64 para evitar as armadilhas de quoting do PowerShell.

param([string]$Target = 'davy-jones-hermes')

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'verify_stack.sh'
if (-not (Test-Path $script)) { Write-Error "nao encontrei $script"; exit 2 }

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script))
# tr -d '\r' protege contra final de linha CRLF do Windows
ssh $Target "echo $b64 | base64 -d | tr -d '\r' > /tmp/verify_stack.sh && bash /tmp/verify_stack.sh"
exit $LASTEXITCODE
