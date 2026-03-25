---
name: vs-context-menu
description: Add native-looking context menus to custom WPF UI in Visual Studio extensions (tool windows, custom tree views, list views). Use when the user wants to show a right-click context menu from their own UI that looks native to VS. Covers defining VSCT context menus (type="Context"), grouping commands with separators, and programmatically showing them via IVsUIShell.ShowContextMenu. Do NOT use regular WPF ContextMenu — it won't match VS theming or support command routing. Covers VSSDK and VSIX Community Toolkit (in-process). VisualStudio.Extensibility (out-of-process) does not support VSCT-based context menus on custom UI.
---

# Adding Context Menus to Custom UI in Visual Studio Extensions

When you build custom WPF UI inside a Visual Studio extension (for example a tree view in a tool window), you need context menus that look and behave like native VS menus — with proper theming, keyboard navigation, and command routing. **Do not use the standard WPF `ContextMenu` class.** It won't match the VS theme, won't participate in VS command routing, and won't support `BeforeQueryStatus` for dynamic enable/disable.

Instead, define your context menus in VSCT (the same command table used for toolbars and main menu items), then show them programmatically from your WPF event handlers using `IVsUIShell.ShowContextMenu`.

---

## VisualStudio.Extensibility (out-of-process) — Not Supported

The new out-of-process extensibility model does **not** support showing VSCT-based context menus from custom Remote UI controls. Remote UI runs in a separate process and cannot call `IVsUIShell.ShowContextMenu`. If you need context menus on custom UI, use the in-process VSSDK / Community Toolkit approach below.

---

## VSSDK and VSIX Community Toolkit (in-process)

Both approaches use the same underlying VSCT command table and `IVsUIShell` API. The Community Toolkit simplifies command registration (via `[Command]` and `BaseCommand<T>`) but the context menu definition and display mechanism are identical.

### Architecture overview

Adding a context menu to custom UI requires three pieces:

1. **VSCT menu definitions** — Declare context menus (`type="Context"`), groups, and buttons in your `.vsct` file.
2. **WPF event handlers** — Handle `PreviewMouseRightButtonDown` (to select and track the clicked item) and `PreviewMouseRightButtonUp` (to show the correct context menu).
3. **`IVsUIShell.ShowContextMenu`** — The VS shell API that displays the VSCT-defined menu at a screen coordinate.

### Step 1: Define context menus in VSCT

Each distinct right-click target (node type, item type, etc.) gets its own context menu. Menus of `type="Context"` are invisible until you show them programmatically.

