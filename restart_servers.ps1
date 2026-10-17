$ErrorActionPreference = "Stop"

$BackendPort = 8080
$FrontendPort = 8081
$RepositoryRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendPath = Join-Path $RepositoryRoot "backend"
$FrontendPath = Join-Path $RepositoryRoot "frontend"

foreach ($command in @("python", "flutter")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found on PATH."
    }
}

foreach ($path in @($BackendPath, $FrontendPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Expected project directory was not found: $path"
    }
}

foreach ($port in @($BackendPort, $FrontendPort)) {
    $processIds = @(
        Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
    )

    foreach ($listenerId in $processIds) {
        $process = Get-Process -Id $listenerId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }

        Write-Host "Stopping $($process.ProcessName) (PID $listenerId) using port $port..."
        try {
            Stop-Process -Id $listenerId -Force -ErrorAction Stop
        }
        catch {
            throw "Could not stop PID $listenerId using port $port. Run this script with sufficient permissions. $($_.Exception.Message)"
        }
    }

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $remainingListeners = @(
            Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
        )
        if ($remainingListeners.Count -eq 0) {
            break
        }

        Start-Sleep -Milliseconds 250
    }

    if ($remainingListeners.Count -gt 0) {
        throw "Port $port is still in use after stopping its listener. Check permissions and retry."
    }
}

Start-Process -FilePath "powershell.exe" `
    -WorkingDirectory $BackendPath `
    -ArgumentList @(
        "-NoExit",
        "-Command",
        "python -m flask run --host=127.0.0.1 --port=$BackendPort"
    )

Start-Process -FilePath "powershell.exe" `
    -WorkingDirectory $FrontendPath `
    -ArgumentList @(
        "-NoExit",
        "-Command",
        "flutter run -d web-server --web-hostname 127.0.0.1 --web-port $FrontendPort --dart-define=CODE_EXEC_ENDPOINT=http://127.0.0.1:$BackendPort/execute"
    )

Write-Host "Backend:  http://127.0.0.1:$BackendPort"
Write-Host "Frontend: http://127.0.0.1:$FrontendPort"
