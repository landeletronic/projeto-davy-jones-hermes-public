#requires -Version 5.0
<#
  Oracao do compartilhamento SMB da pasta do projeto (lado Windows).
  Verifica QUE o compartilhamento existe e COMO esta compartilhado (o efeito, nao só o arquivo).
  PASS/FAIL por item + resumo. Exit code 0 = ok, 1 = houve FAIL.
  Nao requer elevacao.
  Uso: powershell -File tools\verify-share-davy-jones-hermes.ps1
#>
$ErrorActionPreference = 'Stop'

$Folder = 'C:\Users\usuario\Downloads\davy-jones-hermes'
$Share  = 'davy-jones-hermes'
$User   = 'B550M-AORUS-ELI\tlandskron'

$script:pass = 0; $script:fail = 0; $script:warn = 0
function Check($desc, [bool]$ok) { if ($ok) { "  PASS  $desc"; $script:pass++ } else { "  FAIL  $desc"; $script:fail++ } }
function Warn($desc)  { "  WARN  $desc"; $script:warn++ }
function Info($desc)  { "  INFO  $desc" }

function SidsOf($acl) {
    $acl.Access | ForEach-Object {
        try { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
        catch { $_.IdentityReference.Value }
    }
}

"== PASTA / SHARE =="
Check "pasta existe ($Folder)" (Test-Path -LiteralPath $Folder)

$sh = Get-SmbShare -Name $Share -ErrorAction SilentlyContinue
Check "share '$Share' existe" ([bool]$sh)
if ($sh) {
    Check "share aponta para a pasta correta" ($sh.Path -eq $Folder)
    Check "share nao usa cache offline (CachingMode=None)" ($sh.CachingMode -eq 'None')

    $sa = @(Get-SmbShareAccess -Name $Share)
    Check "share: exatamente 1 regra (somente $User)" ($sa.Count -eq 1)
    Check "share: $User com Change (leitura + gravacao)" (
        [bool]($sa | Where-Object { $_.AccountName -eq $User -and $_.AccessRight -eq 'Change' }))
    $extras = @($sa | Where-Object { $_.AccountName -ne $User })
    Check "share: nenhum outro usuario (Todos/Administradores/etc.)" ($extras.Count -eq 0)
    if ($extras.Count) { $extras | ForEach-Object { Info "  regra extra: $($_.AccountName) = $($_.AccessRight)" } }
}

"== ACL (NTFS) =="
if (Test-Path -LiteralPath $Folder) {
    $acl = Get-Acl -LiteralPath $Folder
    Check "ACL: heranca desabilitada (permissoes explicitas)" ($acl.AreAccessRulesProtected)
    Check "ACL: owner = $User" ($acl.Owner -eq $User)

    $sids = SidsOf $acl
    $allow = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Allow' })

    Check "ACL: no maximo 2 contas (usuario + SISTEMA)" ($allow.Count -eq 2)
    Check "ACL: $User com FullControl" (
        [bool]($acl.Access | Where-Object { $_.IdentityReference.Value -eq $User -and $_.FileSystemRights -match 'FullControl' }))
    Check "ACL: SISTEMA com FullControl (servicos do Windows)" ($sids -contains 'S-1-5-18')

    $proibidos = @{
        'S-1-5-32-544' = 'Administradores'
        'S-1-5-32-545' = 'Usuarios'
        'S-1-1-0'      = 'Todos'
        'S-1-5-11'     = 'Usuarios Autenticados'
    }
    foreach ($sid in $proibidos.Keys) {
        Check "ACL: sem $($proibidos[$sid]) (SID $sid)" (-not ($sids -contains $sid))
    }
    $outros = @($sids | Where-Object { $_ -ne 'S-1-5-18' -and $_ -ne $acl.Owner -and $_ -notlike 'S-1-5-21-*' })
    if ($outros.Count) { Info "SIDs na ACL: $($outros -join ', ')" }
}

"== REDE / FIREWALL (informativo) =="
try {
    $aberta = @(Get-NetFirewallRule -Name 'FPS-SMB-In-TCP*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Enabled -eq 'True' })
    if ($aberta.Count -eq 0) {
        Warn "SMB de entrada BLOQUEADO no firewall (decisao do usuario): o share NAO e alcancavel de outras maquinas"
    } else {
        Info "SMB de entrada liberado nos perfis: $((($aberta.Profile | Sort-Object -Unique) -join ', '))"
    }
} catch { Warn "nao foi possivel ler as regras de firewall: $($_.Exception.Message)" }

""
"== RESUMO =="
"  PASS=$script:pass  FAIL=$script:fail  WARN=$script:warn"
if ($script:fail -eq 0) { "  >> SHARE OK <<"; exit 0 } else { "  >> SHARE COM PROBLEMAS <<"; exit 1 }