```xml
<?xml version="1.0" encoding="utf-8"?>
<CommandTable xmlns="http://schemas.microsoft.com/VisualStudio/2005-10-18/CommandTable"
              xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <Extern href="stdidcmd.h"/>
  <Extern href="vsshlids.h"/>
  <Include href="KnownImageIds.vsct"/>
  <Include href="VSGlobals.vsct"/>

  <Commands package="MyPackage">

    <!-- ==================== CONTEXT MENUS ==================== -->
    <Menus>
      <!-- Context menu shown when right-clicking a "Project" item -->
      <Menu guid="MyPackage" id="ProjectContextMenu" type="Context">
        <Strings>
          <CommandName>Project</CommandName>
        </Strings>
      </Menu>

      <!-- Context menu shown when right-clicking a "File" item -->
      <Menu guid="MyPackage" id="FileContextMenu" type="Context">
        <Strings>
          <CommandName>File</CommandName>
        </Strings>
      </Menu>
    </Menus>

    <!-- ==================== GROUPS ==================== -->
    <!-- Groups control visual separators. Each group within a menu
         is separated from the next by a horizontal line. -->
    <Groups>
      <!-- Primary actions for Project nodes -->
      <Group guid="MyPackage" id="ProjectActionsGroup" priority="0x0100">
        <Parent guid="MyPackage" id="ProjectContextMenu"/>
      </Group>

      <!-- Secondary actions (e.g. Refresh) for Project nodes -->
      <Group guid="MyPackage" id="ProjectRefreshGroup" priority="0x0200">
        <Parent guid="MyPackage" id="ProjectContextMenu"/>
      </Group>

      <!-- Actions for File nodes -->
      <Group guid="MyPackage" id="FileActionsGroup" priority="0x0100">
        <Parent guid="MyPackage" id="FileContextMenu"/>
      </Group>

      <Group guid="MyPackage" id="FileDeleteGroup" priority="0x0200">
        <Parent guid="MyPackage" id="FileContextMenu"/>
      </Group>
    </Groups>

    <!-- ==================== BUTTONS ==================== -->
    <Buttons>
      <!-- "Open" command in the Project context menu -->
      <Button guid="MyPackage" id="OpenProject" priority="0x0100" type="Button">
        <Parent guid="MyPackage" id="ProjectActionsGroup"/>
        <Icon guid="ImageCatalogGuid" id="OpenFolder"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Open</ButtonText>
        </Strings>
      </Button>

      <!-- "Refresh" command in the Project context menu (second group = separator above) -->
      <Button guid="MyPackage" id="RefreshProject" priority="0x0100" type="Button">
        <Parent guid="MyPackage" id="ProjectRefreshGroup"/>
        <Icon guid="ImageCatalogGuid" id="Refresh"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Refresh</ButtonText>
        </Strings>
      </Button>

      <!-- "Open" command in the File context menu -->
      <Button guid="MyPackage" id="OpenFile" priority="0x0100" type="Button">
        <Parent guid="MyPackage" id="FileActionsGroup"/>
        <Icon guid="ImageCatalogGuid" id="OpenFile"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Open</ButtonText>
        </Strings>
      </Button>

      <!-- "Delete" command in the File context menu -->
      <Button guid="MyPackage" id="DeleteFile" priority="0x0100" type="Button">
        <Parent guid="MyPackage" id="FileDeleteGroup"/>
        <Icon guid="ImageCatalogGuid" id="Cancel"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Delete</ButtonText>
        </Strings>
      </Button>
    </Buttons>
  </Commands>

  <Symbols>
    <GuidSymbol name="MyPackage" value="{YOUR-GUID-HERE}">
      <!-- Menus -->
      <IDSymbol name="ProjectContextMenu" value="0x1000" />
      <IDSymbol name="FileContextMenu" value="0x1001" />

      <!-- Groups -->
      <IDSymbol name="ProjectActionsGroup" value="0x1100" />
      <IDSymbol name="ProjectRefreshGroup" value="0x1101" />
      <IDSymbol name="FileActionsGroup" value="0x1200" />
      <IDSymbol name="FileDeleteGroup" value="0x1201" />

      <!-- Commands -->
      <IDSymbol name="OpenProject" value="0x0100" />
      <IDSymbol name="RefreshProject" value="0x0101" />
      <IDSymbol name="OpenFile" value="0x0200" />
      <IDSymbol name="DeleteFile" value="0x0201" />
    </GuidSymbol>
  </Symbols>
</CommandTable>
```

**Key points:**
- `type="Context"` makes the menu invisible in the main UI — it only appears when you call `ShowContextMenu`.
- **Groups create separators.** Buttons in the same group appear together; a horizontal line separates groups.
- **Priority** within a group controls button ordering (lower = higher in the menu).
- Use `KnownMonikers` icons via `<Icon guid="ImageCatalogGuid" id="..."/>` with the `IconIsMoniker` flag.

### Step 2: Give each item type a context menu ID

If your custom UI has different item types (e.g., a tree view with project nodes and file nodes), each item type should know which VSCT context menu to display. A simple pattern is an abstract property on the base class:

