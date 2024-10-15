Set objShell = CreateObject("WScript.Shell")
strScriptPath = objShell.CurrentDirectory

' ExportSysmonLogs.ps1ÇîÒï\é¶Ç≈é¿çs
objShell.Run "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & strScriptPath & "\ExportSysmonLogs.ps1""", 0, True
