$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$PSScriptRoot\RunExportSysmonLogs.vbs`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 30)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "Export Sysmon Logs" -Action $action -Trigger $trigger -Settings $settings
