#requires -Version 5.0
<#
  Compartilha a pasta do laboratorio na LAN APENAS com o usuario tlandskron.
    - Share SMB : davy-jones-hermes  ->  C:\Users\usuario\Downloads\davy-jones-hermes
    - Permissao de share : somente tlandskron (Change = leitura + gravacao)
    - NTFS : somente tlandskron + SISTEMA (Controle Total); heranca removida
    - Administradores / Usuarios / Todos / Usuarios Autenticados : REMOVIDOS
    - O firewall NAO e alterado (decisao do usuario)
  Idempotente: pode rodar quantas vezes quiser.
  Requer elevacao (New-SmbShare / Set-Acl).
#>
$ErrorActionPreference = 'Stop'

$Folder = 'C:\Users\usuario\Downloads\davy-jones-hermes'
$Share  = 'davy-jones-hermes'
$User   = 'B550M-AORUS-ELI\tlandskron'
$System = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')  # NT AUTHORITY\SYSTEM

function Say($m) { Write-Output $m }

$Log = 'C:\Users\usuario\AppData\Local\Temp\opencode\share-davy-jones-hermes.log'
Start-Transcript -Path $Log -Force | Out-Null

try {
    if (-not (Test-Path -LiteralPath $Folder)) { throw "Pasta nao encontrada: $Folder" }

    # ---------- 1) NTFS ----------
    Say "== NTFS: $Folder"
    $acl = Get-Acl -LiteralPath $Folder
    $acl.SetAccessRuleProtection($true, $false)                       # nao herda + descarta as herdadas
    foreach ($ace in @($acl.Access)) { [void]$acl.RemoveAccessRule($ace) }   # limpa as explicitas
    $inh   = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User,   'FullControl', $inh, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($System, 'FullControl', $inh, $prop, $allow)))
    $acl.SetOwner((New-Object System.Security.Principal.NTAccount($User)))
    Set-Acl -LiteralPath $Folder -AclObject $acl
    Say "   owner definido para: $((Get-Acl -LiteralPath $Folder).Owner)"

    # ---------- 2) Share ----------
    Say "== SMB share: $Share"
    if (Get-SmbShare -Name $Share -ErrorAction SilentlyContinue) {
        Say "   share ja existia -> recriando"
        Remove-SmbShare -Name $Share -Force
    }
    New-SmbShare -Name $Share -Path $Folder -ChangeAccess $User -CachingMode None `
        -Description 'Lab davy-jones-hermes (somente tlandskron)' | Out-Null
    # garante que ninguem mais tem permissao de share (ex.: Everyone)
    Get-SmbShareAccess -Name $Share | ForEach-Object {
        if ($_.AccountName -ne $User) {
            Say "   revogando acesso de share de: $($_.AccountName)"
            Revoke-SmbShareAccess -Name $Share -AccountName $_.AccountName -Force | Out-Null
        }
    }

    # ---------- 3) Verificacao ----------
    Say ""
    Say "===== VERIFICACAO ====="
    Say "--- share ---"
    Get-SmbShare -Name $Share | Format-List Name,Path,Description,CachingMode
    Say "--- permissoes de SHARE ---"
    (Get-SmbShareAccess -Name $Share | Format-Table AccountName,AccessControlType,AccessRight -AutoSize | Out-String).TrimEnd() | Write-Output
    Say "--- ACL (NTFS) da pasta ---"
    $acl2 = Get-Acl -LiteralPath $Folder
    Say "Owner: $($acl2.Owner)"
    Say "InheritanceProtected: $($acl2.AreAccessRulesProtected)"
    ($acl2.Access | Format-Table IdentityReference,FileSystemRights,AccessControlType,IsInherited -AutoSize | Out-String).TrimEnd() | Write-Output
    Say ""
    Say "--- firewall (somente leitura, NAO alterado) ---"
    ($(Get-NetFirewallRule -Name 'FPS-SMB-In-TCP*' -ErrorAction SilentlyContinue |
        Select-Object Name,Enabled,Profile | Format-Table -AutoSize | Out-String).TrimEnd()) | Write-Output

    Say "RESULTADO: OK"
}
catch {
    Say "RESULTADO: ERRO -> $($_.Exception.Message)"
}
finally {
    Stop-Transcript | Out-Null
}
