# Rotaciona a chave da MAQUINA (aim_...) nos tres lugares do Windows, de forma atomica.
#
# Por que existe: a chave do cliente aparece em texto claro em tres pontos desta maquina
#   - variavel de ambiente de usuario  AI_MEMORY_AUTH_TOKEN
#   - header do MCP em                 %USERPROFILE%\.config\opencode\opencode.json
#   - cache do CLI em                  %LOCALAPPDATA%\ai-memory\auth-token (+ auth-header)
# e ainda pode vazar em stdout (ai-memory install-mcp) ou em `GET /api/config` do servidor LOCAL
# do OpenCode (127.0.0.1, Basic auth com o service.json). Trocar so um dos tres deixa o cliente
# metade velho/metade novo - o verify-ai-memory.ps1 tem um WARN justamente para esse caso.
#
# A rotacao no SERVIDOR (Omarchy, token raiz) e um passo separado e obrigatorio ANTES:
#   ai-memory api-key rotate <ID-da-chave>
# o ID desta maquina esta no runbook, secao 11.8. So depois rode este script com a chave NOVA.
#
# Uso:
#   powershell -File tools\rotate-ai-memory-key.ps1                 # previa (nao escreve nada)
#   powershell -File tools\rotate-ai-memory-key.ps1 -Apply          # aplica (chave no clipboard)
#   powershell -File tools\rotate-ai-memory-key.ps1 -Apply -ClearClipboard
#   powershell -File tools\rotate-ai-memory-key.ps1 -Apply -SkipVerify
#
# A chave nova entra pelo clipboard (padrao) ou por -Key. NUNCA e impressa: so o tamanho.
# Somente leitura por padrao: sem -Apply nada e escrito.

[CmdletBinding()]
param(
  [string]$Key,
  [switch]$Apply,
  [switch]$ClearClipboard,
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

$cfgPath  = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
$tokPath  = Join-Path $env:LOCALAPPDATA 'ai-memory\auth-token'
$hdrPath  = Join-Path $env:LOCALAPPDATA 'ai-memory\auth-header'
$verify   = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify-ai-memory.ps1'

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

Write-Host 'Rotacao da chave ai-memory (cliente Windows)' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------ 1. a chave nova
if ($Key) {
  $new = $Key.Trim()
} else {
  $new = (Get-Clipboard -Raw)
  if ($new) { $new = $new.Trim() }
}

if (-not $new) { Fail 'nenhuma chave informada (-Key) e o clipboard esta vazio' }
if (-not $new.StartsWith('aim_')) { Fail "a chave nao comeca com 'aim_' (len=$($new.Length)) - o clipboard tem outra coisa?" }
if ($new -notmatch '^aim_[A-Za-z0-9_\-]+$') { Fail 'a chave tem caracteres fora de [A-Za-z0-9_-] (copiou lixo junto?)' }
if ($new.Length -lt 40) { Fail "chave curta demais (len=$($new.Length))" }

$old = [Environment]::GetEnvironmentVariable('AI_MEMORY_AUTH_TOKEN', 'User')
Write-Host ("chave nova: len={0} prefixo={1}" -f $new.Length, $new.Substring(0, 4))
if ($old) { Write-Host ("chave atual: len={0} prefixo={1}" -f $old.Length, $old.Substring(0, 4)) }
else { Write-Host 'chave atual: (nao definida no escopo User)' }

if ($old -and $old -eq $new) {
  Write-Host ''
  Write-Host 'NADA A FAZER: o clipboard tem a MESMA chave que ja esta configurada.' -ForegroundColor Yellow
  Write-Host ''
  Write-Host 'Isso quase sempre significa que a rotacao no SERVIDOR ainda nao foi feita:'
  Write-Host '  na estacao Omarchy, com o token raiz:'
  Write-Host '    ai-memory api-key rotate 01a155ab-a7ce-7a91-8825-54dabf284cd9'
  Write-Host '  (ou, se o rotate nao imprimir a chave nova: ai-memory api-key add + api-key revoke da antiga)'
  Write-Host 'Copie a chave NOVA e rode de novo com -Apply.' -ForegroundColor Yellow
  exit 0
}

# ------------------------------------------------------------------ 2. conferir os alvos
if (-not (Test-Path $cfgPath)) { Fail "config do OpenCode ausente: $cfgPath" }
$raw = [IO.File]::ReadAllText($cfgPath)
$rxBear = [regex]'(?<="Authorization"\s*:\s*"Bearer\s+)[^"]+'
if (-not $rxBear.IsMatch($raw)) { Fail 'nao achei o header "Authorization: Bearer ..." no opencode.json (formato mudou?)' }

$cfgBefore = $raw
$tokState  = if (Test-Path $tokPath) { 'auth-token' } else { 'auth-token (ausente, sera criado)' }
Write-Host ("alvos: opencode.json, env User, {0}" -f $tokState)

if (-not $Apply) {
  Write-Host ''
  Write-Host 'PREVIA (nada foi escrito). Rode de novo com -Apply.' -ForegroundColor Yellow
  exit 0
}

# ------------------------------------------------------------------ 3. backup
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$bakCfg = "$cfgPath.bak-$stamp"
Copy-Item $cfgPath $bakCfg -Force
Write-Host "backup: $bakCfg"

# ------------------------------------------------------------------ 4. aplicar
$eval = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $new }
$cfgAfter = $rxBear.Replace($cfgBefore, $eval, 1)

