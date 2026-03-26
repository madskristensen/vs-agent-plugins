---
name: showing-message-boxes
description: Show message boxes, user prompts, info bars, and other notification dialogs in Visual Studio extensions. Use when the user asks how to display a message, prompt, confirmation dialog, notification, info bar, or status bar message in a Visual Studio IDE extension. Covers both the new VisualStudio.Extensibility (out-of-process) model and the legacy VSSDK / Community Toolkit (in-process) model.
---

# Showing Message Boxes and User Prompts in Visual Studio Extensions

Visual Studio provides multiple notification mechanisms. Choose the right one based on how urgently you need the user's attention:

| Mechanism | When to use |
|-----------|-------------|
| **Status bar** | Non-critical — user doesn't need to act |
| **Info bar** | Important but not blocking — user can act when ready |
| **Message box / User prompt** | Blocking — user must acknowledge or choose before continuing |
| **Output window** | Informational logging — user can review at their leisure |

Using the VS-native APIs matters because they handle window parenting, theming, focus management, and threading automatically — raw WPF or WinForms dialogs do none of this and can appear behind the IDE or break input focus.

**When to use this vs. alternatives:**
- User must decide before continuing (save/discard, confirm delete) → message box / `ShowPromptAsync`
- User should know but can act later (update available, build warning) → info bar (see also [vs-info-bar](../showing-info-bars/SKILL.md))
- Informational, no action needed (operation completed) → status bar
- Detailed diagnostic output (build log, analysis results) → Output Window (see also [vs-error-handling](../handling-extension-errors/SKILL.md))
- Ongoing status with progress (indexing, loading) → progress notification (see also [vs-background-tasks-progress](../showing-background-progress/SKILL.md))
- Need structured user input (multiple fields, file pickers) → custom dialog or tool window (see also [vs-tool-window](../adding-tool-windows/SKILL.md))

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Use `ShellExtensibility.ShowPromptAsync()` from the `Microsoft.VisualStudio.Extensibility` SDK. This is the recommended approach for new extensions.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespace:** `Microsoft.VisualStudio.Extensibility.Shell`

### Simple OK prompt

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken cancellationToken)
{
    await this.Extensibility.Shell().ShowPromptAsync(
        "This is a user prompt.",
        PromptOptions.OK,
        cancellationToken);
}
```

### Confirmation with OK/Cancel

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
{
    if (!await this.Extensibility.Shell().ShowPromptAsync(
        "Continue with executing the command?",
        PromptOptions.OKCancel,
        ct))
    {
        return;
    }

    // User confirmed — proceed
}
```

### Change the default button to Cancel

```csharp
if (!await this.Extensibility.Shell().ShowPromptAsync(
    "Continue with executing the command?",
    PromptOptions.OKCancel.WithCancelAsDefault(),
    ct))
{
    return;
}
```

### Built-in PromptOptions

| Option | Buttons | Default returns |
|--------|---------|-----------------|
| `PromptOptions.OK` | OK | `true` / Close → `false` |
| `PromptOptions.OKCancel` | OK, Cancel | OK → `true`, Cancel/Close → `false` |
| `PromptOptions.RetryCancel` | Retry, Cancel | Retry → `true`, Cancel/Close → `false` |

#### Confirmation with icons

| Option | Icon |
|--------|------|
| `PromptOptions.ErrorConfirm` | Error icon |
| `PromptOptions.WarningConfirm` | Warning icon |
| `PromptOptions.AlertConfirm` | Alert icon |
| `PromptOptions.InformationConfirm` | Information icon |
| `PromptOptions.HelpConfirm` | Help icon |

### Custom prompt with multiple choices

Define an enum for the return values:

```csharp
public enum TokenThemeResult
{
    None,
    Solarized,
    OneDark,
    GruvBox,
}
```

Then build a custom `PromptOptions<TResult>`:

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
{
    TokenThemeResult selected = await this.Extensibility.Shell().ShowPromptAsync(
        "Select a token color theme:",
        new PromptOptions<TokenThemeResult>
        {
            Choices =
            {
                { "Solarized", TokenThemeResult.Solarized },
                { "One Dark", TokenThemeResult.OneDark },
                { "GruvBox", TokenThemeResult.GruvBox },
            },
            DismissedReturns = TokenThemeResult.None,
            DefaultChoiceIndex = 0,
            Title = "Theme Selector",
            Icon = ImageMoniker.KnownValues.Settings,
        },
        ct);
}
```

### Input prompt (single-line string input)

```csharp
string? projectName = await this.Extensibility.Shell().ShowPromptAsync(
    "Enter the project name:",
    new InputPromptOptions { DefaultText = "MyProject" },
    ct);
```

### ShowPromptAsync from an in-proc VSSDK package (hybrid model)

If you're mixing the new extensibility model into an existing VSSDK package:

```csharp
public class MyPackage : AsyncPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        VisualStudioExtensibility extensibility =
            await this.GetServiceAsync<VisualStudioExtensibility, VisualStudioExtensibility>();
        await extensibility.Shell().ShowPromptAsync(
            "Hello from in-proc",
            PromptOptions.OK,
            cancellationToken);
    }
}
```

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit wraps the VSSDK APIs with simpler, discoverable helpers.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Message box

```csharp
// Simple synchronous message box
VS.MessageBox.Show("Title", "The message");

// Async with buttons and icon
await VS.MessageBox.ShowAsync(
    "Title",
    "The message",
    OLEMSGICON.OLEMSGICON_INFO,
    OLEMSGBUTTON.OLEMSGBUTTON_OKCANCEL);
```

### Info bar (non-blocking notification)

```csharp
var model = new InfoBarModel(
    new[] { new InfoBarTextSpan("An update is available. "),
            new InfoBarHyperlink("Install now") });

