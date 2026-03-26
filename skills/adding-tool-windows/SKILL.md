---
name: adding-tool-windows
description: Create and show tool windows in Visual Studio extensions. Use when the user asks how to add a custom tool window, dockable panel, or tool pane to a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process, Remote UI), VSIX Community Toolkit (BaseToolWindow with async initialization), and legacy VSSDK (ToolWindowPane) approaches.
---

# Adding Tool Windows to Visual Studio Extensions

A tool window is a dockable panel in Visual Studio (like Solution Explorer or Error List). It consists of an outer shell managed by VS and custom content provided by your extension.

Tool windows give extensions a persistent, dockable surface whose position, visibility, and dock state VS saves automatically across sessions. Without them, interactive extensions are limited to transient dialogs or output text.

**When to use a tool window vs. alternatives:**
- Persistent UI the user returns to repeatedly → **tool window**
- One-shot confirmation or choice → message box (see [vs-message-box](../showing-message-boxes/SKILL.md))
- Non-blocking notification → info bar (see [vs-info-bar](../showing-info-bars/SKILL.md))
- UI tightly coupled to a specific document → editor margin (see [vs-editor-margin](../adding-editor-margins/SKILL.md))
- Detailed log output → Output Window pane (see [vs-error-handling](../handling-extension-errors/SKILL.md))

## Implementation checklist

- [ ] Create the tool window class (extends `ToolWindow` or `BaseToolWindow<>` or `ToolWindowPane`)
- [ ] Create the UI content (RemoteUserControl + XAML template, or WPF UserControl)
- [ ] Create a command to show the tool window
- [ ] Register in `.vsixmanifest` (Toolkit/VSSDK only)

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Tool windows use **Remote UI** — your extension runs out-of-process and defines XAML `DataTemplate`s that VS renders in-process. This keeps VS stable even if your extension crashes.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility.ToolWindows`, `Microsoft.VisualStudio.Extensibility.UI`

### Step 1: Create the tool window class

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.ToolWindows;
using Microsoft.VisualStudio.RpcContracts.RemoteUI;

[VisualStudioContribution]
internal class MyToolWindow : ToolWindow
{
    private readonly MyToolWindowContent content = new();

    public MyToolWindow(VisualStudioExtensibility extensibility)
        : base(extensibility)
    {
        Title = "My Tool Window";
    }

    public override ToolWindowConfiguration ToolWindowConfiguration => new()
    {
        Placement = ToolWindowPlacement.DocumentWell,
        DockDirection = Dock.Right,
        AllowAutoCreation = true,
    };

    public override async Task InitializeAsync(CancellationToken cancellationToken)
    {
        // Do any async work BEFORE the UI is created (e.g., load data, query services).
        // This runs before GetContentAsync is called.
    }

    public override Task<IRemoteUserControl> GetContentAsync(CancellationToken cancellationToken)
        => Task.FromResult<IRemoteUserControl>(content);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            content.Dispose();
        base.Dispose(disposing);
    }
}
```

### Step 2: Create the RemoteUserControl

**MyToolWindowContent.cs:**

```csharp
using Microsoft.VisualStudio.Extensibility.UI;

internal class MyToolWindowContent : RemoteUserControl
{
    public MyToolWindowContent()
        : base(dataContext: new MyToolWindowData())
    {
    }

    public override async Task ControlLoadedAsync(CancellationToken cancellationToken)
    {
        await base.ControlLoadedAsync(cancellationToken);
        // Called after the UI is rendered — safe to start background updates here.
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
    }
}
```

### Step 3: Define the data context

```csharp
using System.Runtime.Serialization;
using Microsoft.VisualStudio.Extensibility.UI;

[DataContract]
internal class MyToolWindowData : NotifyPropertyChangedObject
{
    private string? _statusText = "Ready";

    [DataMember]
    public string? StatusText
    {
        get => _statusText;
        set => SetProperty(ref _statusText, value);
    }

    [DataMember]
    public IAsyncCommand RefreshCommand { get; }

    public MyToolWindowData()
    {
        RefreshCommand = new AsyncCommand(async (parameter, ct) =>
        {
            StatusText = "Refreshing...";
            // Do work
            StatusText = "Done";
        });
    }
}
```

### Step 4: Define the XAML (embedded resource)

**MyToolWindowContent.xaml:**

