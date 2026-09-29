param(
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonPath = Join-Path $BackendDir '.venv\Scripts\python.exe'
$LogDir = Join-Path $BackendDir 'logs'
$StdOutLog = Join-Path $LogDir 'backend.out.log'
$StdErrLog = Join-Path $LogDir 'backend.err.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# Do not start a second copy when the service is already listening.
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    exit 0
}

if (-not (Test-Path -LiteralPath $PythonPath)) {
    "[$(Get-Date -Format s)] Python environment not found: $PythonPath" | Add-Content -LiteralPath $StdErrLog
    exit 1
}

$arguments = @(
    '-m', 'uvicorn', 'app.main:app',
    '--host', '0.0.0.0',
    '--port', $Port
)

Start-Process `
    -FilePath $PythonPath `
    -ArgumentList $arguments `
    -WorkingDirectory $BackendDir `
    -RedirectStandardOutput $StdOutLog `
    -RedirectStandardError $StdErrLog `
    -WindowStyle Hidden | Out-Null