InfoBar infoBar = await VS.InfoBar.CreateAsync(ToolWindowGuids80.SolutionExplorer, model);
infoBar.ActionItemClicked += OnInfoBarAction;
await infoBar.TryShowInfoBarUIAsync();
```

### Status bar

```csharp
await VS.StatusBar.ShowMessageAsync("Operation completed successfully.");
```

---

## 3. VSSDK (in-process, legacy)

The low-level Visual Studio SDK APIs. Use these when you don't have the Community Toolkit or need full control.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Message box — VsShellUtilities.ShowMessageBox

```csharp
VsShellUtilities.ShowMessageBox(
    this.package,                          // IServiceProvider (your AsyncPackage)
    "Hello World!",                        // message
    "Command",                             // title
    OLEMSGICON.OLEMSGICON_INFO,            // icon
    OLEMSGBUTTON.OLEMSGBUTTON_OK,          // buttons
    OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST); // default button
```

Returns an `int` matching `VSConstants.MessageBoxResult` values for branching on the user's choice.

### Info bar (non-blocking notification)

Info bars require implementing `IVsInfoBarUIEvents` and using `IVsInfoBarUIFactory`:

```csharp
var shell = (IVsShell)ServiceProvider.GetService(typeof(SVsShell));
shell.GetProperty((int)__VSSPROPID7.VSSPROPID_MainWindowInfoBarHost, out var host);
var infoBarHost = (IVsInfoBarHost)host;

var infoBarModel = new InfoBarModel(
    new[] { new InfoBarTextSpan("An update is available. "),
            new InfoBarHyperlink("Install now") },
    KnownMonikers.StatusInformation,
    isCloseButtonVisible: true);

var factory = (IVsInfoBarUIFactory)ServiceProvider.GetService(typeof(SVsInfoBarUIFactory));
IVsInfoBarUIElement uiElement = factory.CreateInfoBar(infoBarModel);
uiElement.Advise(this, out _);
infoBarHost.AddInfoBar(uiElement);
```

### Status bar

```csharp
IVsStatusbar statusBar = (IVsStatusbar)ServiceProvider.GetService(typeof(SVsStatusbar));
statusBar.SetText("Operation completed successfully.");
```

---

> **Important:** Do NOT use `System.Windows.MessageBox` or `System.Windows.Forms.MessageBox` directly in any approach. They don't parent correctly against the Visual Studio main window.

## Key guidance

- **New extensions** → use `VisualStudio.Extensibility` + `ShowPromptAsync`. It runs out-of-process and won't crash VS.
- **Existing VSSDK extensions** → use `VS.MessageBox` from the Community Toolkit, or `VsShellUtilities.ShowMessageBox`.
- **Never** use raw WPF/WinForms `MessageBox.Show()` — it creates parenting issues with the VS window.
- Keep at most **3 choices** in a prompt (the API enforces this in the new model).
- Always pass a `CancellationToken` and handle dismissal gracefully.

## Troubleshooting

- **Prompt doesn't appear (Extensibility):** Verify you're `await`-ing `ShowPromptAsync`. Without `await`, the method returns immediately and the prompt may never display or may appear after the command has already finished.
- **MessageBox appears behind Visual Studio:** You're using `System.Windows.MessageBox` or `System.Windows.Forms.MessageBox` instead of the VS APIs. Switch to `VsShellUtilities.ShowMessageBox`, `VS.MessageBox.ShowAsync`, or `ShowPromptAsync`.
- **Dialog hangs / deadlock (VSSDK):** You're calling a synchronous message box API from a background thread without switching to the UI thread first. Use `await JoinableTaskFactory.SwitchToMainThreadAsync()` before the call, or use the async Toolkit overload `VS.MessageBox.ShowAsync`.
- **Custom prompt returns `None` unexpectedly:** The user dismissed the dialog (clicked X or pressed Escape). Always set `DismissedReturns` to a safe default and handle that value explicitly.
- **Info bar doesn't appear:** For VSSDK, verify you're obtaining the correct `IVsInfoBarHost` — the main window host vs. a tool window host are different objects. For the Toolkit, ensure you pass a valid tool window GUID to `VS.InfoBar.CreateAsync`.

## What NOT to do

> **Do NOT** use `System.Windows.MessageBox` or `System.Windows.Forms.MessageBox` — not parented to VS, can appear behind IDE, not themed. Use `VS.MessageBox.ShowAsync` (Toolkit), `VsShellUtilities.ShowMessageBox` (VSSDK), or `ShowPromptAsync` (Extensibility).

> **Do NOT** show message boxes from a background thread without switching to UI thread first — use `VS.MessageBox.ShowAsync` (Toolkit, handles thread switching) or `SwitchToMainThreadAsync()` before `VsShellUtilities.ShowMessageBox` (VSSDK).

> **Do NOT** show message boxes during solution load, package init, or unattended operations — use an InfoBar instead for background-triggered notifications.

> **Do NOT** display raw exception messages in user-facing message boxes — log the full exception; show a user-friendly summary.

> **Do NOT** use more than 3 choices in a prompt — the Extensibility API enforces this limit. Use a custom dialog for more options.

## See also

- [vs-error-handling](../handling-extension-errors/SKILL.md)
- [vs-async-threading](../handling-async-threading/SKILL.md)
- [vs-background-tasks-progress](../showing-background-progress/SKILL.md)
- [vs-tool-window](../adding-tool-windows/SKILL.md)
- [vs-info-bar](../showing-info-bars/SKILL.md)

## References

- [User Prompts (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/user-prompt/user-prompts)
- [Notifications recipe (VSSDK Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/notifications)
- [Notifications and Progress UX Guidelines](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/notifications-and-progress-for-visual-studio)
