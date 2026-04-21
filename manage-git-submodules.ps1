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
$script:scope = $null
$script:allScopes = $null



# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

function Start-BabaDeluxeCli {
  if (-not (Test-GitRepository)) {
    Write-BabaFailure 'This script must be run inside a Git repository.'
    exit 1
  }

  Select-WorkingScope

  while (-not $script:quit) {
    Show-Menu
    $choice = Read-Host 'Choose an option'
    try {
      Invoke-MenuChoice -Choice $choice
    } catch {
      Show-BabaScreen -Title 'Operation Failed'
      Write-BabaFailure $_.Exception.Message
      Pause-Baba
    }
  }

  Show-BabaScreen -Title 'Goodbye'
  Write-BabaSuccess 'BabaDeluxe has released the submodules back into the void.'
}



# ---------------------------------------------------------------------------
# Scope selection
# ---------------------------------------------------------------------------

function Get-DirectoriesWithSubmodules {
  param([Parameter(Mandatory)] [string] $RootPath)
  @(Get-ChildItem -Path $RootPath -Directory | Sort-Object Name | Where-Object {
      Test-Path (Join-Path $_.FullName '.gitmodules')
    } | Select-Object -ExpandProperty Name)
}

function New-SingleScope {
  param([string] $Path, [string] $Label)
  [pscustomobject]@{ Path = $Path; Label = $Label; IsAll = $false }
}

function New-AllScope {
  param([string] $RootPath, [string[]] $Dirs)
  $allPaths = $Dirs | ForEach-Object { Join-Path $RootPath $_ }
  $script:allScopes = @($allPaths | ForEach-Object {
      [pscustomobject]@{ Path = $_; Label = (Split-Path $_ -Leaf); IsAll = $false }
    })
  [pscustomobject]@{ Path = $RootPath; Label = "ALL listed folders ($($Dirs.Count))"; IsAll = $true }
}

function Show-ScopeOptions {
  param([string] $InvokedFrom, [string[]] $BabaDirs)

  Write-BabaInfo 'Where do you want to manage submodules?'
  Write-Host ''
  Write-Host '  [1] ' -NoNewline -ForegroundColor $script:brand.AccentDark
  Write-Host "Current folder  ($InvokedFrom)" -ForegroundColor Gray
  Write-Host '  [2] ' -NoNewline -ForegroundColor $script:brand.AccentDark
  Write-Host "All listed folders  ($($BabaDirs.Count) found)" -ForegroundColor $script:brand.Highlight

  $index = 3
  foreach ($dir in $BabaDirs) {
    Write-Host ('  [' + $index + '] ') -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $dir -ForegroundColor Gray
    $index++
  }
  Write-Host ''
}

function Read-ScopeChoice {
  param([string] $InvokedFrom, [string[]] $BabaDirs)

  while ($true) {
    $raw = (Read-Host 'Scope').Trim()

    if ($raw -eq '1') { return New-SingleScope -Path $InvokedFrom -Label $InvokedFrom }
    if ($raw -eq '2') { return New-AllScope -RootPath $InvokedFrom -Dirs $BabaDirs }

    if ($raw -match '^\d+$') {
      $i = [int]$raw - 3
      if ($i -ge 0 -and $i -lt $BabaDirs.Count) {
        $full = Join-Path $InvokedFrom $BabaDirs[$i]
        return New-SingleScope -Path $full -Label $BabaDirs[$i]
      }
    }

    Write-BabaFailure "Invalid selection '$raw' — try again."
    Write-Host ''
  }
}

function Select-WorkingScope {
  Show-BabaScreen -Title 'Select Scope'

  $invokedFrom = $PSScriptRoot
  $babaDirs = @(Get-DirectoriesWithSubmodules -RootPath $invokedFrom)

  if ($babaDirs.Count -eq 0) {
    # Informational fallback — not an error, just a constraint
    Write-BabaStatus '[!]' 'No subfolders containing .gitmodules found. Falling back to current folder.' $script:brand.Warning
    $script:scope = New-SingleScope -Path $invokedFrom -Label $invokedFrom
    $script:allScopes = $null
    return
  }

  Show-ScopeOptions -InvokedFrom $invokedFrom -BabaDirs $babaDirs
  $script:scope = Read-ScopeChoice -InvokedFrom $invokedFrom -BabaDirs $babaDirs

  if (-not $script:scope.IsAll) {
    Set-Location $script:scope.Path
  }

  Write-Host ''
  Write-BabaSuccess "Scope set to: $($script:scope.Label)"
}



# ---------------------------------------------------------------------------
# Scope-aware runner
# ---------------------------------------------------------------------------

function Invoke-InScope {
  param(
    [Parameter(Mandatory)] [scriptblock] $Action,
    [switch] $WithDiagnosis
  )

  if ($script:scope.IsAll) {
    foreach ($s in $script:allScopes) {
      Write-Host ''
      Write-BabaInfo "--- $($s.Label) ---"
      Push-Location $s.Path
      try {
        & $Action
        if ($WithDiagnosis) {
          Write-Host ''
          Write-SubmoduleDiagnosis
        }
      } catch {
        Write-BabaFailure "Failed in '$($s.Label)': $($_.Exception.Message)"
      } finally {
        Pop-Location
      }
    }

    return
  }

  & $Action
  if ($WithDiagnosis) {
    Write-Host ''
    Write-SubmoduleDiagnosis
  }
}



# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

function Get-SubmoduleStatusLines {
  # Returns raw status lines including uninitialized (-), dirty (+), conflicted (U), and clean entries
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('submodule', 'status', '--recursive')
  return @($result.StandardOutputLines)
}

function Get-DeclaredSubmodulePaths {
  # Reads paths declared in .gitmodules — source of truth regardless of init state
  if (-not (Test-Path '.gitmodules')) { return @() }
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--file', '.gitmodules', '--get-regexp', 'submodule\..*\.path')
  return @(
    $result.StandardOutputLines |
    Where-Object { $_ -match '^submodule\..+\.path\s+(.+)$' } |
    ForEach-Object { $Matches[1].Trim() }
  )
}

function Get-DeclaredSubmoduleDetails {
  # Returns objects with Path, Url, Branch ($null when not configured) for each declared submodule
  if (-not (Test-Path '.gitmodules')) { return @() }
  $paths = @(Get-DeclaredSubmodulePaths)
  return @($paths | ForEach-Object {
      $path = $_
      $name = ($path -replace '/', '\.')

      $urlResult = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--file', '.gitmodules', "submodule.$name.url")
      $branchResult = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--file', '.gitmodules', "submodule.$name.branch")

      [pscustomobject]@{
        Path   = $path
        Url    = if ($urlResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($urlResult.StandardOutputLines[0])) { $urlResult.StandardOutputLines[0] } else { $null }
        Branch = if ($branchResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchResult.StandardOutputLines[0])) { $branchResult.StandardOutputLines[0] } else { $null }
      }
    })
}

function Get-SubmoduleUrl {
  param([Parameter(Mandatory)] [string] $Path)

  $details = @(Get-DeclaredSubmoduleDetails | Where-Object { $_.Path -eq $Path } | Select-Object -First 1)
  if ($details.Count -eq 0) { return $null }

  return $details[0].Url
}

function Get-RegisteredSubmodules {
  return @(Get-DeclaredSubmodulePaths)
}

