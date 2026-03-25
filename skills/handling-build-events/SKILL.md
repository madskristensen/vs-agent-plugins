---
name: handling-build-events
description: Subscribe to and handle build events in Visual Studio extensions. Use when the user asks how to listen for builds, react to build start or completion, detect build failures, track project build status, run code before or after a build, or use IVsUpdateSolutionEvents in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Handling Build Events in Visual Studio Extensions

When your extension needs to react to solution or project builds — for example, running analysis after a successful build, showing a notification on failure, or tracking build timing — you need to subscribe to build events. Visual Studio provides multiple mechanisms across its extensibility models.

Build events let extensions integrate into the development feedback loop — the moment code compiles, your extension can validate output, update UI, or trigger downstream processes. Without them, extensions must poll for build state, which is both wasteful and unreliable. The critical nuance is that build event handlers run on the UI thread, so long-running work in an event handler freezes the entire IDE.

**When to use this vs. alternatives:**
- React to build start, completion, or failure → **this skill**
- React to solution/project open, close, or rename → [vs-solution-events](../handling-solution-events/SKILL.md)
- Surface build errors/warnings in the Error List → [vs-error-list](../integrating-error-list/SKILL.md)
- Show progress during a long custom build step → [vs-background-tasks-progress](../showing-background-progress/SKILL.md)
- Intercept the Build command itself (before it runs) → [vs-command-intercept](../intercepting-commands/SKILL.md)

## Decision guide: which build event API to use

| Approach | Scope | Key feature |
|----------|-------|-------------|
| **VisualStudio.Extensibility** | Out-of-process | No dedicated build event API yet — use activation constraints or in-proc hybrid |
| **Community Toolkit** `VS.Events.BuildEvents` | In-process | Simple .NET events wrapping `IVsUpdateSolutionEvents2` |
| **VSSDK** `IVsUpdateSolutionEvents` / `IVsUpdateSolutionEvents2` | In-process | Full control — solution-level build begin/done, per-project begin/done, cancel |
| **DTE** `BuildEvents` (`EnvDTE`) | In-process (legacy) | COM automation events — `OnBuildBegin`, `OnBuildDone`, `OnBuildProjConfigBegin/Done` |

> **Recommendation:** For in-process extensions, use the **Community Toolkit** (`VS.Events.BuildEvents`) for the simplest subscription model. Fall back to **VSSDK `IVsUpdateSolutionEvents2`** when you need to cancel builds or access configuration-level details. The VisualStudio.Extensibility model does not yet have a dedicated build events API.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently provide a dedicated API for subscribing to build events from out-of-process extensions.

### Workaround: activation constraints

You can use `ActivationConstraint.SolutionState` or other activation constraints to control when your extension components become active based on solution state, but these are not build event callbacks.

### Workaround: in-proc hybrid extension

If you need to react to build events from an Extensibility extension, use an in-proc hybrid approach:

```csharp
[VisualStudioContribution]
internal class MyExtension : Extension
{
    public override ExtensionConfiguration? ExtensionConfiguration => new()
    {
        RequiresInProcessHosting = true,
    };
}
```

Then use the Toolkit or VSSDK APIs described in sections 2 and 3 below.

---

## 2. VSIX Community Toolkit (in-process)

The Toolkit wraps `IVsUpdateSolutionEvents2` into simple .NET events accessible via `VS.Events.BuildEvents`.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Subscribe to build events

