#Requires -Version 7.6

<#
.SYNOPSIS
  Builds the VS Code extension and Vue webview in parallel, then composes final-dist.
.DESCRIPTION
  Runs `pnpm build` in babadeluxe-webview and babadeluxe-vscode concurrently,
  then assembles their outputs into babadeluxe-vscode/final-dist.
  Exits with code 1 if either build fails.
.PARAMETER Production
  Reserved for future production-specific build flags (e.g. minification, source maps).
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

[string] $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
[string] $finalDist = Join-Path $root 'babadeluxe-vscode/final-dist'

Write-Host ''
Write-Host 'Building BabaDeluxe VS Code extension (+ Vue webview) and composing it...' -ForegroundColor Green

Write-Host 'Cleaning dist folder...'
Remove-Item -Path $finalDist -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Building webview and extension in parallel...'
$jobs = @(
  Start-ThreadJob -ScriptBlock {
    Set-Location (Join-Path $using:root 'babadeluxe-webview')
    $output = pnpm build 2>&1 | Out-String
    [PSCustomObject]@{ Name = 'webview'; ExitCode = $LASTEXITCODE; Output = $output }
  }
  Start-ThreadJob -ScriptBlock {
    Set-Location (Join-Path $using:root 'babadeluxe-vscode')
    $output = pnpm build 2>&1 | Out-String
    [PSCustomObject]@{ Name = 'extension'; ExitCode = $LASTEXITCODE; Output = $output }
  }
)

[PSCustomObject[]] $results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$failedBuilds = $results | Where-Object { $_.ExitCode -ne 0 }
if ($failedBuilds) {
  foreach ($result in $failedBuilds) {
    Write-Host "[$($result.Name)] build failed (exit $($result.ExitCode)):" -ForegroundColor Red
    Write-Host $result.Output
  }
  exit 1
}

# Compose final dist folder
Write-Host 'Composing final distribution...' -ForegroundColor Green

if (Test-Path $finalDist) { Remove-Item $finalDist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $finalDist | Out-Null

Write-Host 'Copying extension files...'
Copy-Item "babadeluxe-vscode/dist/*" $finalDist -Recurse

Write-Host 'Copying webview files...'
Copy-Item "babadeluxe-webview/dist/*" $finalDist -Recurse

Write-Host 'Build and composition complete!' -ForegroundColor Green
Write-Host ">:) Ready to publish from: $finalDist" -ForegroundColor Yellow
