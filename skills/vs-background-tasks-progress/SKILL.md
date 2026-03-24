---
name: vs-background-tasks-progress
description: Show progress for background tasks in Visual Studio extensions. Use when the user asks how to display a progress bar, use the Task Status Center, show status bar progress, use a threaded wait dialog, report long-running background work, or use WorkProgress in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Showing Progress for Background Tasks in Visual Studio Extensions

When your extension performs long-running work, you must show progress to the user so they know the operation is in progress and how far along it is. Visual Studio provides several progress UI mechanisms — choosing the right one depends on how much attention the task demands.

## Decision guide: which progress UI to use

| Mechanism | Blocking? | When to use | User attention |
|-----------|-----------|-------------|----------------|
| **Status bar progress** | No | Quick background tasks (< 10 s) | Low — user doesn't need to act |
| **Task Status Center** | No | Long-running background tasks (indexing, analysis, sync) | Low — appears in bottom-left corner, user can check anytime |
| **Threaded Wait Dialog** | Semi-blocking | Tasks the user must wait for but shouldn't freeze the IDE | Medium — modal dialog appears after a delay |
| **ProgressReporter** (Extensibility) | No | Out-of-process extensions that need non-blocking progress | Low — displayed in the Task Status Center |

> **Rule of thumb:** Prefer non-blocking progress (status bar or Task Status Center). Use the Threaded Wait Dialog only when the user initiated an action and must wait for the result before continuing.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Use `ShellExtensibility.StartProgressReportingAsync()` to start progress reporting. It returns a `ProgressReporter` (implements `IProgress<ProgressStatus>` and `IDisposable`) that displays progress in the VS Task Status Center.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility.Shell`, `Microsoft.VisualStudio.RpcContracts.ProgressReporting`

### Progress from a command

```csharp
[VisualStudioContribution]
internal class AnalyzeCommand : Command
{
    public AnalyzeCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Analyze Solution")
    {
        Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
        Icon = new(ImageMoniker.KnownValues.Search, IconSettings.IconAndText),
    };

    public override async Task ExecuteCommandAsync(
        IClientContext context, CancellationToken ct)
    {
        using ProgressReporter progress = await this.Extensibility.Shell()
            .StartProgressReportingAsync("Analyzing solution", ct);

        progress.Report(new ProgressStatus(percentComplete: 0, "Starting analysis..."));

        await Task.Delay(1000, ct); // Step 1
        progress.Report(new ProgressStatus(percentComplete: 33, "Scanning files..."));

        await Task.Delay(1000, ct); // Step 2
        progress.Report(new ProgressStatus(percentComplete: 66, "Processing results..."));

        await Task.Delay(1000, ct); // Step 3
        progress.Report(new ProgressStatus(percentComplete: 100, "Complete"));
    }
}
```

### Cancellable progress

Pass `ProgressReporterOptions` to make the task cancellable by the user:

```csharp
using ProgressReporter progress = await this.Extensibility.Shell()
    .StartProgressReportingAsync(
        "Long running task",
        new ProgressReporterOptions(isWorkCancellable: true),
        ct);

progress.Report(new ProgressStatus(percentComplete: 0, "Working..."));
```

### Indeterminate progress (unknown total)

Pass `null` for `percentComplete` to show an indeterminate spinner:

```csharp
progress.Report(new ProgressStatus(percentComplete: null, "Scanning..."));
```

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit provides three progress mechanisms via simple static APIs.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### a) Status bar progress

The simplest option. Shows a progress bar integrated into the status bar at the bottom of the VS window. Non-blocking — the user can continue working.

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    var totalSteps = 5;

    for (int currentStep = 1; currentStep <= totalSteps; currentStep++)
    {
        await VS.StatusBar.ShowProgressAsync(
            $"Processing step {currentStep}/{totalSteps}",
            currentStep,
            totalSteps);

        await Task.Delay(1000); // Simulate work
    }

    // Progress automatically clears when currentStep == totalSteps
}
```

To show a simple text message without a progress bar:

```csharp
await VS.StatusBar.ShowMessageAsync("Operation completed successfully.");
```

To start and stop a status bar animation:

```csharp
await VS.StatusBar.StartAnimationAsync(StatusAnimation.Build);
// ... do work ...
await VS.StatusBar.EndAnimationAsync(StatusAnimation.Build);
```

### b) Task Status Center

The Task Status Center (TSC) is the icon area at the bottom-left of the status bar. It's designed for long-running background tasks (like indexing, NuGet restores, etc.). Tasks are listed when the user clicks the icon. Non-blocking and supports cancellation.

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    await StartBackgroundTaskAsync();
}

