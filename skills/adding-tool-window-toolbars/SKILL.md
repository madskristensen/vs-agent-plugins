---
name: adding-tool-window-toolbars
description: Add a toolbar to a custom tool window in Visual Studio extensions. Use when the user asks how to add buttons, toolbar, or command bar to a tool window, or wants to place commands at the top of a tool window pane. The toolbar must be defined declaratively via VSCT (Menus, Groups, Buttons) or ToolbarConfiguration — never by adding a WPF ToolBar control to the UserControl XAML. Covers VisualStudio.Extensibility (out-of-process, ToolbarConfiguration), VSIX Community Toolkit (in-process, VSCT + ToolWindowPane.ToolBar), and legacy VSSDK (in-process, VSCT + ToolWindowPane.ToolBar) approaches.
---

# Adding a Toolbar to a Tool Window in Visual Studio Extensions

A tool window toolbar is a horizontal strip of command buttons docked at the top (or any edge) of a tool window. Unlike IDE-level toolbars, a tool window toolbar is always attached to its window, cannot be undocked, and scales to the window's width.

> **Critical rule:** The toolbar **must** be defined declaratively — in a `.vsct` file (VSSDK / Community Toolkit) or via `ToolbarConfiguration` (VisualStudio.Extensibility). **Never** add a WPF `<ToolBar>` or `<ToolBarTray>` element to the UserControl XAML loaded in the tool window. A WPF toolbar will not participate in the VS command system — it won't support keyboard shortcuts, key bindings, command routing, theming, or the standard toolbar overflow/chevron behavior that the native VS toolbar chrome provides.

Tool window toolbars provide primary actions that are always visible without opening a context menu. They integrate with the VS command table (`.vsct` or `ToolbarConfiguration`), meaning buttons automatically get keyboard shortcuts, localization, theming, and accessibility. Using the VS-native toolbar instead of a WPF toolbar also ensures consistent visual behavior (overflow chevron, high DPI, theme changes).

**When to use this vs. alternatives:**
- Persistent action buttons at the top of a tool window → **Tool window toolbar** (this skill)
- Search functionality in a tool window → [vs-tool-window-search](../adding-tool-window-search/SKILL.md)
- Creating the tool window itself → [vs-tool-window](../adding-tool-windows/SKILL.md)
- IDE-level menu/toolbar commands (not in a tool window) → [vs-commands](../adding-commands/SKILL.md)
- Context menu on right-click within a tool window → [vs-context-menu](../adding-context-menus/SKILL.md)

## Implementation checklist

- [ ] Create the tool window (see [vs-tool-window](../adding-tool-windows/SKILL.md))
- [ ] Define toolbar commands (VisualStudio.Extensibility: `Command` classes; VSSDK: `.vsct` buttons)
- [ ] Define the toolbar (VisualStudio.Extensibility: `ToolbarConfiguration`; VSSDK: `.vsct` menu type="Toolbar")
- [ ] Wire the toolbar to the tool window pane

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Toolbars are declared in code using `ToolbarConfiguration` and referenced from the `ToolWindowConfiguration`. No `.vsct` file is needed.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility`, `Microsoft.VisualStudio.Extensibility.Commands`, `Microsoft.VisualStudio.Extensibility.ToolWindows`

### Step 1: Define the toolbar commands

Each toolbar button is a standard `Command`. Place them in a `Commands/` folder.

**Commands/RefreshCommand.cs:**

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Commands;

namespace MyExtension.Commands;

[VisualStudioContribution]
internal class RefreshCommand : Command
{
    public RefreshCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Refresh")
    {
        Icon = new(ImageMoniker.KnownValues.Refresh, IconSettings.IconAndText),
    };

    public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
    {
        // Refresh logic here
    }
}
```

**Commands/ClearAllCommand.cs:**

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Commands;

namespace MyExtension.Commands;

[VisualStudioContribution]
internal class ClearAllCommand : Command
{
    public ClearAllCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Clear All")
    {
        Icon = new(ImageMoniker.KnownValues.ClearWindowContent, IconSettings.IconAndText),
    };

