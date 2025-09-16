#Requires -Version 5.1


function Find-DirectoriesWithBabadeluxePackages {
    param(
        [string]$RootPath = $PSScriptRoot
    )
    
    $results = @()

    Get-ChildItem -Path $RootPath -Directory | ForEach-Object {
        $packageJsonPath = Join-Path $_.FullName 'package.json'
        if (Test-Path $packageJsonPath) {
            try {
                $packageInfo = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
                $results += [PSCustomObject]@{
                    Path         = $_.FullName
                    RelativePath = Resolve-Path $_.FullName -Relative
                    PackageName  = $packageInfo.name
                }
            }
            catch {
                Write-Warning "Failed to parse package.json at: $packageJsonPath"
            }
        }
    }

    return $results
}

function Show-DirectorySelectionMenu {
    param(
        [PSCustomObject[]]$Directories
    )
    
    Write-Host "`nFound directories with @babadeluxe/ packages:" -ForegroundColor Cyan
    Write-Host ("`n" + "=" * 60) -ForegroundColor Gray
    
    for ($index = 0; $index -lt $Directories.Count; $index++) {
        $directory = $Directories[$index]
        Write-Host "$($index + 1): " -NoNewline -ForegroundColor Yellow
        Write-Host "$($directory.RelativePath)" -ForegroundColor White
        Write-Host "   Packages: " -NoNewline -ForegroundColor Gray
        Write-Host ($directory.BabadeluxePackages -join ', ') -ForegroundColor Green
    }
    
    Write-Host ("`n" + "=" * 60) -ForegroundColor Gray
    
    do {
        $selection = Read-Host "`nEnter directory numbers (comma-separated, e.g., 1,3,5) or 'all' for all directories"
        
        if ($selection.ToLower() -eq 'all') {
            return $Directories
        }
        
        try {
            $selectedIndices = $selection -split ',' | ForEach-Object { 
                $trimmed = $_.Trim()
                if ($trimmed -match '^\d+$') {
                    $number = [int]$trimmed
                    if ($number -ge 1 -and $number -le $Directories.Count) {
                        $number - 1
                    }
                    else {
                        throw "Number $number is out of range"
                    }
                }
                else {
                    throw "Invalid input: $trimmed"
                }
            }
            
            return $Directories[$selectedIndices]
        }
        catch {
            Write-Host "Invalid selection. Please enter valid numbers between 1 and $($Directories.Count), separated by commas." -ForegroundColor Red
        }
    } while ($true)
}


