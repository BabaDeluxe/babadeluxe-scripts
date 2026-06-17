#Requires -Version 7.6

<#
.SYNOPSIS
  Builds the VS Code extension and Vue webview in parallel, then composes the final dist.
.DESCRIPTION
  Runs `pnpm build` in babadeluxe-webview and babadeluxe-vscode concurrently,
  then copies the webview output into the extension's dist/webview folder.
  Exits with code 1 if either build fails.
.PARAMETER Production
  Reserved for future production-specific build flags (e.g. minification, source maps).
#>

[CmdletBinding()]
param(
    [switch]$Production
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Root paths
[string]$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
[string]$webviewPath = Join-Path $root 'babadeluxe-webview'
[string]$vscodePath   = Join-Path $root 'babadeluxe-vscode'
[string]$finalDist    = Join-Path $vscodePath 'dist'   # extension's dist folder
[string]$webviewTarget = Join-Path $finalDist 'webview'

Write-Host ''
Write-Host 'Building BabaDeluxe VS Code extension (+ Vue webview) and composing it...' -ForegroundColor Green

# Validate required directories
if (-not (Test-Path $webviewPath)) {
    Write-Error "Webview project directory not found: $webviewPath"
    exit 1
}
if (-not (Test-Path $vscodePath)) {
    Write-Error "Extension project directory not found: $vscodePath"
    exit 1
}

# Clean extension dist folder (ensure fresh start)
Write-Host 'Cleaning extension dist folder...' -ForegroundColor Yellow
if (Test-Path $finalDist) {
    Remove-Item -Path $finalDist -Recurse -Force
}

# Build webview and extension in parallel
Write-Host 'Building webview and extension in parallel...' -ForegroundColor Yellow
$jobs = @(
    Start-ThreadJob -ScriptBlock {
        param($path)
        Set-Location $path
        $output = pnpm build 2>&1 | Out-String
        [PSCustomObject]@{
            Name     = 'webview'
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    } -ArgumentList $webviewPath

    Start-ThreadJob -ScriptBlock {
        param($path)
        Set-Location $path
        $output = pnpm build 2>&1 | Out-String
        [PSCustomObject]@{
            Name     = 'extension'
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    } -ArgumentList $vscodePath
)

[PSCustomObject[]]$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

# Check for build failures
$failedBuilds = $results | Where-Object { $_.ExitCode -ne 0 }
if ($failedBuilds) {
    foreach ($result in $failedBuilds) {
        Write-Host "[$($result.Name)] build failed (exit $($result.ExitCode)):" -ForegroundColor Red
        Write-Host $result.Output
    }
    exit 1
}

# Verify that extension dist was created
if (-not (Test-Path $finalDist)) {
    Write-Error "Extension dist folder not created after build."
    exit 1
}

# Copy webview files into extension dist/webview
Write-Host 'Copying webview files...' -ForegroundColor Yellow
$webviewSource = Join-Path $webviewPath 'dist'
if (-not (Test-Path $webviewSource)) {
    Write-Error "Webview dist folder not found: $webviewSource"
    exit 1
}

if (-not (Test-Path $webviewTarget)) {
    New-Item -ItemType Directory -Force -Path $webviewTarget | Out-Null
}
Copy-Item -Path "$webviewSource\*" -Destination $webviewTarget -Recurse -Force

# Verify final structure
Write-Host 'Verifying build output...' -ForegroundColor Yellow
$extensionJs = Join-Path $finalDist 'extension.js'
$webviewIndex = Join-Path $webviewTarget 'index.html'

if (-not (Test-Path $extensionJs)) {
    Write-Error "Extension build incomplete: extension.js not found."
    exit 1
}
if (-not (Test-Path $webviewIndex)) {
    Write-Error "Webview copy incomplete: index.html not found."
    exit 1
}

Write-Host ''
Write-Host '✓ Build and composition complete!' -ForegroundColor Green
Write-Host "  Extension: $extensionJs" -ForegroundColor Cyan
Write-Host "  Webview:   $webviewTarget" -ForegroundColor Cyan
Write-Host ''
Write-Host "Ready to debug!" -ForegroundColor Green
Write-Host "IMPORTANT: Restart your debugging session (stop and F5 again) to load the new code." -ForegroundColor Yellow