    public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
    {
        // Clear logic here
    }
}
```

### Step 2: Define the toolbar configuration

The `ToolbarConfiguration` declares which commands appear on the toolbar and their order. This static property can live on any class — commonly the `Extension` entry point or the tool window class itself.

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Commands;

namespace MyExtension;

[VisualStudioContribution]
internal class MyToolWindowToolbar
{
    [VisualStudioContribution]
    public static ToolbarConfiguration MyToolbar => new("%MyToolbar.DisplayName%")
    {
        Children =
        [
            ToolbarChild.Command<RefreshCommand>(),
            ToolbarChild.Separator,
            ToolbarChild.Command<ClearAllCommand>(),
        ],
    };
}
```

To localize the display name, add a string resource entry for `MyToolbar.DisplayName`. If localization is not needed, use a plain string:

```csharp
public static ToolbarConfiguration MyToolbar => new("My Window Toolbar")
{
    Children =
    [
        ToolbarChild.Command<RefreshCommand>(),
        ToolbarChild.Separator,
        ToolbarChild.Command<ClearAllCommand>(),
    ],
};
```

### Step 3: Reference the toolbar from the tool window

Set the `Toolbar` property on `ToolWindowConfiguration` to bind the toolbar to the tool window.

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.ToolWindows;
using Microsoft.VisualStudio.RpcContracts.RemoteUI;

namespace MyExtension;

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
        Toolbar = new(MyToolWindowToolbar.MyToolbar),
    };

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

### Grouping toolbar items

Use `ToolbarChild.Group` for visual grouping separated by dividers, or `ToolbarChild.Separator` for a simple separator line between individual commands:

```csharp
public static ToolbarConfiguration MyToolbar => new("My Window Toolbar")
{
    Children =
    [
        ToolbarChild.Group(
            GroupChild.Command<RefreshCommand>(),
            GroupChild.Command<ClearAllCommand>()),
        ToolbarChild.Group(
            GroupChild.Command<SettingsCommand>()),
    ],
};
```

---

## 2. VSIX Community Toolkit (in-process)

The toolbar is defined in the `.vsct` file using a `Menu` element with `type="ToolWindowToolbar"`. The `ToolWindowPane` (inner `Pane` class) then references it via the `ToolBar` property.

**NuGet packages:** `Community.VisualStudio.Toolkit`, `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Community.VisualStudio.Toolkit`, `Microsoft.VisualStudio.Shell`

### Step 1: Define the toolbar in the .vsct file

The `.vsct` file must declare three things: a **Menu** (the toolbar itself), a **Group** parented to the toolbar, and **Button** elements parented to the group.

**MyExtensionPackage.vsct:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<CommandTable xmlns="http://schemas.microsoft.com/VisualStudio/2005-10-18/CommandTable"
              xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <Extern href="stdidcmd.h"/>
  <Extern href="vsshlids.h"/>
  <Include href="KnownImageIds.vsct"/>

  <Commands package="guidMyExtensionPackage">

    <!-- ═══ Toolbar (Menu of type ToolWindowToolbar) ═══ -->
    <Menus>
      <Menu guid="guidMyExtensionCmdSet" id="MyToolWindowToolbar" type="ToolWindowToolbar">
        <CommandFlag>DefaultDocked</CommandFlag>
        <Strings>
          <ButtonText>My Window Toolbar</ButtonText>
        </Strings>
      </Menu>
    </Menus>

    <!-- ═══ Group parented to the toolbar ═══ -->
    <Groups>
      <Group guid="guidMyExtensionCmdSet" id="MyToolWindowToolbarGroup" priority="0x0000">
        <Parent guid="guidMyExtensionCmdSet" id="MyToolWindowToolbar"/>
      </Group>
    </Groups>

    <!-- ═══ Buttons on the toolbar ═══ -->
    <Buttons>
      <Button guid="guidMyExtensionCmdSet" id="RefreshCommandId" priority="0x0100" type="Button">
        <Parent guid="guidMyExtensionCmdSet" id="MyToolWindowToolbarGroup"/>
        <Icon guid="ImageCatalogGuid" id="Refresh"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Refresh</ButtonText>
        </Strings>
      </Button>

      <Button guid="guidMyExtensionCmdSet" id="ClearAllCommandId" priority="0x0200" type="Button">
        <Parent guid="guidMyExtensionCmdSet" id="MyToolWindowToolbarGroup"/>
        <Icon guid="ImageCatalogGuid" id="ClearWindowContent"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Clear All</ButtonText>
        </Strings>
      </Button>
    </Buttons>

  </Commands>

  <Symbols>
    <GuidSymbol name="guidMyExtensionPackage" value="{YOUR-PACKAGE-GUID}"/>

    <GuidSymbol name="guidMyExtensionCmdSet" value="{YOUR-CMDSET-GUID}">
      <!-- Toolbar and group -->
      <IDSymbol name="MyToolWindowToolbar"      value="0x1000"/>
      <IDSymbol name="MyToolWindowToolbarGroup"  value="0x1050"/>
      <!-- Buttons -->
      <IDSymbol name="RefreshCommandId"          value="0x0100"/>
      <IDSymbol name="ClearAllCommandId"         value="0x0101"/>
    </GuidSymbol>
  </Symbols>

