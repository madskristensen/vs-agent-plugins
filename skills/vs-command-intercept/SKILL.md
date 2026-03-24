---
name: vs-command-intercept
description: Intercept existing Visual Studio commands to run custom logic before, after, or instead of the default handler. Use when the user asks how to intercept a command, hook into an existing command, override a built-in VS command, run code before/after Save or Build, listen for command execution, or wrap existing command behavior. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Intercepting Existing Commands in Visual Studio Extensions

Command interception lets you run custom logic **before**, **after**, or **instead of** a built-in or third-party Visual Studio command. Common scenarios:

- Run validation before a file is saved
- Log or instrument when the user builds the solution
- Replace the default formatting behavior with a custom formatter
- Show a confirmation prompt before a destructive action

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently support intercepting existing commands. You can only define new commands with `Command`. There is no equivalent of `IOleCommandTarget` chaining or `VS.Commands.InterceptAsync` in the out-of-process model.

**If you need to intercept existing commands, use the VSIX Community Toolkit or VSSDK (in-process) approach.**

For some scenarios you may be able to achieve similar results by listening to events instead of intercepting the command directly. For example, use `IDocumentEventsListener` to react to document save events rather than intercepting the Save command.

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit provides `VS.Commands.InterceptAsync` — a one-line API to intercept any known command by its GUID and ID. You supply callbacks for before and/or after the command executes.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Basic interception — run code before and after a command

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;

namespace MyExtension;

public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await this.RegisterCommandsAsync();

        // Intercept the Save command (Ctrl+S)
        await VS.Commands.InterceptAsync(VSConstants.VSStd97CmdID.Save, ExecuteBeforeSave, ExecuteAfterSave);
    }

    private CommandProgression ExecuteBeforeSave()
    {
        // Return CommandProgression.Continue to let the Save command proceed
        // Return CommandProgression.Stop to cancel the Save command
        return CommandProgression.Continue;
    }

    private void ExecuteAfterSave()
    {
        // Runs after the Save command completes
    }
}
```

### Cancel a command with `CommandProgression.Stop`

```csharp
await VS.Commands.InterceptAsync(VSConstants.VSStd97CmdID.SaveAll, () =>
{
    var result = VS.MessageBox.Show(
        "Save All",
        "Are you sure you want to save all files?",
        OLEMSGICON.OLEMSGICON_QUERY,
        OLEMSGBUTTON.OLEMSGBUTTON_YESNO);

    // Cancel the command if the user clicks No
    return result == VSConstants.MessageBoxResult.IDYES
        ? CommandProgression.Continue
        : CommandProgression.Stop;
});
```

### Intercept with only a before-handler

Pass the before-handler only — no after-handler:

```csharp
await VS.Commands.InterceptAsync(VSConstants.VSStd97CmdID.Build, () =>
{
    ThreadHelper.JoinableTaskFactory.Run(async delegate
    {
        OutputWindowPane pane = await VS.Windows.GetOutputWindowPaneAsync(Windows.VSOutputWindowPane.General);
        pane?.WriteLine($"Build started at {DateTime.Now}");
    });
    return CommandProgression.Continue;
});
```

### Intercept with only an after-handler

Pass `null` for the before-handler:

```csharp
await VS.Commands.InterceptAsync(VSConstants.VSStd97CmdID.Build, null, () =>
{
    VS.StatusBar.ShowMessageAsync("Build completed!").FireAndForget();
});
```

### Common commands to intercept

Commands are identified by their command group GUID and command ID. The most common are in `VSConstants.VSStd97CmdID` and `VSConstants.VSStd2KCmdID`:

| Command | Constant | Description |
|---------|----------|-------------|
| Save | `VSConstants.VSStd97CmdID.Save` | Ctrl+S |
| Save All | `VSConstants.VSStd97CmdID.SaveAll` | Ctrl+Shift+S |
| Build | `VSConstants.VSStd97CmdID.Build` | Build Solution |
| Rebuild | `VSConstants.VSStd97CmdID.Rebuild` | Rebuild Solution |
| Cut | `VSConstants.VSStd97CmdID.Cut` | Ctrl+X |
| Copy | `VSConstants.VSStd97CmdID.Copy` | Ctrl+C |
| Paste | `VSConstants.VSStd97CmdID.Paste` | Ctrl+V |
| Undo | `VSConstants.VSStd97CmdID.Undo` | Ctrl+Z |
| Redo | `VSConstants.VSStd97CmdID.Redo` | Ctrl+Y |
| Format Document | `VSConstants.VSStd2KCmdID.FORMATDOCUMENT` | Format entire document |
| Format Selection | `VSConstants.VSStd2KCmdID.FORMATSELECTION` | Format selected text |
| Find | `VSConstants.VSStd97CmdID.Find` | Ctrl+F |
| Replace | `VSConstants.VSStd97CmdID.Replace` | Ctrl+H |

### Intercepting a command by raw GUID and ID

For commands not in `VSConstants`, use the overload that takes a `CommandID`:

```csharp
using System.ComponentModel.Design;

var commandGuid = new Guid("your-command-group-guid");
var commandId = new CommandID(commandGuid, 0x0100);

await VS.Commands.InterceptAsync(commandId, () =>
{
    // Before handler
    return CommandProgression.Continue;
});
```

### Key points

- `InterceptAsync` must be called after the package is initialized (inside `InitializeAsync`).
- The before-handler runs synchronously on the UI thread. Keep it fast — offload heavy work to a background thread.
- Return `CommandProgression.Continue` to let the original command execute, or `CommandProgression.Stop` to cancel it.
- The after-handler receives no arguments and no return value.

---

## 3. VSSDK (in-process, legacy)

With the raw VSSDK, command interception is done by implementing `IOleCommandTarget` and inserting your implementation into the command target chain using `IVsRegisterPriorityCommandTarget`.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.OLE.Interop`, `Microsoft.VisualStudio.Shell.Interop`

