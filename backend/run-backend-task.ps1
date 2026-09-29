$ErrorActionPreference = 'Stop'

$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonPath = Join-Path $BackendDir '.venv\Scripts\python.exe'
$LogDir = Join-Path $BackendDir 'logs'
$StdOutLog = Join-Path $LogDir 'backend.out.log'
$StdErrLog = Join-Path $LogDir 'backend.err.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Set-Location -LiteralPath $BackendDir

if (-not (Test-Path -LiteralPath $PythonPath)) {
    "[$(Get-Date -Format s)] Python environment not found: $PythonPath" | Add-Content -LiteralPath $StdErrLog
    exit 1
}

# The scheduled task owns this foreground process, so Windows keeps the backend
# alive for the whole user session instead of treating it as a child helper.
# PowerShell can surface native stderr as an error record even when Uvicorn is
# healthy, so allow the server's own log stream while it is running.
$ErrorActionPreference = 'Continue'
& $PythonPath -m uvicorn app.main:app --host 0.0.0.0 --port 8000 `
    1>> $StdOutLog `
    2>> $StdErrLog

$exitCode = $LASTEXITCODE
exit $exitCode