```csharp
internal abstract class MyNodeBase : INotifyPropertyChanged
{
    public string Label { get; set; }

    /// <summary>
    /// The VSCT context menu ID to show on right-click. Return 0 for no context menu.
    /// </summary>
    public abstract int ContextMenuId { get; }

    // ... other shared properties
}

internal class ProjectNode : MyNodeBase
{
    public override int ContextMenuId => PackageIds.ProjectContextMenu;
}

internal class FileNode : MyNodeBase
{
    public override int ContextMenuId => PackageIds.FileContextMenu;
}

internal class LoadingNode : MyNodeBase
{
    // No context menu for placeholder nodes
    public override int ContextMenuId => 0;
}
```

`PackageIds` is the auto-generated class from VSCT (created by the VSIX Synchronizer or the SDK build). It contains `const int` fields for every `IDSymbol` in your `.vsct` file.

### Step 3: Handle right-click in WPF and show the VSCT context menu

There are two parts to the right-click handling:

1. **`PreviewMouseRightButtonDown`** — Walk up the visual tree to find the clicked item, select it, and store a reference to it. This runs synchronously _before_ VS evaluates `BeforeQueryStatus` on your commands.
2. **`PreviewMouseRightButtonUp`** — Look up the context menu ID from the clicked item and call `IVsUIShell.ShowContextMenu`.

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

public partial class MyToolWindowControl : UserControl
{
    // Tracks which node was right-clicked, so commands can access it
    // during BeforeQueryStatus (which runs before Execute).
    private static MyNodeBase _rightClickedNode;

    internal static MyNodeBase RightClickedNode => _rightClickedNode;

    public MyToolWindowControl()
    {
        InitializeComponent();

        MyTreeView.PreviewMouseRightButtonDown += TreeView_PreviewMouseRightButtonDown;
        MyTreeView.PreviewMouseRightButtonUp += TreeView_PreviewMouseRightButtonUp;
    }

    private void TreeView_PreviewMouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        // Walk up from the click target to find the TreeViewItem
        DependencyObject source = e.OriginalSource as DependencyObject;
        while (source != null && source is not TreeViewItem)
        {
            source = VisualTreeHelper.GetParent(source);
        }

        if (source is TreeViewItem item)
        {
            // Select the item under the cursor (VS convention)
            item.IsSelected = true;
            item.Focus();

            // Store the node reference synchronously — this must happen
            // BEFORE BeforeQueryStatus runs on the context menu commands.
            _rightClickedNode = item.DataContext as MyNodeBase;

            e.Handled = true;
        }
        else
        {
            _rightClickedNode = null;
        }
    }

    private void TreeView_PreviewMouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_rightClickedNode == null || _rightClickedNode.ContextMenuId == 0)
            return;

        ShowVsContextMenu(_rightClickedNode.ContextMenuId, e);
        e.Handled = true;
    }

    private void ShowVsContextMenu(int menuId, MouseButtonEventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        var shell = (IVsUIShell)ServiceProvider.GlobalProvider.GetService(typeof(SVsUIShell));
        if (shell == null)
            return;

        // Force VS to re-evaluate BeforeQueryStatus on all commands in the menu.
        // Without this, command states may be stale from a previous invocation.
        shell.UpdateCommandUI(1); // 1 = fImmediateUpdate

        // Convert the mouse position to screen coordinates
        UIElement source = e.OriginalSource as UIElement ?? this;
        Point screenPoint = source.PointToScreen(e.GetPosition(source));

        // Use YOUR package's command set GUID (from the auto-generated PackageGuids class)
        Guid cmdSetGuid = PackageGuids.MyPackage;

        var points = new POINTS[]
        {
            new()
            {
                x = (short)screenPoint.X,
                y = (short)screenPoint.Y
            }
        };

        shell.ShowContextMenu(0, ref cmdSetGuid, menuId, points, null);
    }
}
```

**Critical details:**
- Call `shell.UpdateCommandUI(1)` before `ShowContextMenu`. Without this, `BeforeQueryStatus` handlers are only called once and the results are cached, so toggling enable/disable or visibility won't work correctly.
- The GUID passed to `ShowContextMenu` must match the `guid` attribute on the `<Menu>` element in your `.vsct` file.
- The `menuId` is the integer ID of the context menu (e.g., `PackageIds.ProjectContextMenu`).
- The `POINTS` struct uses screen coordinates — use `PointToScreen` to convert from WPF element-relative coordinates.

### Step 4: Implement commands with BeforeQueryStatus

Commands placed in context menus typically use `BeforeQueryStatus` to enable/disable themselves based on the right-clicked item. With the Community Toolkit, use `BaseCommand<T>`:

```csharp
using Community.VisualStudio.Toolkit;