function Invoke-CommandInDirectories {
    param(
        [PSCustomObject[]]$Directories,
        [string]$Command
    )
    
    Write-Host "`nExecuting command in $($Directories.Count) director$(if($Directories.Count -ne 1){'ies'} else {'y'})..." -ForegroundColor Cyan
    Write-Host "Command: " -NoNewline -ForegroundColor Gray
    Write-Host "$Command" -ForegroundColor White
    
    $processes = @()
    
    foreach ($directory in $Directories) {
        Write-Host "Starting: " -NoNewline -ForegroundColor Gray
        Write-Host "$($directory.RelativePath)" -ForegroundColor White
        
        $processInfo = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList "/c", "cd /d `"$($directory.Path)`" && $Command" `
            -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\output_$($directory.RelativePath -replace '[\\/:*?""<>|]', '_').txt" `
            -RedirectStandardError "$env:TEMP\error_$($directory.RelativePath -replace '[\\/:*?""<>|]', '_').txt"
            
        $processes += [PSCustomObject]@{
            Process    = $processInfo
            Directory  = $directory
            OutputFile = "$env:TEMP\output_$($directory.RelativePath -replace '[\\/:*?""<>|]', '_').txt"
            ErrorFile  = "$env:TEMP\error_$($directory.RelativePath -replace '[\\/:*?""<>|]', '_').txt"
        }
    }
    
    Write-Host "`nWaiting for all processes to complete..." -ForegroundColor Yellow
    
    $processes | ForEach-Object {
        $_.Process | Wait-Process
    }
    
    foreach ($proc in $processes) {
        Write-Host "`n[$($proc.Directory.RelativePath)] Output:" -ForegroundColor Cyan
        
        $hasErrors = $false
        $outputContent = ""
        $errorContent = ""
        
        if (Test-Path $proc.OutputFile) {
            $outputContent = Get-Content $proc.OutputFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($outputContent)) {
                Write-Host $outputContent -ForegroundColor White
            }
            Remove-Item $proc.OutputFile -Force -ErrorAction SilentlyContinue
        }
        
        if (Test-Path $proc.ErrorFile) {
            $errorContent = Get-Content $proc.ErrorFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($errorContent)) {
                Write-Host "[$($proc.Directory.RelativePath)] Errors:" -ForegroundColor Red
                Write-Host $errorContent -ForegroundColor Red
                $hasErrors = $true
            }
            Remove-Item $proc.ErrorFile -Force -ErrorAction SilentlyContinue
        }
        
        $exitCode = $proc.Process.ExitCode
        $processSucceeded = $false
        
        if ($null -eq $exitCode -or $exitCode -eq "") {
            $processSucceeded = -not $hasErrors -and $proc.Process.HasExited
            $displayExitCode = if ($processSucceeded) { "0 (inferred)" } else { "unknown" }
        }
        else {
            $processSucceeded = $exitCode -eq 0
            $displayExitCode = $exitCode
        }
        
        if ($processSucceeded) {
            Write-Host "[$($proc.Directory.RelativePath)] Completed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "[$($proc.Directory.RelativePath)] Failed with exit code: $displayExitCode" -ForegroundColor Red
        }
        
        $proc | Add-Member -NotePropertyName "ProcessSucceeded" -NotePropertyValue $processSucceeded -Force
    }
    
    $failedProcesses = $processes | Where-Object { -not $_.ProcessSucceeded }
    
    if ($failedProcesses.Count -gt 0) {
        Write-Host "`nFailed operations:" -ForegroundColor Red
        $failedProcesses | ForEach-Object {
            $exitCode = $_.Process.ExitCode
            $displayExitCode = if ($null -eq $exitCode -or $exitCode -eq "") { "unknown" } else { $exitCode }
            Write-Host "  - $($_.Directory.RelativePath) (Exit code: $displayExitCode)" -ForegroundColor Red
        }
        Write-Host "`n$($failedProcesses.Count) operation(s) failed out of $($processes.Count) total." -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "`nAll operations completed successfully! >:3" -ForegroundColor Green
    }
}


function Start-BabadeluxeMonorepoUtility {
    Write-Host "Babadeluxe Monorepo-like Utility" -ForegroundColor Magenta
    Write-Host "=============================" -ForegroundColor Magenta
    Write-Host "Supports command chaining like: del /s /q node_modules && npm i" -ForegroundColor Gray
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    
    $command = Read-Host "`nEnter command to execute"
    
    if ([string]::IsNullOrWhiteSpace($command)) {
        Write-Host "No command provided. Exiting." -ForegroundColor Red
        return
    }
    
    Write-Host "`nScanning for directories with @babadeluxe/ packages..." -ForegroundColor Cyan
    $directories = Find-DirectoriesWithBabadeluxePackages
    
    if ($directories.Count -eq 0) {
        Write-Host "No directories found containing @babadeluxe/ packages." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($directories.Count) director$(if($directories.Count -ne 1){'ies'} else {'y'}) with @babadeluxe/ packages." -ForegroundColor Green
    
    do {
        $scope = Read-Host "`nExecute on [A]ll directories or [S]pecific directories? (default: All)"
        $scope = if ([string]::IsNullOrWhiteSpace($scope)) { 'A' } else { $scope.ToUpper() }
    } while ($scope -notin @('A', 'ALL', 'S', 'SPECIFIC'))
    
    if ($scope -in @('S', 'SPECIFIC')) {
        $selectedDirectories = Show-DirectorySelectionMenu -Directories $directories
    }
    else {
        $selectedDirectories = $directories
        Write-Host "`nSelected all $($directories.Count) directories." -ForegroundColor Green
    }
    
    Invoke-CommandInDirectories -Directories $selectedDirectories -Command $command
}


Set-Location $PSScriptRoot
Start-BabadeluxeMonorepoUtility
