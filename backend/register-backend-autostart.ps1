$ErrorActionPreference = 'Stop'

$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartScript = Join-Path $BackendDir 'start-backend.ps1'
$PythonPath = Join-Path $BackendDir '.venv\Scripts\python.exe'
$TaskName = 'ShiguangLossBackend'
$TaskArguments = '-m uvicorn app.main:app --host 0.0.0.0 --port 8000'

$action = New-ScheduledTaskAction -Execute $PythonPath -Argument $TaskArguments -WorkingDirectory $BackendDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Start the Shiguang Loss backend when the current Windows user logs in.' `
    -Force | Out-Null

# Start the task immediately as well, so the current session is usable now.
Start-ScheduledTask -TaskName $TaskName

Write-Output "Registered scheduled task: $TaskName"
Write-Output "Manual start script: $StartScript"
Write-Output "Task executable: $PythonPath"
