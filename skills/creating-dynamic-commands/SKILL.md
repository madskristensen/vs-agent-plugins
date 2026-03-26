---
name: creating-dynamic-commands
description: Create dynamic menu items that change at runtime based on data in Visual Studio extensions. Use when the user asks about dynamic menus, runtime-generated menu items, recent files lists, DynamicItemStart, BaseDynamicCommand, OleMenuCommand with MatchedCommandId, or menus that change their items based on runtime state in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Dynamic Commands in Visual Studio Extensions

Dynamic commands create menu items on the fly based on runtime data. Unlike regular commands that have a fixed set of buttons, dynamic commands generate one menu item per data item — perfect for "recent files" lists, open-document pickers, or any contextual menu that changes over time.

Dynamic commands solve a fundamental UX problem: static menus can't represent variable-length data. Without dynamic commands, you'd have to pre-allocate hidden menu items and show/hide them — which is fragile and limits list size.

**When to use this vs. alternatives:**
- Menu items generated from runtime data (lists, recent items) → **this skill**
- Fixed commands that show/hide based on context → [vs-command-visibility](../controlling-command-visibility/SKILL.md)
- A static set of commands with fixed menu entries → [vs-commands](../adding-commands/SKILL.md)
- An interactive list that doesn't fit in a menu (too many items) → tool window with a list UI (see [vs-tool-window](../adding-tool-windows/SKILL.md))

---

## 1. VSIX Community Toolkit (in-process)

The toolkit provides `BaseDynamicCommand<TCommand, TItem>` to make dynamic menus easy.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Step 1 — Define the command in .vsct

A dynamic command is defined like a regular button, but with the `DynamicItemStart` flag. This tells Visual Studio that the button is the anchor for a list of dynamic items.

```xml
<Buttons>
  <Button guid="MyPackage" id="DynamicCommand" priority="0x0100" type="Button">
    <Parent guid="MyPackage" id="MyMenuGroup" />
    <CommandFlag>DynamicItemStart</CommandFlag>
    <CommandFlag>DynamicVisibility</CommandFlag>
    <Strings>
      <ButtonText>Dynamic Item</ButtonText>
    </Strings>
  </Button>
</Buttons>
```

> **Important:** The command IDs that follow your button ID must be left *unassigned*. Visual Studio uses those sequential IDs for each dynamic item.

### Step 2 — Implement the command class

Create a class that inherits from `BaseDynamicCommand<TCommand, TItem>` where `TItem` is the data type each menu item represents.

Override three methods:

1. `GetItems()` — return the list of items to create menu entries for.
2. `BeforeQueryStatus(...)` — set the text and visibility of each menu item.
3. `ExecuteAsync(...)` — handle the click on a dynamic item.

```csharp
[Command("489ba882-f600-4c8b-89db-eb366a4ee3b3", 0x0100)]
public class RecentItemsCommand : BaseDynamicCommand<RecentItemsCommand, string>
{
    protected override IReadOnlyList<string> GetItems()
    {
        // Return whatever data should generate menu items.
        return new[] { "Alpha", "Beta", "Gamma" };
    }

    protected override void BeforeQueryStatus(OleMenuCommand menuItem, EventArgs e, string item)
    {
        // Set the text that appears in the menu for this item.
        menuItem.Text = item;
    }

    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e, string item)
    {
        await VS.MessageBox.ShowAsync($"You clicked: {item}");
    }
}
```

Register the command the same way as any other command:

```csharp
protected override async Task InitializeAsync(
    CancellationToken cancellationToken,
    IProgress<ServiceProgressData> progress)
{
    await this.RegisterCommandsAsync();
}
```

### How it works

When the menu opens, Visual Studio calls `GetItems()` to fetch the current list. It creates one menu entry per item and calls `BeforeQueryStatus` for each, so you can set the text, icon, enabled state, or visibility. When the user clicks an entry, `ExecuteAsync` (or `Execute`) is invoked with the corresponding item.

### Using complex data types

The generic `TItem` parameter can be any type:

```csharp
public class RecentFile
{
    public string FilePath { get; set; }
    public DateTime LastOpened { get; set; }
}

[Command("489ba882-f600-4c8b-89db-eb366a4ee3b3", 0x0200)]
public class RecentFilesCommand : BaseDynamicCommand<RecentFilesCommand, RecentFile>
{
    protected override IReadOnlyList<RecentFile> GetItems()
    {
        return MySettings.GetRecentFiles();
    }

    protected override void BeforeQueryStatus(OleMenuCommand menuItem, EventArgs e, RecentFile item)
    {
        menuItem.Text = Path.GetFileName(item.FilePath);
    }

    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e, RecentFile item)
    {
        await VS.Documents.OpenAsync(item.FilePath);
    }
}
```

---

## 2. VSSDK (in-process, legacy)

In raw VSSDK, dynamic commands are built using `OleMenuCommand` with the `MatchedCommandId` pattern.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `System.ComponentModel.Design`

### Step 1 — .vsct definition

Same as the toolkit approach — use `DynamicItemStart`:

```xml
<Buttons>
  <Button guid="guidMyCmdSet" id="cmdidDynamicStart" priority="0x0100" type="Button">
    <Parent guid="guidMyCmdSet" id="MyMenuGroup" />
    <CommandFlag>DynamicItemStart</CommandFlag>
    <CommandFlag>DynamicVisibility</CommandFlag>
    <Strings>
      <ButtonText>Dynamic Item</ButtonText>
    </Strings>
  </Button>
</Buttons>
```

### Step 2 — Register with OleMenuCommand

```csharp
protected override async Task InitializeAsync(
    CancellationToken cancellationToken,
    IProgress<ServiceProgressData> progress)
{
    await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

    OleMenuCommandService commandService =
        await GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;

    var dynamicItemRootId = new CommandID(
        new Guid("your-command-set-guid"), 0x0100);

    var dynamicCommand = new OleMenuCommand(
        OnDynamicItemInvoked,
        changeHandler: null,
        beforeQueryStatus: OnBeforeQueryStatusDynamic,
        dynamicItemRootId);

    // This predicate tells VS which command IDs belong to this dynamic set
    dynamicCommand.MatchedCommandId = 0;

    commandService.AddCommand(dynamicCommand);
}
```

### Step 3 — BeforeQueryStatus callback

```csharp
private readonly string[] _items = { "Alpha", "Beta", "Gamma" };

private void OnBeforeQueryStatusDynamic(object sender, EventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();
    var cmd = (OleMenuCommand)sender;

    // The MatchedCommandId is set by VS to indicate which dynamic item is being queried
    int index = cmd.MatchedCommandId - 0x0100; // Subtract your base command ID

    cmd.Enabled = true;
    cmd.Visible = index < _items.Length;

    if (index < _items.Length)
    {
        cmd.Text = _items[index];
        cmd.MatchedCommandId = 0; // Reset for next query
    }
}
```

### Step 4 — Execute callback

```csharp
private void OnDynamicItemInvoked(object sender, EventArgs e)
{
    ThreadHelper.ThrowIfNotOnUIThread();
    var cmd = (OleMenuCommand)sender;

    int index = cmd.MatchedCommandId - 0x0100;
    if (index >= 0 && index < _items.Length)
    {
        string clickedItem = _items[index];
        VsShellUtilities.ShowMessageBox(
            this, $"You clicked: {clickedItem}", "Dynamic Command",
            OLEMSGICON.OLEMSGICON_INFO, OLEMSGBUTTON.OLEMSGBUTTON_OK,
            OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
    }
}
```

> **Note:** The raw VSSDK approach is error-prone because you must manually manage command ID arithmetic and `MatchedCommandId` state. The toolkit's `BaseDynamicCommand<TCommand, TItem>` is strongly recommended over this pattern.

---

## 3. VisualStudio.Extensibility (out-of-process)

The VisualStudio.Extensibility SDK does **not** currently have a direct equivalent of `DynamicItemStart` / `BaseDynamicCommand` for runtime-generated menu items.

However, you can achieve similar behavior by:

1. **Toggling command visibility** — show/hide a predefined set of commands based on context using `VisibleWhen` constraints and runtime state.

2. **Using a tool window with a list** — present dynamic items in a tool window with a list/tree UI instead of a menu. This is often a better UX for large or variable-length lists.

3. **Using a mixed in-proc/out-of-proc extension** — keep your main logic out-of-process but use an in-process companion for the dynamic command registration.

---

## Troubleshooting

- **Dynamic menu items don't appear:** Verify the `.vsct` button has the `DynamicItemStart` command flag. Without it, VS treats the command as a single static button.
- **Only the first item appears:** Your `GetItems()` override (Toolkit) or `MatchedCommandId` loop (VSSDK) isn't returning all items. Debug by checking the data source and ensuring the ID range is large enough.
- **Click handler fires for the wrong item:** The `MatchedCommandId` offset calculation is off. The selected item index is `commandId - baseCommandId`. Verify your base ID matches the `IDSymbol` value in `.vsct`.
- **Menu flickers or items appear stale:** The data source for dynamic items is changing between `BeforeQueryStatus` calls. Cache the list at a stable point and only refresh on explicit triggers.

## What NOT to do

> **Do NOT** pre-allocate fixed hidden commands as a substitute — use `DynamicItemStart` and `BaseDynamicCommand` (Toolkit) or `OleMenuCommand` with `MatchedCommandId` (VSSDK).

> **Do NOT** use dynamic commands for very large lists (50+ items) — use a tool window with a searchable list instead.

> **Do NOT** use VisualStudio.Extensibility for dynamic menu items — it doesn't support `DynamicItemStart`. Use in-process Toolkit/VSSDK, or present items in a tool window.

## See also

- [vs-commands](../adding-commands/SKILL.md)
- [vs-command-visibility](../controlling-command-visibility/SKILL.md)
- [vs-context-menu](../adding-context-menus/SKILL.md)
- [vs-tool-window](../adding-tool-windows/SKILL.md)

## Additional resources

- [VSIX Cookbook — Dynamic Commands](https://www.vsixcookbook.com/recipes/dynamic-commands.html)
- [VSIX Cookbook — Menus & Commands](https://www.vsixcookbook.com/recipes/menus-buttons-commands.html)
- [Visual Studio Command Table (.vsct) Files](https://learn.microsoft.com/visualstudio/extensibility/internals/visual-studio-command-table-dot-vsct-files)
