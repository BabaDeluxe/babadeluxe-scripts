Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

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

$script:quit = $false

function Start-BabaDeluxeCli {
  if (-not (Test-GitRepository)) {
    Write-BabaFailure 'This script must be run inside a Git repository.'
    exit 1
  }

  while (-not $script:quit) {
    Show-Menu
    $choice = Read-Host 'Choose an option'

    try {
      Invoke-MenuChoice -Choice $choice
    }
    catch {
      Show-BabaScreen -Title 'Operation Failed'
      Write-BabaFailure $_.Exception.Message
      Pause-Baba
    }
  }

  Show-BabaScreen -Title 'Goodbye'
  Write-BabaSuccess 'BabaDeluxe has released the submodules back into the void.'
}

function Show-Submodules {
  Show-BabaScreen -Title 'Submodule Status'
  Invoke-GitCommand -Arguments @('submodule', 'status', '--recursive')
  Pause-Baba
}

function Show-SubmoduleSummary {
  Show-BabaScreen -Title 'Submodule Summary'
  Invoke-GitCommand -Arguments @('submodule', 'summary')
  Pause-Baba
}

function Run-CommandInSubmodules {
  Show-BabaScreen -Title 'Foreach Runner'
  $command = Read-Host 'Shell command for all submodules'
  Invoke-GitCommand -Arguments @('submodule', 'foreach', '--recursive', $command)
  Pause-Baba
}

function Initialize-Submodules {
  Show-BabaScreen -Title 'Initialize Submodules'
  Invoke-GitCommand -Arguments @('submodule', 'update', '--init', '--recursive')
  Pause-Baba
}

function Update-Submodules {
  Show-BabaScreen -Title 'Update Submodules'
  Invoke-GitCommand -Arguments @('submodule', 'update', '--remote', '--init', '--recursive')
  Pause-Baba
}

function Sync-Submodules {
  Show-BabaScreen -Title 'Sync Submodule URLs'
  Invoke-GitCommand -Arguments @('submodule', 'sync', '--recursive')
  Pause-Baba
}

function Repair-Submodules {
  Show-BabaScreen -Title 'Repair Submodules'
  Invoke-GitCommand -Arguments @('submodule', 'sync', '--recursive')
  Invoke-GitCommand -Arguments @('submodule', 'update', '--init', '--recursive')
  Pause-Baba
}

function Add-Submodule {
  Show-BabaScreen -Title 'Add Submodule'
  $repository = Read-Host 'Repository URL'
  $path = Read-Host 'Path inside superproject'
  $branch = Read-Host 'Branch to track (leave empty to omit)'

  $arguments = @('submodule', 'add')

  if (-not [string]::IsNullOrWhiteSpace($branch)) {
    $arguments += @('-b', $branch)
  }

  $arguments += @($repository, $path)

  Invoke-GitCommand -Arguments $arguments
  Pause-Baba
}

function Remove-Submodule {
  Show-BabaScreen -Title 'Remove Submodule'
  $path = Read-Host 'Submodule path'
  Invoke-GitCommand -Arguments @('submodule', 'deinit', '-f', '--', $path)
  Invoke-GitCommand -Arguments @('rm', '-f', '--', $path)
  Pause-Baba
}

function Set-SubmoduleBranch {
  Show-BabaScreen -Title 'Set Tracked Branch'
  $path = Read-Host 'Submodule path'
  $branch = Read-Host 'Branch name'
  Invoke-GitCommand -Arguments @('submodule', 'set-branch', '-b', $branch, '--', $path)
  Pause-Baba
}

function Set-SubmoduleUrl {
  Show-BabaScreen -Title 'Set Submodule URL'
  $path = Read-Host 'Submodule path'
  $url = Read-Host 'New URL'
  Invoke-GitCommand -Arguments @('submodule', 'set-url', '--', $path, $url)
  Pause-Baba
}

function Show-Menu {
  Show-BabaScreen -Title 'Submodule Manager'

  Write-BabaInfo "Repository root: $((Get-Location).Path)"
  Write-Host ''

  foreach ($item in @(Get-MenuItems)) {
    if ($item.IsGroup) {
      Write-Host $item.Label -ForegroundColor $script:brand.Accent
      continue
    }

    Write-Host ('  [' + $item.Key + '] ') -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $item.Label -ForegroundColor Gray
  }

  Write-Host ''
  Write-Host 'Type the number and press Enter. Type q to quit.' -ForegroundColor DarkGray
  Write-Host ''
}

function Invoke-MenuChoice {
  param(
    [Parameter(Mandatory)]
    [string] $Choice
  )

  switch ($Choice.Trim().ToLowerInvariant()) {
    '1' { Show-Submodules }
    '2' { Show-SubmoduleSummary }
    '3' { Run-CommandInSubmodules }
    '4' { Initialize-Submodules }
    '5' { Update-Submodules }
    '6' { Sync-Submodules }
    '7' { Repair-Submodules }
    '8' { Add-Submodule }
    '9' { Remove-Submodule }
    '10' { Set-SubmoduleBranch }
    '11' { Set-SubmoduleUrl }
    'q' { $script:quit = $true }
    'quit' { $script:quit = $true }
    default {
      Write-BabaFailure "Unknown menu option: $Choice"
      Pause-Baba
    }
  }
}