</CommandTable>
```

**VSCT structure summary:**

| Element | Purpose |
|---------|---------|
| `<Menu type="ToolWindowToolbar">` | Declares the toolbar. The `type` attribute is what makes VS render it as a tool window toolbar instead of a main menu bar or context menu. |
| `<CommandFlag>DefaultDocked</CommandFlag>` | Ensures the toolbar is docked by default. |
| `<Group>` with `<Parent>` pointing to the toolbar | Creates a logical grouping on the toolbar. Multiple groups produce visual separators between them. |
| `<Button>` with `<Parent>` pointing to the group | Each button is a command on the toolbar. |

> **Do not** parent buttons directly to the `<Menu>`. Always create at least one `<Group>` as an intermediary — this is how VS command tables work. Buttons parented directly to a `Menu` will not appear.

### Step 2: Wire the toolbar to the tool window pane

In the `BaseToolWindow<T>` inner `Pane` class, set `this.ToolBar` to a `CommandID` pointing at the toolbar's GUID/ID pair.

```csharp
using System;
using System.ComponentModel.Design;
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
        return new MyToolWindowControl();
    }

    [Guid("YOUR-PANE-GUID")]
    internal class Pane : ToolWindowPane
    {
        public Pane()
        {
            BitmapImageMoniker = KnownMonikers.ToolWindow;

            // Wire up the toolbar defined in .vsct
            ToolBar = new CommandID(
                PackageGuids.guidMyExtensionCmdSet,
                PackageIds.MyToolWindowToolbar);
        }
    }
}
```

The `PackageGuids` and `PackageIds` constants are auto-generated from the `.vsct` file's `<Symbols>` section by the VSCT compiler.

### Step 3: Implement the toolbar button commands

Each button gets its own `BaseCommand<T>` class:

**Commands/RefreshCommand.cs:**

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.RefreshCommandId)]
internal sealed class RefreshCommand : BaseCommand<RefreshCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Refresh", "Refreshing data...");
    }
}
```

**Commands/ClearAllCommand.cs:**

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.ClearAllCommandId)]
internal sealed class ClearAllCommand : BaseCommand<ClearAllCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Clear", "Clearing all items...");
    }
}
```

### Step 4: Register in the package

```csharp
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration(Vsix.Name, Vsix.Description, Vsix.Version)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[ProvideToolWindow(typeof(MyToolWindow.Pane), Style = VsDockStyle.Tabbed, Window = WindowGuids.SolutionExplorer)]
[Guid(PackageGuids.guidMyExtensionPackageString)]
public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await this.RegisterCommandsAsync();
        this.RegisterToolWindows();
    }
}
```

### Controlling toolbar position

By default the toolbar docks at the top. Set `ToolBarLocation` to change the edge:

```csharp
public Pane()
{
    ToolBar = new CommandID(
        PackageGuids.guidMyExtensionCmdSet,
        PackageIds.MyToolWindowToolbar);
    ToolBarLocation = (int)VSTWT_LOCATION.VSTWT_TOP;    // Top (default)
    // Other options: VSTWT_LEFT, VSTWT_RIGHT, VSTWT_BOTTOM
}
```

### Multiple groups on the toolbar

Define additional groups in the `.vsct` file to create visual separators between clusters of buttons:

```xml
<Groups>
  <Group guid="guidMyExtensionCmdSet" id="ToolbarGroup1" priority="0x0000">
    <Parent guid="guidMyExtensionCmdSet" id="MyToolWindowToolbar"/>
  </Group>
  <Group guid="guidMyExtensionCmdSet" id="ToolbarGroup2" priority="0x0100">
    <Parent guid="guidMyExtensionCmdSet" id="MyToolWindowToolbar"/>
  </Group>
