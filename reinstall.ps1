$directories = @('babadeluxe-shared', 'babadeluxe-webview', 'babadeluxe-backend', 'babadeluxe-xo-config', 'babadeluxe-vscode')

Set-Location $PSScriptRoot

$removeProcesses = foreach ($dir in $directories) {
    Start-Process bash -ArgumentList "-c", "cd '$dir' && rm -rf node_modules" -NoNewWindow -PassThru
}

Wait-Process -Id $removeProcesses.Id

$installProcesses = foreach ($dir in $directories) {
    Start-Process powershell -ArgumentList "-Command", "cd '$dir'; npm i" -NoNewWindow -PassThru
}

Wait-Process -Id $installProcesses.Id

$failed = ($removeProcesses + $installProcesses) | Where-Object { $_.ExitCode -ne 0 }

if ($failed.Count -gt 0) {
    Write-Host "At least one operation failed." -ForegroundColor Red
    exit 1
}

Write-Host "Successfully nuked node_modules and reinstalled all dependencies. >:3" -ForegroundColor Green
