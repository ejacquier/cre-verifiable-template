# Testing Plan: CRE Verifiable Build Template

## Context

This template provides a reproducible build system for CRE TypeScript workflows. The build runs via `cre workflow hash workflow` which invokes `make build`, which runs `docker build` on the host, which runs `make build` again inside a Linux container to compile the workflow to WASM.

The goal is to ensure every failure mode surfaces a clear, actionable error message so users can resolve issues without assistance.

### Architecture

```
User runs: cre workflow hash workflow --public_key <addr> --target production-settings
  → cre CLI invokes: make build (in workflow/ directory)
    → Host Makefile (else branch): docker build --platform=linux/amd64 ...
      → Dockerfile:
        1. COPY package.json bun.lock ./
        2. RUN bun install --frozen-lockfile
        3. COPY . .
        4. RUN make build (with CRE_DOCKER_BUILD_IMAGE=true)
          → Docker Makefile (ifeq branch):
            a. Check bun.lock exists
            b. mkdir -p wasm
            c. bun cre-compile main.ts wasm/workflow.wasm
      → Export wasm/ to host
```

### Files Under Test

- `workflow/Makefile` — build orchestration, cross-platform
- `workflow/Dockerfile` — containerized build environment
- `workflow/package.json` — dependencies
- `workflow/bun.lock` — locked dependency tree
- `workflow/main.ts` — workflow entry point
- `workflow/config.production.json` / `config.staging.json` — workflow configs
- `workflow/workflow.yaml` — workflow definition
- `project.yaml` / `secrets.yaml` — project-level CRE config

---

## Test Matrix

### Platform Coverage

Every test case must be executed on:

| Platform | Shell | Make binary | Notes |
|----------|-------|-------------|-------|
| **Windows (PowerShell)** | cmd.exe / PowerShell | GNU Make via Chocolatey (Windows-native) | Most restrictive — no POSIX shell, no `/dev/null`, no `[ ]` syntax |
| **Windows (Git Bash)** | MSYS2 sh.exe | Same Chocolatey make, but SHELL resolves to sh.exe | Works but different from PowerShell |
| **macOS (zsh/bash)** | /bin/zsh or /bin/bash | Xcode make or Homebrew make | Standard POSIX environment |

> **Critical constraint**: The Makefile `else` branch (host path) must ONLY use plain commands (`docker build`, `echo`). Any POSIX shell syntax (`/dev/null`, `||`, `[ ]`, `@#` comments) will crash Windows-native make.

---

## Section 1: Happy Path

### T1.1 — Full build and hash (production)

```bash
cre workflow hash workflow --public_key 0xb0f2D38245dD6d397ebBDB5A814b753D56c30715 --target production-settings
```

**Expected**: Build succeeds, outputs Binary hash, Config hash, Workflow hash.

**Verify**:
- [ ] Works on Windows PowerShell
- [ ] Works on Windows Git Bash
- [ ] Works on macOS
- [ ] Binary hash is identical across all three platforms
- [ ] Config hash is identical across all three platforms
- [ ] Workflow hash is identical across all three platforms

### T1.2 — Full build and hash (staging)

```bash
cre workflow hash workflow --public_key 0xb0f2D38245dD6d397ebBDB5A814b753D56c30715 --target staging-settings
```

**Expected**: Build succeeds. Config hash differs from production (different config file). Binary hash is identical to T1.1.

### T1.3 — Repeated builds produce identical hashes

Run T1.1 three times in a row on the same platform.

**Expected**: All three runs produce the exact same Binary hash, Config hash, and Workflow hash.

### T1.4 — Clean clone produces identical hash

```bash
git clone https://github.com/ejacquier/cre-verifiable-template.git /tmp/fresh-clone
cd /tmp/fresh-clone
cre workflow hash workflow --public_key 0xb0f2D38245dD6d397ebBDB5A814b753D56c30715 --target production-settings
```

**Expected**: Workflow hash matches T1.1 exactly. This validates the third-party verification flow.

### T1.5 — Build from path with spaces

Clone or copy the repo to a path containing spaces (e.g. `C:\Users\emman\My Projects\cre-verifiable-template`).

```bash
cre workflow hash workflow --public_key 0xb0f2D38245dD6d397ebBDB5A814b753D56c30715 --target production-settings
```

**Expected**: Build succeeds. `$(CURDIR)` is quoted in the Makefile to handle this.

---

## Section 2: Missing Files

### T2.1 — Missing `bun.lock`

**Setup**: Delete `workflow/bun.lock`

**Expected error at Dockerfile step** (COPY fails):
```
"/bun.lock": not found
```

**Current UX**: Raw Docker checksum error with internal hash — **BAD**. User has no idea what to do.

