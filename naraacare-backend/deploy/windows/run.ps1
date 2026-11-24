<#
Runs one NaraaCare service on this Windows PC and restarts it if it stops.
Started by the scheduled tasks that install-tasks.ps1 creates; you can also run it by hand.

  api     uvicorn on 127.0.0.1:8000 (Cloudflare Tunnel is the only way in from the internet)
  worker  tools/dev_worker.py (report / export / support jobs; no Redis needed)

Logs: naraacare-backend\var\logs\<service>.out.log and <service>.err.log
(the previous run's logs are kept as .1).
See setup/hosting-windows-pc.md.
#>
param(
    [Parameter(Mandatory)][ValidateSet('api', 'worker')][string]$Service,
    [string]$Uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
)

$ErrorActionPreference = 'Stop'
$backend = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dbEnvFile = Join-Path $backend '..\naraacare-database\.env'
$logDir = Join-Path $backend 'var\logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

if (-not $Uv -or -not (Test-Path $Uv)) { throw 'uv.exe not found; pass -Uv <full path>' }

function Read-EnvFile([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $values[$Matches[1]] = $Matches[2].Trim().Trim('"') }
    }
    $values
}

switch ($Service) {
    'api' {
        $arguments = @(
            'run', '--no-sync', 'python', '-m', 'uvicorn', 'app.main:create_app', '--factory',
            '--host', '127.0.0.1', '--port', '8000',
            '--no-server-header', '--no-access-log', '--ws-max-size', '8192',
            '--proxy-headers', '--forwarded-allow-ips', '127.0.0.1'
        )
    }
    'worker' {
        # The worker logs in as app_worker (the ops routines are granted to that role only).
        $db = Read-EnvFile $dbEnvFile
        $password = [uri]::EscapeDataString($db['FLYWAY_PLACEHOLDERS_APP_WORKER_PASSWORD'])
        $env:DATABASE_URL = "postgresql+asyncpg://app_worker:$password@localhost:5432/naraacare"
        $arguments = @('run', '--no-sync', 'python', 'tools/dev_worker.py')
    }
}

$out = Join-Path $logDir "$Service.out.log"
$err = Join-Path $logDir "$Service.err.log"

while ($true) {
    foreach ($log in $out, $err) {
        if (Test-Path $log) { Move-Item -Force $log "$log.1" }
    }
    $process = Start-Process -FilePath $Uv -ArgumentList $arguments -WorkingDirectory $backend `
        -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru -Wait
    Add-Content (Join-Path $logDir 'restarts.log') "$(Get-Date -Format s) $Service exited with code $($process.ExitCode); restarting in 10 s"
    Start-Sleep -Seconds 10
}
