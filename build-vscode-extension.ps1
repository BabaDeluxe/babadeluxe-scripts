#!/usr/bin/env pwsh

param(
    [switch]$Production
)

chcp 65001 | Out-Null
Write-Host ""

Write-Host "🚀 Building BabaDeluxe VS Code extension (+ Vue webview) and composing it..." -ForegroundColor Green

Write-Host "🧹 Cleaning dist folder..."
Remove-Item -Path "babadeluxe-vscode/final-dist" -Recurse -Force -ErrorAction SilentlyContinue

# Parallel: Build webview + extension
Write-Host "🎨🔧 Building webview and extension in parallel..."
$jobs = @()

$jobs += Start-Job -ScriptBlock {
    Set-Location babadeluxe-webview
    npm run build
    return $LASTEXITCODE
}

$jobs += Start-Job -ScriptBlock {
    Set-Location babadeluxe-vscode
    npm run build
    return $LASTEXITCODE
}

# Wait for parallel builds
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

if ($results -contains 1) {
    Write-Error "Build failed"
    exit 1
}

# Compose final dist folder
Write-Host "📂 Composing final distribution..." -ForegroundColor Green
$finalDist = "babadeluxe-vscode/final-dist"

# Clean and create final-dist
if (Test-Path $finalDist) { Remove-Item $finalDist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $finalDist

# Copy extension build (the main extension files)
Write-Host "🔧 Copying extension files..."
Copy-Item "babadeluxe-vscode/dist/*" $finalDist -Recurse

# Copy extension build (the main extension files)
Write-Host "🔧 Copying webview files..."
Copy-Item "babadeluxe-webview/dist/*" $finalDist -Recurse

Write-Host "✅ Build and composition complete!" -ForegroundColor Green
Write-Host "📦 Ready to publish from: $finalDist" -ForegroundColor Yellow