[Command(PackageIds.OpenProject)]
internal sealed class OpenProjectCommand : BaseCommand<OpenProjectCommand>
{
    protected override void BeforeQueryStatus(EventArgs e)
    {
        // Only enable when a ProjectNode is right-clicked
        Command.Enabled = MyToolWindowControl.RightClickedNode is ProjectNode;
    }

    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        if (MyToolWindowControl.RightClickedNode is not ProjectNode project)
            return;

        // ... perform the action
    }
}
```

With raw VSSDK (no Community Toolkit), register the command in your package's `InitializeAsync`:

```csharp
using Microsoft.VisualStudio.Shell;

protected override async Task InitializeAsync(
    CancellationToken cancellationToken,
    IProgress<ServiceProgressData> progress)
{
    await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

    var commandService = await GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;

    var openProjectCmdId = new CommandID(PackageGuids.MyPackage, PackageIds.OpenProject);
    var openProjectCmd = new OleMenuCommand(OnOpenProject, openProjectCmdId);
    openProjectCmd.BeforeQueryStatus += OnOpenProjectBeforeQueryStatus;
    commandService.AddCommand(openProjectCmd);
}

private void OnOpenProjectBeforeQueryStatus(object sender, EventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();
    if (sender is OleMenuCommand cmd)
    {
        cmd.Enabled = MyToolWindowControl.RightClickedNode is ProjectNode;
    }
}

private void OnOpenProject(object sender, EventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();
    if (MyToolWindowControl.RightClickedNode is not ProjectNode project)
        return;

    // ... perform the action
}
```

### Placing the same command in multiple context menus

Use `<CommandPlacements>` to place a single command button into multiple context menus without duplicating the `<Button>` definition:

```xml
<CommandPlacements>
  <!-- Place "Open in Portal" in both Project and File context menus -->
  <CommandPlacement guid="MyPackage" id="OpenInPortal" priority="0x0100">
    <Parent guid="MyPackage" id="ProjectActionsGroup"/>
  </CommandPlacement>
  <CommandPlacement guid="MyPackage" id="OpenInPortal" priority="0x0100">
    <Parent guid="MyPackage" id="FileActionsGroup"/>
  </CommandPlacement>
</CommandPlacements>
```

### Adding flyout (sub-menu) to a context menu

To add a nested sub-menu inside a context menu, define a menu of `type="Menu"` parented to one of the context menu's groups:

```xml
<Menus>
  <!-- Flyout submenu inside the Project context menu -->
  <Menu guid="MyPackage" id="AdvancedFlyout" priority="0x0100" type="Menu">
    <Parent guid="MyPackage" id="ProjectActionsGroup"/>
    <CommandFlag>IconIsMoniker</CommandFlag>
    <Strings>
      <CommandName>Advanced</CommandName>
    </Strings>
  </Menu>
</Menus>

<Groups>
  <!-- Group inside the flyout for its buttons -->
  <Group guid="MyPackage" id="AdvancedFlyoutGroup" priority="0x0100">
    <Parent guid="MyPackage" id="AdvancedFlyout"/>
  </Group>
</Groups>

<Buttons>
  <Button guid="MyPackage" id="AdvancedAction1" priority="0x0100" type="Button">
    <Parent guid="MyPackage" id="AdvancedFlyoutGroup"/>
    <Strings>
      <ButtonText>Advanced Action 1</ButtonText>
    </Strings>
  </Button>