```csharp
public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(
        CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await this.RegisterCommandsAsync();

        // Solution-level events
        VS.Events.BuildEvents.SolutionBuildStarted += OnSolutionBuildStarted;
        VS.Events.BuildEvents.SolutionBuildDone += OnSolutionBuildDone;
        VS.Events.BuildEvents.SolutionBuildCancelled += OnSolutionBuildCancelled;

        // Per-project events
        VS.Events.BuildEvents.ProjectBuildStarted += OnProjectBuildStarted;
        VS.Events.BuildEvents.ProjectBuildDone += OnProjectBuildDone;

        // Clean events
        VS.Events.BuildEvents.ProjectCleanStarted += OnProjectCleanStarted;
        VS.Events.BuildEvents.ProjectCleanDone += OnProjectCleanDone;

        // Configuration change events
        VS.Events.BuildEvents.ProjectConfigurationChanged += OnProjectConfigChanged;
        VS.Events.BuildEvents.SolutionConfigurationChanged += OnSolutionConfigChanged;
    }

    private void OnSolutionBuildStarted(object sender, EventArgs e)
    {
        // Solution build has started
    }

    private void OnSolutionBuildDone(bool succeeded)
    {
        // Solution build complete — 'succeeded' is true if no projects failed
        if (!succeeded)
        {
            // Show a notification about build failure
        }
    }

    private void OnSolutionBuildCancelled()
    {
        // User cancelled the build
    }

    private void OnProjectBuildStarted(Project? project)
    {
        // A specific project started building
        string? name = project?.Name;
    }

    private void OnProjectBuildDone(ProjectBuildDoneEventArgs args)
    {
        // A specific project finished building
        string? name = args.Project?.Name;
        bool success = args.IsSuccessful;
    }

    private void OnProjectCleanStarted(Project? project)
    {
        // A project clean operation started
    }

    private void OnProjectCleanDone(ProjectBuildDoneEventArgs args)
    {
        // A project clean operation completed
    }

    private void OnProjectConfigChanged(Project? project)
    {
        // Active project configuration changed (e.g., Debug → Release)
    }

    private void OnSolutionConfigChanged()
    {
        // Active solution configuration changed
    }
}
```

### Available Toolkit build events

| Event | Signature | When fired |
|-------|-----------|------------|
| `SolutionBuildStarted` | `EventHandler` | Before any build actions begin |
| `SolutionBuildDone` | `Action<bool>` | After all builds complete (`true` = all succeeded) |
| `SolutionBuildCancelled` | `Action` | When the user cancels the build |
| `ProjectBuildStarted` | `Action<Project?>` | When a specific project begins building |
| `ProjectBuildDone` | `Action<ProjectBuildDoneEventArgs>` | When a specific project finishes building |
| `ProjectCleanStarted` | `Action<Project?>` | When a project clean begins |
| `ProjectCleanDone` | `Action<ProjectBuildDoneEventArgs>` | When a project clean finishes |
| `ProjectConfigurationChanged` | `Action<Project?>` | When a project's active configuration changes |
| `SolutionConfigurationChanged` | `Action` | When the solution configuration changes |

### Example: show an InfoBar on build failure

```csharp
VS.Events.BuildEvents.SolutionBuildDone += async (bool succeeded) =>
{
    if (!succeeded)
    {
        var model = new InfoBarModel(
            "Build failed. Check the Error List for details.",
            KnownMonikers.StatusError,
            isCloseButtonVisible: true);

        InfoBar infoBar = await VS.InfoBar.CreateAsync(model);
        await infoBar.TryShowInfoBarUIAsync();
    }
};
```

### Example: track build timing

```csharp
private System.Diagnostics.Stopwatch? _buildTimer;

VS.Events.BuildEvents.SolutionBuildStarted += (s, e) =>
{
    _buildTimer = System.Diagnostics.Stopwatch.StartNew();
};

VS.Events.BuildEvents.SolutionBuildDone += async (bool succeeded) =>
{
    _buildTimer?.Stop();
    string status = succeeded ? "succeeded" : "failed";
    await VS.StatusBar.ShowMessageAsync(
        $"Build {status} in {_buildTimer?.Elapsed.TotalSeconds:F1}s");
};
```

---

## 3. VSSDK (in-process, legacy)

Use `IVsUpdateSolutionEvents2` with `IVsSolutionBuildManager` to receive build events. This gives you full control, including the ability to cancel a build in `UpdateSolution_Begin`.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Implement IVsUpdateSolutionEvents2