function Get-MenuItems {
  @(
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Inspect' }
    [pscustomobject]@{ IsGroup = $false; Key = '1'; Label = 'Show submodules' }
    [pscustomobject]@{ IsGroup = $false; Key = '2'; Label = 'Show submodule summary' }
    [pscustomobject]@{ IsGroup = $false; Key = '3'; Label = 'Run command in all submodules' }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = '' }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Repair and sync' }
    [pscustomobject]@{ IsGroup = $false; Key = '4'; Label = 'Initialize submodules' }
    [pscustomobject]@{ IsGroup = $false; Key = '5'; Label = 'Update submodules from remote' }
    [pscustomobject]@{ IsGroup = $false; Key = '6'; Label = 'Sync URLs from .gitmodules' }
    [pscustomobject]@{ IsGroup = $false; Key = '7'; Label = 'Repair common issues' }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = '' }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Manage' }
    [pscustomobject]@{ IsGroup = $false; Key = '8'; Label = 'Add submodule' }
    [pscustomobject]@{ IsGroup = $false; Key = '9'; Label = 'Remove submodule' }
    [pscustomobject]@{ IsGroup = $false; Key = '10'; Label = 'Set tracked branch' }
    [pscustomobject]@{ IsGroup = $false; Key = '11'; Label = 'Set URL' }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = '' }
    [pscustomobject]@{ IsGroup = $false; Key = 'q'; Label = 'Quit' }
  )
}

function Test-GitRepository {
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('rev-parse', '--show-toplevel')
  return $result.ExitCode -eq 0
}

function Invoke-GitCommand {
  param(
    [Parameter(Mandatory)]
    [string[]] $Arguments
  )

  $displayCommand = Get-GitDisplayCommand -Arguments $Arguments
  Write-BabaCommand $displayCommand

  $result = Invoke-NativeCommand -FileName 'git' -Arguments $Arguments

  foreach ($line in @($result.StandardOutputLines)) {
    Write-Host $line -ForegroundColor Gray
  }

  foreach ($line in @($result.StandardErrorLines)) {
    $color = if ($result.ExitCode -eq 0) { $script:brand.Warning } else { $script:brand.Failure }
    Write-Host $line -ForegroundColor $color
  }

  if ($result.ExitCode -ne 0) {
    throw (New-GitCommandException -DisplayCommand $displayCommand -ExitCode $result.ExitCode -StandardOutputLines @($result.StandardOutputLines) -StandardErrorLines @($result.StandardErrorLines))
  }

  if (@($result.StandardOutputLines).Count -eq 0 -and @($result.StandardErrorLines).Count -eq 0) {
    Write-BabaSuccess 'Command completed without output.'
  }
  else {
    Write-BabaSuccess "Command completed with exit code $($result.ExitCode)."
  }

  return $result
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory)]
    [string] $FileName,
    [Parameter(Mandatory)]
    [string[]] $Arguments
  )

  $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processStartInfo.FileName = $FileName
  $processStartInfo.UseShellExecute = $false
  $processStartInfo.RedirectStandardOutput = $true
  $processStartInfo.RedirectStandardError = $true
  $processStartInfo.WorkingDirectory = (Get-Location).Path

  foreach ($argument in $Arguments) {
    [void] $processStartInfo.ArgumentList.Add($argument)
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processStartInfo

  try {
    [void] $process.Start()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
      ExitCode            = $process.ExitCode
      StandardOutputLines = @(Split-OutputLines -Text $standardOutput)
      StandardErrorLines  = @(Split-OutputLines -Text $standardError)
    }
  }
  finally {
    $process.Dispose()
  }
}

function Split-OutputLines {
  param(
    [AllowEmptyString()]
    [string] $Text
  )

  if ([string]::IsNullOrEmpty($Text)) {
    return @()
  }

  @($Text -split '\r?\n' | Where-Object { $_ -ne '' })
}

function New-GitCommandException {
  param(
    [Parameter(Mandatory)]
    [string] $DisplayCommand,
    [Parameter(Mandatory)]
    [int] $ExitCode,
    [string[]] $StandardOutputLines,
    [string[]] $StandardErrorLines
  )

  if (-not $StandardOutputLines) { $StandardOutputLines = @() }
  if (-not $StandardErrorLines) { $StandardErrorLines = @() }

  $messageLines = @(
    'Git command failed.'
    "Command: $DisplayCommand"
    "Exit code: $ExitCode"
  )

  if ($StandardErrorLines.Count -gt 0) {
    $messageLines += ''
    $messageLines += 'stderr:'
    $messageLines += $StandardErrorLines
  }

  if ($StandardOutputLines.Count -gt 0) {
    $messageLines += ''
    $messageLines += 'stdout:'
    $messageLines += $StandardOutputLines
  }

  return [System.Exception]::new(($messageLines -join [System.Environment]::NewLine))
}

function Get-GitDisplayCommand {
  param(
    [Parameter(Mandatory)]
    [string[]] $Arguments
  )

  $formattedArguments = foreach ($argument in $Arguments) {
    if ($argument -match '[\s"]') {
      '"' + ($argument -replace '"', '\"') + '"'
    }
    else {
      $argument
    }
  }

  'git ' + ($formattedArguments -join ' ')
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
  Write-BabaFrame '║  BabaDeluxe Submodule Tamer                              ║' $script:brand.Accent
  Write-BabaFrame '║  purple paws. sharp claws. civilized git control.        ║' $script:brand.Highlight
  Write-BabaFrame '╚════════════════════════════════════════════════════════════╝' $script:brand.AccentDark
  Write-Host ''
  Write-Host " $Title " -ForegroundColor Black -BackgroundColor Magenta
  Write-Host ''
}

function Pause-Baba {
  Write-Host ''
  Read-Host 'Press Enter to continue' | Out-Null
}

function Write-BabaFrame {
  param(
    [Parameter(Mandatory)]
    [string] $Text,
    [ConsoleColor] $Color = 'Magenta'
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

function Write-BabaCommand {
  param(
    [Parameter(Mandatory)]
    [string] $Text
  )

  Write-BabaStatus '[git]' $Text $script:brand.Accent
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

Start-BabaDeluxeCli