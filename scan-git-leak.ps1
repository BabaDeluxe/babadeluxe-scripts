<#
.SYNOPSIS
Recursively searches all Git repositories under a root path for commits whose file
snapshots contain a search term.

.DESCRIPTION
Finds repository roots recursively, enumerates all commits, and runs `git grep`
against each commit snapshot. This is slower than patch-history scanning, but it is
the correct choice when you need to know whether the repository contents at a given
commit contained the term anywhere in tracked files.

.PARAMETER RootPath
The directory to search recursively for Git repositories.

.PARAMETER SearchTerm
The text or regex pattern to search for.

.PARAMETER CaseSensitive
Search case-sensitively.

.PARAMETER UseRegex
Treat SearchTerm as a regex. By default, SearchTerm is treated as a literal string.

.PARAMETER IncludePath
Optional Git pathspec filters, for example: 'src/**', '*.cs', '*.ts'

.PARAMETER OutputCsvPath
Optional path to export results as CSV.

.EXAMPLE
pwsh ./Find-GitCommitSnapshotTerm.ps1 -RootPath 'D:\src' -SearchTerm 'FeatureFlagAlpha'

.EXAMPLE
pwsh ./Find-GitCommitSnapshotTerm.ps1 `
  -RootPath 'D:\src' `
  -SearchTerm 'tenantId' `
  -IncludePath 'src/**' `
  -OutputCsvPath '.\output\snapshot-results.csv'

.OUTPUTS
PSCustomObject
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$RootPath,

  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$SearchTerm,

  [Parameter()]
  [switch]$CaseSensitive,

  [Parameter()]
  [switch]$UseRegex,

  [Parameter()]
  [string[]]$IncludePath = @(),

  [Parameter()]
  [string]$OutputCsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-GitAvailable {
  [CmdletBinding()]
  param()

  $gitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
  if ($null -eq $gitCommand) {
    throw "git was not found in PATH."
  }
}

function Invoke-Git {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepositoryPath,

    [Parameter(Mandatory)]
    [string[]]$Arguments,

    [Parameter()]
    [int[]]$AllowedExitCodes = @(0)
  )

  $output = & git -C $RepositoryPath @Arguments 2>&1
  $exitCode = $LASTEXITCODE

  if ($AllowedExitCodes -notcontains $exitCode) {
    $details = ($output | Out-String).Trim()
    throw "Git command failed with exit code $exitCode in '$RepositoryPath': git $($Arguments -join ' ')`n$details"
  }

  return @($output | ForEach-Object { $_.ToString() })
}

function Resolve-GitRepositoryRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$CandidatePath
  )

  $root = & git -C $CandidatePath rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  $trimmedRoot = $root.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmedRoot)) {
    return $null
  }

  return [System.IO.Path]::GetFullPath($trimmedRoot)
}

function Get-GitRepositoryRoots {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$SearchRoot
  )

  $resolvedSearchRoot = [System.IO.Path]::GetFullPath($SearchRoot)
  $repoRoots = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  foreach ($gitDirectory in Get-ChildItem -LiteralPath $resolvedSearchRoot -Directory -Filter '.git' -Force -Recurse -ErrorAction SilentlyContinue) {
    $candidatePath = $gitDirectory.Parent.FullName
    $repoRoot = Resolve-GitRepositoryRoot -CandidatePath $candidatePath

    if ($repoRoot -ne $null) {
      $null = $repoRoots.Add($repoRoot)
    }
  }

  foreach ($gitFile in Get-ChildItem -LiteralPath $resolvedSearchRoot -File -Filter '.git' -Force -Recurse -ErrorAction SilentlyContinue) {
    $candidatePath = $gitFile.Directory.FullName
    $repoRoot = Resolve-GitRepositoryRoot -CandidatePath $candidatePath

    if ($repoRoot -ne $null) {
      $null = $repoRoots.Add($repoRoot)
    }
  }

  return @($repoRoots | Sort-Object)
}

Test-GitAvailable

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
  throw "RootPath does not exist or is not a directory: $RootPath"
}

$repositories = Get-GitRepositoryRoots -SearchRoot $RootPath
$results = [System.Collections.Generic.List[object]]::new()

foreach ($repository in $repositories) {
  Write-Verbose "Enumerating commits in repository: $repository"

  $commitHashes = Invoke-Git -RepositoryPath $repository -Arguments @('rev-list', '--all')
  $totalCommitCount = $commitHashes.Count

  for ($commitIndex = 0; $commitIndex -lt $totalCommitCount; $commitIndex++) {
    $commitHash = $commitHashes[$commitIndex].Trim()
    if ([string]::IsNullOrWhiteSpace($commitHash)) {
      continue
    }

    Write-Progress `
      -Activity "Scanning commit snapshots" `
      -Status "$repository ($($commitIndex + 1)/$totalCommitCount)" `
      -PercentComplete ((($commitIndex + 1) / [math]::Max($totalCommitCount, 1)) * 100)

    $grepArguments = @(
      'grep'
      '-n'
      '-I'
      '--full-name'
    )

    if (-not $CaseSensitive) {
      $grepArguments += '-i'
    }

    if (-not $UseRegex) {
      $grepArguments += '-F'
    }

    $grepArguments += @('-e', $SearchTerm, $commitHash)

    if ($IncludePath.Count -gt 0) {
      $grepArguments += '--'
      $grepArguments += $IncludePath
    }

    $grepOutput = Invoke-Git -RepositoryPath $repository -Arguments $grepArguments -AllowedExitCodes @(0, 1)

    if ($grepOutput.Count -eq 0) {
      continue
    }

    $matchingFiles = [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($line in $grepOutput) {
      $trimmedLine = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
        continue
      }

      $parts = $trimmedLine -split ':', 4
      if ($parts.Count -lt 4) {
        continue
      }

      $filePath = $parts[1].Trim()
      if ([string]::IsNullOrWhiteSpace($filePath)) {
        continue
      }

      $null = $matchingFiles.Add($filePath)
    }

    if ($matchingFiles.Count -eq 0) {
      continue
    }

    $metadata = Invoke-Git `
      -RepositoryPath $repository `
      -Arguments @('show', '-s', '--format=%H%x1f%aI%x1f%an%x1f%s', $commitHash)

    $header = (($metadata -join "`n").Trim()).Split([char]0x1f)
    if ($header.Count -lt 4) {
      continue
    }

    $results.Add([PSCustomObject]@{
        repositoryPath    = $repository
        searchMode        = 'SnapshotHistory'
        commitHash        = $header[0]
        authorDate        = [datetimeoffset]::Parse($header[1])
        authorName        = $header[2]
        subject           = $header[3]
        matchingFileCount = $matchingFiles.Count
        matchingFiles     = @($matchingFiles | Sort-Object)
        matchingFilesText = (@($matchingFiles | Sort-Object) -join '; ')
      })
  }
}

Write-Progress -Activity "Scanning commit snapshots" -Completed

if ($PSBoundParameters.ContainsKey('OutputCsvPath')) {
  $outputDirectory = Split-Path -Path $OutputCsvPath -Parent

  if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
  }

  $results |
  Sort-Object repositoryPath, authorDate, commitHash |
  Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding utf8
}

$results | Sort-Object repositoryPath, authorDate, commitHash
