Set objShell = CreateObject("WScript.Shell")
strScriptPath = objShell.CurrentDirectory

' ExportSysmonLogs.ps1を非表示で実行
objShell.Run "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & strScriptPath & "\ExportSysmonLogs.ps1""", 0, True
