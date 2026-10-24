# Verifica o acesso do Windows (B550M-AORUS-ELI) ao servidor ai-memory da estacao Omarchy.
#
# Uso:  powershell -File tests/verify-ai-memory.ps1
#
# Somente leitura: nao escreve pagina, nao altera config, nao imprime segredos.
# Sai com codigo 0 quando nao ha FAIL. WARN nao derruba (mesma convencao do verify_stack.sh).
#
# Regra do AGENTS.md secao 1: todo fix/invariante novo ganha um check. Este script e o
# check do cliente ai-memory; a suite do lab (verify_stack.sh) continua sendo o oraculo do host.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$script:pass = 0
$script:fail = 0
$script:warn = 0
function Ok   ($m) { Write-Host "  PASS  $m" -ForegroundColor Green;  $script:pass++ }
function Bad  ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:fail++ }
function Warn ($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }

$repo     = Split-Path -Parent $PSScriptRoot
$cfgDir   = Join-Path $env:USERPROFILE '.config\opencode'
$cfgFile  = Join-Path $cfgDir 'opencode.json'
$plugin   = Join-Path $cfgDir 'plugins\ai-memory-opencode2.ts'
$marker   = Join-Path $repo '.ai-memory.toml'
$expectWs = 'default'
$expectPj = 'davy-jones-hermes'

Write-Host 'ai-memory - cliente Windows (OpenCode 2)' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- 1. binario
$candidates = @()
$cmd = Get-Command ai-memory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd -and $cmd.Source) { $candidates += [string]$cmd.Source }
$candidates += (Join-Path $env:LOCALAPPDATA 'Programs\ai-memory\ai-memory.exe')
$candidates = @($candidates | Where-Object { $_ -and (Test-Path $_) })

