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
# UI helpers
# ---------------------------------------------------------------------------

function Show-BabaScreen {
  param([string] $Title)
  Clear-Host
  Write-Host ''
  Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor $script:brand.Accent
  Write-Host '║  BabaDeluxe Submodule Tamer                              ║' -ForegroundColor $script:brand.Accent
  Write-Host '║  purple paws. sharp claws. civilized git control.        ║' -ForegroundColor $script:brand.Muted
  Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor $script:brand.Accent
  Write-Host ''
  if (-not [string]::IsNullOrWhiteSpace($Title)) {
    Write-Host " $Title " -ForegroundColor $script:brand.Highlight
    Write-Host ''
  }
}

function Write-BabaInfo    { param([string]$Msg) Write-Host "[~] $Msg" -ForegroundColor $script:brand.Highlight }
function Write-BabaSuccess { param([string]$Msg) Write-Host "[✓] $Msg" -ForegroundColor $script:brand.Success }
function Write-BabaFailure { param([string]$Msg) Write-Host "[✗] $Msg" -ForegroundColor $script:brand.Failure }

function Write-BabaStatus {
  param([string]$Tag, [string]$Msg, [string]$Color)
  Write-Host "$Tag " -NoNewline -ForegroundColor $Color
  Write-Host $Msg
}

function Pause-Baba {
  Write-Host ''
  Read-Host 'Press Enter to continue'
}



# ---------------------------------------------------------------------------
# Native command runner
# ---------------------------------------------------------------------------

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory)] [string]   $FileName,
    [Parameter(Mandatory)] [string[]] $Arguments
  )

  $stdout = [System.Collections.Generic.List[string]]::new()
  $stderr = [System.Collections.Generic.List[string]]::new()

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName               = $FileName
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }

  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  $null = $proc.Start()
  $proc.WaitForExit()

  while (-not $proc.StandardOutput.EndOfStream) { $stdout.Add($proc.StandardOutput.ReadLine()) }
  while (-not $proc.StandardError.EndOfStream)  { $stderr.Add($proc.StandardError.ReadLine()) }

  [pscustomobject]@{
    ExitCode            = $proc.ExitCode
    StandardOutputLines = [string[]]$stdout
    StandardErrorLines  = [string[]]$stderr
  }
}

function Invoke-GitCommand {
  param([string[]] $Arguments)
  Write-Host "[git] git $($Arguments -join ' ')" -ForegroundColor $script:brand.Muted
  $result = Invoke-NativeCommand -FileName 'git' -Arguments $Arguments
  if ($result.StandardOutputLines.Count -gt 0) {
    $result.StandardOutputLines | ForEach-Object { Write-Host $_ }
  }
  if ($result.StandardErrorLines.Count -gt 0) {
    $result.StandardErrorLines | ForEach-Object { Write-Host $_ -ForegroundColor $script:brand.Muted }
  }
  if ($result.ExitCode -ne 0) {
    Write-BabaFailure "git exited with code $($result.ExitCode)."
  } else {
    Write-BabaSuccess "Done (exit $($result.ExitCode))."
  }
}

