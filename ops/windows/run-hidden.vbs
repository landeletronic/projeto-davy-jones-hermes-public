' run-hidden.vbs - roda um .ps1 desta pasta SEM abrir janela nenhuma.
'
' Por que existe: uma tarefa agendada que chama "powershell.exe" direto e roda na
' sessao do usuario (InteractiveToken) abre o console do PowerShell por ~1 s (ate
' ~7 s quando notifica). A cada 30 min isso roubava o foco e engolia o que a pessoa
' estava digitando (2026-10-22). wscript e um host grafico (sem console) e o Run
' com 0 (SW_HIDE) garante que o PowerShell filho nasce oculto.
'
' Uso: wscript.exe //nologo run-hidden.vbs watch-alerts.ps1

Option Explicit

Dim fso, sh, pasta, alvo, cmd

If WScript.Arguments.Count = 0 Then
    WScript.Echo "uso: wscript.exe //nologo run-hidden.vbs <script.ps1>"
    WScript.Quit 2
End If

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

pasta = fso.GetParentFolderName(WScript.ScriptFullName)
alvo  = WScript.Arguments(0)

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
      & pasta & "\" & alvo & """"

' 0 = janela oculta, False = nao espera terminar (a tarefa nao fica pendurada)
sh.Run cmd, 0, False
