<#
Makes this PC run the NaraaCare backend on its own: run once in an ADMIN PowerShell.

  - NaraaCare-API     starts at boot, runs run.ps1 -Service api, restarts on failure
  - NaraaCare-Worker  starts at boot, runs run.ps1 -Service worker
  - NaraaCare-Backup  every night at 02:30, runs backup-db.ps1
  - Turns off sleep and hibernate while plugged in

The tasks run as your Windows user whether or not you are signed in (no password stored).
Remove everything again with:  .\install-tasks.ps1 -Remove
See setup/hosting-windows-pc.md.
#>
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$principalCheck = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this in PowerShell opened with "Run as administrator".'
}

$names = 'NaraaCare-API', 'NaraaCare-Worker', 'NaraaCare-Backup'
foreach ($name in $names) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
}
if ($Remove) { Write-Output 'NaraaCare tasks removed.'; return }

$uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
if (-not $uv) { throw 'uv.exe not found on PATH.' }
$run = Join-Path $PSScriptRoot 'run.ps1'
$backup = Join-Path $PSScriptRoot 'backup-db.ps1'
$user = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited

function New-PsAction([string]$Arguments) {
    New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass $Arguments"
}

$serviceSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$boot = New-ScheduledTaskTrigger -AtStartup

Register-ScheduledTask -TaskName 'NaraaCare-API' -Principal $principal -Trigger $boot -Settings $serviceSettings `
    -Action (New-PsAction "-File `"$run`" -Service api -Uv `"$uv`"") | Out-Null
Register-ScheduledTask -TaskName 'NaraaCare-Worker' -Principal $principal -Trigger $boot -Settings $serviceSettings `
    -Action (New-PsAction "-File `"$run`" -Service worker -Uv `"$uv`"") | Out-Null

$backupSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'NaraaCare-Backup' -Principal $principal -Settings $backupSettings `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '02:30') `
    -Action (New-PsAction "-File `"$backup`"") | Out-Null

powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Start-ScheduledTask -TaskName 'NaraaCare-API'
Start-ScheduledTask -TaskName 'NaraaCare-Worker'
Write-Output 'Installed. Check: curl http://localhost:8000/api/v1/health/ready'
