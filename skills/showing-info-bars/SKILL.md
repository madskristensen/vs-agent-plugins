---
name: showing-info-bars
description: Show InfoBar (gold bar) notifications in Visual Studio extensions. Use when the user asks how to display an InfoBar, gold bar, yellow bar, non-blocking notification, or inline notification in a tool window, document window, or the main window of a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Showing InfoBar Notifications in Visual Studio Extensions

An InfoBar (also called a gold bar or yellow bar) is a non-blocking notification that appears at the top of a tool window, document window, or the main IDE window. Use it when you need the user's attention but don't want to interrupt their workflow.

InfoBars are the right default for most extension notifications because they're non-blocking — the user can continue working and respond when ready. They persist until explicitly dismissed (unlike status bar messages that disappear) and support actionable links and buttons. Using a message box when an info bar would suffice trains users to reflexively dismiss dialogs, reducing the effectiveness of truly important prompts.

**When to use an InfoBar vs. alternatives:**
- Important but non-blocking notification with actionable links → **InfoBar** (this skill)
- Blocking question the user must answer before continuing → message box (see [vs-message-box](../showing-message-boxes/SKILL.md))
- Brief, non-critical status update → status bar (see [vs-message-box](../showing-message-boxes/SKILL.md))
- Errors with source location for click-to-navigate → Error List (see [vs-error-list](../integrating-error-list/SKILL.md))
- Detailed log output → Output Window (see [vs-error-handling](../handling-extension-errors/SKILL.md))

## Decision guide: when to use an InfoBar vs. other notifications

| Mechanism | Blocking? | When to use |
|-----------|-----------|-------------|
| **Status bar** | No | Non-critical info the user doesn't need to act on |
| **InfoBar** | No | Important but non-blocking — user can act when ready |
| **Message box / User prompt** | Yes | User must acknowledge or choose before continuing |
| **Output window** | No | Logging and diagnostic information |

### InfoBar placement options

| Location | When to use |
|----------|-------------|
| **Tool window** (e.g., Solution Explorer) | Notification related to a specific tool window's content |
| **Document window** | Notification relevant to a specific open file |
| **Main window** (global) | IDE-wide notification (use sparingly — causes layout shift) |

> **Best practice:** Keep InfoBar text short and actionable. Show at most one or two action items. Avoid stacking many InfoBars — the user sees a maximum of three before the region becomes scrollable.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently provide a dedicated InfoBar API. For non-blocking notifications in out-of-process extensions, use **User Prompts** (`ShellExtensibility.ShowPromptAsync()`), which display a non-modal dialog.

If you specifically need an InfoBar (e.g., attached to a tool window), you must use an **in-proc compatible extension** — one that sets `RequiresInProcessHosting = true` in its `ExtensionConfiguration` — and then use the VSSDK or Toolkit APIs described below.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespace:** `Microsoft.VisualStudio.Extensibility.Shell`

### User prompt as an alternative to InfoBar

```csharp
[VisualStudioContribution]
internal class NotifyCommand : Command
{
    public NotifyCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Notify User")
    {
        Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    };

    public override async Task ExecuteCommandAsync(
        IClientContext context, CancellationToken ct)
    {
        // Non-blocking prompt — closest out-of-proc alternative to an InfoBar
        bool update = await this.Extensibility.Shell().ShowPromptAsync(
            "An update is available. Would you like to install it now?",
            PromptOptions.OKCancel,
            ct);

        if (update)
        {
            // Perform the update
        }
    }
}
```

### In-proc hybrid: using VSSDK InfoBar from an Extensibility extension

```csharp
[VisualStudioContribution]
internal class MyExtension : Extension
{
    public override ExtensionConfiguration? ExtensionConfiguration => new()
    {
        RequiresInProcessHosting = true,
    };
}

[VisualStudioContribution]
internal class ShowInfoBarCommand : Command
{
    public ShowInfoBarCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Show InfoBar")
    {
        Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    };

    public override async Task ExecuteCommandAsync(
        IClientContext context, CancellationToken ct)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

        // Use VSSDK InfoBar from in-proc hybrid extension
        var model = new InfoBarModel(
            new[] {
                new InfoBarTextSpan("A new version is available. "),
                new InfoBarHyperlink("Update now")
            },
            KnownMonikers.StatusInformation,
            isCloseButtonVisible: true);

        IVsInfoBarUIFactory factory = (IVsInfoBarUIFactory)
            ServiceProvider.GlobalProvider.GetService(typeof(SVsInfoBarUIFactory));

        IVsInfoBarUIElement uiElement = factory.CreateInfoBar(model);

        // Show in main window
        IVsShell shell = (IVsShell)
            ServiceProvider.GlobalProvider.GetService(typeof(SVsShell));
        shell.GetProperty((int)__VSSPROPID7.VSSPROPID_MainWindowInfoBarHost,
            out object hostObj);

        if (hostObj is IVsInfoBarHost host)
        {
            host.AddInfoBar(uiElement);
        }
    }
}
```

