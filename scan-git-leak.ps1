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
The directory to search recursively for Git repositories. Forward slashes, trailing
slashes, and relative paths are all accepted.

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
pwsh ./Find-GitCommitSnapshotTerm.ps1 -RootPath 'D:/src' -SearchTerm 'FeatureFlagAlpha'

.EXAMPLE
pwsh ./Find-GitCommitSnapshotTerm.ps1 `
  -RootPath 'D:/src' `
  -SearchTerm 'tenantId' `
  -IncludePath 'src/**' `
  -OutputCsvPath './output/snapshot-results.csv'

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


# region --- Git Helpers ---


function Test-GitAvailable {
  [CmdletBinding()]
  param()

  $gitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
  if ($null -eq $gitCommand) {
    throw 'git was not found in PATH.'
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
    $repoRoot = Resolve-GitRepositoryRoot -CandidatePath $gitDirectory.Parent.FullName
    if ($null -ne $repoRoot) {
      $null = $repoRoots.Add($repoRoot)
    }
  }

  foreach ($gitFile in Get-ChildItem -LiteralPath $resolvedSearchRoot -File -Filter '.git' -Force -Recurse -ErrorAction SilentlyContinue) {
    $repoRoot = Resolve-GitRepositoryRoot -CandidatePath $gitFile.Directory.FullName
    if ($null -ne $repoRoot) {
      $null = $repoRoots.Add($repoRoot)
    }
  }

  return @($repoRoots | Sort-Object)
}


# endregion


# region --- Grep Helpers ---

function ConvertFrom-GrepOutput {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string[]]$GrepOutput
  )

  $matchingFiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  foreach ($line in $GrepOutput) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    # Format: <commit>:<filepath>:<linenum>:<content>
    # Split on the first two colons only to isolate the filepath
    $firstColon = $line.IndexOf(':')
    if ($firstColon -lt 0) { continue }

    $secondColon = $line.IndexOf(':', $firstColon + 1)
    if ($secondColon -lt 0) { continue }

    $filePath = $line.Substring($firstColon + 1, $secondColon - $firstColon - 1)
    if (-not [string]::IsNullOrWhiteSpace($filePath)) {
      $null = $matchingFiles.Add($filePath)
    }
  }

  return , $matchingFiles
}

function Build-GrepArguments {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$SearchTerm,

    [Parameter(Mandatory)]
    [string]$CommitHash,

    [Parameter()]
    [switch]$CaseSensitive,

    [Parameter()]
    [switch]$UseRegex,

    [Parameter()]
    [string[]]$IncludePath = @()
  )

  $grepArguments = @('grep', '-n', '-I', '--full-name')

  if (-not $CaseSensitive) {
    $grepArguments += '-i'
  }

  if (-not $UseRegex) {
    $grepArguments += '-F'
  }

  $grepArguments += @('-e', $SearchTerm, $CommitHash)

  if ($IncludePath.Count -gt 0) {
    $grepArguments += '--'
    $grepArguments += $IncludePath
  }

  return $grepArguments
}


# endregion


# region --- Commit Helpers ---


function Get-CommitMetadata {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepositoryPath,

    [Parameter(Mandatory)]
    [string]$CommitHash
  )

  $metadata = Invoke-Git `
    -RepositoryPath $RepositoryPath `
    -Arguments @('show', '-s', '--format=%H%x1f%aI%x1f%an%x1f%s', $CommitHash)

  $header = (($metadata -join "`n").Trim()).Split([char]0x1f)
  if ($header.Count -lt 4) {
    return $null
  }

  return [PSCustomObject]@{
    commitHash = $header[0]
    authorDate = [datetimeoffset]::Parse($header[1])
    authorName = $header[2]
    subject    = $header[3]
  }
}


