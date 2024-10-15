# 出力先フォルダの設定（BackupLogs_日時でフォルダを作成）
$baseOutputFolder = "C:\ExportedLogs"
$currentDate = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFolder = Join-Path $baseOutputFolder "$currentDate"

# フォルダが存在しない場合は作成
if (!(Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Force -Path $backupFolder | Out-Null
}

# Sysmonログのエクスポートファイルパス
$sysmonExportPath = Join-Path $backupFolder "sysmon.evtx"

# Sysmonログをevtx形式でエクスポート (エラー処理を追加)
try {
    wevtutil epl Microsoft-Windows-Sysmon/Operational $sysmonExportPath
}
catch {
    Write-Error -Message "Sysmonログのエクスポートに失敗しました。$($_.Exception.Message)"
    Exit 1
}

# Windowsイベントログのエクスポートファイルパス
$systemExportPath = Join-Path $backupFolder "system.evtx"
$applicationExportPath = Join-Path $backupFolder "application.evtx"
$securityExportPath = Join-Path $backupFolder "security.evtx"

# Windowsイベントログのエクスポート
try {
    wevtutil epl System $systemExportPath
    wevtutil epl Application $applicationExportPath
    wevtutil epl Security $securityExportPath
}
catch {
    Write-Error -Message "Windowsイベントログのエクスポートに失敗しました。$($_.Exception.Message)"
    Exit 1
}

Write-Host "すべてのログが正常にエクスポートされました: $backupFolder"