```csharp
public sealed class MyPackage : AsyncPackage, IVsUpdateSolutionEvents2
{
    private uint _buildEventsCookie;
    private IVsSolutionBuildManager2? _buildManager;

    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        _buildManager = (IVsSolutionBuildManager2)
            await GetServiceAsync(typeof(SVsSolutionBuildManager));
        _buildManager.AdviseUpdateSolutionEvents(this, out _buildEventsCookie);
    }

    protected override void Dispose(bool disposing)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        if (_buildEventsCookie != 0 && _buildManager != null)
        {
            _buildManager.UnadviseUpdateSolutionEvents(_buildEventsCookie);
            _buildEventsCookie = 0;
        }

        base.Dispose(disposing);
    }

    // --- Solution-level events ---

    public int UpdateSolution_Begin(ref int pfCancelUpdate)
    {
        // Called before any build actions. Set pfCancelUpdate = 1 to cancel.
        return VSConstants.S_OK;
    }

    public int UpdateSolution_Done(int fSucceeded, int fModified, int fCancelCommand)
    {
        // fSucceeded: 1 if no builds failed
        // fModified: 1 if any build succeeded
        // fCancelCommand: 1 if the build was cancelled
        return VSConstants.S_OK;
    }

    public int UpdateSolution_Cancel()
    {
        // Build was cancelled by the user
        return VSConstants.S_OK;
    }

    // --- Per-project events ---

    public int UpdateProjectCfg_Begin(
        IVsHierarchy pHierProj, IVsCfg pCfgProj,
        IVsCfg pCfgSln, uint dwAction, ref int pfCancel)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        // dwAction values:
        //   0x010000 = Build
        //   0x100000 = Clean
        //   0x410000 = Rebuild (clean + build)

        pHierProj.GetProperty(
            VSConstants.VSITEMID_ROOT,
            (int)__VSHPROPID.VSHPROPID_Name,
            out object nameObj);
        string projectName = nameObj as string ?? "Unknown";

        return VSConstants.S_OK;
    }

    public int UpdateProjectCfg_Done(
        IVsHierarchy pHierProj, IVsCfg pCfgProj,
        IVsCfg pCfgSln, uint dwAction, int fSuccess, int fCancel)
    {
        // fSuccess: 1 if the project built successfully
        return VSConstants.S_OK;
    }

    // --- Events not typically needed ---

    public int OnActiveProjectCfgChange(IVsHierarchy pIVsHierarchy)
    {
        // Active project or solution configuration changed
        // pIVsHierarchy == null means solution-level config change
        return VSConstants.S_OK;
    }

    public int UpdateSolution_StartUpdate(ref int pfCancelUpdate)
    {
        return VSConstants.S_OK;
    }
}
```

### Alternative: DTE BuildEvents (COM automation)

The older `EnvDTE.BuildEvents` interface provides COM-style events. Keep a strong reference to the `BuildEvents` object to prevent garbage collection of the COM event sink.

```csharp
public sealed class MyPackage : AsyncPackage
{
    private EnvDTE.BuildEvents? _buildEvents; // Must keep a reference!

    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        DTE2 dte = (DTE2)await GetServiceAsync(typeof(EnvDTE.DTE));
        _buildEvents = dte.Events.BuildEvents;

        _buildEvents.OnBuildBegin += OnBuildBegin;
        _buildEvents.OnBuildDone += OnBuildDone;
        _buildEvents.OnBuildProjConfigBegin += OnBuildProjConfigBegin;
        _buildEvents.OnBuildProjConfigDone += OnBuildProjConfigDone;
    }

    private void OnBuildBegin(
        EnvDTE.vsBuildScope scope, EnvDTE.vsBuildAction action)
    {
        // scope: vsBuildScopeSolution, vsBuildScopeProject, vsBuildScopeBatch
        // action: vsBuildActionBuild, vsBuildActionRebuildAll, vsBuildActionClean, vsBuildActionDeploy
    }

    private void OnBuildDone(
        EnvDTE.vsBuildScope scope, EnvDTE.vsBuildAction action)
    {
        // Build completed
    }

    private void OnBuildProjConfigBegin(
        string project, string projectConfig, string platform, string solutionConfig)
    {
        // A specific project configuration started building
    }

    private void OnBuildProjConfigDone(
        string project, string projectConfig, string platform,
        string solutionConfig, bool success)
    {
        // A specific project configuration finished building
        // 'success' indicates whether it built successfully
    }
}
```

