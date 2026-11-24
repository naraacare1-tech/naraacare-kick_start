<#
Nightly backup: the naraacare database (pg_dump custom format) and the uploaded files folder.
Keeps the last 14 days. Copy the backup folder off this PC regularly (cloud drive, USB disk):
a backup on the same disk does not survive a disk failure.

Restore a dump:  pg_restore -U postgres -d naraacare --clean --if-exists <file>.dump
See setup/hosting-windows-pc.md.
#>
param(
    [string]$BackupDir = 'D:\NaraaCare-backups',
    [int]$KeepDays = 14
)

$ErrorActionPreference = 'Stop'
$backend = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dbEnvFile = Join-Path $backend '..\naraacare-database\.env'
$pgDump = 'C:\Program Files\PostgreSQL\18\bin\pg_dump.exe'
New-Item -ItemType Directory -Force $BackupDir | Out-Null

$db = @{}
foreach ($line in Get-Content $dbEnvFile) {
    if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $db[$Matches[1]] = $Matches[2].Trim().Trim('"') }
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$dump = Join-Path $BackupDir "naraacare_$stamp.dump"
$env:PGPASSWORD = $db['POSTGRES_PASSWORD']
& $pgDump -h localhost -p 5432 -U postgres -F c -f $dump naraacare
$code = $LASTEXITCODE
Remove-Item Env:PGPASSWORD
if ($code -ne 0) { throw "pg_dump failed with exit code $code" }

$storage = Join-Path $backend 'var\storage'
if (Test-Path $storage) {
    Compress-Archive -Path (Join-Path $storage '*') -DestinationPath (Join-Path $BackupDir "storage_$stamp.zip") -Force
}

Get-ChildItem $BackupDir -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } | Remove-Item
Add-Content (Join-Path $BackupDir 'backup.log') "$(Get-Date -Format s) ok $dump"
