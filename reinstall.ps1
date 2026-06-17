#Requires -Version 5.1

<#
.SYNOPSIS
  Reinstalls pnpm dependencies across all babadeluxe workspace packages.
.DESCRIPTION
  Iterates each workspace package directory, removes node_modules (with admin elevation if required),
  and runs `pnpm i` in sequence. Exits with code 1 immediately on the first package failure.
#>

$ErrorActionPreference = 'Stop'

# List of workspace package directories
[string[]]$directories = @(
    'babadeluxe-shared',
    'babadeluxe-webview',
    'babadeluxe-backend',
    'babadeluxe-xo-config',
    'babadeluxe-vscode'
)

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# --- Admin elevation (from stash) ---
# Elevate only once if needed (handles cases where removing node_modules requires admin rights)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    # Restart the script with elevated privileges
    $cmd = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process pwsh.exe -Verb RunAs -ArgumentList $cmd
    exit
}
Write-Host "Running as Administrator" -ForegroundColor Green

# --- Remove node_modules (from stash) ---
Write-Host "`n[1/2] Removing node_modules..." -ForegroundColor Yellow
foreach ($dir in $directories) {
    $nodeModulesPath = Join-Path $root "$dir\node_modules"
    if (Test-Path $nodeModulesPath) {
        Write-Host "  -> $dir" -ForegroundColor DarkGray
        try {
            Remove-Item -Path $nodeModulesPath -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host "  ! Failed to remove $nodeModulesPath : $($_.Exception.Message)" -ForegroundColor Red
            # Continue, but we might fail later; we'll just let the install proceed
        }
    }
}
Write-Host "  node_modules removed (where present)`n" -ForegroundColor Green

# --- Install dependencies (using pnpm, like upstream) ---
Write-Host "[2/2] Installing dependencies with pnpm..." -ForegroundColor Yellow
foreach ($dir in $directories) {
    $dirPath = Join-Path $root $dir
    Write-Host "`n  pnpm i -> $dir" -ForegroundColor Cyan
    & pnpm i --dir $dirPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed in $dir" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nSuccessfully reinstalled all dependencies. >:3" -ForegroundColor Green