private async Task StartBackgroundTaskAsync()
{
    IVsTaskStatusCenterService tsc = await VS.Services.GetTaskStatusCenterAsync();

    var options = default(TaskHandlerOptions);
    options.Title = "Analyzing solution";
    options.ActionsAfterCompletion = CompletionActions.None;

    TaskProgressData data = default;
    data.CanBeCanceled = true;

    ITaskHandler handler = tsc.PreRegister(options, data);
    Task task = DoLongRunningWorkAsync(data, handler);
    handler.RegisterTask(task);
}

private async Task DoLongRunningWorkAsync(TaskProgressData data, ITaskHandler handler)
{
    float totalSteps = 5;

    for (float currentStep = 1; currentStep <= totalSteps; currentStep++)
    {
        // Check for cancellation
        if (handler.UserCancellation.IsCancellationRequested)
        {
            data.PercentComplete = (int)(currentStep / totalSteps * 100);
            data.ProgressText = "Cancelled";
            handler.Progress.Report(data);
            return;
        }

        await Task.Delay(1000);

        data.PercentComplete = (int)(currentStep / totalSteps * 100);
        data.ProgressText = $"Step {currentStep} of {totalSteps} completed";
        handler.Progress.Report(data);
    }
}
```

**Task Status Center — key concepts:**

| Concept | Description |
|---------|-------------|
| `TaskHandlerOptions.Title` | Text shown in the TSC list |
| `TaskProgressData.CanBeCanceled` | If `true`, user can cancel via the TSC UI |
| `TaskProgressData.PercentComplete` | 0–100 integer for the progress bar |
| `TaskProgressData.ProgressText` | Dynamic text shown under the title |
| `CompletionActions.None` | Task disappears from the list when done |
| `CompletionActions.RetainOnFaulted` | Keep the entry visible if the task throws |
| `handler.UserCancellation` | `CancellationToken` triggered when user clicks Cancel |
| `handler.PreRegister` / `RegisterTask` | Pre-register shows the task immediately; `RegisterTask` links the actual `Task` |

### c) Threaded Wait Dialog

A modal dialog that appears only after a configurable delay (e.g., 1 second). It writes progress to the status bar while waiting for the delay, then shows a dialog. Use this when the user initiated an action and must wait for it to finish.

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    var factory = await VS.Services.GetThreadedWaitDialogAsync() as IVsThreadedWaitDialogFactory;
    IVsThreadedWaitDialog4 dialog = factory.CreateInstance();

    // Show the dialog after 1 second of waiting
    dialog.StartWaitDialog(
        szWaitCaption: "Processing",
        szWaitMessage: "Please wait while the operation completes...",
        szProgressText: "",
        varStatusBmpAnim: null,
        szStatusBarText: "Processing...",
        iDelayToShowDialog: 1,       // seconds before the dialog appears
        fIsCancelable: true,
        fShowMarqueeProgress: false);

    var totalSteps = 5;

    for (int currentStep = 1; currentStep <= totalSteps; currentStep++)
    {
        dialog.UpdateProgress(
            szUpdatedWaitMessage: "Please wait...",
            szProgressText: $"Step {currentStep}/{totalSteps}",
            szStatusBarText: $"Step {currentStep}/{totalSteps}",
            iCurrentStep: currentStep,
            iTotalSteps: totalSteps,
            fDisableCancel: false,
            out bool cancelled);

        if (cancelled) break;

        await Task.Delay(1000); // Simulate work
    }

    // Dismiss the dialog
    (dialog as IDisposable).Dispose();
}
```

> **Important:** The Threaded Wait Dialog keeps the UI thread responsive (unlike a raw `Thread.Sleep`) — VS continues pumping messages. But the modal dialog blocks user interaction with the IDE.

---

## 3. VSSDK (in-process, legacy)

The raw VSSDK APIs for the same three mechanisms. Use these when you don't have the Community Toolkit.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### a) Status bar progress

```csharp
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

IVsStatusbar statusBar = (IVsStatusbar)Package.GetGlobalService(typeof(SVsStatusbar));

uint cookie = 0;
int totalSteps = 5;

// Initialize the progress bar
statusBar.Progress(ref cookie, 1, "", 0, 0);

for (uint currentStep = 1; currentStep <= totalSteps; currentStep++)
{
    statusBar.Progress(ref cookie, 1, $"Step {currentStep}/{totalSteps}", currentStep, (uint)totalSteps);
    await Task.Delay(1000);
}

// Clear the progress bar
statusBar.Progress(ref cookie, 0, "", 0, 0);
```

Status bar text only (no progress bar):

```csharp
IVsStatusbar statusBar = (IVsStatusbar)Package.GetGlobalService(typeof(SVsStatusbar));
statusBar.SetText("Operation completed.");
```

### b) Task Status Center

