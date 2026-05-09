# babadeluxe-scripts

<p align="left">
  <img src="https://img.shields.io/badge/license-EUPL%201.2-6a5acd?style=flat-rounded" alt="license">
  <img src="https://img.shields.io/badge/shell-PowerShell-8a2be2?style=flat-rounded" alt="PowerShell">
</p>

> **Central workspace and PowerShell automation scripts for the BabaDeluxe monorepo.** All other repos are cloned here as submodules so cross-repo tasks can be run from a single location.

## Overview

This repo is the operational hub of the BabaDeluxe ecosystem. It contains no application code — only automation scripts and Git submodule references to every other BabaDeluxe repository. Clone this once and you have the entire codebase in one place.

## Submodules

| Submodule | Description |
| :--- | :--- |
| `babadeluxe-vscode` | VS Code extension |
| `babadeluxe-webview` | Chat UI (Vue 3) |
| `babadeluxe-backend` | Backend / Socket.io gateway |
| `babadeluxe-shared` | Shared types, schemas, utilities |
| `babadeluxe-landing` | Landing page |
| `babadeluxe-xo-config` | Shared XO linting config |
| `agent-resources` | AI agent prompt and commit templates |

### Initial setup

Clone with all submodules initialised:

```bash
git clone --recurse-submodules https://github.com/BabaDeluxe/babadeluxe-scripts.git
```

Or initialise after cloning:

```bash
git submodule update --init --recursive
```

## Scripts

### `exec.ps1` — Universal task runner

Runs any npm/pnpm script across all (or selected) submodules in parallel or sequence.

```powershell
# Run `pnpm install` in all submodules
.\exec.ps1 -Script "install"

# Run `pnpm build` in specific repos
.\exec.ps1 -Script "build" -Repos babadeluxe-vscode,babadeluxe-webview
```

### `build-vscode-extension.ps1` — Extension build pipeline

Builds and packages the VS Code extension (`.vsix`) in one step. Runs the webview build first if needed, then compiles the extension.

```powershell
.\build-vscode-extension.ps1
```

### `update-shared.ps1` — Publish and sync `@babadeluxe/shared`

Builds and publishes a new version of `@babadeluxe/shared`, then updates the dependency in all consuming repos.

```powershell
.\update-shared.ps1
```

### `update-xo-config.ps1` — Publish and sync `@babadeluxe/xo-config`

Same workflow as `update-shared.ps1` but for the shared linting config.

```powershell
.\update-xo-config.ps1
```

### `reinstall.ps1` — Clean reinstall

Deletes all `node_modules` and lock files across submodules, then runs a fresh `pnpm install` everywhere.

```powershell
.\reinstall.ps1
```

### `manage-git-submodules.ps1` — Submodule Tamer

Interactive menu for all submodule operations. See the full guide below.

```powershell
.\manage-git-submodules.ps1
```

### `scan-git-leak.ps1` — Secret scanning

Scans the Git history of all submodules for accidentally committed secrets (API keys, tokens, credentials) using pattern matching.

```powershell
.\scan-git-leak.ps1
```

---

## 🦠 Submodule Tamer — Field Guide

> _"purple paws. sharp claws. civilized git control."_

Oi! Pull up a chair, chuck a snag on the barbie, and get comfy — because today you're gonna learn to wrangle git submodules like a true blue legend. This ain't a dry man page. This is **Osmosis Jones meets git internals**, and we're going straight to the bloodstream.

### The Three Laws — Don't Skip This, Mate

#### Law 1 — A submodule is a pointer, not a copy

Your parent repo doesn't store submodule code. It stores a **commit SHA** — a tiny sticky note saying _"that other repo? I want it at THIS exact commit."_ When that pointer drifts from what's actually checked out on disk, chaos reigns.

```
Parent repo (.gitmodules + index)
    │
    └──► babadeluxe-backend  @ bf034360...   ← pinned pointer
                │
                └──► actual files on disk    ← this might be somewhere else entirely
```

