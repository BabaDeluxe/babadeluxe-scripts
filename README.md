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

### `manage-git-submodules.ps1` — Submodule management

Helper for common submodule operations: updating pointers, pulling latest, checking status across all repos.

```powershell
.\manage-git-submodules.ps1
```

### `scan-git-leak.ps1` — Secret scanning

Scans the Git history of all submodules for accidentally committed secrets (API keys, tokens, credentials) using pattern matching.

```powershell
.\scan-git-leak.ps1
```

## License

This project is licensed under the **European Union Public License 1.2 (EUPL-1.2)**. See [LICENSE](./LICENSE.md) for the full text.

---

**BabaDeluxe** — _Redefining the Future of Software Development._
