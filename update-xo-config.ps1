param(
    [string[]]$Directories = @('babadeluxe-vscode', 'babadeluxe-backend', 'babadeluxe-shared'),
    [string]$PackageName = '@babadeluxe/xo-config'
)

Set-Location -Path $PSScriptRoot

$scriptBlock = {
    param($Directory, $Package)
    
    Set-Location -Path $Directory
    
    Write-Host "[$Directory] Uninstalling $Package..." -ForegroundColor Yellow
    npm uninstall $Package
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[$Directory] Uninstall failed"
        return $false
    }
    
    Write-Host "[$Directory] Installing $Package as dev dependency..." -ForegroundColor Cyan
    npm i -D "$Package@latest"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[$Directory] Install failed"
        return $false
    }
    
    Write-Host "[$Directory] Successfully reinstalled $Package" -ForegroundColor Green
    return $true
}

$jobs = foreach ($directory in $Directories) {
    $directoryPath = Join-Path -Path $PWD -ChildPath $directory
    
    if (-not (Test-Path -Path $directoryPath)) {
        Write-Warning "Directory not found: $directoryPath"
        continue
    }
    
    Start-Job -ScriptBlock $scriptBlock -ArgumentList $directoryPath, $PackageName
}

if ($jobs.Count -eq 0) {
    Write-Error "No jobs were started"
    exit 1
}

Write-Host "Running reinstall in $($jobs.Count) directories..." -ForegroundColor Magenta
$results = Receive-Job -Job $jobs -Wait

$failedJobs = $results | Where-Object { $_ -eq $false }

Remove-Job -Job $jobs

if ($failedJobs.Count -gt 0) {
    Write-Error "Failed operations: $($failedJobs.Count)/$($jobs.Count)"
    exit 1
}

Write-Host "Successfully updated $PackageName in all target directories. >:3" -ForegroundColor Green
exit 0
