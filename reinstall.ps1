#Requires -Version 5.1

<#
.SYNOPSIS
  Reinstalls pnpm dependencies across all babadeluxe workspace packages.
.DESCRIPTION
  Iterates each workspace package directory and runs `pnpm i` in sequence.
  Exits with code 1 immediately on the first package failure.
#>

$ErrorActionPreference = 'Stop'

[string[]] $directories = @(
  'babadeluxe-shared',
  'babadeluxe-webview',
  'babadeluxe-backend',
  'babadeluxe-xo-config',
  'babadeluxe-vscode'
)

[string] $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

foreach ($dir in $directories) {
  [string] $dirPath = Join-Path -Path $root -ChildPath $dir
  Write-Host "  pnpm i -> $dir" -ForegroundColor Cyan
  & pnpm i --dir $dirPath
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed in $dir" -ForegroundColor Red
    exit 1
  }
}

Write-Host 'Successfully reinstalled all dependencies. >:3' -ForegroundColor Green