</Groups>
```

Parent some buttons to `ToolbarGroup1` and others to `ToolbarGroup2`. VS renders a thin divider between groups.

---

## 3. VSSDK (in-process, legacy)

The raw VSSDK approach is structurally identical to the Community Toolkit — the toolbar is declared in `.vsct` and bound via `ToolWindowPane.ToolBar`. The difference is that commands are registered manually with `OleMenuCommandService` instead of using `BaseCommand<T>`.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Step 1: Define the toolbar in the .vsct file

Use the same `.vsct` structure as section 2 — `<Menu type="ToolWindowToolbar">`, `<Group>`, and `<Button>` elements. The format is identical.

### Step 2: Set the toolbar in the ToolWindowPane constructor

```csharp
using System;
using System.ComponentModel.Design;
using System.Runtime.InteropServices;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[Guid("YOUR-TOOL-WINDOW-GUID")]
public class MyToolWindow : ToolWindowPane
{
    public const string CmdSetGuidString = "YOUR-CMDSET-GUID";
    public static readonly Guid CmdSetGuid = new(CmdSetGuidString);
    public const int ToolbarId = 0x1000;

    public MyToolWindow() : base(null)
    {
        Caption = "My Tool Window";

        // Bind the toolbar declared in .vsct to this tool window
        ToolBar = new CommandID(CmdSetGuid, ToolbarId);
        ToolBarLocation = (int)VSTWT_LOCATION.VSTWT_TOP;
    }
}
```

### Step 3: Register toolbar button commands in the package

```csharp
using System;
using System.ComponentModel.Design;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[ProvideToolWindow(typeof(MyToolWindow), Style = VsDockStyle.Tabbed, Window = ToolWindowGuids.SolutionExplorer)]
[Guid("YOUR-PACKAGE-GUID")]
public sealed class MyPackage : AsyncPackage
{
    // Command IDs matching the .vsct Symbols
    private const int RefreshCommandId = 0x0100;
    private const int ClearAllCommandId = 0x0101;

    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        OleMenuCommandService commandService =
            await GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;

        // Register toolbar button handlers
        var refreshCmdId = new CommandID(MyToolWindow.CmdSetGuid, RefreshCommandId);
        commandService.AddCommand(new MenuCommand(OnRefresh, refreshCmdId));

        var clearCmdId = new CommandID(MyToolWindow.CmdSetGuid, ClearAllCommandId);
        commandService.AddCommand(new MenuCommand(OnClearAll, clearCmdId));

        // Register the command that shows the tool window
        var showCmdId = new CommandID(MyToolWindow.CmdSetGuid, 0x0200);
        commandService.AddCommand(new MenuCommand(ShowToolWindow, showCmdId));
    }

    private void OnRefresh(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        // Refresh logic — access the tool window content if needed:
        var window = (MyToolWindow)FindToolWindow(typeof(MyToolWindow), 0, false);
        // window?.Content ...
    }

    private void OnClearAll(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        // Clear logic
    }

    private void ShowToolWindow(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var window = FindToolWindow(typeof(MyToolWindow), 0, true);
        if (window?.Frame == null)
            throw new NotSupportedException("Cannot create tool window");

        IVsWindowFrame frame = (IVsWindowFrame)window.Frame;
        Microsoft.VisualStudio.ErrorHandler.ThrowOnFailure(frame.Show());
    }
}
```

### Enabling/disabling toolbar buttons at runtime (VSSDK)

Use `OleMenuCommand` instead of `MenuCommand` to get a `BeforeQueryStatus` callback:

```csharp
var refreshCmdId = new CommandID(MyToolWindow.CmdSetGuid, RefreshCommandId);
var oleCmd = new OleMenuCommand(OnRefresh, refreshCmdId);
oleCmd.BeforeQueryStatus += (s, e) =>
{
    ThreadHelper.ThrowIfNotOnUIThread();
    oleCmd.Enabled = /* your condition */;
};
commandService.AddCommand(oleCmd);
```

---

## Why NOT a WPF ToolBar in XAML

It may be tempting to add a `<ToolBar>` to your tool window's UserControl:

```xml
<!-- ❌ DO NOT DO THIS -->
<UserControl ...>
    <DockPanel>
        <ToolBar DockPanel.Dock="Top">
            <Button Content="Refresh" Click="OnRefresh"/>
        </ToolBar>
        <TextBox />
    </DockPanel>