```xml
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              xmlns:vs="http://schemas.microsoft.com/visualstudio/extensibility/2022/xaml">
    <StackPanel Orientation="Vertical" Margin="10">
        <TextBlock Text="{Binding StatusText}" />
        <Button Content="Refresh" Command="{Binding RefreshCommand}" Margin="0,8,0,0" />
    </StackPanel>
</DataTemplate>
```

Add it as an embedded resource in your `.csproj`:

```xml
<ItemGroup>
  <!-- Simple case: XAML file name matches the RemoteUserControl class name -->
  <EmbeddedResource Include="MyToolWindowContent.xaml" />
  <Page Remove="MyToolWindowContent.xaml" />

  <!-- When the XAML file name differs from the RemoteUserControl class name -->
  <EmbeddedResource Include="Views\MyToolWindowView.xaml">
    <!-- LogicalName must match the fully qualified RemoteUserControl class name + ".xaml" -->
    <LogicalName>MyCompany.MyExtension.RemoteUI.MyToolWindowContent.xaml</LogicalName>
  </EmbeddedResource>
</ItemGroup>
```

### Step 5: Create a command to show the tool window

```csharp
[VisualStudioContribution]
public class ShowMyToolWindowCommand : Command
{
    public ShowMyToolWindowCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("My Tool Window")
    {
        Placements = new[] { CommandPlacement.KnownPlacements.ViewOtherWindowsMenu },
        Icon = new(ImageMoniker.KnownValues.ToolWindow, IconSettings.IconAndText),
    };

    public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
    {
        await this.Extensibility.Shell().ShowToolWindowAsync<MyToolWindow>(activate: true, ct);
    }
}
```

### Conditional visibility

Tool windows can auto-show/hide based on activation constraints:

```csharp
public override ToolWindowConfiguration ToolWindowConfiguration => new()
{
    Placement = ToolWindowPlacement.DocumentWell,
    // Show only when a .cs file is the active document
    VisibleWhen = ActivationConstraint.ClientContext(
        ClientContextKey.Shell.ActiveSelectionFileName, @"\.cs$"),
};
```

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit provides `BaseToolWindow<T>` which uses an **async factory pattern** — do your async work in `CreateAsync` before returning the WPF control. This prevents blocking the UI thread during initialization.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Step 1: Create the tool window class

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Imaging;
using Microsoft.VisualStudio.Shell;

public class MyToolWindow : BaseToolWindow<MyToolWindow>
{
    public override string GetTitle(int toolWindowId) => "My Tool Window";

    public override Type PaneType => typeof(Pane);

    public override async Task<FrameworkElement> CreateAsync(int toolWindowId, CancellationToken cancellationToken)
    {
        // ✅ Do ALL async work here BEFORE creating the WPF control.
        // This runs on a background thread — the UI is NOT blocked.
        var data = await LoadDataFromServiceAsync(cancellationToken);

        // Only return the control after async work is done.
        return new MyToolWindowControl(data);
    }

    [Guid("d3b3ebd9-87d1-41cd-bf84-268d88953417")]
    internal class Pane : ToolWindowPane
    {
        public Pane()
        {
            BitmapImageMoniker = KnownMonikers.StatusInformation;
        }
    }

    private async Task<MyData> LoadDataFromServiceAsync(CancellationToken ct)
    {
        // Simulate loading data from a service or file
        await Task.Delay(500, ct);
        return new MyData { Message = "Loaded!" };
    }
}
```

> **Key pattern:** `CreateAsync` is the async factory. Do ALL slow work (file I/O, service calls, solution queries) inside `CreateAsync` before instantiating the `UserControl`. This ensures the WPF content is ready when VS renders the tool window, with zero UI-thread blocking.

### Step 2: Create the WPF UserControl

**MyToolWindowControl.xaml:**

```xml
<UserControl x:Class="MyExtension.MyToolWindowControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:toolkit="clr-namespace:Community.VisualStudio.Toolkit;assembly=Community.VisualStudio.Toolkit"
             toolkit:Themes.UseVsTheme="True">
    <StackPanel Orientation="Vertical" Margin="10">
        <TextBlock x:Name="StatusLabel" Text="Ready" />
        <Button Content="Refresh" Click="OnRefreshClick" Margin="0,8,0,0" />
    </StackPanel>
</UserControl>
```

**MyToolWindowControl.xaml.cs:**

```csharp
using System.Windows;
using System.Windows.Controls;

namespace MyExtension
{
    public partial class MyToolWindowControl : UserControl
    {
        public MyToolWindowControl(MyData data)
        {
            InitializeComponent();
            StatusLabel.Text = data.Message;
        }