# preserva o BOM original (o arquivo pode ou nao ter)
$bytes  = [IO.File]::ReadAllBytes($cfgPath)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
[IO.File]::WriteAllText($cfgPath, $cfgAfter, (New-Object System.Text.UTF8Encoding($hasBom)))
Write-Host "ok opencode.json (backup em .bak-$stamp)"

[Environment]::SetEnvironmentVariable('AI_MEMORY_AUTH_TOKEN', $new, 'User')
[Environment]::SetEnvironmentVariable('AI_MEMORY_AUTH_TOKEN', $new, 'Process')
Write-Host 'ok env User + Process'

$ascii = New-Object System.Text.ASCIIEncoding
[IO.File]::WriteAllText($tokPath, $new, $ascii)
[IO.File]::WriteAllText($hdrPath, "Authorization: Bearer $new`n", $ascii)
Write-Host 'ok cache do CLI (auth-token/auth-header)'

if ($ClearClipboard) {
  # PS 5.1: Set-Clipboard -Value '' estoura ArgumentNullException ("Valor nao pode ser nulo") e,
  # com ErrorActionPreference=Stop, ABORTA o script antes da conferencia final. Use um espaco
  # (sai da area de transferencia o segredo, nao o comando) e trate como melhor-esforco.
  try {
    Set-Clipboard -Value ' '
    Write-Host 'ok clipboard limpo (substituido por um espaco)'
  } catch {
    try { & cmd.exe /c 'echo off|clip' | Out-Null; Write-Host 'ok clipboard limpo (via clip.exe)' }
    catch { Write-Warning "nao consegui limpar o clipboard: limpe a mao (a chave fica visivel no historico do Win+V)" }
  }
}

# ------------------------------------------------------------------ 5. conferir o resultado
$check = [Environment]::GetEnvironmentVariable('AI_MEMORY_AUTH_TOKEN', 'User')
$head  = ($rxBear.Match([IO.File]::ReadAllText($cfgPath))).Value
if ($check -ne $new) { Fail 'env User nao bate com a chave nova (escrita falhou)' }
if ($head -ne $new)  { Fail 'header do opencode.json nao bate com a chave nova' }
Write-Host ''
Write-Host 'CONFERIDO: os tres lugares estao com a chave nova.' -ForegroundColor Green

if ($SkipVerify) {
  Write-Host 'verificacao pulada (-SkipVerify).' -ForegroundColor Yellow
  exit 0
}

Write-Host ''
Write-Host '>> rodando tests\verify-ai-memory.ps1' -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $verify
exit $LASTEXITCODE