function New-SnapshotResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepositoryPath,

    [Parameter(Mandatory)]
    [PSCustomObject]$CommitMetadata,

    [Parameter(Mandatory)]
    [System.Collections.Generic.HashSet[string]]$MatchingFiles
  )

  $sortedFiles = @($MatchingFiles | Sort-Object)

  return [PSCustomObject]@{
    repositoryPath    = $RepositoryPath
    searchMode        = 'SnapshotHistory'
    commitHash        = $CommitMetadata.commitHash
    authorDate        = $CommitMetadata.authorDate
    authorName        = $CommitMetadata.authorName
    subject           = $CommitMetadata.subject
    matchingFileCount = $MatchingFiles.Count
    matchingFiles     = $sortedFiles
    matchingFilesText = ($sortedFiles -join '; ')
  }
}


# endregion


# region --- CSV Export ---


function Export-ResultsToCsv {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Collections.Generic.List[object]]$Results,

    [Parameter(Mandatory)]
    [string]$OutputCsvPath
  )

  $outputDirectory = Split-Path -Path $OutputCsvPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
  }

  $Results |
  Sort-Object repositoryPath, authorDate, commitHash |
  Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding utf8
}


# endregion


# region --- Entry Point ---

Test-GitAvailable

# Normalize path: handles forward slashes, trailing slashes, and relative paths
$resolvedRootPath = [System.IO.Path]::GetFullPath(
  $RootPath.TrimEnd('\', '/', ' ')
)

if (-not (Test-Path -LiteralPath $resolvedRootPath -PathType Container)) {
  throw "RootPath does not exist or is not a directory: $resolvedRootPath"
}

[string[]]$repositories = @(Get-GitRepositoryRoots -SearchRoot $resolvedRootPath)
$results = [System.Collections.Generic.List[object]]::new()

foreach ($repository in $repositories) {
  Write-Verbose "Enumerating commits in repository: $repository"

  [string[]]$commitHashes = @(Invoke-Git -RepositoryPath $repository -Arguments @('rev-list', '--all'))
  $totalCommitCount = $commitHashes.Count

  for ($commitIndex = 0; $commitIndex -lt $totalCommitCount; $commitIndex++) {
    $commitHash = $commitHashes[$commitIndex].Trim()
    if ([string]::IsNullOrWhiteSpace($commitHash)) { continue }

    Write-Progress `
      -Activity 'Scanning commit snapshots' `
      -Status "$repository ($($commitIndex + 1)/$totalCommitCount)" `
      -PercentComplete ((($commitIndex + 1) / [math]::Max($totalCommitCount, 1)) * 100)

    $grepArguments = Build-GrepArguments `
      -SearchTerm $SearchTerm `
      -CommitHash $commitHash `
      -CaseSensitive:$CaseSensitive `
      -UseRegex:$UseRegex `
      -IncludePath $IncludePath

    [string[]]$grepOutput = @(Invoke-Git -RepositoryPath $repository -Arguments $grepArguments -AllowedExitCodes @(0, 1))
    if ($grepOutput.Count -eq 0) { continue }

    $matchingFiles = ConvertFrom-GrepOutput -GrepOutput $grepOutput
    if ($matchingFiles.Count -eq 0) { continue }

    $commitMetadata = Get-CommitMetadata -RepositoryPath $repository -CommitHash $commitHash
    if ($null -eq $commitMetadata) { continue }

    $results.Add((New-SnapshotResult -RepositoryPath $repository -CommitMetadata $commitMetadata -MatchingFiles $matchingFiles))
  }
}

Write-Progress -Activity 'Scanning commit snapshots' -Completed

if ($results.Count -eq 0) {
  Write-Host "Scan complete. No matches found for '$SearchTerm' across $($repositories.Count) repositories." -ForegroundColor Green
} else {
  Write-Host "Scan complete. Found $($results.Count) matching commits for '$SearchTerm' across $($repositories.Count) repositories." -ForegroundColor Yellow
}

if ($PSBoundParameters.ContainsKey('OutputCsvPath')) {
  Export-ResultsToCsv -Results $results -OutputCsvPath $OutputCsvPath
}

$results | Sort-Object repositoryPath, authorDate, commitHash

# endregion