function Test-GitRepository {
  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('rev-parse', '--git-dir')
  return $result.ExitCode -eq 0
}



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
    Write-BabaStatus '[!]' 'No subfolders containing .gitmodules found. Falling back to current folder.' $script:brand.Warning
    $script:scope = New-SingleScope -Path $invokedFrom -Label $invokedFrom
    $script:allScopes = $null
    Set-Location $invokedFrom
    return
  }

  Show-ScopeOptions -InvokedFrom $invokedFrom -BabaDirs $babaDirs
  $script:scope = Read-ScopeChoice -InvokedFrom $invokedFrom -BabaDirs $babaDirs

  # Always set working directory to the selected single scope so all subsequent
  # git calls are rooted correctly, even after a [r] re-scope mid-session.
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

  # Single scope: ensure we are still in the correct directory (guards against
  # any accidental cwd drift between menu interactions).
  Set-Location $script:scope.Path

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

      $urlResult    = Invoke-NativeCommand -FileName 'git' -Arguments @('config', '--file', '.gitmodules', "submodule.$name.url")
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
  $declared    = @(Get-DeclaredSubmoduleDetails)
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
      $pinnedCommitResult = Invoke-NativeCommand -FileName 'git' -Arguments @('ls-tree', 'HEAD', $p)
      $pinnedCommit = if ($pinnedCommitResult.ExitCode -eq 0 -and $pinnedCommitResult.StandardOutputLines.Count -gt 0) {
        if ($pinnedCommitResult.StandardOutputLines[0] -match '^\S+\s+commit\s+([0-9a-f]+)') { $Matches[1] } else { $null }
      } else { $null }

      $currentCommitResult = if (Test-Path $p) {
        Push-Location $p
        try { Invoke-NativeCommand -FileName 'git' -Arguments @('rev-parse', 'HEAD') }
        finally { Pop-Location }
      } else { $null }
      $currentCommit = if ($currentCommitResult -and $currentCommitResult.ExitCode -eq 0) { $currentCommitResult.StandardOutputLines[0] } else { $null }

      Write-Host "       $p" -ForegroundColor $script:brand.Muted

      if (-not $pinnedCommit -or -not $currentCommit) {
        Write-BabaStatus '[!]' "  Could not resolve commit pointers for '$p'." $script:brand.Muted
        continue
      }

      $aheadBehindResult = if (Test-Path $p) {
        Push-Location $p
        try { Invoke-NativeCommand -FileName 'git' -Arguments @('rev-list', '--left-right', '--count', "$pinnedCommit...HEAD") }
        finally { Pop-Location }
      } else { $null }

      if ($aheadBehindResult -and $aheadBehindResult.ExitCode -eq 0 -and $aheadBehindResult.StandardOutputLines.Count -gt 0) {
        $parts        = $aheadBehindResult.StandardOutputLines[0] -split '\s+'
        $parentBehind = [int]$parts[0]  # commits in pinned not in HEAD = submodule is behind pinned
        $subAhead     = [int]$parts[1]  # commits in HEAD not in pinned = submodule is ahead of pinned

        if ($subAhead -gt 0 -and $parentBehind -eq 0) {
          Write-BabaStatus '[!]' "  $subAhead new commit(s) in submodule not yet pinned by the parent." $script:brand.Warning
          Write-BabaStatus '[!]' '  To pin: stage and commit the submodule pointer in the parent repo.' $script:brand.Highlight
        } elseif ($parentBehind -gt 0 -and $subAhead -eq 0) {
          Write-BabaStatus '[!]' "  Submodule is $parentBehind commit(s) behind what the parent has pinned." $script:brand.Warning
          Write-BabaStatus '[!]' '  To fix: run option [4] Initialize & Update submodules.' $script:brand.Highlight
        } else {
          Write-BabaStatus '[!]' "  Diverged — $subAhead commit(s) ahead and $parentBehind commit(s) behind the pinned pointer." $script:brand.Warning
          Write-BabaStatus '[!]' '  To reset to pinned: run option [4] Initialize & Update submodules.' $script:brand.Highlight
          Write-BabaStatus '[!]' '  To pin current state: stage and commit the submodule pointer in the parent repo.' $script:brand.Highlight
        }
      } else {
        Write-BabaStatus '[!]' '  Pinned commit not reachable locally — submodule may need fetching.' $script:brand.Warning
        Write-BabaStatus '[!]' '  Run option [4] Initialize & Update submodules to fetch and align.' $script:brand.Highlight
      }
    }

    Write-Host ''
  }

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
    # Detached HEAD means the submodule is sitting on a raw commit SHA with no branch pointer.
    # With --merge in place, the usual cause is missing branch metadata in .gitmodules,
    # so git has no branch to merge into and falls back to a detached checkout.
    # Without a branch, git cannot push, pull, or know where to send new commits.
    # Option [10] will set the tracked branch in .gitmodules and then check it out automatically.
    Write-BabaStatus '[!]' 'Cause: no tracked branch is configured for the submodule, so git falls back to a detached commit checkout.' $script:brand.Muted
    Write-BabaStatus '[!]' 'Effect: pushes and pulls will fail; new commits may be lost on next update.' $script:brand.Warning
    Write-BabaStatus '[!]' 'Fix: run option [10] — it sets the tracked branch in .gitmodules and checks it out for you, then run option [4].' $script:brand.Highlight
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
  # Stage only .gitmodules and submodule pointer entries — never the full working tree.
  # git add -A would sweep up any unrelated staged/unstaged work into a generic chore commit.
  $subPaths = @(Get-DeclaredSubmodulePaths)
  $pathsToStage = @('.gitmodules') + $subPaths

  $result = Invoke-NativeCommand -FileName 'git' -Arguments @('status', '--porcelain')
  if ($result.StandardOutputLines.Count -gt 0) {
    Write-Host ''
    Write-BabaInfo 'Committing submodule changes...'
    foreach ($p in $pathsToStage) {
      if (Test-Path $p) {
        Invoke-GitCommand -Arguments @('add', '--', $p)
      }
    }
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
  $selected = Read-SubmoduleChoice -Paths $Paths -Prompt $Prompt
  if (-not $selected) { throw 'Invalid selection. Aborting.' }
  return $selected
}