</Buttons>
```

### Showing context menus for ListView or DataGrid items

The same pattern works for any WPF `ItemsControl`. For a `ListView`:

```csharp
MyListView.PreviewMouseRightButtonDown += (s, e) =>
{
    DependencyObject source = e.OriginalSource as DependencyObject;
    while (source != null && source is not ListViewItem)
    {
        source = VisualTreeHelper.GetParent(source);
    }

    if (source is ListViewItem listItem)
    {
        listItem.IsSelected = true;
        _rightClickedItem = listItem.DataContext as MyItemBase;
        e.Handled = true;
    }
    else
    {
        _rightClickedItem = null;
    }
};

MyListView.PreviewMouseRightButtonUp += (s, e) =>
{
    if (_rightClickedItem?.ContextMenuId is int id and > 0)
    {
        ShowVsContextMenu(id, e);
        e.Handled = true;
    }
};
```

### Hiding or showing individual commands dynamically

Use `BeforeQueryStatus` to hide commands entirely (not just disable):

```csharp
protected override void BeforeQueryStatus(EventArgs e)
{
    // Hide the command entirely when not applicable (instead of graying out)
    Command.Visible = MyToolWindowControl.RightClickedNode is ProjectNode;
    Command.Enabled = Command.Visible;
}
```

In VSCT, add `DynamicVisibility` and `DefaultInvisible` flags so the button starts hidden and `BeforeQueryStatus` can toggle it:

```xml
<Button guid="MyPackage" id="SpecialAction" priority="0x0100" type="Button">
  <Parent guid="MyPackage" id="ProjectActionsGroup"/>
  <CommandFlag>DynamicVisibility</CommandFlag>
  <CommandFlag>DefaultInvisible</CommandFlag>
  <Strings>
    <ButtonText>Special Action</ButtonText>
  </Strings>
</Button>
```

---

## Common mistakes

| Mistake | Fix |
|---|---|
| Using WPF `ContextMenu` on a tree view inside a tool window | Use VSCT `type="Context"` menus + `IVsUIShell.ShowContextMenu` |
| Context menu shows stale enabled/disabled state | Call `shell.UpdateCommandUI(1)` before `ShowContextMenu` |
| `BeforeQueryStatus` sees the wrong node | Store the right-clicked node in `PreviewMouseRightButtonDown` (synchronous, before query status runs) — don't rely on `SelectedItem` which may update asynchronously |
| Menu doesn't appear | Verify the GUID passed to `ShowContextMenu` matches the `guid` on the `<Menu>` in VSCT, and the `menuId` matches the `IDSymbol` value |
| No separators between command groups | Each `<Group>` with a different priority creates a separator; put buttons in separate groups to get dividers |

## What NOT to do

> **Do NOT** use WPF `ContextMenu` controls on tree views or custom controls inside tool windows. WPF context menus don't integrate with the VS command system — they won't support keyboard shortcuts, command routing, `BeforeQueryStatus` enable/disable, or VS theming. Use VSCT `type="Context"` menus shown via `IVsUIShell.ShowContextMenu` instead.

> **Do NOT** call `ShowContextMenu` without first calling `shell.UpdateCommandUI(1)`. Without this, `BeforeQueryStatus` handlers don't re-evaluate, and commands may show stale enabled/disabled/visible state from the previous invocation.

> **Do NOT** rely on `SelectedItem` in `BeforeQueryStatus` to determine the right-clicked node. `SelectedItem` updates asynchronously and may not reflect the node under the cursor when `BeforeQueryStatus` runs. Instead, capture the right-clicked node in `PreviewMouseRightButtonDown` (synchronous, fires before query status) and store it in a field.

> **Do NOT** parent `<Button>` elements directly to a `<Menu>` in `.vsct`. Always create at least one `<Group>` as an intermediary — buttons parented directly to a menu will not appear. Groups also provide automatic separators between logical clusters of commands.

> **Do NOT** forget to match the GUID in `ShowContextMenu` with the `guid` on the `<Menu>` element in your `.vsct` file. A mismatched GUID causes the menu to silently not appear, with no error message.
