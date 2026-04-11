#Requires -Version 7.6

<#
.SYNOPSIS
  Runs a shell command in parallel across all babadeluxe workspace packages.
.DESCRIPTION
  Scans subdirectories named babadeluxe-* and lets the user select a subset,
  then executes a cmd.exe command in each in parallel with real-time streamed output.
  Supports Windows command chaining (&&, del, etc.).
.PARAMETER FailFast
  When set, kills all remaining processes as soon as any one exits with a non-zero code.
#>

param(
  [switch] $FailFast
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:brand = [pscustomobject]@{
  Name       = 'BabaDeluxe'
  Accent     = 'Magenta'
  AccentDark = 'DarkMagenta'
  Highlight  = 'Cyan'
  Success    = 'Green'
  Failure    = 'Red'
  Warning    = 'Yellow'
  Muted      = 'DarkGray'
}

if (-not ([System.Management.Automation.PSTypeName]'BabaProcessReader').Type) {
  Add-Type @'
using System.Collections.Concurrent;
using System.Diagnostics;

public sealed class BabaProcessReader {
  public readonly ConcurrentQueue<string> OutputQueue = new ConcurrentQueue<string>();
  public readonly ConcurrentQueue<string> ErrorQueue  = new ConcurrentQueue<string>();

  public BabaProcessReader(Process process) {
    process.OutputDataReceived += (s, e) => { if (e.Data != null) OutputQueue.Enqueue(e.Data); };
    process.ErrorDataReceived  += (s, e) => { if (e.Data != null) ErrorQueue.Enqueue(e.Data); };
  }
}
'@
}

function Find-BabadeluxeDirectories {
  param(
    [string] $RootPath = $PSScriptRoot
  )

  $results = [System.Collections.Generic.List[pscustomobject]]::new()

  foreach ($dir in Get-ChildItem -Path $RootPath -Directory | Where-Object { $_.Name -like 'babadeluxe-*' }) {
    [string] $packageJsonPath = Join-Path $dir.FullName 'package.json'
    [string] $packageName = $dir.Name

    if (Test-Path $packageJsonPath) {
      try {
        $packageInfo = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        $nameProp = $packageInfo.PSObject.Properties['name']
        if ($null -ne $nameProp) { $packageName = [string] $nameProp.Value }
      } catch {
        Write-Warning "Failed to parse package.json at: $packageJsonPath"
      }
    }

    $results.Add([pscustomobject]@{
        Path         = $dir.FullName
        RelativePath = Resolve-Path $dir.FullName -Relative
        PackageName  = $packageName
      })
  }

  return $results.ToArray()
}

function Show-DirectorySelectionMenu {
  param(
    [pscustomobject[]] $Directories
  )

  Show-BabaScreen -Title 'Select Directories'
  Write-BabaInfo 'Choose which directories to target.'
  Write-Host ''
  Write-BabaFrame ('=' * 60) $script:brand.AccentDark

  for ([int] $index = 0; $index -lt $Directories.Count; $index++) {
    $directory = $Directories[$index]
    Write-Host "  [$($index + 1)] " -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $directory.RelativePath -ForegroundColor Gray
    Write-Host "       $($directory.PackageName)" -ForegroundColor $script:brand.Muted
  }

  Write-BabaFrame ('=' * 60) $script:brand.AccentDark
  Write-Host ''

  do {
    [string] $selection = Read-Host "Enter numbers (comma-separated, e.g. 1,3,5) or 'all'"

    if ($selection.ToLowerInvariant() -eq 'all') {
      return $Directories
    }

    try {
      [int[]] $selectedIndices = $selection -split ',' | ForEach-Object {
        [string] $trimmed = $_.Trim()
        if ($trimmed -match '^\d+$') {
          [int] $number = [int] $trimmed
          if ($number -ge 1 -and $number -le $Directories.Count) {
            $number - 1
          } else {
            throw "Number $number is out of range (1-$($Directories.Count))."
          }
        } else {
          throw "Invalid input: '$trimmed'."
        }
      }

      return $Directories[$selectedIndices]
    } catch {
      Write-BabaFailure "Invalid selection: $($_.Exception.Message)"
    }
  } while ($true)
}

function Invoke-CommandInDirectories {
  param(
    [pscustomobject[]] $Directories,
    [string]           $Command,
    [switch]           $FailFast
  )

  Show-BabaScreen -Title 'Running'

  [string] $dirWord = if ($Directories.Count -ne 1) { 'directories' } else { 'directory' }
  Write-BabaInfo "Executing in $($Directories.Count) $dirWord..."
  Write-BabaStatus '[>]' $Command $script:brand.Accent

  if ($FailFast) {
    Write-BabaStatus '[!]' 'FailFast enabled — first failure kills all remaining processes.' $script:brand.Warning
  }

  Write-Host ''
  $pending = [System.Collections.Generic.List[pscustomobject]]::new()

  foreach ($directory in $Directories) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = "/c $Command"
    $psi.WorkingDirectory = $directory.Path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true

    $reader = [BabaProcessReader]::new($process)

    [void] $process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    Write-BabaStatus '[+]' $directory.RelativePath $script:brand.Muted

    $pending.Add([pscustomobject]@{
        Process     = $process
        Directory   = $directory
        OutputQueue = $reader.OutputQueue
        ErrorQueue  = $reader.ErrorQueue
        WasKilled   = $false
        ExitCode    = -1
      })
  }

  Write-Host ''
  Write-BabaStatus '[~]' 'Waiting for all processes to complete...' $script:brand.Highlight
  Write-Host ''

  [bool]   $shouldStop = $false
  [string] $line = $null

  do {
    [bool] $anyRunning = $false

    foreach ($proc in $pending) {
      while ($proc.OutputQueue.TryDequeue([ref] $line)) {
        Write-Host "  [$($proc.Directory.RelativePath)] " -NoNewline -ForegroundColor $script:brand.Muted
        Write-Host $line -ForegroundColor Gray
      }
      while ($proc.ErrorQueue.TryDequeue([ref] $line)) {
        Write-Host "  [$($proc.Directory.RelativePath)] " -NoNewline -ForegroundColor $script:brand.Warning
        Write-Host $line -ForegroundColor $script:brand.Warning
      }

      if (-not $proc.Process.HasExited) {
        $anyRunning = $true
      } elseif ($FailFast -and $proc.Process.ExitCode -ne 0 -and -not $shouldStop) {
        $shouldStop = $true
        Write-Host ''
        Write-BabaFailure "[$($proc.Directory.RelativePath)] Failed (exit $($proc.Process.ExitCode)) — killing remaining processes."
        foreach ($other in $pending) {
          if (-not $other.Process.HasExited) {
            $other.Process.Kill()
            $other.WasKilled = $true
          }
        }
      }
    }

    if (-not $shouldStop -and $anyRunning) {
      Start-Sleep -Milliseconds 20
    }
  } while (-not $shouldStop -and $anyRunning)

  # WaitForExit() guarantees all OutputDataReceived/ErrorDataReceived events
  # have fired before the final drain — skipping it drops the last lines.
  foreach ($proc in $pending) {
    $proc.Process.WaitForExit()
    while ($proc.OutputQueue.TryDequeue([ref] $line)) {
      Write-Host "  [$($proc.Directory.RelativePath)] " -NoNewline -ForegroundColor $script:brand.Muted
      Write-Host $line -ForegroundColor Gray
    }
    while ($proc.ErrorQueue.TryDequeue([ref] $line)) {
      Write-Host "  [$($proc.Directory.RelativePath)] " -NoNewline -ForegroundColor $script:brand.Warning
      Write-Host $line -ForegroundColor $script:brand.Warning
    }
    $proc.ExitCode = $proc.Process.ExitCode
    $proc.Process.Dispose()
  }

  Write-Host ''
  Write-BabaFrame ('=' * 60) $script:brand.AccentDark
  [int] $failCount = 0

  foreach ($proc in $pending) {
    if ($proc.WasKilled) {
      Write-BabaStatus '[—]' "$($proc.Directory.RelativePath)  Killed (FailFast)." $script:brand.Muted
    } elseif ($proc.ExitCode -eq 0) {
      Write-BabaSuccess "$($proc.Directory.RelativePath)  exit 0"
    } else {
      Write-BabaFailure "$($proc.Directory.RelativePath)  exit $($proc.ExitCode)"
      $failCount++
    }
  }

  Write-BabaFrame ('=' * 60) $script:brand.AccentDark
  Write-Host ''

  if ($failCount -gt 0 -or $shouldStop) {
    Write-BabaFailure "$failCount of $($pending.Count) operation(s) failed."
    exit 1
  }

  Write-BabaSuccess 'All operations completed successfully! >:3'
}