        private void OnRefreshClick(object sender, RoutedEventArgs e)
        {
            StatusLabel.Text = "Refreshed!";
        }
    }
}
```

### Step 3: Register in your package

```csharp
[ProvideToolWindow(typeof(MyToolWindow.Pane), Style = VsDockStyle.Tabbed, Window = WindowGuids.SolutionExplorer)]
public sealed class MyPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        this.RegisterToolWindows();
    }
}
```

> The package must inherit from `ToolkitPackage`, not `AsyncPackage`.

### Step 4: Create a command to show it

```csharp
[Command(PackageIds.MyToolWindowCommand)]
internal sealed class ShowMyToolWindowCommand : BaseCommand<ShowMyToolWindowCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await MyToolWindow.ShowAsync();
    }
}
```

---

## 3. VSSDK (in-process, legacy)

The raw VSSDK uses `ToolWindowPane` and `AsyncPackage.FindToolWindow`. To follow async best practices, use `AsyncPackage` and perform initialization in `InitializeAsync` before the tool window UI loads.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Step 1: Create the ToolWindowPane

```csharp
using System;
using System.Runtime.InteropServices;
using Microsoft.VisualStudio.Shell;

[Guid("a1b2c3d4-e5f6-7890-abcd-ef1234567890")]
public class MyToolWindow : ToolWindowPane
{
    public MyToolWindow() : base(null)
    {
        this.Caption = "My Tool Window";

        // ⚠️ Do NOT do slow work here — this runs on the UI thread.
        // The WPF content is set later after async init completes.
    }

    /// <summary>
    /// Called by the package after async initialization is done.
    /// Sets the WPF content with pre-loaded data.
    /// </summary>
    public void SetContent(MyToolWindowControl control)
    {
        this.Content = control;
    }
}
```

### Step 2: Create the WPF UserControl

**MyToolWindowControl.xaml:**

```xml
<UserControl x:Class="MyExtension.MyToolWindowControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <StackPanel Orientation="Vertical" Margin="10">
        <TextBlock x:Name="StatusLabel" Text="Ready" />
        <Button Content="Refresh" Click="OnRefreshClick" Margin="0,8,0,0" />
    </StackPanel>
</UserControl>
```

**MyToolWindowControl.xaml.cs:**

```csharp
using System.Windows;
using System.Windows.Controls;

namespace MyExtension
{
    public partial class MyToolWindowControl : UserControl
    {
        public MyToolWindowControl(string initialMessage)
        {
            InitializeComponent();
            StatusLabel.Text = initialMessage;
        }

        private void OnRefreshClick(object sender, RoutedEventArgs e)
        {
            StatusLabel.Text = "Refreshed!";
        }
    }
}
```

### Step 3: Register and initialize in your package

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[ProvideToolWindow(typeof(MyToolWindow), Style = VsDockStyle.Tabbed, Window = ToolWindowGuids.SolutionExplorer)]
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid("your-package-guid-here")]
public sealed class MyPackage : AsyncPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        // ✅ Background-thread async work happens here.
        var data = await LoadDataAsync(cancellationToken);

        // Switch to UI thread to create WPF controls and register commands.
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        // Now find/create the tool window pane and set its UI.
        var window = (MyToolWindow)FindToolWindow(typeof(MyToolWindow), 0, true);
        if (window?.Frame == null)
            throw new NotSupportedException("Cannot create tool window");

        window.SetContent(new MyToolWindowControl(data.Message));

        // Register the command to show the tool window.
        OleMenuCommandService commandService = await GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
        var cmdId = new CommandID(PackageGuids.MyCmdSet, PackageIds.ShowMyToolWindowCommand);
        commandService?.AddCommand(new MenuCommand(ShowToolWindow, cmdId));
    }

    private void ShowToolWindow(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var window = FindToolWindow(typeof(MyToolWindow), 0, true);
        if (window?.Frame == null)
            throw new NotSupportedException("Cannot create tool window");

        IVsWindowFrame windowFrame = (IVsWindowFrame)window.Frame;
        Microsoft.VisualStudio.ErrorHandler.ThrowOnFailure(windowFrame.Show());
    }

    private async Task<MyData> LoadDataAsync(CancellationToken ct)
    {
        await Task.Delay(500, ct);
        return new MyData { Message = "Loaded!" };
    }
}
```

