param(
    [string[]]$Directories = @('babadeluxe-vscode', 'babadeluxe-backend', 'babadeluxe-shared')
)

Set-Location -Path $PSScriptRoot

$packages = @(
    '@babadeluxe/xo-config@latest',
    '@typescript-eslint/eslint-plugin@^8.43.0',
    '@typescript-eslint/parser@^8.43.0',
    'xo@^1.2.2'
)

$scriptBlock = {
    param($Directory, $PackageList)
    
    Set-Location -Path $Directory
    
    Write-Host "[$Directory] Uninstalling packages..." -ForegroundColor Yellow
    npm uninstall $PackageList
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[$Directory] Uninstall failed"
        return $false
    }
    
    Write-Host "[$Directory] Installing packages as dev dependencies..." -ForegroundColor Cyan
    npm i -D $PackageList
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[$Directory] Install failed"
        return $false
    }
    
    Write-Host "[$Directory] Successfully reinstalled packages" -ForegroundColor Green
    return $true
}

$jobs = foreach ($directory in $Directories) {
    $directoryPath = Join-Path -Path $PWD -ChildPath $directory
    
    if (-not (Test-Path -Path $directoryPath)) {
        Write-Warning "Directory not found: $directoryPath"
        continue
    }
    
    Start-Job -ScriptBlock $scriptBlock -ArgumentList $directoryPath, $packages
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

Write-Host "Successfully updated packages in all target directories. >:3" -ForegroundColor Green
exit 0