The Tamer's whole job is making sure the sticky note and the actual checkout agree with each other.

#### Law 2 — `--remote` follows the branch, not the pointer

Running `git submodule update --remote` tells git _"go fetch the latest commit on the tracked branch and check it out."_ This **moves the submodule forward** but does **not** update the parent's pointer. You still have to `git add <path>` and commit in the parent to pin it.

```
Before --remote:   parent says bf034360 ── sub is at bf034360  ✓ aligned
After  --remote:   parent still says bf034360 ── sub is now at d7a91c2  ✗ drifted
After  pin:        parent now says d7a91c2 ── sub is at d7a91c2  ✓ aligned again
```

#### Law 3 — Nested subs inherit their parent's state

If `babadeluxe-backend` is in **detached HEAD**, its children (`babadeluxe-backend/docs`, `babadeluxe-backend/agent-resources`) **cannot resolve commit pointers**. Fix the parent first — the kids sort themselves out. Every time. No exceptions.

---

### Your Daily Cycle

#### 🌅 Morning — fresh clone or pulling from upstream

```
Run option [4] — Initialize & Update submodules
```

This fires `git submodule update --remote --init --recursive`. It fetches, checks out, recurses into nested subs, and leaves everything aligned to the pinned pointer (or the latest on each tracked branch when `--remote` is passed).

#### 🛠️ During the day — you committed inside a submodule

You've been working in `babadeluxe-landing`. You committed there. Now the parent repo sees _"1 new commit not yet pinned."_

```powershell
# From the PARENT repo:
git add babadeluxe-landing
git commit -m "chore: pin babadeluxe-landing to latest"
```

Or use **option [11] Update submodule URL** if the URL changed — it auto-commits for you.

#### 🌇 End of day — verify nothing's drifted

```
Run option [1] — Show submodules
```

Green `[✓]` on all? Ship it. Any `[!]` warnings? Decide: pin the new commits or reset to pinned. Don't leave the repo ambiguous overnight.

---

### The Full Menu, Decoded

#### 🔍 Inspect

| Option | What it runs | When to use it |
|--------|-------------|----------------|
| `[1]` Show submodules | `git submodule status --recursive` + diagnosis | Every morning, or any time you're confused |
| `[2]` Show submodule summary | Same + `git submodule summary` | When you want the actual commit diff between pinned and current |

#### 🔄 Sync and Update

| Option | What it runs | When to use it |
|--------|-------------|----------------|
| `[4]` Initialize & Update | `git submodule update --remote --init --recursive` | Subs are missing, empty, wrong commit, or you just cloned |
| `[5]` Sync URLs | `git submodule sync --recursive` | You edited a URL in `.gitmodules` and need `.git/config` to catch up |

#### 🛠️ Manage

| Option | What it does | Single scope only? |
|--------|--------------|--------------------|
| `[7]` Add submodule | Prompts for URL + path + optional branch, runs `git submodule add` | ✅ Yes |
| `[8]` Remove submodule | Deinits, removes from index, clears `.git/modules` cache | ✅ Yes |
| `[9]` Set tracked branch | Runs `git submodule set-branch -b <branch>` | ✅ Yes |
| `[10]` Fix missing tracked branches | Auto-fetches branches from remote, lets you pick, writes to `.gitmodules` | ❌ Works across all scopes |

#### ⚡ Workflows (Auto-commit)

| Option | What it does |
|--------|-------------|
| `[11]` Update submodule URL | Changes the URL in `.gitmodules`, syncs to `.git/config`, auto-commits |
| `[12]` Move/Rename submodule | `git mv` then auto-commits |
| `[13]` Clean up submodules | Pick the ONE submodule to keep, nukes the rest, updates URL, auto-commits |
| `[14]` Set `ignore = dirty` on all | Adds `ignore = dirty` to every `.gitmodules` entry — stops git from screaming about uncommitted changes _inside_ subs |

---

### Diagnosis Messages, Decoded