```csharp
private async Task StartBackgroundTaskAsync()
{
    var tsc = (IVsTaskStatusCenterService)await AsyncServiceProvider.GlobalProvider
        .GetServiceAsync(typeof(SVsTaskStatusCenterService));

    var options = default(TaskHandlerOptions);
    options.Title = "Indexing project files";
    options.ActionsAfterCompletion = CompletionActions.None;

    TaskProgressData data = default;
    data.CanBeCanceled = true;

    ITaskHandler handler = tsc.PreRegister(options, data);
    Task task = DoLongRunningWorkAsync(data, handler);
    handler.RegisterTask(task);
}

private async Task DoLongRunningWorkAsync(TaskProgressData data, ITaskHandler handler)
{
    float totalSteps = 10;

    for (float currentStep = 1; currentStep <= totalSteps; currentStep++)
    {
        if (handler.UserCancellation.IsCancellationRequested) return;

        await Task.Delay(500);

        data.PercentComplete = (int)(currentStep / totalSteps * 100);
        data.ProgressText = $"Indexed {currentStep} of {totalSteps} files";
        handler.Progress.Report(data);
    }
}
```

### c) Threaded Wait Dialog

```csharp
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

var factory = (IVsThreadedWaitDialogFactory)Package.GetGlobalService(typeof(SVsThreadedWaitDialogFactory));
IVsThreadedWaitDialog2 dialog;
factory.CreateInstance(out dialog);

dialog.StartWaitDialog(
    "Processing",                          // caption
    "Working on it...",                    // message
    "",                                     // progress text
    null,                                   // status bar animation
    "",                                     // status bar text
    1,                                      // delay in seconds
    true,                                   // cancelable
    true);                                  // show marquee

int totalSteps = 5;

for (int i = 1; i <= totalSteps; i++)
{
    bool cancelled;
    dialog.HasCanceled(out cancelled);
    if (cancelled) break;

    dialog.UpdateProgress(
        "Working...",
        $"Step {i}/{totalSteps}",
        $"Step {i}/{totalSteps}",
        i,
        totalSteps,
        false,                              // disable cancel
        out cancelled);

    await Task.Delay(1000);
}

dialog.EndWaitDialog(out int cancelledResult);
```

---

## Complete pattern: combining progress with error handling

### Community Toolkit example

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    // Start a Task Status Center entry for the background work
    IVsTaskStatusCenterService tsc = await VS.Services.GetTaskStatusCenterAsync();

    var options = default(TaskHandlerOptions);
    options.Title = "Deploying extension";
    options.ActionsAfterCompletion = CompletionActions.RetainOnFaulted;

    TaskProgressData data = default;
    data.CanBeCanceled = true;

    ITaskHandler handler = tsc.PreRegister(options, data);

    Task task = Task.Run(async () =>
    {
        try
        {
            float totalSteps = 3;

            data.ProgressText = "Packaging...";
            data.PercentComplete = 0;
            handler.Progress.Report(data);
            await PackageAsync(handler.UserCancellation);

            data.ProgressText = "Uploading...";
            data.PercentComplete = 33;
            handler.Progress.Report(data);
            await UploadAsync(handler.UserCancellation);

            data.ProgressText = "Verifying...";
            data.PercentComplete = 66;
            handler.Progress.Report(data);
            await VerifyAsync(handler.UserCancellation);

            data.ProgressText = "Done!";
            data.PercentComplete = 100;
            handler.Progress.Report(data);

            await VS.StatusBar.ShowMessageAsync("Deployment completed successfully.");
        }
        catch (OperationCanceledException)
        {
            await VS.StatusBar.ShowMessageAsync("Deployment cancelled.");
        }
        catch (Exception ex)
        {
            await ex.LogAsync();
            await VS.StatusBar.ShowMessageAsync("Deployment failed. See Output window.");
        }
    });

    handler.RegisterTask(task);
}
```

---

## Key guidance

- **Never block the UI thread** with `Thread.Sleep` or synchronous waits during long operations. Use `async`/`await` and one of the progress APIs above.
- **Status bar progress** is best for quick, non-critical operations (< 10 seconds).
- **Task Status Center** is best for long-running background work — it's non-blocking, supports cancellation, and the user can check progress at any time. This is what VS uses for NuGet restores and project loading.
- **Threaded Wait Dialog** is semi-blocking — use it only when the user explicitly initiated an action and needs to wait.
- Always support **cancellation** for operations that take more than a few seconds.
- Use `CompletionActions.RetainOnFaulted` to keep failed tasks visible in the Task Status Center so the user can see the error.
- The **VisualStudio.Extensibility** progress API is the simplest — just call `progress.Report()` with the current step.

## References

- [Progress bars for background tasks (Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/show-progress)
- [Notifications and Progress UX Guidelines](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/notifications-and-progress-for-visual-studio)
- [Using the Status Bar](https://learn.microsoft.com/visualstudio/extensibility/extending-the-status-bar)
