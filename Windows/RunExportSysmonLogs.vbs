Set objShell = CreateObject("WScript.Shell")
strScriptPath = objShell.CurrentDirectory

' ExportSysmonLogs.ps1���\���Ŏ��s
objShell.Run "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & strScriptPath & "\ExportSysmonLogs.ps1""", 0, True