function Remove-SubmoduleByPath {
  param([string] $Path)

  # Require explicit typed confirmation — deinit + git rm + Remove-Item are irreversible.
  Write-Host ''
  Write-BabaStatus '[!]' "You are about to permanently remove submodule '$Path'." $script:brand.Warning
  Write-BabaStatus '[!]' 'This will deinit it, remove it from the index, and delete its cached module data.' $script:brand.Warning
  Write-Host ''
  $confirm = (Read-Host "Type YES to confirm removal of '$Path'").Trim()
  if ($confirm -ne 'YES') {
    Write-BabaInfo "Aborted — '$Path' was not removed."
    return
  }

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
    $details     = @(Get-DeclaredSubmoduleDetails)
    $statusLines = @(Get-SubmoduleStatusLines)
    Write-SubmoduleTable -Details $details -StatusLines $statusLines
  }
  Pause-Baba
}

function Show-SubmoduleSummary {
  Show-BabaScreen -Title 'Submodule Summary'
  Invoke-InScope -WithDiagnosis {
    $details     = @(Get-DeclaredSubmoduleDetails)
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
    # Warn about any submodule with local uncommitted changes before --remote resets them.
    # git submodule update --remote hard-resets each sub to the remote branch tip,
    # discarding any uncommitted work inside the submodule without asking.
    $declared = @(Get-DeclaredSubmodulePaths)
    $dirtySubmodules = @($declared | Where-Object {
        $p = $_
        if (-not (Test-Path $p)) { return $false }
        Push-Location $p
        try {
          $statusResult = Invoke-NativeCommand -FileName 'git' -Arguments @('status', '--porcelain')
          return $statusResult.StandardOutputLines.Count -gt 0
        } finally {
          Pop-Location
        }
      })

    if ($dirtySubmodules.Count -gt 0) {
      Write-Host ''
      Write-BabaStatus '[!]' 'The following submodule(s) have uncommitted local changes:' $script:brand.Warning
      foreach ($p in $dirtySubmodules) {
        Write-Host "       $p" -ForegroundColor $script:brand.Muted
      }
      Write-BabaStatus '[!]' 'Running --remote will hard-reset these to the remote branch tip.' $script:brand.Warning
      Write-BabaStatus '[!]' 'Uncommitted work inside these submodules will be lost.' $script:brand.Failure
      Write-Host ''
      $confirm = (Read-Host 'Continue anyway? (y/N)').Trim()
      if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-BabaInfo 'Aborted. Commit or stash changes inside the submodule(s) first.'
        return
      }
    }

    # --merge integrates the remote tip into the tracked branch instead of detaching HEAD onto a raw SHA.
    # Without it, every update leaves submodules in detached HEAD state — on a commit with no branch pointer.
    Invoke-GitCommand -Arguments @('submodule', 'update', '--remote', '--init', '--recursive', '--merge')
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
  $path       = Read-Host 'Path'

  $branch    = $null
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
  $url  = Get-SubmoduleUrl -Path $path

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
    $missing  = @($declared | Where-Object { -not $_.Branch })

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

      # Write the tracked branch into .gitmodules so future updates know where to follow.
      Invoke-GitCommand -Arguments @('submodule', 'set-branch', '-b', $branch, '--', $sub.Path)

      # If the submodule directory exists and is currently in detached HEAD state,
      # check out the branch immediately so it has a real branch pointer right now —
      # not just after the next 'git submodule update'.
      if (Test-Path $sub.Path) {
        $headResult = Invoke-NativeCommand -FileName 'git' -ArgumentList @('symbolic-ref', '--quiet', 'HEAD') 2>$null
        Push-Location $sub.Path
        try {
          $headResult = Invoke-NativeCommand -FileName 'git' -Arguments @('symbolic-ref', '--quiet', 'HEAD')
          if ($headResult.ExitCode -ne 0) {
            Write-BabaInfo "Checking out branch '$branch' in detached submodule '$($sub.Path)'..."
            Invoke-GitCommand -Arguments @('checkout', $branch)
          }
        } finally {
          Pop-Location
        }
      }
    }

    # Also fix any submodule that already has a branch configured in .gitmodules but is still
    # sitting in detached HEAD — e.g. after a plain 'git submodule update' without --merge.
    $detached = @($declared | Where-Object {
        $p = $_.Path
        $_.Branch -and (Test-Path $p) -and (& {
            Push-Location $p
            try {
              $r = Invoke-NativeCommand -FileName 'git' -Arguments @('symbolic-ref', '--quiet', 'HEAD')
              return $r.ExitCode -ne 0
            } finally { Pop-Location }
          })
      })

    foreach ($sub in $detached) {
      Write-Host ''
      Write-BabaInfo "Submodule '$($sub.Path)' has tracked branch '$($sub.Branch)' but is detached — checking out..."
      Push-Location $sub.Path
      try {
        Invoke-GitCommand -Arguments @('checkout', $sub.Branch)
      } finally {
        Pop-Location
      }
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

  $path   = Select-SingleSubmodule -RegisteredPaths $paths
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

function Remove-StaleSubmodules {
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
    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = 'Inspect';                              Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '1';  Label = 'Show submodules';                      Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '2';  Label = 'Show submodule summary';               Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = '';                                      Hint = '';                                                            RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = 'Sync and update';                      Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '4';  Label = 'Initialize & Update submodules';       Hint = 'Missing, empty, or wrong commit? Run this.';                  RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '5';  Label = 'Sync URLs from .gitmodules';           Hint = 'Changed a URL in .gitmodules? Run this to apply it.';         RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = '';                                      Hint = '';                                                            RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = 'Manage';                               Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = '7';  Label = 'Add submodule';                        Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '8';  Label = 'Remove submodule';                     Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '9';  Label = 'Set tracked branch';                   Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '10'; Label = 'Fix missing tracked branches';         Hint = 'Also checks out the branch in any detached submodule.';       RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = '';                                      Hint = '';                                                            RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = 'Workflows (Auto-commit)';              Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '11'; Label = 'Update submodule URL';                 Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '12'; Label = 'Move/Rename submodule';                Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '13'; Label = 'Clean up submodules';                  Hint = '';                                                            RequiresSingleScope = $true  }
    [pscustomobject]@{ IsGroup = $false; Key = '14'; Label = 'Set ignore = dirty on all submodules'; Hint = 'Stop git from flagging submodule internal changes as dirty.'; RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $true;  Key = '';   Label = '';                                      Hint = '';                                                            RequiresSingleScope = $false }

    [pscustomobject]@{ IsGroup = $false; Key = 'r';  Label = 'Change scope';                         Hint = '';                                                            RequiresSingleScope = $false }
    [pscustomobject]@{ IsGroup = $false; Key = 'q';  Label = 'Quit';                                 Hint = '';                                                            RequiresSingleScope = $false }
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
}

function Invoke-MenuChoice {
  param([string] $Choice)

  switch ($Choice.Trim()) {
    '1'  { Show-Submodules }
    '2'  { Show-SubmoduleSummary }
    '4'  { Sync-SubmodulesFull }
    '5'  { Sync-Submodules }
    '7'  { Add-Submodule }
    '8'  { Remove-Submodule }
    '9'  { Set-SubmoduleBranch }
    '10' { Fix-MissingTrackedBranches }
    '11' { Update-SubmoduleUrl }
    '12' { Move-Submodule }
    '13' { Remove-StaleSubmodules }
    '14' { Set-SubmoduleIgnoreDirty }
    'r'  { Select-WorkingScope }
    'q'  { $script:quit = $true }
    default { Write-BabaFailure "Unknown option '$Choice'." }
  }
}



# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

Start-BabaDeluxeCli