function Write-SubmoduleTable {
  param([object[]] $Details, [string[]] $StatusLines)

  $uninitializedPaths = @(
    $StatusLines |
    Where-Object { $_ -match '^\s*-[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )
  $dirtyPaths = @(
    $StatusLines |
    Where-Object { $_ -match '^\s*\+[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )
  $conflictedPaths = @(
    $StatusLines |
    Where-Object { $_ -match '^\s*U[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )

  Write-Host ''
  foreach ($d in $Details) {
    $stateColor = $script:brand.Success
    $stateLabel = 'clean'

    if ($d.Path -in $uninitializedPaths) { $stateColor = $script:brand.Warning; $stateLabel = ' not initialized' }
    elseif ($d.Path -in $conflictedPaths) { $stateColor = $script:brand.Failure; $stateLabel = 'conflict' }
    elseif ($d.Path -in $dirtyPaths) { $stateColor = $script:brand.Warning; $stateLabel = 'wrong commit' }

    $branchDisplay = if ($d.Branch) { $d.Branch } else { '(default)' }

    Write-Host '  ' -NoNewline
    Write-Host $d.Path -ForegroundColor $script:brand.Highlight -NoNewline
    Write-Host '  ' -NoNewline
    Write-Host "[$stateLabel]" -ForegroundColor $stateColor
    Write-Host "    url:    $(if ($d.Url) { $d.Url } else { '(no url)' })" -ForegroundColor $script:brand.Muted
    Write-Host "    branch: $branchDisplay" -ForegroundColor $script:brand.Muted
    Write-Host ''
  }
}

function Write-SubmoduleDiagnosis {
  # Cross-references .gitmodules declarations vs git submodule status to emit targeted tips
  $declared = @(Get-DeclaredSubmoduleDetails)
  $statusLines = @(Get-SubmoduleStatusLines)

  if ($declared.Count -eq 0 -and -not (Test-Path '.gitmodules')) {
    Write-BabaStatus '[?]' 'No .gitmodules file found — this repo has no declared submodules.' $script:brand.Warning
    return
  }

  if ($declared.Count -eq 0 -and (Test-Path '.gitmodules')) {
    Write-BabaStatus '[?]' '.gitmodules exists but contains no path entries — it may be malformed.' $script:brand.Warning
    return
  }

  $uninitializedPaths = @(
    $statusLines |
    Where-Object { $_ -match '^\s*-[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )

  $conflictedPaths = @(
    $statusLines |
    Where-Object { $_ -match '^\s*U[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )

  $dirtyPaths = @(
    $statusLines |
    Where-Object { $_ -match '^\s*\+[0-9a-f]{40}\s+(\S+)' } |
    ForEach-Object { $Matches[1] }
  )

  if ($uninitializedPaths.Count -gt 0) {
    Write-BabaStatus '[?]' "$($uninitializedPaths.Count) submodule(s) declared but not initialized:" $script:brand.Warning
    foreach ($p in $uninitializedPaths) {
      Write-Host "       $p" -ForegroundColor $script:brand.Muted
    }
    Write-BabaStatus '[!]' 'Run option [4] Initialize & Update submodules to fix this.' $script:brand.Highlight
  }

  if ($conflictedPaths.Count -gt 0) {
    Write-BabaStatus '[?]' "$($conflictedPaths.Count) submodule(s) have merge conflicts:" $script:brand.Failure
    foreach ($p in $conflictedPaths) {
      Write-Host "       $p" -ForegroundColor $script:brand.Muted
    }
    Write-BabaStatus '[!]' 'Resolve conflicts inside each submodule directory manually.' $script:brand.Highlight
  }

  if ($dirtyPaths.Count -gt 0) {
    Write-BabaStatus '[?]' "$($dirtyPaths.Count) submodule(s) checked out at a different commit than recorded:" $script:brand.Warning

    foreach ($p in $dirtyPaths) {
      # Extract the commit the parent repo has pinned for this submodule
      $pinnedCommitResult = Invoke-NativeCommand -FileName 'git' -Arguments @('ls-tree', 'HEAD', $p)
      $pinnedCommit = if ($pinnedCommitResult.ExitCode -eq 0 -and $pinnedCommitResult.StandardOutputLines.Count -gt 0) {
        # ls-tree format: <mode> commit <hash>\t<path>
        if ($pinnedCommitResult.StandardOutputLines[0] -match '^\S+\s+commit\s+([0-9a-f]+)') { $Matches[1] } else { $null }
      } else { $null }

      # Extract the commit currently checked out in the submodule
      $currentCommitResult = if (Test-Path $p) {
        Push-Location $p
        try { Invoke-NativeCommand -FileName 'git' -Arguments @('rev-parse', 'HEAD') }
        finally { Pop-Location }
      } else { $null }
      $currentCommit = if ($currentCommitResult -and $currentCommitResult.ExitCode -eq 0) { $currentCommitResult.StandardOutputLines[0] } else { $null }

      Write-Host "       $p" -ForegroundColor $script:brand.Muted

      if (-not $pinnedCommit -or -not $currentCommit) {
        # Cannot determine direction — fall back to neutral advice
        Write-BabaStatus '[!]' "  Could not resolve commit pointers for '$p'." $script:brand.Muted
        continue
      }

      # Count commits ahead/behind: current vs pinned
      $subBehindBehindResult = if (Test-Path $p) {
        Push-Location $p
        try { Invoke-NativeCommand -FileName 'git' -Arguments @('rev-list', '--left-right', '--count', "$pinnedCommit...HEAD") }
        finally { Pop-Location }
      } else { $null }

      if ($subBehindBehindResult -and $subBehindBehindResult.ExitCode -eq 0 -and $subBehindBehindResult.StandardOutputLines.Count -gt 0) {
        $parts = $subBehindBehindResult.StandardOutputLines[0] -split '\s+'
        $parentBehind = [int]$parts[0]  # commits in pinned not in HEAD = submodule is behind pinned
        $subBehind = [int]$parts[1]  # commits in HEAD not in pinned = submodule is ahead of pinned

        if ($subBehind -gt 0 -and $parentBehind -eq 0) {
          Write-BabaStatus '[!]' "  $subBehind new commit(s) in submodule not yet pinned by the parent." $script:brand.Warning
          Write-BabaStatus '[!]' '  To pin: stage and commit the submodule pointer in the parent repo.' $script:brand.Highlight
        } elseif ($parentBehind -gt 0 -and $subBehind -eq 0) {
          Write-BabaStatus '[!]' "  Submodule is $parentBehind commit(s) behind what the parent has pinned." $script:brand.Warning
          Write-BabaStatus '[!]' '  To fix: run option [4] Initialize & Update submodules.' $script:brand.Highlight
        } else {
          # Diverged — both ahead and behind (e.g. local branch diverged from pinned commit)
          Write-BabaStatus '[!]' "  Diverged — $subBehind commit(s) ahead and $parentBehind commit(s) behind the pinned pointer." $script:brand.Warning
          Write-BabaStatus '[!]' '  To reset to pinned: run option [4] Initialize & Update submodules.' $script:brand.Highlight
          Write-BabaStatus '[!]' '  To pin current state: stage and commit the submodule pointer in the parent repo.' $script:brand.Highlight
        }
      } else {
        # rev-list failed (e.g. pinned commit not reachable — submodule not fetched)
        Write-BabaStatus '[!]' "  Pinned commit not reachable locally — submodule may need fetching." $script:brand.Warning
        Write-BabaStatus '[!]' '  Run option [4] Initialize & Update submodules to fetch and align.' $script:brand.Highlight
      }
    }

    Write-Host ''
  }

  # Use Branch field from already-fetched details — no redundant git config calls
  $untrackedBranch = @($declared | Where-Object { -not $_.Branch } | ForEach-Object { $_.Path })

  if ($untrackedBranch.Count -gt 0) {
    Write-BabaStatus '[?]' "$($untrackedBranch.Count) submodule(s) have no tracked branch configured:" $script:brand.Warning
    foreach ($p in $untrackedBranch) {
      Write-Host "       $p" -ForegroundColor $script:brand.Muted
    }
    Write-BabaStatus '[!]' 'Without a tracked branch, git submodule update --remote has no branch to follow.' $script:brand.Highlight
    Write-BabaStatus '[!]' 'Run option [10] Fix missing tracked branches to auto-resolve.' $script:brand.Highlight
    Write-Host ''
  }

  $detachedPaths = @($declared | Where-Object {
      $submodulePath = $_.Path
      if (-not (Test-Path $submodulePath)) { return $false }
      Push-Location $submodulePath
      try {
        $headResult = Invoke-NativeCommand -FileName 'git' -Arguments @('symbolic-ref', '--quiet', 'HEAD')
        return $headResult.ExitCode -ne 0
      } finally {
        Pop-Location
      }
    } | ForEach-Object { $_.Path })

  if ($detachedPaths.Count -gt 0) {
    Write-BabaStatus '[?]' "$($detachedPaths.Count) submodule(s) are in detached HEAD state:" $script:brand.Warning
    foreach ($p in $detachedPaths) {
      Write-Host "       $p" -ForegroundColor $script:brand.Muted
    }
    Write-BabaStatus '[!]' 'Run option [10] Fix missing tracked branches, then option [4] Initialize & Update.' $script:brand.Highlight
    Write-Host ''
  }

  if ($uninitializedPaths.Count -eq 0 -and $conflictedPaths.Count -eq 0 -and $dirtyPaths.Count -eq 0 -and $untrackedBranch.Count -eq 0 -and $detachedPaths.Count -eq 0 -and $declared.Count -gt 0) {
    Write-BabaSuccess "All $($declared.Count) declared submodule(s) are initialized, tracked, and clean."
  }
}

function Assert-HasSubmodules {
  param([string[]] $Paths)
  if ($Paths.Count -eq 0) {
    throw 'No registered submodules found in scope.'
  }
}

function Assert-SingleScope {
  if ($script:scope.IsAll) {
    throw "This command targets a specific submodule and requires a single repository scope.`nUse [r] to change scope and select one folder."
  }
}

function Commit-SubmoduleChanges {
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('status', '--porcelain')
  if ($result.StandardOutputLines.Count -gt 0) {
    Write-Host ''
    Write-BabaInfo 'Committing changes...'
    Invoke-GitCommand -Arguments @('add', '-A')
    Invoke-GitCommand -Arguments @('commit', '-m', 'chore: :wrench: Updated git submodules')
    Write-BabaSuccess 'Changes committed successfully.'
  } else {
    Write-BabaSuccess 'Action complete (no changes to commit).'
  }
}

function Show-SubmoduleList {
  param([string[]] $Paths)
  $index = 1
  foreach ($p in $Paths) {
    Write-Host ('  [' + $index + '] ') -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $p -ForegroundColor Gray
    $index++
  }
  Write-Host ''
}

function Read-SubmoduleChoice {
  param([string[]] $Paths, [string] $Prompt = 'Select submodule')
  $raw = (Read-Host $Prompt).Trim()
  if ($raw -match '^\d+$') {
    $i = [int]$raw - 1
    if ($i -ge 0 -and $i -lt $Paths.Count) {
      return $Paths[$i]
    }
  }
  return $null
}

function Select-SingleSubmodule {
  param([string[]] $RegisteredPaths, [string] $Prompt = 'Select submodule')
  Show-SubmoduleList -Paths $RegisteredPaths
  $selected = Read-SubmoduleChoice -Paths $RegisteredPaths -Prompt $Prompt
  if (-not $selected) { throw 'Invalid selection. Aborting.' }
  return $selected
}

function Remove-SubmoduleByPath {
  param([string] $Path)
  Write-BabaInfo "Removing '$Path'..."

  $deinitResult = Invoke-NativeCommand -FileName 'git' -Arguments @('submodule', 'deinit', '-f', '--', $Path)
  if ($deinitResult.ExitCode -ne 0) {
    Write-BabaStatus '[~]' "deinit skipped (not initialized): $Path" $script:brand.Muted
  } else {
    Write-BabaSuccess "Deinitialized: $Path"
  }

  $lsFilesResult = Invoke-NativeCommand -FileName 'git' -Arguments @('ls-files', '--error-unmatch', $Path)
  if ($lsFilesResult.ExitCode -eq 0) {
    Invoke-GitCommand -Arguments @('rm', '-f', '--', $Path)
  } else {
    Write-BabaStatus '[~]' "Path not in index — removing .gitmodules entry directly: $Path" $script:brand.Muted
    $configRemoveResult = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--file', '.gitmodules', '--remove-section', "submodule.$Path")
    if ($configRemoveResult.ExitCode -eq 0) {
      Write-BabaSuccess "Removed .gitmodules entry for: $Path"
    } else {
      Write-BabaStatus '[~]' ".gitmodules entry not found or already removed for: $Path" $script:brand.Muted
    }
    $localConfigResult = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--remove-section', "submodule.$Path")
    if ($localConfigResult.ExitCode -eq 0) {
      Write-BabaSuccess "Removed .git/config entry for: $Path"
    }
  }

  $modulesPath = Join-Path '.git/modules' $Path
  if (Test-Path $modulesPath) {
    Write-BabaInfo "Cleaning cached module data at $modulesPath..."
    Remove-Item -Path $modulesPath -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Select-BranchFromRemote {
  param(
    [Parameter(Mandatory)] [string] $RepositoryUrl,
    [string] $Prompt = 'Select branch (or type custom)',
    [switch] $AutoPickSingle
  )

  Write-BabaInfo "Fetching branches from $RepositoryUrl ..."
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('ls-remote', '--heads', $RepositoryUrl)

  $branches = @()
  if ($result.ExitCode -eq 0) {
    $branches = @($result.StandardOutputLines | ForEach-Object {
        if ($_ -match 'refs/heads/(.+)$') { $Matches[1] }
      } | Sort-Object)
  }

  if ($branches.Count -eq 0) {
    Write-BabaStatus '[!]' 'Could not fetch branches or no branches found.' $script:brand.Warning
    return $null
  }

  if ($AutoPickSingle -and $branches.Count -eq 1) {
    Write-BabaSuccess "Only one branch found: $($branches[0]). Auto-selected."
    return $branches[0]
  }

  Write-Host ''
  Write-Host 'Available branches:' -ForegroundColor $script:brand.Accent
  $index = 1
  foreach ($b in $branches) {
    Write-Host ('  [' + $index + '] ') -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $b -ForegroundColor Gray
    $index++
  }
  Write-Host '  [m]  Enter branch name manually' -ForegroundColor $script:brand.Muted
  Write-Host ''

  while ($true) {
    $choice = (Read-Host $Prompt).Trim()
    if ($choice -eq 'm') {
      $manual = Read-Host 'Enter branch name'
      if (-not [string]::IsNullOrWhiteSpace($manual)) { return $manual }
      Write-BabaFailure 'Branch name cannot be empty.'
      continue
    }
    if ($choice -match '^\d+$') {
      $i = [int]$choice - 1
      if ($i -ge 0 -and $i -lt $branches.Count) { return $branches[$i] }
    }
    Write-BabaFailure "Invalid selection '$choice' — try again."
  }
}



# ---------------------------------------------------------------------------
# Commands — Inspect
# ---------------------------------------------------------------------------

function Show-Submodules {
  Show-BabaScreen -Title 'Submodule Status'
  Invoke-InScope -WithDiagnosis {
    $details = @(Get-DeclaredSubmoduleDetails)
    $statusLines = @(Get-SubmoduleStatusLines)
    Write-SubmoduleTable -Details $details -StatusLines $statusLines
  }
  Pause-Baba
}

function Show-SubmoduleSummary {
  Show-BabaScreen -Title 'Submodule Summary'
  Invoke-InScope -WithDiagnosis {
    $details = @(Get-DeclaredSubmoduleDetails)
    $statusLines = @(Get-SubmoduleStatusLines)
    Write-SubmoduleTable -Details $details -StatusLines $statusLines
    Write-Host ''
    Invoke-GitCommand -Arguments @('submodule', 'summary')
  }
  Pause-Baba
}



# ---------------------------------------------------------------------------
# Commands — Sync and update
# ---------------------------------------------------------------------------

function Sync-SubmodulesFull {
  Show-BabaScreen -Title 'Initialize & Update Submodules'
  Write-BabaStatus '[i]' 'Use this when submodules are missing, empty, or checked out at the wrong commit.' $script:brand.Muted
  Write-Host ''
  Invoke-InScope -WithDiagnosis {
    Invoke-GitCommand -Arguments @('submodule', 'update', '--remote', '--init', '--recursive')
  }
  Pause-Baba
}

function Sync-Submodules {
  Show-BabaScreen -Title 'Sync Submodule URLs'
  Write-BabaStatus '[i]' 'Use this after changing a URL in .gitmodules — propagates it to .git/config.' $script:brand.Muted
  Write-Host ''
  Invoke-InScope -WithDiagnosis {
    Invoke-GitCommand -Arguments @('submodule', 'sync', '--recursive')
  }
  Pause-Baba
}



# ---------------------------------------------------------------------------
# Commands — Manage
# ---------------------------------------------------------------------------

function Add-Submodule {
  Assert-SingleScope
  Show-BabaScreen -Title 'Add Submodule'

  $repository = Read-Host 'Repository URL'
  $path = Read-Host 'Path'

  $branch = $null
  $useBranch = Read-Host 'Specify a branch to track? (y/N)'
  if ($useBranch -eq 'y' -or $useBranch -eq 'Y') {
    $branch = Select-BranchFromRemote -RepositoryUrl $repository -Prompt 'Select branch'
    if (-not $branch) {
      Write-BabaStatus '[!]' 'Falling back to manual branch entry.' $script:brand.Warning
      $branch = Read-Host 'Branch name (leave empty to omit)'
    }
  }

  $arguments = @('submodule', 'add')
  if (-not [string]::IsNullOrWhiteSpace($branch)) {
    $arguments += @('-b', $branch)
  }
  $arguments += @($repository, $path)

  Invoke-InScope -WithDiagnosis {
    Invoke-GitCommand -Arguments $arguments
  }
  Pause-Baba
}

function Remove-Submodule {
  Assert-SingleScope
  Show-BabaScreen -Title 'Remove Submodule'

  $paths = @(Get-RegisteredSubmodules)
  Assert-HasSubmodules -Paths $paths

  $path = Select-SingleSubmodule -RegisteredPaths $paths

  Invoke-InScope -WithDiagnosis {
    $subsHere = @(Get-DeclaredSubmodulePaths)
    if ($path -in $subsHere) {
      Remove-SubmoduleByPath -Path $path
    } else {
      Write-BabaStatus '[~]' "Submodule '$path' not found in this folder – skipping." $script:brand.Muted
    }
  }

  Pause-Baba
}

function Set-SubmoduleBranch {
  Assert-SingleScope
  Show-BabaScreen -Title 'Set Tracked Branch'

  $paths = @(Get-RegisteredSubmodules)
  Assert-HasSubmodules -Paths $paths

  $path = Select-SingleSubmodule -RegisteredPaths $paths
  $url = Get-SubmoduleUrl -Path $path

  if ($url) {
    $branch = Select-BranchFromRemote -RepositoryUrl $url -Prompt 'Select branch'
    if (-not $branch) {
      Write-BabaStatus '[!]' 'Falling back to manual branch entry.' $script:brand.Warning
      $branch = Read-Host 'Branch name'
    }
  } else {
    Write-BabaStatus '[!]' 'Could not determine submodule URL. Manual entry required.' $script:brand.Warning
    $branch = Read-Host 'Branch name'
  }

  if ([string]::IsNullOrWhiteSpace($branch)) { throw 'Branch name cannot be empty.' }

  Invoke-InScope -WithDiagnosis {
    $subsHere = @(Get-DeclaredSubmodulePaths)
    if ($path -in $subsHere) {
      Invoke-GitCommand -Arguments @('submodule', 'set-branch', '-b', $branch, '--', $path)
    } else {
      Write-BabaStatus '[~]' "Submodule '$path' not found – skipping." $script:brand.Muted
    }
  }

  Pause-Baba
}

function Set-SubmoduleIgnoreDirty {
  Show-BabaScreen -Title 'Set ignore = dirty on All Submodules'
  Write-BabaStatus '[i]' 'Adds ignore = dirty to every submodule in .gitmodules.' $script:brand.Muted
  Write-BabaStatus '[i]' 'Git will stop reporting untracked/modified files inside submodules as dirty.' $script:brand.Muted
  Write-Host ''

  Invoke-InScope -WithDiagnosis {
    $declared = @(Get-DeclaredSubmoduleDetails)

    if ($declared.Count -eq 0) {
      Write-BabaStatus '[~]' 'No declared submodules found in this scope.' $script:brand.Muted
      return
    }

    foreach ($sub in $declared) {
      $name = ($sub.Path -replace '/', '\.')

      $existing = Invoke-NativeCommand -FileName 'git' -Arguments @(
        'config', '--file', '.gitmodules', "submodule.$name.ignore"
      )

      if ($existing.ExitCode -eq 0 -and $existing.StandardOutputLines[0] -eq 'dirty') {
        Write-BabaStatus '[~]' "Already set — skipping: $($sub.Path)" $script:brand.Muted
        continue
      }

      Invoke-GitCommand -Arguments @(
        'config', '--file', '.gitmodules', "submodule.$name.ignore", 'dirty'
      )
      Write-BabaSuccess "Set ignore = dirty: $($sub.Path)"
    }

    Commit-SubmoduleChanges
  }

  Pause-Baba
}

function Fix-MissingTrackedBranches {
  Show-BabaScreen -Title 'Fix Missing Tracked Branches'

  Invoke-InScope -WithDiagnosis {
    $declared = @(Get-DeclaredSubmoduleDetails)

    # Branch is $null when not configured — no redundant git config calls needed
    $missing = @($declared | Where-Object { -not $_.Branch })

    if ($missing.Count -eq 0) {
      Write-BabaSuccess 'No submodules are missing a tracked branch in this scope.'
      return
    }

    Write-BabaInfo "Found $($missing.Count) submodule(s) missing a tracked branch."

    foreach ($sub in $missing) {
      Write-Host ''
      Write-BabaInfo "Resolving branch for '$($sub.Path)'..."

      if (-not $sub.Url) {
        Write-BabaStatus '[!]' "No URL found for '$($sub.Path)'. Manual entry required." $script:brand.Warning
        $branch = Read-Host 'Branch name'
      } else {
        $branch = Select-BranchFromRemote -RepositoryUrl $sub.Url -Prompt "Select branch for '$($sub.Path)'" -AutoPickSingle
        if (-not $branch) {
          $branch = Read-Host "Branch name for '$($sub.Path)'"
        }
      }

      if ([string]::IsNullOrWhiteSpace($branch)) {
        Write-BabaStatus '[~]' "Skipped '$($sub.Path)'." $script:brand.Muted
        continue
      }

      Invoke-GitCommand -Arguments @('submodule', 'set-branch', '-b', $branch, '--', $sub.Path)
    }
  }

  Pause-Baba
}



# ---------------------------------------------------------------------------
# Commands — Workflows (auto-commit)
# ---------------------------------------------------------------------------

function Update-SubmoduleUrl {
  Assert-SingleScope
  Show-BabaScreen -Title 'Update Submodule URL'

  $paths = @(Get-RegisteredSubmodules)
  Assert-HasSubmodules -Paths $paths

  $path = Select-SingleSubmodule -RegisteredPaths $paths
  $newUrl = Read-Host "New URL for '$path'"
  if ([string]::IsNullOrWhiteSpace($newUrl)) { throw 'URL cannot be empty.' }

  Invoke-InScope -WithDiagnosis {
    $subsHere = @(Get-DeclaredSubmodulePaths)
    if ($path -in $subsHere) {
      Invoke-GitCommand -Arguments @('submodule', 'set-url', '--', $path, $newUrl)
      Invoke-GitCommand -Arguments @('submodule', 'sync', '--', $path)
    } else {
      Write-BabaStatus '[~]' "Submodule '$path' not found – skipping." $script:brand.Muted
    }

    Commit-SubmoduleChanges
  }

  Pause-Baba
}

function Move-Submodule {
  Assert-SingleScope
  Show-BabaScreen -Title 'Move/Rename Submodule'

  $paths = @(Get-RegisteredSubmodules)
  Assert-HasSubmodules -Paths $paths

  $oldPath = Select-SingleSubmodule -RegisteredPaths $paths -Prompt 'Select submodule to move'
  $newPath = Read-Host "New path/name for '$oldPath'"
  if ([string]::IsNullOrWhiteSpace($newPath)) { throw 'Path cannot be empty.' }

  Invoke-InScope -WithDiagnosis {
    $subsHere = @(Get-DeclaredSubmodulePaths)
    if ($oldPath -in $subsHere) {
      Write-BabaInfo "Moving '$oldPath' -> '$newPath'..."
      Invoke-GitCommand -Arguments @('mv', $oldPath, $newPath)
    } else {
      Write-BabaStatus '[~]' "Submodule '$oldPath' not found – skipping." $script:brand.Muted
    }

    Commit-SubmoduleChanges
  }

  Pause-Baba
}

function Cleanup-Submodules {
  Assert-SingleScope
  Show-BabaScreen -Title 'Clean up submodules'

  $paths = @(Get-RegisteredSubmodules)
  Assert-HasSubmodules -Paths $paths

  Write-BabaInfo 'Select the SINGLE submodule to KEEP. All others will be removed.'
  Write-Host ''

  $keeper = Select-SingleSubmodule -RegisteredPaths $paths -Prompt 'Submodule to keep'
  $newUrl = Read-Host "Correct URL for '$keeper'"
  if ([string]::IsNullOrWhiteSpace($newUrl)) { throw 'URL cannot be empty.' }

  Invoke-InScope -WithDiagnosis {
    $subsHere = @(Get-DeclaredSubmodulePaths)
    foreach ($p in $subsHere) {
      if ($p -eq $keeper) { continue }

      Write-Host ''
      Remove-SubmoduleByPath -Path $p
    }

    if ($keeper -in $subsHere) {
      Write-Host ''
      Write-BabaInfo "Updating URL for '$keeper'..."
      Invoke-GitCommand -Arguments @('submodule', 'set-url', '--', $keeper, $newUrl)
      Invoke-GitCommand -Arguments @('submodule', 'sync', '--recursive')
    } else {
      Write-BabaStatus '[~]' "Keeper submodule '$keeper' not found in this folder – skipping URL update." $script:brand.Warning
    }

    Commit-SubmoduleChanges
  }

  Pause-Baba
}



# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

function Get-MenuItems {
  @(
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Inspect'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '1'; Label = 'Show submodules'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '2'; Label = 'Show submodule summary'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = ''; Hint = ''; RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Sync and update'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '4'; Label = 'Initialize & Update submodules'; Hint = 'Missing, empty, or wrong commit? Run this.'; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '5'; Label = 'Sync URLs from .gitmodules'; Hint = 'Changed a URL in .gitmodules? Run this to apply it.'; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = ''; Hint = ''; RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Manage'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '7'; Label = 'Add submodule'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '8'; Label = 'Remove submodule'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '9'; Label = 'Set tracked branch'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '10'; Label = 'Fix missing tracked branches'; Hint = ''; RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = ''; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = 'Workflows (Auto-commit)'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '11'; Label = 'Update submodule URL'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '12'; Label = 'Move/Rename submodule'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '13'; Label = 'Clean up submodules'; Hint = ''; RequiresSingleScope = $true }
    [pscustomobject]@{ IsGroup = $false; Key = '14'; Label = 'Set ignore = dirty on all submodules'; Hint = 'Stop git from flagging submodule internal changes as dirty.'; RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true; Key = ''; Label = ''; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = 'r'; Label = 'Change scope'; Hint = ''; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = 'q'; Label = 'Quit'; Hint = ''; RequiresSingleScope = $false }
  )
}

function Show-Menu {
  Show-BabaScreen -Title 'Submodule Manager'
  Write-BabaInfo "Scope: $($script:scope.Label)"
  Write-Host ''

  $items = @(Get-MenuItems)
  if ($script:scope.IsAll) {
    $items = $items | Where-Object { -not $_.RequiresSingleScope }
  }

  foreach ($item in $items) {
    if ($item.IsGroup) {
      Write-Host $item.Label -ForegroundColor $script:brand.Accent
      continue
    }

    Write-Host ('  [' + $item.Key + '] ') -NoNewline -ForegroundColor $script:brand.AccentDark
    Write-Host $item.Label -ForegroundColor Gray

    if (-not [string]::IsNullOrWhiteSpace($item.Hint)) {
      Write-Host "       $($item.Hint)" -ForegroundColor $script:brand.Muted
    }
  }

  Write-Host ''
  Write-Host 'Type the number and press Enter. Type r to change scope. Type q to quit.' -ForegroundColor DarkGray
  Write-Host ''
}

function Invoke-MenuChoice {
  param([Parameter(Mandatory)] [string] $Choice)

  switch ($Choice.Trim().ToLowerInvariant()) {
    '1' { Show-Submodules }
    '2' { Show-SubmoduleSummary }
    '4' { Sync-SubmodulesFull }
    '5' { Sync-Submodules }
    '7' { Add-Submodule }
    '8' { Remove-Submodule }
    '9' { Set-SubmoduleBranch }
    '10' { Fix-MissingTrackedBranches }
    '11' { Update-SubmoduleUrl }
    '12' { Move-Submodule }
    '13' { Cleanup-Submodules }
    '14' { Set-SubmoduleIgnoreDirty }
    'r' { Select-WorkingScope }
    'q' { $script:quit = $true }
    'quit' { $script:quit = $true }
    default {
      Write-BabaFailure "Unknown menu option: $Choice"
      Pause-Baba
    }
  }
}



# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

function Test-GitRepository {
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('rev-parse', '--show-toplevel')
  return $result.ExitCode -eq 0
}

function Invoke-GitCommand {
  param([Parameter(Mandatory)] [string[]] $Arguments)

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

  if (@($result.StandardOutputLines).Count -gt 0 -or @($result.StandardErrorLines).Count -gt 0) {
    Write-BabaSuccess "Done (exit $($result.ExitCode))."
  }

  return $result
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory)] [string] $FileName,
    [Parameter(Mandatory)] [string[]] $Arguments
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
  } finally {
    $process.Dispose()
  }
}

function Split-OutputLines {
  param([AllowEmptyString()] [string] $Text)
  if ([string]::IsNullOrEmpty($Text)) { return @() }
  @($Text -split '\r?\n' | Where-Object { $_ -ne '' })
}

function New-GitCommandException {
  param(
    [Parameter(Mandatory)] [string] $DisplayCommand,
    [Parameter(Mandatory)] [int] $ExitCode,
    [string[]] $StandardOutputLines,
    [string[]] $StandardErrorLines
  )

  if (-not $StandardOutputLines) { $StandardOutputLines = @() }
  if (-not $StandardErrorLines) { $StandardErrorLines = @() }

  $parts = [System.Collections.Generic.List[string]]::new()
  $parts.Add('Git command failed.')
  $parts.Add("Command: $DisplayCommand")
  $parts.Add("Exit code: $ExitCode")

  if ($StandardErrorLines.Count -gt 0) {
    $parts.Add('')
    $parts.Add('stderr:')
    foreach ($line in $StandardErrorLines) { $parts.Add($line) }
  }
  if ($StandardOutputLines.Count -gt 0) {
    $parts.Add('')
    $parts.Add('stdout:')
    foreach ($line in $StandardOutputLines) { $parts.Add($line) }
  }

  return [System.Exception]::new(($parts -join [System.Environment]::NewLine))
}

function Get-GitDisplayCommand {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  $formattedArguments = foreach ($argument in $Arguments) {
    if ($argument -match '[\s"]') { '"' + ($argument -replace '"', '\"') + '"' }
    else { $argument }
  }
  'git ' + ($formattedArguments -join ' ')
}



# ---------------------------------------------------------------------------
# UI primitives
# ---------------------------------------------------------------------------

function Show-BabaScreen {
  param([Parameter(Mandatory)] [string] $Title)
  Clear-Host
  Show-BabaHeader -Title $Title
}

function Show-BabaHeader {
  param([Parameter(Mandatory)] [string] $Title)
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
  param([Parameter(Mandatory)] [string] $Text, [ConsoleColor] $Color = 'Magenta')
  Write-Host $Text -ForegroundColor $Color
}

function Write-BabaInfo {
  param([Parameter(Mandatory)] [string] $Text)
  Write-BabaStatus '[~]' $Text $script:brand.Highlight
}

function Write-BabaSuccess {
  param([Parameter(Mandatory)] [string] $Text)
  Write-BabaStatus '[✓]' $Text $script:brand.Success
}

function Write-BabaFailure {
  param([Parameter(Mandatory)] [string] $Text)
  Write-BabaStatus '[✗]' $Text $script:brand.Failure
}

function Write-BabaCommand {
  param([Parameter(Mandatory)] [string] $Text)
  Write-BabaStatus '[git]' $Text $script:brand.Accent
}

function Write-BabaStatus {
  param(
    [Parameter(Mandatory)] [string] $Prefix,
    [Parameter(Mandatory)] [string] $Text,
    [Parameter(Mandatory)] [ConsoleColor] $Color
  )
  Write-Host $Prefix -NoNewline -ForegroundColor $Color
  Write-Host " $Text" -ForegroundColor $Color
}

Start-BabaDeluxeCli