</UserControl>
```

This approach has serious drawbacks:

| Issue | Detail |
|-------|--------|
| **No command routing** | WPF buttons don't participate in the VS command table. They cannot be discovered via **Tools > Customize** or the command well. |
| **No keyboard shortcuts** | VS keybindings (`<KeyBindings>` in `.vsct`) only work with commands registered in the command table. |
| **No theming** | The native VS toolbar chrome automatically adapts to the current VS theme (light, dark, blue, high contrast). A WPF `ToolBar` won't match unless you manually bind every color. |
| **No overflow chevron** | The native toolbar handles overflow gracefully when the window is too narrow. A WPF `ToolBar`'s overflow is a different control with different behavior. |
| **Inconsistent UX** | Tool window toolbars throughout VS all use the native chrome. A WPF toolbar will look and feel different, breaking user expectations. |

Always define the toolbar declaratively via `.vsct` or `ToolbarConfiguration`.

---

## Key guidance

- **VisualStudio.Extensibility** — Define a `ToolbarConfiguration` with `ToolbarChild.Command<T>()` entries. Reference it from `ToolWindowConfiguration.Toolbar`. No `.vsct` file needed.
- **Community Toolkit / VSSDK** — Declare a `<Menu type="ToolWindowToolbar">` in the `.vsct` file, with groups and buttons. Set `ToolWindowPane.ToolBar = new CommandID(...)` in the pane constructor.
- **Never** put a WPF `<ToolBar>` in the tool window's UserControl XAML. Use the VS command-table-based toolbar for proper command routing, keyboard shortcuts, theming, and overflow behavior.
- Parent buttons to **groups**, not directly to the toolbar menu.
- Use `<CommandFlag>DefaultDocked</CommandFlag>` on the toolbar `<Menu>` element.
- Use `<CommandFlag>IconIsMoniker</CommandFlag>` with `guid="ImageCatalogGuid"` on buttons to reference KnownMonikers icons.
- Set `ToolBarLocation` on the `ToolWindowPane` to control which edge the toolbar docks to (default is top).

## Troubleshooting

- **Toolbar doesn't appear in tool window:** For VSSDK/Toolkit, verify `ToolWindowPane.ToolBar` is set to the correct `CommandID` matching the toolbar `<Menu>` GUID and ID in `.vsct`. For Extensibility, ensure `ToolWindowConfiguration.Toolbar` references your `ToolbarConfiguration`.
- **Buttons appear but clicks do nothing:** The button's command handler isn't registered. For VSSDK, verify `OleMenuCommandService.AddCommand` is called. For Extensibility, ensure command classes have `[VisualStudioContribution]`.
- **Toolbar buttons are grayed out:** The command's `QueryStatus`/`BeforeQueryStatus` is returning disabled. Check visibility rules and `OleMenuCommand.Enabled` property.
- **Icons don't appear on buttons:** For `.vsct`, ensure `<CommandFlag>IconIsMoniker</CommandFlag>` is set and the `guid` is `ImageCatalogGuid`. For Extensibility, verify the `IconName` property references a valid `KnownMonikers` value.
- **Toolbar appears in the wrong tool window:** The `ToolBar` property is set on the wrong `ToolWindowPane`. Each pane has its own `ToolBar` property — set it in the correct pane's constructor.

## See also

- [vs-tool-window](../adding-tool-windows/SKILL.md) — creating tool windows that host toolbars
- [vs-tool-window-search](../adding-tool-window-search/SKILL.md) — adding search alongside the toolbar
- [vs-commands](../adding-commands/SKILL.md) — command registration (toolbar buttons are commands)
- [vs-context-menu](../adding-context-menus/SKILL.md) — right-click menus as an alternative to toolbar actions

## References

- [Add a toolbar to a tool window (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/adding-a-toolbar-to-a-tool-window)
- [Add a tool window — toolbar section (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/adding-a-tool-window#add-a-toolbar-to-the-tool-window)
- [Menus and Toolbars (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/command/menus-and-toolbars)
- [Tool Windows — toolbar section (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/tool-window/tool-window#add-a-toolbar-to-a-tool-window)
- [Custom Tool Windows (VSIX Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/custom-tool-windows)
- [VSCT XML Schema Reference](https://learn.microsoft.com/visualstudio/extensibility/vsct-xml-schema-reference)
