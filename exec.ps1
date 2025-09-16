#Requires -Version 5.1

function Find-DirectoriesWithBabadeluxePackages {
    param(
        [string]$RootPath = $PSScriptRoot,
        [string]$PackagePrefix = '@babadeluxe/'
    )
    
    $matchingDirectories = @()
    
    Get-ChildItem -Path $RootPath -Recurse -Filter 'package.json' | ForEach-Object {
        try {
            $packageContent = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
            $allDependencies = @{}
            
            if ($packageContent.dependencies) {
                $packageContent.dependencies.PSObject.Properties | ForEach-Object { 
                    $allDependencies[$_.Name] = $_.Value 
                }
            }
            
            if ($packageContent.devDependencies) {
                $packageContent.devDependencies.PSObject.Properties | ForEach-Object { 
                    $allDependencies[$_.Name] = $_.Value 
                }
            }
            
            $hasBabadeluxePackage = $allDependencies.Keys | Where-Object { $_.StartsWith($PackagePrefix) }
            
            if ($hasBabadeluxePackage) {
                $matchingDirectories += [PSCustomObject]@{
                    Path               = $_.Directory.FullName
                    RelativePath       = Resolve-Path -Path $_.Directory.FullName -Relative
                    BabadeluxePackages = $hasBabadeluxePackage
                }
            }
        }
        catch {
            Write-Warning "Failed to parse package.json at: $($_.FullName)"
        }
    }
    
    return $matchingDirectories
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
        
        # Use cmd.exe directly to handle && properly
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
    
    # Display output and errors
    foreach ($proc in $processes) {
        Write-Host "`n[$($proc.Directory.RelativePath)] Output:" -ForegroundColor Cyan
        
        if (Test-Path $proc.OutputFile) {
            $output = Get-Content $proc.OutputFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($output)) {
                Write-Host $output -ForegroundColor White
            }
            Remove-Item $proc.OutputFile -Force -ErrorAction SilentlyContinue
        }
        
        if (Test-Path $proc.ErrorFile) {
            $errors = Get-Content $proc.ErrorFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($errors)) {
                Write-Host "[$($proc.Directory.RelativePath)] Errors:" -ForegroundColor Red
                Write-Host $errors -ForegroundColor Red
            }
            Remove-Item $proc.ErrorFile -Force -ErrorAction SilentlyContinue
        }
        
        if ($proc.Process.ExitCode -eq 0) {
            Write-Host "[$($proc.Directory.RelativePath)] Completed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "[$($proc.Directory.RelativePath)] Failed with exit code: $($proc.Process.ExitCode)" -ForegroundColor Red
        }
    }
    
    $failedProcesses = $processes | Where-Object { $_.Process.ExitCode -ne 0 }
    
    if ($failedProcesses.Count -gt 0) {
        Write-Host "`nFailed operations:" -ForegroundColor Red
        $failedProcesses | ForEach-Object {
            Write-Host "  - $($_.Directory.RelativePath) (Exit code: $($_.Process.ExitCode))" -ForegroundColor Red
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