function Start-BabadeluxeMonorepoUtility {
  param(
    [switch] $FailFast
  )

  Show-BabaScreen -Title 'Monorepo Utility'
  Write-BabaInfo 'Supports command chaining like: del /s /q node_modules && npm i'
  Write-Host "  PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor $script:brand.Muted
  Write-Host ''

  [string] $command = Read-Host 'Enter command to execute'

  if ([string]::IsNullOrWhiteSpace($command)) {
    Write-BabaFailure 'No command provided. Exiting.'
    return
  }

  Write-Host ''
  Write-BabaInfo 'Scanning for babadeluxe- directories...'
  [pscustomobject[]] $directories = Find-BabadeluxeDirectories

  if ($directories.Count -eq 0) {
    Write-BabaStatus '[!]' 'No babadeluxe- directories found.' $script:brand.Warning
    return
  }

  [string] $dirWord = if ($directories.Count -ne 1) { 'directories' } else { 'directory' }
  Write-BabaSuccess "Found $($directories.Count) $dirWord."
  Write-Host ''

  do {
    [string] $scope = Read-Host 'Execute on [A]ll directories or [S]pecific directories? (default: All)'
    $scope = if ([string]::IsNullOrWhiteSpace($scope)) { 'A' } else { $scope.ToUpperInvariant() }
  } while ($scope -notin @('A', 'ALL', 'S', 'SPECIFIC'))

  [pscustomobject[]] $selectedDirectories = if ($scope -in @('S', 'SPECIFIC')) {
    Show-DirectorySelectionMenu -Directories $directories
  } else {
    Write-BabaSuccess "Selected all $($directories.Count) $dirWord."
    $directories
  }

  Invoke-CommandInDirectories -Directories $selectedDirectories -Command $command -FailFast:$FailFast
}