### Step 1: Implement `IOleCommandTarget`

```csharp
using System;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;

namespace MyExtension;

internal sealed class SaveCommandInterceptor : IOleCommandTarget
{
    private readonly AsyncPackage _package;

    public SaveCommandInterceptor(AsyncPackage package)
    {
        _package = package;
    }

    public int QueryStatus(ref Guid pguidCmdGroup, uint cCmds, OLECMD[] prgCmds, IntPtr pCmdText)
    {
        // Return OLECMDERR_E_UNKNOWNGROUP to let the next handler in the chain process this
        return (int)Constants.OLECMDERR_E_UNKNOWNGROUP;
    }

    public int Exec(ref Guid pguidCmdGroup, uint nCmdID, uint nCmdexecopt, IntPtr pvaIn, IntPtr pvaOut)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        // Check if this is the Save command
        if (pguidCmdGroup == typeof(VSConstants.VSStd97CmdID).GUID
            && nCmdID == (uint)VSConstants.VSStd97CmdID.Save)
        {
            // --- Before logic ---
            var result = VsShellUtilities.ShowMessageBox(
                _package,
                "Save this file?",
                "Confirm Save",
                OLEMSGICON.OLEMSGICON_QUERY,
                OLEMSGBUTTON.OLEMSGBUTTON_YESNO,
                OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);

            if (result != (int)VSConstants.MessageBoxResult.IDYES)
            {
                // Cancel the command — do not pass it down the chain
                return VSConstants.S_OK;
            }
        }

        // Not our command, or we want to continue — let the next handler process it
        return (int)Constants.OLECMDERR_E_UNKNOWNGROUP;
    }
}
```

### Step 2: Register the interceptor in the package

Use `IVsRegisterPriorityCommandTarget` to insert your `IOleCommandTarget` at a higher priority than the default handlers:

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid("YOUR-PACKAGE-GUID")]
public sealed class MyExtensionPackage : AsyncPackage
{
    private uint _interceptorCookie;

    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        var priorityCommandTarget = await GetServiceAsync(typeof(SVsRegisterPriorityCommandTarget))
            as IVsRegisterPriorityCommandTarget;

        var interceptor = new SaveCommandInterceptor(this);

        priorityCommandTarget?.RegisterPriorityCommandTarget(
            0,                      // reserved, must be 0
            interceptor,
            out _interceptorCookie);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && _interceptorCookie != 0)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var priorityCommandTarget = GetService(typeof(SVsRegisterPriorityCommandTarget))
                as IVsRegisterPriorityCommandTarget;
            priorityCommandTarget?.UnregisterPriorityCommandTarget(_interceptorCookie);
            _interceptorCookie = 0;
        }

        base.Dispose(disposing);
    }
}
```

### Intercepting for after-execution logic

`IOleCommandTarget.Exec` intercepts **before** the default handler. To run logic **after** the command executes, you need to let the default handler run first by calling the next target in the chain. The simplest way is to use `IVsUIShell.PostExecCommand` to queue your post-execution logic, or track state and use `IOleCommandTarget` chaining.

A simpler approach for after-execution scenarios: use `DTE.Events.CommandEvents` to listen for command completion:

```csharp
using EnvDTE;
using EnvDTE80;
using Microsoft.VisualStudio.Shell;

// In InitializeAsync, after SwitchToMainThreadAsync:
var dte = await GetServiceAsync(typeof(DTE)) as DTE2;
var commandEvents = dte.Events.CommandEvents;

// Keep a reference to prevent GC
_commandEvents = commandEvents;

commandEvents.AfterExecute += (string guid, int id, object customIn, object customOut) =>
{
    // Check if this is the command you care about
    if (guid == typeof(VSConstants.VSStd97CmdID).GUID.ToString("B")
        && id == (int)VSConstants.VSStd97CmdID.Save)
    {
        // Runs after Save completes
    }
};
```

> **Important:** Store a reference to the `CommandEvents` object in a field. If it gets garbage collected, the event handler silently stops firing.

---

## Key guidance

- **VisualStudio.Extensibility** does not support command interception. Use event listeners (e.g., `IDocumentEventsListener`) as an alternative for some scenarios.
- **Community Toolkit** — `VS.Commands.InterceptAsync` is the simplest approach. Use `CommandProgression.Stop` to cancel, `CommandProgression.Continue` to allow. Call it in `InitializeAsync`.
- **VSSDK** — Implement `IOleCommandTarget` and register it via `IVsRegisterPriorityCommandTarget`. Always unregister in `Dispose`. For after-execution logic, use `DTE.Events.CommandEvents.AfterExecute`.
- Keep before-handlers fast — they run on the UI thread.
- Always handle the case where the user cancels (return appropriate results).
- For file save scenarios, consider whether events (`RunningDocumentTable`, `IDocumentEventsListener`) are more appropriate than command interception.

## References

- [Intercepting Commands (VSIX Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/menus-buttons-commands#intercept-commands)
- [IOleCommandTarget (VSSDK)](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.ole.interop.iolecommandtarget)
- [IVsRegisterPriorityCommandTarget (VSSDK)](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.interop.ivsregisterprioritcommandtarget)
- [Command Events (DTE Automation)](https://learn.microsoft.com/visualstudio/extensibility/internals/commands-and-menus-that-use-interop-assemblies)