#### `[?] N submodule(s) checked out at a different commit than recorded`

| What you see | What it means | What to do |
|---|---|---|
| `N new commit(s) in submodule not yet pinned by the parent` | Sub is **ahead** — `--remote` or local work pushed it forward | `git add <path> && git commit` in the parent |
| `Submodule is N commit(s) behind what the parent has pinned` | Sub is **behind** — someone else pinned newer, your checkout is stale | Run `[4]` |
| `Diverged — N ahead and M behind the pinned pointer` | Both the sub and the pinned commit have moved | Decide: pin current (`git add`) or reset to pinned (`[4]`) |

#### `[!] Could not resolve commit pointers for 'path'`

Almost always caused by the **parent being in detached HEAD**. Fix the parent (check out a real branch), then re-run `[4]`.

#### `[?] N submodule(s) are in detached HEAD state`

```powershell
cd <submodule-path>
git checkout main   # or whatever the tracked branch is
cd ..
# Then run option [4]
```

#### `warning: unable to rmdir 'babadeluxe-docs': Directory not empty`

Totally cosmetic. Not an error. Carry on.

---

### Nested Submodules — The Matryoshka Problem

```
babadeluxe-scripts/          ← parent repo, runs the Tamer
    babadeluxe-backend/      ← sub #1
        agent-resources/     ← sub #1a  (nested inside backend)
        docs/                ← sub #1b  (nested inside backend)
    babadeluxe-landing/      ← sub #2
    babadeluxe-webview/      ← sub #3
```

When `babadeluxe-backend` is in detached HEAD, its nested children report `"Could not resolve commit pointers"` — but **they're fine**. Their parent is the problem. Fix the parent, re-run `[4]` with `--recursive`, done.

---

### Team Rules & CI/CD

**Golden rules:**

1. Never leave a diverged submodule uncommitted overnight
2. Always pin after `--remote` — stage and commit new pointers in the parent immediately
3. Branch tracking is not optional — every sub must have `branch =` in `.gitmodules` (option `[10]` fixes missing ones)
4. `ignore = dirty` (option `[14]`) is useful locally, but keep CI able to see everything

**CI init step** — always use pinned, never `--remote` in CI:

```bash
git submodule update --init --recursive
```

**Red flags in PRs:**

| What you see in the diff | What it means |
|---|---|
| Submodule path shows a SHA change | Someone pinned a new version — check it's intentional |
| `.gitmodules` URL change with no `[5]` sync | Teammates' `.git/config` won't update until they run `[5]` |

---

### 🃏 Quick Reference Card

```
╔════════════════════════════════════════════════════════════╗
║  BabaDeluxe Submodule Tamer — Quick Reference Card       ║
╚════════════════════════════════════════════════════════════╝

DAILY FLOW
──────────
Morning:          [4]  Initialize & Update
Made sub changes: git add <path> && git commit  (in parent)
Verify state:     [1]  Show submodules

SOMETHING'S WRONG
──────────────────
Sub is empty/missing:                [4]
Sub on wrong commit:                 [4]
Sub is detached HEAD:                cd <sub> → git checkout <branch> → [4]
Nested sub says "can't resolve":     Fix parent detached HEAD first → [4]
URL changed in .gitmodules:          [5]
No tracked branch configured:        [10]

MANAGE
──────
Add a sub:        [7]   Remove a sub:   [8]
Set branch:       [9]   Update URL:     [11]
Move/rename:      [12]  Clean up all:   [13]
Stop dirty noise: [14]

DIAGNOSIS LEGEND
────────────────
[✓] clean — all good, have a Tim Tam
[~] info — FYI, no action needed
[?] warning — something needs attention
[!] action required — here's what to do
[✗] failure — something went wrong, read the error
```

---

## License

This project is licensed under the **European Union Public License 1.2 (EUPL-1.2)**. See [LICENSE](./LICENSE.md) for the full text.

---

**BabaDeluxe** — _Redefining the Future of Software Development._