function Show-BabaScreen {
  param(
    [Parameter(Mandatory)]
    [string] $Title
  )

  Clear-Host
  Show-BabaHeader -Title $Title
}

function Show-BabaHeader {
  param(
    [Parameter(Mandatory)]
    [string] $Title
  )

  Write-Host ''
  Write-BabaFrame '╔════════════════════════════════════════════════════════════╗' $script:brand.AccentDark
  Write-BabaFrame '║  BabaDeluxe Monorepo Utility                             ║' $script:brand.Accent
  Write-BabaFrame '║  run once. run everywhere. run babadeluxe.               ║' $script:brand.Highlight
  Write-BabaFrame '╚════════════════════════════════════════════════════════════╝' $script:brand.AccentDark
  Write-Host ''
  Write-Host " $Title " -ForegroundColor Black -BackgroundColor Magenta
  Write-Host ''
}

function Write-BabaFrame {
  param(
    [Parameter(Mandatory)]
    [string] $Text,
    [ConsoleColor] $Color = $script:brand.Accent
  )

  Write-Host $Text -ForegroundColor $Color
}

function Write-BabaInfo {
  param(
    [Parameter(Mandatory)]
    [string] $Text
  )

  Write-BabaStatus '[~]' $Text $script:brand.Highlight
}

function Write-BabaSuccess {
  param(
    [Parameter(Mandatory)]
    [string] $Text
  )

  Write-BabaStatus '[✓]' $Text $script:brand.Success
}

function Write-BabaFailure {
  param(
    [Parameter(Mandatory)]
    [string] $Text
  )

  Write-BabaStatus '[✗]' $Text $script:brand.Failure
}

function Write-BabaStatus {
  param(
    [Parameter(Mandatory)]
    [string] $Prefix,
    [Parameter(Mandatory)]
    [string] $Text,
    [Parameter(Mandatory)]
    [ConsoleColor] $Color
  )

  Write-Host $Prefix -NoNewline -ForegroundColor $Color
  Write-Host " $Text" -ForegroundColor $Color
}

[string] $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $root
Start-BabadeluxeMonorepoUtility -FailFast:$FailFast
