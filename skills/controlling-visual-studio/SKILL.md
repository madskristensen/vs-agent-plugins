---
name: controlling-visual-studio
description: >
  Control a running Visual Studio IDE instance from the agent's terminal. Use
  this skill whenever you need to make Visual Studio *do* something — open a
  file (optionally at a specific line), execute any IDE command
  (Build.BuildSolution, Edit.FormatDocument, File.SaveAll, Debug.Start, etc.),
  start or stop the debugger, enumerate or modify projects and documents, or
  otherwise programmatically operate the live VS instance the user is working
  in. Works by acquiring the `EnvDTE.DTE` COM automation object from the
  Windows Running Object Table (ROT) via PowerShell. Triggers on phrases such
  as "open in Visual Studio", "open file at line", "run VS command", "execute
  DTE", "build the solution", "save all in VS", "go to line in VS", "start
  debugging", or any task that requires controlling the live VS IDE.
  Windows-local only — does not work over SSH, WSL, dev containers, or
  Codespaces.
---

# Controlling Visual Studio from PowerShell

Control a running Visual Studio instance from a PowerShell terminal by
acquiring its `EnvDTE.DTE` COM automation object out of the Windows Running
Object Table (ROT).

> **Scope:** Windows-local only. Does **not** work over SSH, WSL, dev
> containers, or Codespaces — the ROT is per-Windows-session.

## Layout

```text
controlling-visual-studio/
├── SKILL.md                      ← this file
├── scripts/
│   ├── RotHelper.dll             ← prebuilt P/Invoke + ROT helper (~4 KB)
│   └── Connect-VsDte.ps1         ← bootstrap + high-level verbs
└── src/
    ├── RotHelper.cs              ← source for the DLL (auditable)
    └── build.ps1                 ← rebuild scripts/RotHelper.dll
```

## Usage

Dot-source `Connect-VsDte.ps1` once per pwsh session, then call the verbs.
Substitute the absolute path to the skill folder; the script knows its own
location (`$PSScriptRoot`) and finds `RotHelper.dll` next to it.

```powershell
. '<skill-dir>/scripts/Connect-VsDte.ps1'

# Open a file at a specific line
Open-VsFile -Path C:\repo\src\Foo.cs -Line 42

# Execute any registered DTE command
Invoke-VsCommand 'File.SaveAll'
Invoke-VsCommand 'View.ErrorList'
Invoke-VsCommand 'Edit.FormatDocument'

# Build, with timeout
Invoke-VsBuild -TimeoutSeconds 600   # async + poll
Invoke-VsBuild -WaitForBuildToFinish # synchronous

# Direct DTE access for anything not wrapped
$dte = Get-VsDte
$dte.Debugger.CurrentMode      # 1=Design, 2=Break, 3=Run
$dte.ActiveDocument.FullName
```

## How instance selection works

`Get-VsDte` picks the right Visual Studio instance using this priority:

1. **Parent-process walk** (`ProcessHelper.FindAncestorByName($PID,'devenv')`).
   Deterministic when pwsh was launched from VS's integrated terminal.
   Uses `NtQueryInformationProcess` — completes in milliseconds.
2. **Solution-name match** (`-SolutionMatch '*MySolution*'`) when not running
   under devenv.
3. **First instance found** — last-resort fallback.

The selected DTE is cached in a script-scoped variable; subsequent calls in
the same session reuse it (with a liveness check).

## Verbs exposed by `Connect-VsDte.ps1`

| Function              | Purpose                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `Get-VsDte`           | Acquire (or reuse cached) DTE for the host VS instance.          |
| `Open-VsFile`         | Open a file, optionally jumping to `Line`/`Column`.              |
| `Invoke-VsCommand`    | Call `DTE.ExecuteCommand(name, args)`.                           |
| `Invoke-VsBuild`      | Build the solution; sync or async-with-timeout.                  |
| `Invoke-WithComRetry` | Wrap any DTE call to retry `RPC_E_CALL_REJECTED` / `RETRYLATER`. |

Discover command names via `(Get-VsDte).Commands | ? Name | Select Name`.

## Common pattern — open every git-changed file

```powershell
. '<skill-dir>/scripts/Connect-VsDte.ps1'
$repoRoot = (& git rev-parse --show-toplevel).Trim()
git -C $repoRoot status --porcelain=v1 | ForEach-Object {
    $path = $_.Substring(3).Trim().Trim('"')
    if ($path -match ' -> ') { $path = $path -replace '^.* -> ','' }
    $full = Join-Path $repoRoot $path
    if (Test-Path -LiteralPath $full -PathType Leaf) { Open-VsFile -Path $full }
}
```

## Performance

Per-invocation wall time on a modern dev box (cold pwsh, warm DLL):

| Phase                       | Time            |
| --------------------------- | --------------- |
| `pwsh.exe` startup          | ~300–400 ms     |
| `Add-Type -Path` (load DLL) | ~60–110 ms      |
| Parent-process walk         | ~5 ms           |
| ROT enumeration             | ~25 ms          |
| First DTE call              | ~30 ms          |
| **Total**                   | **~450–550 ms** |

For lower latency (~5–10 ms per call) consider an in-VS named-pipe server
shipped as a VSIX. Out of scope for this skill.

## Rebuilding the DLL

If you change `src/RotHelper.cs`:

```powershell
pwsh -NoProfile -File '<skill-dir>/src/build.ps1'
```

This regenerates `scripts/RotHelper.dll`.

## Safety guidance

- **DTE is powerful.** It can build, debug, close unsaved documents, kill the
  debugger, save/overwrite files, and execute arbitrary registered commands.
  Treat it with the same caution as a terminal command.
- **Query before you mutate.** When unsure of state, read `$dte.Solution`,
  `$dte.Debugger.CurrentMode`, `$dte.ActiveDocument` first.
- **Don't auto-confirm destructive prompts.** Some `ExecuteCommand` calls
  raise UI prompts (e.g. closing dirty documents); never script `SendKeys` to
  dismiss them.
- **Modal commands block the IDE** (e.g. `Tools.Options`). Avoid invoking
  modal commands from automation unless the user explicitly asks.

## Troubleshooting

| Symptom                                      | Cause                                              | Fix                                                                 |
| -------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| ``RotHelper.dll not found``                  | Skill checked in without binary, or moved          | Run ``src/build.ps1`` to regenerate.                                |
| ROT empty but ``devenv.exe`` is running      | Integrity-level mismatch                           | Match elevation between VS and pwsh.                                |
| ``RPC_E_CALL_REJECTED`` / ``RETRYLATER``     | VS busy                                            | Wrap in ``Invoke-WithComRetry``.                                    |
| Wrong instance picked                        | Multiple devenvs, terminal not a child of VS       | Pass ``-SolutionMatch '*Name*'`` to ``Get-VsDte``.                  |
| ``MoveToLineAndOffset`` throws               | Active item is not a text document (e.g. designer) | ``Open-VsFile`` already best-efforts this; check ``Document.Type``. |
| Hangs in ``Invoke-VsBuild``                  | Long build, or VS prompting                        | Increase ``-TimeoutSeconds``; check VS UI for modal dialogs.        |
| Works in Windows PowerShell, fails in pwsh 7 | MTA apartment                                      | Launch with ``pwsh -STA`` for sessions making many DTE calls.       |