**Ideal UX**:
```
✗ Build failed: bun.lock is missing in workflow/
  Run 'cd workflow && make lock' to generate it, or ask the workflow author to include their lockfile.
```

**Where to fix**: `cre` CLI should pre-flight check for `bun.lock` before invoking make. The Makefile also has a secondary check inside the Docker branch as a safety net.

**Verify**:
- [ ] Error message is clear and actionable
- [ ] Suggests `make lock` as the fix
- [ ] Works on all 3 platforms

### T2.2 — Missing `package.json`

**Setup**: Delete `workflow/package.json`

**Expected error at Dockerfile step** (COPY fails):
```
"/package.json": not found
```

**Current UX**: Raw Docker checksum error — **BAD**. Cryptic hash in the error message.

**Ideal UX**:
```
✗ Build failed: package.json not found in workflow/
  This file is required. Ensure your workflow directory contains a valid package.json.
```

**Where to fix**: `cre` CLI pre-flight check.

### T2.3 — Missing `main.ts`

**Setup**: Delete `workflow/main.ts`

**Expected error inside Docker**:
```
❌ File not found: /app/main.ts
error: "cre-compile" exited with code 1
make: *** [Makefile:10: build] Error 1
```

**Current UX**: The bun error `❌ File not found: /app/main.ts` is decent, but wrapped in Docker/make noise.

**Ideal UX**:
```
✗ Build failed: main.ts not found in workflow/
  The workflow entry point is missing. Check that main.ts exists and is not in .dockerignore.
```

**Where to fix**: `cre` CLI pre-flight check, or parse the Docker output to extract the meaningful line.

### T2.4 — Missing `Dockerfile`

**Setup**: Delete `workflow/Dockerfile`

**Expected error**:
```
failed to read dockerfile: open Dockerfile: no such file or directory
```

**Current UX**: Reasonably clear but lacks guidance.

**Ideal UX**:
```
✗ Build failed: Dockerfile not found in workflow/
  The Dockerfile is required for reproducible builds. Restore it from the template.
```

**Where to fix**: `cre` CLI pre-flight check.

### T2.5 — Missing `Makefile`

**Setup**: Delete `workflow/Makefile`

**Expected error**:
```
make: *** No rule to make target 'build'. Stop.
```

**Current UX**: Confusing if user doesn't know about the Makefile — **BAD**.

**Ideal UX**:
```
✗ Build failed: Makefile not found in workflow/
  The Makefile is required for the build. Restore it from the template.
```

**Where to fix**: `cre` CLI pre-flight check (check Makefile exists before invoking make).

### T2.6 — Missing `config.production.json` (when targeting production)

**Setup**: Delete `workflow/config.production.json`

**Expected**: Determine what happens — does `cre` fail? Does it build but produce an empty config hash?

**Ideal UX**:
```
✗ Config file not found: workflow/config.production.json
  The --target production-settings requires this file. Check that it exists.
```

**Where to fix**: `cre` CLI, before or after build.

### T2.7 — Missing `workflow.yaml`

**Setup**: Delete `workflow/workflow.yaml`

**Expected**: Determine what happens.

**Ideal UX**: Clear error indicating the workflow definition is missing.

---

## Section 3: Corrupted / Mismatched Files

### T3.1 — Corrupted `bun.lock` (content doesn't match package.json)

**Setup**: Replace `workflow/bun.lock` content with `corrupted`

**Expected**: `bun install --frozen-lockfile` inside Docker should fail because the lockfile doesn't match `package.json`.

**Actual (KNOWN ISSUE)**: Docker may use a cached layer from a previous successful `bun install`, causing the build to **succeed silently with the wrong lockfile**. This is a Docker caching issue.

**Verify**:
- [ ] With `--no-cache`: Does bun correctly reject the corrupted lockfile?
- [ ] Without `--no-cache`: Does Docker use a stale cached layer and silently succeed?
- [ ] If silent success: is this acceptable or does it need a fix?

**Possible fix**: Add a checksum validation step in the Makefile Docker branch, or document that users should `docker builder prune` when debugging lockfile issues.

### T3.2 — `package.json` with wrong dependency versions

**Setup**: Change `@chainlink/cre-sdk` version in package.json to a different version.

**Expected**: `bun install --frozen-lockfile` fails because lockfile doesn't match.

**Verify**:
- [ ] Error message from bun is clear
- [ ] Suggests running `bun install` to regenerate the lockfile

### T3.3 — Syntax error in `main.ts`

**Setup**: Add invalid TypeScript to `main.ts`

**Expected**: `bun cre-compile` fails with a compilation error.

**Verify**:
- [ ] Error message includes the file name and line number
- [ ] Error is readable through the Docker output wrapping

### T3.4 — Invalid JSON in config files

**Setup**: Break JSON syntax in `config.production.json`

**Expected**: `cre` fails when parsing the config.