---

## 2. VSIX Community Toolkit (in-process)

The Toolkit provides a clean `InfoBar` wrapper through `VS.InfoBar`. It significantly simplifies creating InfoBars and handling events. All factory methods are async and return `InfoBar?` (nullable — `null` if the host window couldn't be found).

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### InfoBar in a tool window (e.g., Solution Explorer)

```csharp
var model = new InfoBarModel(
    new[] {
        new InfoBarTextSpan("The project needs to be restored. "),
        new InfoBarHyperlink("Restore now")
    },
    KnownMonikers.NuGet,
    isCloseButtonVisible: true);

// Show in Solution Explorer by passing its GUID
InfoBar? infoBar = await VS.InfoBar.CreateAsync(ToolWindowGuids80.SolutionExplorer, model);

if (infoBar != null)
{
    infoBar.ActionItemClicked += InfoBar_ActionItemClicked;
    await infoBar.TryShowInfoBarUIAsync();
}

// ...

private void InfoBar_ActionItemClicked(object sender, InfoBarActionItemEventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();

    if (e.ActionItem.Text == "Restore now")
    {
        // Perform the restore
    }
}
```

### InfoBar in a document window

Pass the file path of the open document instead of a GUID:

```csharp
var model = new InfoBarModel("This file has been modified outside the editor.");

string filePath = @"C:/Projects/MyApp/Program.cs";
InfoBar? infoBar = await VS.InfoBar.CreateAsync(filePath, model);
await infoBar?.TryShowInfoBarUIAsync();
```

### Global InfoBar (main window — no specific window)

Use the parameterless `VS.InfoBar.CreateAsync()` to attach the InfoBar to the VS main window:

```csharp
var model = new InfoBarModel(
    new[] {
        new InfoBarTextSpan("A critical update is available. "),
        new InfoBarHyperlink("Learn more"),
        new InfoBarTextSpan(" "),
        new InfoBarButton("Install")
    },
    KnownMonikers.StatusWarning,
    isCloseButtonVisible: true);

// CreateAsync (no window parameter) → main window InfoBar
InfoBar? infoBar = await VS.InfoBar.CreateAsync(model);

if (infoBar != null)
{
    infoBar.ActionItemClicked += OnGlobalInfoBarAction;
    await infoBar.TryShowInfoBarUIAsync();
}

// ...

private void OnGlobalInfoBarAction(object sender, InfoBarActionItemEventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();

    if (e.ActionItem.Text == "Install")
    {
        // Start update
    }
    else if (e.ActionItem.Text == "Learn more")
    {
        System.Diagnostics.Process.Start("https://example.com/release-notes");
    }
}
```

### InfoBar on a custom tool window (ToolWindowPane)

When you have a custom `ToolWindowPane`, the Toolkit's `InfoBar` class works with any `IVsWindowFrame`. But you can also use the built-in `ToolWindowPane.AddInfoBar()` method directly:

```csharp
[Guid("your-tool-window-guid")]
public class MyToolWindow : ToolWindowPane
{
    public MyToolWindow() : base(null)
    {
        Caption = "My Tool Window";
        Content = new MyToolWindowControl();
    }

    public async Task ShowInfoBarAsync()
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

        var model = new InfoBarModel(
            new[] {
                new InfoBarTextSpan("Configuration changed. "),
                new InfoBarHyperlink("Reload")
            },
            KnownMonikers.Refresh,
            isCloseButtonVisible: true);

        // Option A: Use the Toolkit wrapper
        string toolWindowGuid = typeof(MyToolWindow).GUID.ToString("B");
        InfoBar? infoBar = await VS.InfoBar.CreateAsync(toolWindowGuid, model);
        await infoBar?.TryShowInfoBarUIAsync();

        // Option B: Use ToolWindowPane's built-in method
        AddInfoBar(model);
    }

    // ToolWindowPane raises these events for InfoBars added via AddInfoBar()
    protected override void OnInfoBarClosed(IVsInfoBarUIElement element)
    {
        // InfoBar was closed by the user
    }

    protected override void OnInfoBarActionItemClicked(
        IVsInfoBarUIElement element, IVsInfoBarActionItem actionItem)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        if (actionItem.Text == "Reload")
        {
            // Reload configuration
        }
    }
}
```

### InfoBar on an ITextView (editor)

The Toolkit provides an extension method to attach an InfoBar directly to a text view:

```csharp
InfoBar? infoBar = await textView.CreateInfoBarAsync(model);
await infoBar?.TryShowInfoBarUIAsync();
```

### Programmatically closing an InfoBar

```csharp
infoBar.Close();
```

---

## 3. VSSDK (in-process, legacy)

The VSSDK requires you to manually create the `InfoBarModel`, use `IVsInfoBarUIFactory` to produce a `IVsInfoBarUIElement`, find the appropriate `IVsInfoBarHost`, add the element, and subscribe to events via `Advise`/`Unadvise`.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Create and show an InfoBar in a tool window

```csharp
public async Task ShowInfoBarInToolWindowAsync()
{
    await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

    // 1. Build the model
    var model = new InfoBarModel(
        textSpans: new IVsInfoBarTextSpan[]
        {
            new InfoBarTextSpan("This is a "),
            new InfoBarHyperlink("hyperlink"),
            new InfoBarTextSpan(" InfoBar.")
        },
        actionItems: new IVsInfoBarActionItem[]
        {
            new InfoBarButton("Click Me")
        },
        image: KnownMonikers.StatusInformation,
        isCloseButtonVisible: true);

    // 2. Create the UI element
    IVsInfoBarUIFactory factory = (IVsInfoBarUIFactory)
        await GetServiceAsync(typeof(SVsInfoBarUIFactory));
    IVsInfoBarUIElement uiElement = factory.CreateInfoBar(model);

    // 3. Subscribe to events
    uiElement.Advise(new InfoBarEventSink(), out uint cookie);

    // 4. Find the host (Solution Explorer in this example)
    IVsUIShell uiShell = (IVsUIShell)
        await GetServiceAsync(typeof(SVsUIShell));
    Guid toolWindowGuid = new Guid(ToolWindowGuids80.SolutionExplorer);
    uiShell.FindToolWindow(
        (uint)__VSFINDTOOLWIN.FTW_fForceCreate,
        ref toolWindowGuid, out IVsWindowFrame frame);

    frame.GetProperty(
        (int)__VSFPROPID7.VSFPROPID_InfoBarHost, out object hostObj);

    if (hostObj is IVsInfoBarHost host)
    {
        host.AddInfoBar(uiElement);
    }
}
```

### Show InfoBar in the main window (global)

```csharp
public async Task ShowGlobalInfoBarAsync()
{
    await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

    var model = new InfoBarModel("A global notification message.",
        KnownMonikers.StatusWarning, isCloseButtonVisible: true);

    IVsInfoBarUIFactory factory = (IVsInfoBarUIFactory)
        await GetServiceAsync(typeof(SVsInfoBarUIFactory));
    IVsInfoBarUIElement uiElement = factory.CreateInfoBar(model);

    // Get the main window InfoBar host
    IVsShell shell = (IVsShell)await GetServiceAsync(typeof(SVsShell));
    shell.GetProperty(
        (int)__VSSPROPID7.VSSPROPID_MainWindowInfoBarHost, out object hostObj);

    if (hostObj is IVsInfoBarHost host)
    {
        host.AddInfoBar(uiElement);
    }
}
```

### Show InfoBar in a document window

```csharp
public async Task ShowInfoBarInDocumentAsync(string filePath)
{
    await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

    if (!VsShellUtilities.IsDocumentOpen(
        ServiceProvider.GlobalProvider, filePath, Guid.Empty,
        out _, out _, out IVsWindowFrame frame))
    {
        return; // Document not open
    }

    var model = new InfoBarModel("This document has issues.");
    IVsInfoBarUIFactory factory = (IVsInfoBarUIFactory)
        ServiceProvider.GlobalProvider.GetService(typeof(SVsInfoBarUIFactory));
    IVsInfoBarUIElement uiElement = factory.CreateInfoBar(model);

    frame.GetProperty(
        (int)__VSFPROPID7.VSFPROPID_InfoBarHost, out object hostObj);

    if (hostObj is IVsInfoBarHost host)
    {
        host.AddInfoBar(uiElement);
    }
}
```

### Show InfoBar in a ToolWindowPane (built-in support)

`ToolWindowPane` has built-in support via `AddInfoBar()`:

```csharp
[Guid("your-tool-window-guid")]
public class MyToolWindow : ToolWindowPane
{
    public void ShowInfoBar()
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        var model = new InfoBarModel(
            "Configuration has changed.",
            new[] { new InfoBarButton("Reload") },
            KnownMonikers.Refresh);

        // AddInfoBar is a built-in ToolWindowPane method
        AddInfoBar(model);
    }

    // Built-in event handlers
    protected override void OnInfoBarClosed(IVsInfoBarUIElement element)
    {
        // Clean up
    }

    protected override void OnInfoBarActionItemClicked(
        IVsInfoBarUIElement element, IVsInfoBarActionItem actionItem)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (actionItem.Text == "Reload")
        {
            // Reload
        }
    }
}
```

### Handle events via IVsInfoBarUIEvents

When not using `ToolWindowPane.AddInfoBar()`, implement `IVsInfoBarUIEvents` to handle clicks and close:

```csharp
internal class InfoBarEventSink : IVsInfoBarUIEvents
{
    public void OnActionItemClicked(
        IVsInfoBarUIElement infoBarUIElement,
        IVsInfoBarActionItem actionItem)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        if (actionItem is InfoBarHyperlink link && link.Text == "hyperlink")
        {
            // Handle hyperlink click
        }
        else if (actionItem is InfoBarButton button && button.Text == "Click Me")
        {
            // Handle button click
        }
    }

    public void OnClosed(IVsInfoBarUIElement infoBarUIElement)
    {
        // InfoBar was closed — clean up
        // Important: Unadvise to prevent memory leaks
        infoBarUIElement.Unadvise(_cookie);
    }

    internal uint _cookie;
}

// When subscribing:
var sink = new InfoBarEventSink();
uiElement.Advise(sink, out uint cookie);
sink._cookie = cookie;
```

---

## Guidelines

- **Do** keep InfoBar text short and to the point.
- **Do** keep action links and buttons succinct — one or two actions maximum.
- **Do** use appropriate `KnownMonikers` icons (`StatusInformation`, `StatusWarning`, `StatusError`).
- **Do** use `Unadvise` to clean up event subscriptions (VSSDK approach) or handle `OnClosed` to avoid leaks.
- **Don't** use an InfoBar in place of a modal dialog when the user must respond immediately.
- **Don't** stack multiple InfoBars in the same window unless absolutely necessary (max three visible before scrolling).
- **Don't** use a global (main window) InfoBar unless the message is truly IDE-wide — it causes layout shift.
- **Prefer** the Toolkit's `VS.InfoBar.CreateAsync()` for the simplest in-proc solution.
- **Prefer** `ToolWindowPane.AddInfoBar()` when you own the tool window — it handles event wiring automatically.

## What NOT to do

> **Do NOT** use InfoBars for critical blocking operations — use a message box or user prompt instead. InfoBars are non-blocking by design.

> **Do NOT** stack multiple InfoBars in the same window — consolidate into one with multiple actions, or dismiss the previous one first.

> **Do NOT** use a global (main window) InfoBar unless truly IDE-wide — it causes layout shift. Attach to the relevant tool/document window.

> **Do NOT** forget `Unadvise` (VSSDK) or `OnClosed` handling (Toolkit) — leaked event handlers accumulate memory.

> **Do NOT** use `Process.Start` for InfoBar hyperlinks without validating the URL — never construct URLs from untrusted input.

## Troubleshooting

- **InfoBar doesn't appear:** For Toolkit, verify the tool window GUID passed to `VS.InfoBar.CreateAsync` is valid. For VSSDK, ensure you're obtaining the correct `IVsInfoBarHost` — the main window host differs from per-tool-window hosts.
- **InfoBar appears but action clicks do nothing:** Verify your `ActionItemClicked` handler (Toolkit) or `IVsInfoBarUIEvents.OnActionItemClicked` handler (VSSDK) is subscribed. For VSSDK, verify `uiElement.Advise(this, out _)` was called.
- **Multiple InfoBars stack and become scrollable:** Don't show more than 2-3 InfoBars in the same window. Dismiss previous ones before showing new ones, or consolidate into a single InfoBar with multiple actions.
- **InfoBar persists after it should be gone:** Call `infoBar.Close()` (Toolkit) or `uiElement.Close()` (VSSDK) when the notification is resolved.
- **Global InfoBar causes layout shift:** Don't use the main window InfoBar host for extension-specific messages. Attach to the relevant tool window or document window instead.

## See also

- [vs-message-box](../showing-message-boxes/SKILL.md)
- [vs-error-handling](../handling-extension-errors/SKILL.md)
- [vs-error-list](../integrating-error-list/SKILL.md)
- [vs-tool-window](../adding-tool-windows/SKILL.md)