> **Important:** Always keep a field reference to the `BuildEvents` (or any DTE event) object. The COM runtime will garbage-collect the event sink if the only reference is local, causing events to silently stop firing.

---

## Guidelines

- **Do** unsubscribe from build events (`UnadviseUpdateSolutionEvents`) in `Dispose` when using the VSSDK approach to prevent leaks.
- **Do** keep a strong reference to DTE event objects to prevent COM garbage collection.
- **Do** use `ThreadHelper.ThrowIfNotOnUIThread()` in event handlers that access `IVsHierarchy` properties.
- **Don't** perform long-running work synchronously in build event handlers — queue it on a background thread.
- **Don't** use `EnvDTE.BuildEvents` in new extensions — prefer the Toolkit or `IVsUpdateSolutionEvents2`.
- **Prefer** `VS.Events.BuildEvents` (Toolkit) for the simplest subscription model.
- **Prefer** `IVsUpdateSolutionEvents2` over `IVsUpdateSolutionEvents` — it adds per-project `UpdateProjectCfg_Begin`/`Done` methods.
- **Note:** The `dwAction` parameter in `UpdateProjectCfg_Begin/Done` distinguishes between Build (`0x010000`), Clean (`0x100000`), and Rebuild (`0x410000`).

## Troubleshooting

- **Build events stop firing after a while:** The COM runtime garbage-collected your event sink because you only held a local reference. Store the `BuildEvents` object (DTE) or the advise cookie (`IVsSolutionBuildManager`) in a class-level field.
- **Event handler throws `COMException` or `RPC_E_WRONG_THREAD`:** You're accessing `IVsHierarchy` or other COM objects from a background thread. Add `ThreadHelper.ThrowIfNotOnUIThread()` at the top of your handler.
- **`UpdateSolution_Done` reports success but a project actually failed:** Check `fSucceeded` and `fCanceled` parameters carefully. `fSucceeded == 1` means no errors; `fSucceeded == 0` with `fCanceled == 0` means there were failures.
- **Per-project events not available:** You're implementing `IVsUpdateSolutionEvents` (v1). Switch to `IVsUpdateSolutionEvents2` which adds `UpdateProjectCfg_Begin` and `UpdateProjectCfg_Done`.
- **Events fire but `IVsSolutionBuildManager` returns stale state:** Build state queries during event callbacks may not reflect the final state. If you need post-build results, defer your logic with `await Task.Yield()` or queue it after the callback returns.

## What NOT to do

> **Do NOT** perform long-running work synchronously in build event handlers. They run on the UI thread — blocking causes the IDE to freeze. Queue background work with `JoinableTaskFactory.RunAsync` and return from the handler immediately.

> **Do NOT** use `EnvDTE.BuildEvents` in new extensions. It's a legacy COM automation API that requires careful reference management (COM garbage collection) and doesn't integrate with the modern threading model. Use `VS.Events.BuildEvents` (Toolkit) or `IVsUpdateSolutionEvents2` (VSSDK).

> **Do NOT** forget to unsubscribe from build events (`UnadviseUpdateSolutionEvents`) when your package is disposed. Leaked event subscriptions cause memory leaks and can crash if the callback fires after your objects are disposed.

> **Do NOT** hold only a local reference to DTE event objects. The COM runtime will garbage-collect the event sink, causing events to silently stop firing. Store the event object in a class-level field.

## See also

- [vs-solution-events](../handling-solution-events/SKILL.md) — solution/project lifecycle events (open, close, rename)
- [vs-error-list](../integrating-error-list/SKILL.md) — surfacing build errors in the Error List
- [vs-command-intercept](../intercepting-commands/SKILL.md) — intercepting the Build command before it executes
- [vs-async-threading](../handling-async-threading/SKILL.md) — proper async patterns in event handlers
- [vs-background-tasks-progress](../showing-background-progress/SKILL.md) — showing progress during build-related work