**Verify error quality**: Does it point to the specific file and the JSON parse error location?

### T3.5 — Wrong workflow.yaml schema

**Setup**: Add invalid fields or remove required fields from `workflow.yaml`

**Expected**: `cre` should validate the schema and fail clearly.

---

## Section 4: Environment Issues

### T4.1 — Docker not running

**Setup**: Stop Docker Desktop.

**Expected error from `docker build`**:
```
error during connect: ... dial tcp ...: connection refused
```

**Current UX**: Raw Docker connection error — **BAD**. No mention of Docker Desktop.

**Ideal UX**:
```
✗ Build failed: Cannot connect to Docker.
  Please start Docker Desktop and try again.
```

**Where to fix**: `cre` CLI — check Docker connectivity before invoking make.

**Verify**:
- [ ] Windows PowerShell
- [ ] Windows Git Bash
- [ ] macOS

### T4.2 — Docker running but no internet (image not cached)

**Setup**: Disconnect network, clear Docker image cache (`docker rmi <bun-image>`).

**Expected**: Docker fails to pull the base image.

**Verify**: Error message indicates a network/pull issue, not a cryptic hash mismatch.

### T4.3 — Docker running but low disk space

**Setup**: Fill disk to near capacity.

**Expected**: Docker build fails during layer creation.

**Verify**: Error is not mistaken for a build/code issue.

### T4.4 — `cre` CLI not installed

**Setup**: Remove `cre` from PATH.

**Expected**: `cre: command not found`

**Verify**: Not a template issue, but document in README that CRE CLI is required.

### T4.5 — `make` not installed

**Setup**: Remove `make` from PATH.

**Expected**: `make: command not found`

**Ideal UX from cre CLI**:
```
✗ Build failed: 'make' is not installed.
  Install it with: choco install make (Windows) or xcode-select --install (macOS)
```

**Where to fix**: `cre` CLI pre-flight check.

### T4.6 — Wrong `make` version (MSYS vs Chocolatey on Windows)

**Setup**: Have both MSYS make and Chocolatey make installed.

**Verify**: Build works regardless of which `make` is first on PATH, because the Makefile avoids POSIX syntax in the host path.

### T4.7 — Docker platform mismatch (ARM Mac building linux/amd64)

**Setup**: Run on Apple Silicon Mac.

**Expected**: `--platform=linux/amd64` forces emulated build. Should work but may be slow.

**Verify**:
- [ ] Build succeeds
- [ ] Binary hash matches x86 machines (critical for reproducibility)
- [ ] If hash differs on ARM, document this limitation

---

## Section 5: Cross-Platform Makefile Robustness

These tests specifically validate that the Makefile works with Windows-native make (Chocolatey) which has no POSIX shell.

### T5.1 — No POSIX syntax in host path

**Audit the Makefile `else` branch** (lines that run on the host):

- [ ] No `@#` comments in recipes (Windows make tries to execute `#` via CreateProcess)
- [ ] No `[ ]` test syntax
- [ ] No `/dev/null` redirects
- [ ] No `||` or `&&` chaining
- [ ] No `if/then/fi` blocks
- [ ] Only plain commands: `docker build`, `echo`

### T5.2 — Shell comments only in Docker branch

**Verify**: All `@if`, `@#`, `[ ]` syntax only appears inside `ifeq ($(CRE_DOCKER_BUILD_IMAGE),true)` which runs inside Linux Docker.

### T5.3 — `$(CURDIR)` with spaces

**Verify**: `$(CURDIR)` is quoted with double quotes everywhere it appears in the `else` branch.

### T5.4 — `SHELL` directive not set

**Verify**: The Makefile does NOT set `SHELL`. This is intentional:
- On Windows, make uses its default (usually `cmd.exe` or `sh.exe` from Git)
- Inside Docker (Linux), make uses `/bin/sh`
- Setting SHELL to a Windows path breaks Docker; setting it to a Linux path breaks Windows

---

## Section 6: Verification Flow (Third-Party Auditor)

### T6.1 — Verifier on different OS than deployer

**Setup**: Deploy from macOS, verify from Windows (or vice versa).

**Expected**: Workflow hash is identical.

**This is the core promise of the template.** If this fails, reproducible builds are broken.

### T6.2 — Verifier with different Docker version

**Setup**: Use Docker Desktop 4.x on one machine, Docker Desktop 5.x on another.

**Expected**: Same hash. The pinned base image digest ensures identical container environment.

### T6.3 — Verifier with stale Docker cache

**Setup**: Verifier has previously built a different version of this workflow.

**Expected**: New build produces correct hash. Docker should detect changed files at `COPY . .` and rebuild.

**Verify**: If cache causes wrong hash, document that `docker builder prune` is needed.