> **Key pattern:** Use `AsyncPackage` with `AllowsBackgroundLoading = true`. Perform all async work in `InitializeAsync` on the background thread, then call `JoinableTaskFactory.SwitchToMainThreadAsync()` before touching WPF or VS services that require the UI thread. Never do slow work in the `ToolWindowPane` constructor.

---

## Key guidance

- **VisualStudio.Extensibility** — Use `InitializeAsync` on the `ToolWindow` for pre-load async work; UI is defined via Remote UI `DataTemplate`s that render in-process.
- **Community Toolkit** — Use the `CreateAsync` async factory to load data before returning the WPF `FrameworkElement`. Never do slow work in the `Pane` constructor.
- **VSSDK** — Use `AsyncPackage.InitializeAsync` to do background work, then `SwitchToMainThreadAsync` before creating WPF content. Never block the UI thread in the `ToolWindowPane` constructor.
- Always `Dispose` your tool window content to avoid leaks.
- Place tool window commands under **View > Other Windows** by convention.

## Troubleshooting

- **Tool window doesn't appear in the menu:** Ensure the command to show the tool window is registered. For Extensibility, verify the `[VisualStudioContribution]` attribute is on both the `ToolWindow` class and the `Command` class. For Toolkit, ensure `this.RegisterToolWindows()` is called in `InitializeAsync`.
- **XAML content is blank (Extensibility / Remote UI):** Verify the `.xaml` file is set as `EmbeddedResource` with `<Page Remove="..."/>` in the `.csproj`. If the XAML file name doesn't match the `RemoteUserControl` class name, set the `<LogicalName>` to the fully qualified class name + `.xaml`.
- **Tool window content flickers or is empty on first open (Toolkit):** You're doing async work in the `Pane` constructor instead of `CreateAsync`. Move all async initialization to the `CreateAsync` factory method.
- **"Cannot create tool window" exception (VSSDK):** The `[ProvideToolWindow]` attribute is missing from the package class, or the GUID on the `ToolWindowPane` doesn't match the one in the attribute.
- **Tool window state not persisted between sessions:** For Extensibility, check that `AllowAutoCreation` is set appropriately in `ToolWindowConfiguration`. For VSSDK / Toolkit, verify the `[ProvideToolWindow]` `Style` and `Window` parameters are set.
- **Memory leak when opening/closing the tool window:** You're not disposing the `RemoteUserControl` (Extensibility) or not unsubscribing from events in the WPF `UserControl`. Override `Dispose` and clean up.

## What NOT to do

> **Do NOT** do slow or async work in the `ToolWindowPane` constructor (VSSDK) or `Pane` constructor (Toolkit) — they run on the UI thread and freeze VS. Use `InitializeAsync` (VSSDK) or `CreateAsync` (Toolkit) instead.

> **Do NOT** use synchronous `Package` — use `AsyncPackage` with `AllowsBackgroundLoading = true` (VSSDK) or `ToolkitPackage` (Toolkit). Sync packages degrade IDE launch time.

> **Do NOT** create WPF controls on a background thread — WPF requires the UI thread. Creating controls before `SwitchToMainThreadAsync` causes `InvalidOperationException`.

> **Do NOT** set `ToolWindowPane.Content` to a `FrameworkElement` with inline async calls in its constructor — the WPF constructor should be synchronous and fast.

> **Do NOT** block the UI thread with `.Result`/`.Wait()`/`.GetAwaiter().GetResult()` in tool window initialization — use `async`/`await` with `JoinableTaskFactory`.

> **Do NOT** forget to `Dispose` your `RemoteUserControl` (Extensibility) or unsubscribe from events in WPF `UserControl` — undisposed content causes memory leaks.

> **Do NOT** use `ToolWindowPane` with the older synchronous `Package.FindToolWindow` — use `AsyncPackage` and async initialization. Old templates may show the sync pattern; do not follow them.

## See also

- [vs-commands](../adding-commands/SKILL.md)
- [vs-async-threading](../handling-async-threading/SKILL.md)
- [vs-theming](../theming-extension-ui/SKILL.md)
- [vs-tool-window-toolbar](../adding-tool-window-toolbars/SKILL.md)
- [vs-tool-window-search](../adding-tool-window-search/SKILL.md)

## References

- [Tool Windows (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/tool-window/tool-window)
- [Remote UI (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/inside-the-sdk/remote-ui)
- [Custom Tool Windows (VSIX Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/custom-tool-windows)
- [Add a Tool Window (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/adding-a-tool-window)