if ($candidates.Count -gt 0) {
  $exe = $candidates[0]
  Ok "binario presente: $exe"
  $verOut = & $exe --version 2>&1
  $verTxt = ($verOut | Out-String).Trim()
  if ($verTxt -match '^ai-memory\s+\d+\.\d+\.\d+') { Ok "versao: $verTxt" } else { Bad "versao inesperada: $verTxt" }
  $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
  $binDir   = (Split-Path -Parent $exe).TrimEnd('\')
  $inPath   = @(($userPath -split ';') | Where-Object { $_.Trim().TrimEnd('\') -ieq $binDir }).Count -gt 0
  if ($inPath) {
    Ok 'pasta do binario esta no PATH do usuario'
  } else {
    Bad 'pasta do binario NAO esta no PATH do usuario'
  }
} else {
  Bad 'binario ai-memory nao encontrado (PATH e %LOCALAPPDATA%\Programs\ai-memory)'
  $exe = $null
}

# ---------------------------------------------------------------- 2. credenciais e servidor
$url   = [Environment]::GetEnvironmentVariable('AI_MEMORY_SERVER_URL',   'User')
$token = [Environment]::GetEnvironmentVariable('AI_MEMORY_AUTH_TOKEN',   'User')

if ($url) {
  Ok "AI_MEMORY_SERVER_URL definida (escopo User): $url"
} else {
  Bad 'AI_MEMORY_SERVER_URL ausente no escopo User'
}

if ($token -and $token.StartsWith('aim_')) {
  Ok "AI_MEMORY_AUTH_TOKEN definida (escopo User), chave aim_ de $($token.Length) caracteres"
} else {
  Bad 'AI_MEMORY_AUTH_TOKEN ausente/invalida no escopo User'
}

# ---------------------------------------------------------------- 3. conectividade (o efeito)
if ($url) {
  $base = $url.TrimEnd('/')
  try {
    $h = Invoke-WebRequest -Uri "$base/healthz" -UseBasicParsing -TimeoutSec 30
    if ($h.Content -match '"status"\s*:\s*"ok"') { Ok '/healthz respondeu {"status":"ok"}' }
    else { Warn "/healthz respondeu codigo $($h.StatusCode) com corpo inesperado" }
  } catch {
    Bad "/healthz inacessivel: $($_.Exception.Message)"
  }

  try {
    Invoke-WebRequest -Uri "$base/mcp" -Method Post -Body '{}' -ContentType 'application/json' `
      -UseBasicParsing -TimeoutSec 30 | Out-Null
    Bad '/mcp aceitou requisicao SEM token (esperado 401)'
  } catch [System.Net.WebException] {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($code -eq 401) { Ok '/mcp sem token -> 401 (endpoint protegido)' }
    else { Warn "/mcp sem token -> HTTP $code (esperado 401)" }
  }

  if ($token) {
    $headers = @{
      'Authorization' = "Bearer $token"
      'Content-Type'  = 'application/json'
      'Accept'        = 'application/json, text/event-stream'
    }
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify-ai-memory","version":"0"}}}'
    try {
      $r = Invoke-WebRequest -Uri "$base/mcp" -Method Post -Headers $headers -Body $body `
        -UseBasicParsing -TimeoutSec 60
      if ([int]$r.StatusCode -eq 200) { Ok '/mcp com token -> 200 (autenticacao e handshake MCP ok)' }
      else { Bad "/mcp com token -> HTTP $($r.StatusCode)" }
    } catch [System.Net.WebException] {
      $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
      Bad "/mcp com token -> HTTP $code (401 = chave revogada/ausente; 403 = host nao permitido)"
    }
  }
} else {
  Warn 'checks de conectividade pulados (sem AI_MEMORY_SERVER_URL)'
}

# ---------------------------------------------------------------- 4. config MCP do OpenCode (V2)
if (Test-Path $cfgFile) {
  try {
    $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
    $srv = $cfg.mcp.servers.'ai-memory'
    if ($srv) {
      if ($srv.type -eq 'remote') { Ok 'opencode.json: mcp.servers.ai-memory.type = remote' }
      else { Bad "opencode.json: type = '$($srv.type)' (esperado remote)"; }
      if ($srv.url -match '/mcp$') { Ok "opencode.json: url = $($srv.url)" } else { Bad "opencode.json: url '$($srv.url)' nao termina em /mcp" }
      if ($srv.oauth -eq $false) { Ok 'opencode.json: oauth = false' } else { Bad 'opencode.json: oauth deve ser false' }
      $auth = $srv.headers.Authorization
      if ($auth -match '^Bearer\s+aim_\S+$') { Ok 'opencode.json: header Authorization presente (Bearer aim_...)' }
      else { Bad 'opencode.json: header Authorization ausente/malformado' }
      if ($auth -and $token -and ($auth -replace '^Bearer\s+', '') -ne $token) {
        Warn 'opencode.json: a chave do header difere da variavel de ambiente (rotacao pela metade?)'
      }
      # o MCP deve ser o formato V2 (aninhado); um "mcp" plano e contrato V1
      if ($cfg.mcp.PSObject.Properties.Name -contains 'type') { Bad 'opencode.json: "mcp" parece formato V1 (campo type no nivel de mcp)' }
    } else {
      Bad 'opencode.json: entrada mcp.servers.ai-memory ausente'
    }
  } catch {
    Bad "opencode.json ilegivel: $($_.Exception.Message)"
  }
} else {
  Bad "config ausente: $cfgFile"
}

# ---------------------------------------------------------------- 4b. compactacao (o ajuste fino)
# O ai-memory NAO impede compactacao: quem compacta e o cliente OpenCode. O que se ajusta aqui
# e quanto detalhe recente sobrevive (keep.tokens). O agente nao deve "consertar" isso sozinho:
# keep abaixo de 15k (o default) e regressao; auto=false e escolha consciente, nao default.
if ($cfg -and $cfg.compaction) {
  $auto = $cfg.compaction.auto
  $keep = 0
  if ($cfg.compaction.keep -and $cfg.compaction.keep.tokens) { $keep = [int]$cfg.compaction.keep.tokens }
  if ($auto -ne $false) { Ok "opencode.json: compaction.auto = $auto (compactacao automatica ligada)" }
  else { Warn 'opencode.json: compaction.auto = false (compactacao so manual; verifique se foi intencional)' }

  if ($keep -ge 24000) { Ok "opencode.json: compaction.keep.tokens = $keep (>= 24000, detalhe recente preservado)" }
  elseif ($keep -ge 15000) { Warn "opencode.json: compaction.keep.tokens = $keep (abaixo do alvo 24000; ainda >= default 15000)" }
  elseif ($keep -gt 0) { Bad "opencode.json: compaction.keep.tokens = $keep (abaixo do default 15000)" }
  else { Warn 'opencode.json: compaction.keep.tokens ausente (default 15000)' }
} else {
  Warn 'opencode.json: sem bloco "compaction" (defaults: auto=true, keep=15000)'
}

# ---------------------------------------------------------------- 5. plugin de captura (hooks)
if (Test-Path $plugin) {
  $len = (Get-Item $plugin).Length
  Ok "plugin de captura presente: ai-memory-opencode2.ts ($([Math]::Round($len/1KB)) KB)"
} else {
  Bad "plugin de captura ausente: $plugin"
}

# ---------------------------------------------------------------- 6. marcador do projeto
if (Test-Path $marker) {
  $md = Get-Content $marker -Raw
  $ws = if ($md -match '(?m)^\s*workspace\s*=\s*"([^"]+)"') { $matches[1] } else { $null }
  $pj = if ($md -match '(?m)^\s*project\s*=\s*"([^"]+)"')   { $matches[1] } else { $null }
  if ($ws -eq $expectWs -and $pj -eq $expectPj) {
    Ok ".ai-memory.toml -> $ws/$pj (coordenada das duas maquinas)"
  } else {
    Bad ".ai-memory.toml -> '$ws/$pj' (esperado '$expectWs/$expectPj')"
  }
} else {
  Bad ".ai-memory.toml ausente em $repo"
}

# ---------------------------------------------------------------- 7. nenhum servidor local (nao rodamos setup)
$run = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ai-memory' -ErrorAction SilentlyContinue
if ($run) {
  Bad 'existe entrada de logon "ai-memory" (o setup foi rodado: cria servidor local paralelo)'
} else {
  Ok 'nenhuma entrada de logon ai-memory (cliente puro, sem servidor local)'
}

# ---------------------------------------------------------------- resumo
Write-Host ''
Write-Host ("PASS={0} / FAIL={1} / WARN={2}" -f $script:pass, $script:fail, $script:warn)
if ($script:fail -gt 0) { exit 1 }
exit 0