### T6.4 — Verifier clones from GitHub (CRLF handling)

**Setup**: Clone on Windows (which may convert LF to CRLF via git autocrlf).

**Expected**: Hash still matches. Docker build runs inside Linux where line endings are LF.

**RISK**: If `COPY . .` sends CRLF files into the container, the compiled WASM could differ.

**Verify**:
- [ ] Clone with `core.autocrlf=true` — does hash match?
- [ ] Clone with `core.autocrlf=false` — does hash match?
- [ ] If they differ, add a `.gitattributes` file to enforce LF for all source files

### T6.5 — Wrong public key

**Setup**: Use a different `--public_key` than the deployer.

**Expected**: Workflow hash differs (public key is an input to the hash). Binary and Config hashes should be the same.

**Verify**: Error messaging helps the user understand that the public key must match the deployer.

---

## Section 7: Edge Cases

### T7.1 — Node modules checked into git

**Setup**: Remove `node_modules` from `.dockerignore`, add a `node_modules/` dir.

**Expected**: Build should still work (bun install inside Docker overwrites). But build context size may be huge.

**Verify**: `.dockerignore` includes `node_modules`.

### T7.2 — Stale `wasm/` directory from previous build

**Setup**: Have a `wasm/workflow.wasm` from a previous build in the workflow directory.

**Expected**: `.dockerignore` excludes `wasm` and `*.wasm`, so old artifacts don't enter the Docker context.

**Verify**: `.dockerignore` includes both `wasm` and `*.wasm`.

### T7.3 — Very large workflow (many dependencies)

**Setup**: Add many dependencies to package.json.

**Expected**: Build takes longer but succeeds. `bun install --frozen-lockfile` should handle this.

### T7.4 — Workflow with no config file

**Setup**: Run without `--target` flag.

**Expected**: Determine behavior. Should it default to something, or error clearly?

### T7.5 — Running `cre workflow hash` from wrong directory

**Setup**: Run from inside `workflow/` instead of the project root.

```bash
cd workflow
cre workflow hash . --public_key 0x... --target production-settings
```

**Expected**: Either works, or gives a clear error about expected directory structure.

---

## Section 8: Recommended Improvements

Based on all test results, prioritize fixes in this order:

### Priority 1: `cre` CLI Pre-flight Checks
Add checks before invoking make:
1. Docker is running (`docker info`)
2. `make` is installed
3. Required files exist: `Makefile`, `Dockerfile`, `package.json`, `bun.lock`, `main.ts` (or entry point from workflow.yaml)
4. Config file for the specified `--target` exists

Each check should produce a clean single-line error with a suggested fix.

### Priority 2: `.gitattributes` for Line Ending Safety
```
* text=auto
*.ts text eol=lf
*.json text eol=lf
*.yaml text eol=lf
*.lock text eol=lf
Makefile text eol=lf
Dockerfile text eol=lf
```

This ensures CRLF on Windows doesn't affect the Docker build context.

### Priority 3: Error Message Parsing in `cre` CLI
When `make build` or `docker build` fails, parse stdout/stderr for known error patterns and surface a clean message:

| Pattern | User-friendly message |
|---------|----------------------|
| `not found` + `COPY` | "File X is missing from your workflow directory" |
| `No rule to make target` | "Makefile is missing or corrupted" |
| `connection refused` / `Cannot connect` | "Docker is not running. Start Docker Desktop." |
| `frozen-lockfile` + `error` | "bun.lock is out of sync with package.json. Run 'bun install' to update." |
| `File not found: /app/main.ts` | "main.ts is missing from your workflow directory" |

### Priority 4: Documentation
- Add troubleshooting section to README with common errors and fixes
- Document that Windows users need Docker Desktop + Chocolatey make
- Document that ARM Mac builds use emulation and may be slower

---

## Execution Instructions

For the tester (Claude instance or human):

1. **Clone the repo**: `git clone https://github.com/ejacquier/cre-verifiable-template.git`
2. **Run each test case** on all specified platforms
3. **Record**: actual error message, expected error message, pass/fail, platform
4. **For each failure**: note whether the fix belongs in the Makefile, Dockerfile, cre CLI, or documentation
5. **Output**: a results table and a prioritized list of issues to fix

The test command for happy path is:
```bash
cre workflow hash workflow --public_key 0xb0f2D38245dD6d397ebBDB5A814b753D56c30715 --target production-settings
```

Expected hash (baseline):
```
Binary hash:   03c77e16354e5555f9a74e787f9a6aa0d939e9b8e4ddff06542b7867499c58ea
Config hash:   3bdaebcc2f639d77cb248242c1d01c8651f540cdbf423d26fe3128516fd225b6
Workflow hash: 001de36f9d689b57f2e4f1eaeda1db5e79f7991402e3611e13a5c930599c2297
```
