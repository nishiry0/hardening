# �o�͐�t�H���_�̐ݒ�iBackupLogs_�����Ńt�H���_���쐬�j
$baseOutputFolder = "C:\ExportedLogs"
$currentDate = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFolder = Join-Path $baseOutputFolder "$currentDate"

# �t�H���_�����݂��Ȃ��ꍇ�͍쐬
if (!(Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Force -Path $backupFolder | Out-Null
}

# Sysmon���O�̃G�N�X�|�[�g�t�@�C���p�X
$sysmonExportPath = Join-Path $backupFolder "sysmon.evtx"

# Sysmon���O��evtx�`���ŃG�N�X�|�[�g (�G���[������ǉ�)
try {
    wevtutil epl Microsoft-Windows-Sysmon/Operational $sysmonExportPath
}
catch {
    Write-Error -Message "Sysmon���O�̃G�N�X�|�[�g�Ɏ��s���܂����B$($_.Exception.Message)"
    Exit 1
}

# Windows�C�x���g���O�̃G�N�X�|�[�g�t�@�C���p�X
$systemExportPath = Join-Path $backupFolder "system.evtx"
$applicationExportPath = Join-Path $backupFolder "application.evtx"
$securityExportPath = Join-Path $backupFolder "security.evtx"

# Windows�C�x���g���O�̃G�N�X�|�[�g
try {
    wevtutil epl System $systemExportPath
    wevtutil epl Application $applicationExportPath
    wevtutil epl Security $securityExportPath
}
catch {
    Write-Error -Message "Windows�C�x���g���O�̃G�N�X�|�[�g�Ɏ��s���܂����B$($_.Exception.Message)"
    Exit 1
}

Write-Host "���ׂẴ��O������ɃG�N�X�|�[�g����܂���: $backupFolder"
