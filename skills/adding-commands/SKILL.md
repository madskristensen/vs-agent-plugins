---
name: adding-commands
description: Add commands (menu items, toolbar buttons) to Visual Studio extensions. Use when the user asks how to create a command, add a menu item, add a toolbar button, register a command handler, wire up a .vsct file, use KnownMonikers icons on buttons, or place commands in menus/toolbars in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Adding Commands to Visual Studio Extensions

A command is any user-invokable action — menu items, toolbar buttons, context menu entries, keyboard shortcuts. Each command has an ID, a display name, an optional icon, a placement (where it appears in the UI), and an execution handler.

Commands are the primary way users interact with an extension. Without a command, your extension has no entry point — the user can't trigger it. In the VisualStudio.Extensibility model, commands are fully self-contained (placement, icon, and metadata are declared in code), eliminating the `.vsct` XML file that Toolkit and VSSDK extensions require. The `.vsct` approach gives finer control over placement and menu merging but is harder to author and debug.

**When to use this vs. alternatives:**
- Add an action to a menu, toolbar, or context menu → **this skill**
- Add a context menu entry specifically → combine with [vs-context-menu](../adding-context-menus/SKILL.md)
- Show/hide commands based on context → combine with [vs-command-visibility](../controlling-command-visibility/SKILL.md)
- Create commands that change text/state dynamically → [vs-dynamic-commands](../creating-dynamic-commands/SKILL.md)
- React to existing VS commands (intercept Copy, Build, etc.) → [vs-command-intercept](../intercepting-commands/SKILL.md)

## File organization

Every command class should be in its own `.cs` file inside a top-level `Commands/` folder in the project:

```
MyExtension/
├── Commands/
│   ├── BuildSolutionCommand.cs
│   ├── FormatDocumentCommand.cs
│   └── OpenSettingsCommand.cs
├── MyExtensionPackage.cs          ← (Toolkit / VSSDK only)
├── MyExtension.csproj
└── ...
```

One class per file. Name the file to match the class name.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Commands are self-contained classes that extend `Command`. No `.vsct` file is needed — placement, icon, and metadata are declared in code via `CommandConfiguration`.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility`, `Microsoft.VisualStudio.Extensibility.Commands`

### Basic command

**Commands/BuildSolutionCommand.cs:**

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Commands;

namespace MyExtension.Commands;

[VisualStudioContribution]
internal class BuildSolutionCommand : Command
{
    public BuildSolutionCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Build Solution")
    {
        Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
        Icon = new(ImageMoniker.KnownValues.BuildSolution, IconSettings.IconAndText),
    };

    public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
    {
        // Command logic here
        await this.Extensibility.Shell().ShowPromptAsync(
            "Build started.",
            PromptOptions.OK,
            ct);
    }
}
```

### Command placements

Use `CommandPlacement.KnownPlacements` for standard locations:

| Placement | Menu location |
|-----------|---------------|
| `ToolsMenu` | Tools menu |
| `ViewOtherWindowsMenu` | View > Other Windows |
| `ExtensionsMenu` | Extensions menu |

For custom parent groups, use `CommandPlacement.VsctParent` with the GUID and ID of the parent group from the `.vsct` schema.

### Icons

Use `ImageMoniker.KnownValues` for built-in VS icons:

```csharp
Icon = new(ImageMoniker.KnownValues.BuildSolution, IconSettings.IconAndText),
Icon = new(ImageMoniker.KnownValues.Settings, IconSettings.IconOnly),
Icon = new(ImageMoniker.KnownValues.AddFile, IconSettings.IconAndText),
```

`IconSettings`:
- `IconAndText` — shows both the icon and the display name.
- `IconOnly` — shows only the icon (used in toolbars).

### Custom icons

Place images as embedded resources and reference by custom moniker:

```csharp
[VisualStudioContribution]
internal static ImageMoniker MyCustomIcon = new("MyCustomIcon", KnownImageIds.ImageCatalogGuid);
```

### Shortcuts

```csharp
public override CommandConfiguration CommandConfiguration => new("Format Document")
{
    Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    Shortcuts = [new CommandShortcutConfiguration(ModifierKey.Control, Key.K, ModifierKey.Control, Key.D)],
};
```

### Conditional visibility

Show a command only when specific conditions are met:

```csharp
public override CommandConfiguration CommandConfiguration => new("Analyze C# File")
{
    Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    Icon = new(ImageMoniker.KnownValues.CSFileNode, IconSettings.IconAndText),
    VisibleWhen = ActivationConstraint.ClientContext(
        ClientContextKey.Shell.ActiveSelectionFileName, @"\.cs$"),
};
```

### Enabling/disabling at runtime

Override `CommandConfiguration.EnabledWhen` or toggle state in `ExecuteCommandAsync`:

```csharp
public override CommandConfiguration CommandConfiguration => new("Debug Command")
{
    Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    EnabledWhen = ActivationConstraint.SolutionState(SolutionState.FullyLoaded),
};
```

---

## 2. VSIX Community Toolkit (in-process)

Commands extend `BaseCommand<T>`. Each command is its own class and file. Commands must be declared in a `.vsct` file, which defines the button, its parent group, its icon, and keyboard shortcut.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Step 1: Define the command in the .vsct file

The `.vsct` file declares the command table — symbols, groups, buttons, and their placements. Every command button needs an entry here.

**MyExtensionPackage.vsct:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<CommandTable xmlns="http://schemas.microsoft.com/VisualStudio/2005-10-18/CommandTable"
              xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <Extern href="stdidcmd.h"/>
  <Extern href="vsshlids.h"/>
  <Include href="KnownImageIds.vsct"/>

  <Commands package="guidMyExtensionPackage">

    <!-- Define a command group -->
    <Groups>
      <Group guid="guidMyExtensionCmdSet" id="MyMenuGroup" priority="0x0600">
        <!-- Parent the group under the Tools menu -->
        <Parent guid="guidSHLMainMenu" id="IDM_VS_MENU_TOOLS"/>
      </Group>
    </Groups>

    <!-- Define the command buttons -->
    <Buttons>
      <Button guid="guidMyExtensionCmdSet" id="BuildSolutionCommandId" priority="0x0100" type="Button">
        <Parent guid="guidMyExtensionCmdSet" id="MyMenuGroup"/>
        <Icon guid="ImageCatalogGuid" id="BuildSolution"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Build Solution</ButtonText>
        </Strings>
      </Button>

      <Button guid="guidMyExtensionCmdSet" id="FormatDocumentCommandId" priority="0x0200" type="Button">
        <Parent guid="guidMyExtensionCmdSet" id="MyMenuGroup"/>
        <Icon guid="ImageCatalogGuid" id="FormatDocument"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Format Document</ButtonText>
        </Strings>
      </Button>

      <Button guid="guidMyExtensionCmdSet" id="OpenSettingsCommandId" priority="0x0300" type="Button">
        <Parent guid="guidMyExtensionCmdSet" id="MyMenuGroup"/>
        <Icon guid="ImageCatalogGuid" id="Settings"/>
        <CommandFlag>IconIsMoniker</CommandFlag>
        <Strings>
          <ButtonText>Open Settings</ButtonText>
        </Strings>
      </Button>
    </Buttons>

  </Commands>

  <!-- Symbol definitions -->
  <Symbols>
    <GuidSymbol name="guidMyExtensionPackage" value="{YOUR-PACKAGE-GUID}" />

    <GuidSymbol name="guidMyExtensionCmdSet" value="{YOUR-CMDSET-GUID}">
      <IDSymbol name="MyMenuGroup" value="0x1020" />
      <IDSymbol name="BuildSolutionCommandId" value="0x0100" />
      <IDSymbol name="FormatDocumentCommandId" value="0x0101" />
      <IDSymbol name="OpenSettingsCommandId" value="0x0102" />
    </GuidSymbol>
  </Symbols>

</CommandTable>
```

#### Key rules for .vsct buttons with KnownMonikers icons

1. **Include the image catalog:** Add `<Include href="KnownImageIds.vsct"/>` at the top of the `<CommandTable>`.
2. **Reference the moniker:** On the `<Icon>` element, use `guid="ImageCatalogGuid"` and set `id` to the KnownMoniker name (e.g., `BuildSolution`, `Settings`, `FormatDocument`).
3. **Add the `IconIsMoniker` flag:** Inside each `<Button>`, add `<CommandFlag>IconIsMoniker</CommandFlag>`. Without this flag, VS treats the icon reference as a legacy bitmap strip and the icon won't display.

#### Common KnownMonikers for commands

| KnownMoniker name | Use case |
|-------------------|----------|
| `BuildSolution` | Build / compile actions |
| `FormatDocument` | Formatting commands |
| `Settings` | Settings / configuration |
| `AddFile` | Add or create file |
| `Delete` | Remove / delete |
| `Refresh` | Refresh / reload |
| `Search` | Search / find |
| `Save` | Save operations |
| `RunOutline` | Run / execute |
| `CSFileNode` | C# file operations |
| `StatusInformation` | Information / about |
| `StatusWarning` | Warnings |
| `StatusError` | Error indicators |

> To browse the full list of 3,800+ KnownMonikers, install the **KnownMonikers Explorer** extension from the Visual Studio Marketplace. It adds a tool window (**View > Other Windows > KnownMonikers Explorer**) that lets you search and preview all available monikers.

#### Adding a keyboard shortcut in .vsct

```xml
<KeyBindings>
  <KeyBinding guid="guidMyExtensionCmdSet" id="FormatDocumentCommandId"
              editor="guidVSStd97"
              key1="K" mod1="Control"
              key2="D" mod2="Control" />
</KeyBindings>
```

Place the `<KeyBindings>` block as a sibling of `<Commands>` inside `<CommandTable>`.

#### Parenting buttons under different menus

Change the `<Parent>` on the `<Group>` to target a different menu:

| Menu | guid | id |
|------|------|----|
| Tools | `guidSHLMainMenu` | `IDM_VS_MENU_TOOLS` |
| Edit | `guidSHLMainMenu` | `IDM_VS_MENU_EDIT` |
| View | `guidSHLMainMenu` | `IDM_VS_MENU_VIEW` |
| Extensions | `guidSHLMainMenu` | `IDM_VS_MENU_EXTENSIONS` |
| Solution Explorer context menu | `guidSHLMainMenu` | `IDM_VS_CTXT_SOLNNODE` |
| Code window context menu | `guidSHLMainMenu` | `IDM_VS_CTXT_CODEWIN` |
| Project context menu | `guidSHLMainMenu` | `IDM_VS_CTXT_PROJNODE` |

### Step 2: Create the command class

Each command gets its own file in the `Commands/` folder.

**Commands/BuildSolutionCommand.cs:**

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.BuildSolutionCommandId)]
internal sealed class BuildSolutionCommand : BaseCommand<BuildSolutionCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Build Solution", "Starting build...");
    }
}
```

**Commands/FormatDocumentCommand.cs:**

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.FormatDocumentCommandId)]
internal sealed class FormatDocumentCommand : BaseCommand<FormatDocumentCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Format Document", "Formatting...");
    }
}
```

**Commands/OpenSettingsCommand.cs:**

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.OpenSettingsCommandId)]
internal sealed class OpenSettingsCommand : BaseCommand<OpenSettingsCommand>
{
    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Settings", "Opening settings...");
    }
}
```

### Step 3: Register commands in the package

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration(Vsix.Name, Vsix.Description, Vsix.Version)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[Guid(PackageGuids.MyExtensionPackageString)]
public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await this.RegisterCommandsAsync();
    }
}
```

`RegisterCommandsAsync()` discovers all `BaseCommand<T>` subclasses in the assembly and registers them automatically.

### Enabling/disabling at runtime (Community Toolkit)

Override `BeforeQueryStatus` to toggle the enabled or visible state:

```csharp
protected override void BeforeQueryStatus(EventArgs e)
{
    Command.Enabled = /* your condition */;
    Command.Visible = /* your condition */;
}
```

---

## 3. VSSDK (in-process, legacy)

Commands are registered manually with `OleMenuCommandService`. Like the Toolkit, commands must be declared in a `.vsct` file (see the `.vsct` example in section 2 — the file format is identical).

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`

### Step 1: Define buttons in the .vsct file

Use the same `.vsct` structure shown in section 2. The button definitions, `<Include href="KnownImageIds.vsct"/>`, `guid="ImageCatalogGuid"`, and `<CommandFlag>IconIsMoniker</CommandFlag>` rules are identical.

### Step 2: Create the command class

Each command is a standalone class with a static `Initialize` method and a private constructor. Keep each in its own file under `Commands/`.

**Commands/BuildSolutionCommand.cs:**

```csharp
using System;
using System.ComponentModel.Design;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

internal sealed class BuildSolutionCommand
{
    public static readonly Guid CommandSet = new("YOUR-CMDSET-GUID");
    public const int CommandId = 0x0100;

    private readonly AsyncPackage _package;

    private BuildSolutionCommand(AsyncPackage package, OleMenuCommandService commandService)
    {
        _package = package ?? throw new ArgumentNullException(nameof(package));
        commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

        var menuCommandId = new CommandID(CommandSet, CommandId);
        var menuItem = new MenuCommand(Execute, menuCommandId);
        commandService.AddCommand(menuItem);
    }

    public static async Task InitializeAsync(AsyncPackage package)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);

        var commandService = await package.GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
        _ = new BuildSolutionCommand(package, commandService);
    }

    private void Execute(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        VsShellUtilities.ShowMessageBox(
            _package,
            "Starting build...",
            "Build Solution",
            OLEMSGICON.OLEMSGICON_INFO,
            OLEMSGBUTTON.OLEMSGBUTTON_OK,
            OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
    }
}
```

**Commands/FormatDocumentCommand.cs:**

```csharp
using System;
using System.ComponentModel.Design;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

internal sealed class FormatDocumentCommand
{
    public static readonly Guid CommandSet = new("YOUR-CMDSET-GUID");
    public const int CommandId = 0x0101;

    private readonly AsyncPackage _package;

    private FormatDocumentCommand(AsyncPackage package, OleMenuCommandService commandService)
    {
        _package = package ?? throw new ArgumentNullException(nameof(package));
        commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

        var menuCommandId = new CommandID(CommandSet, CommandId);
        var menuItem = new MenuCommand(Execute, menuCommandId);
        commandService.AddCommand(menuItem);
    }

    public static async Task InitializeAsync(AsyncPackage package)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);

        var commandService = await package.GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
        _ = new FormatDocumentCommand(package, commandService);
    }

    private void Execute(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        VsShellUtilities.ShowMessageBox(
            _package,
            "Formatting document...",
            "Format Document",
            OLEMSGICON.OLEMSGICON_INFO,
            OLEMSGBUTTON.OLEMSGBUTTON_OK,
            OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
    }
}
```

### Step 3: Initialize commands in the package

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Shell;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration("#110", "#112", "1.0")]
[ProvideMenuResource("Menus.ctmenu", 1)]
[Guid("YOUR-PACKAGE-GUID")]
public sealed class MyExtensionPackage : AsyncPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await BuildSolutionCommand.InitializeAsync(this);
        await FormatDocumentCommand.InitializeAsync(this);
        await OpenSettingsCommand.InitializeAsync(this);
    }
}
```

Each command must be initialized explicitly — there is no auto-discovery in raw VSSDK.

### Dynamic enable/disable (VSSDK)

Use `OleMenuCommand` instead of `MenuCommand` to get `BeforeQueryStatus`:

```csharp
var menuCommandId = new CommandID(CommandSet, CommandId);
var menuItem = new OleMenuCommand(Execute, menuCommandId);
menuItem.BeforeQueryStatus += (s, e) =>
{
    ThreadHelper.ThrowIfNotOnUIThread();
    menuItem.Enabled = /* your condition */;
    menuItem.Visible = /* your condition */;
};
commandService.AddCommand(menuItem);
```

---

## Key guidance

- **One command per file.** Place all command files in a root `Commands/` folder. Name the file after the class.
- **VisualStudio.Extensibility** — No `.vsct` file needed. Placement, icons, and shortcuts are declared in `CommandConfiguration`. Use `ImageMoniker.KnownValues` for icons.
- **Community Toolkit & VSSDK** — Both require a `.vsct` file. To use KnownMonikers as icons: (1) add `<Include href="KnownImageIds.vsct"/>`, (2) set `guid="ImageCatalogGuid"` on `<Icon>`, and (3) add `<CommandFlag>IconIsMoniker</CommandFlag>` to the button.
- **`[ProvideMenuResource("Menus.ctmenu", 1)]`** is required on the package for Toolkit and VSSDK — without it, VS won't load the command table.
- Prefer `AsyncPackage` with `AllowsBackgroundLoading = true` for VSSDK. The Toolkit uses `ToolkitPackage` which already handles this.
- Never run heavy logic on the UI thread inside `Execute`. Offload to a background thread and switch back with `JoinableTaskFactory.SwitchToMainThreadAsync()` only when needed.

## Troubleshooting

- **Command doesn't appear in any menu:** For Extensibility, verify the `[VisualStudioContribution]` attribute is on the command class and that `Placements` is set in `CommandConfiguration`. For Toolkit/VSSDK, verify `[ProvideMenuResource("Menus.ctmenu", 1)]` is on the package, the `.vsct` button definition exists, and the GUID/ID symbols match between `.vsct` and code.
- **Icon doesn't display (Toolkit / VSSDK):** Ensure all three pieces are in the `.vsct` button: `<Include href="KnownImageIds.vsct"/>` at the top of the command table, `guid="ImageCatalogGuid"` on the `<Icon>` element, and `<CommandFlag>IconIsMoniker</CommandFlag>` on the button. Missing any one of these causes a blank icon with no error.
- **Command is visible but always disabled:** For Extensibility, check `EnabledWhen` constraints in `CommandConfiguration`. For Toolkit/VSSDK, check your `BeforeQueryStatus` handler — it may be setting `Enabled = false` unconditionally.
- **"Command already registered" exception at startup:** Two commands share the same GUID + ID pair. Each command must have a unique `CommandID`. Check for duplicate `IDSymbol` values in your `.vsct` file.
- **Command handler never fires:** For Toolkit, confirm the `[Command(PackageIds.XYZ)]` attribute references the correct generated constant. For VSSDK, confirm `InitializeAsync` calls your command's `InitializeAsync` and that the `CommandID` matches the `.vsct` symbol.
- **Keyboard shortcut doesn't work:** For Extensibility, verify the `Shortcuts` array in `CommandConfiguration`. For `.vsct`, ensure the `<KeyBinding>` element uses `editor="guidVSStd97"` for global scope and that the key combo doesn't conflict with an existing VS binding.

## What NOT to do

> **Do NOT** do heavy or long-running work inside the command's `Execute` or `ExecuteCommandAsync` handler on the UI thread. Offload to a background thread with `Task.Run` or `await TaskScheduler.Default`, then switch back to the UI thread only when needed. See [vs-async-threading](../handling-async-threading/SKILL.md).

> **Do NOT** forget `[ProvideMenuResource("Menus.ctmenu", 1)]` on the package class (Toolkit/VSSDK). Without it, Visual Studio never loads the command table and all your buttons silently fail to appear.

> **Do NOT** reuse GUID + ID pairs across commands. Each command needs a unique `CommandID`. Duplicates cause an exception at startup and neither command will work.

> **Do NOT** hard-code command GUIDs and IDs as inline strings in multiple places. Define them as constants in a shared class (or use the Toolkit's generated `PackageIds` / `PackageGuids` classes) to prevent mismatches.

> **Do NOT** use synchronous `Package` instead of `AsyncPackage` (VSSDK) or `ToolkitPackage` (Toolkit). Synchronous packages force VS to load your extension on the UI thread at startup, degrading IDE launch time.

## See also

- [vs-context-menu](../adding-context-menus/SKILL.md) — adding commands to right-click context menus
- [vs-command-visibility](../controlling-command-visibility/SKILL.md) — showing/hiding commands based on context
- [vs-dynamic-commands](../creating-dynamic-commands/SKILL.md) — commands that change text or state dynamically
- [vs-command-intercept](../intercepting-commands/SKILL.md) — intercepting built-in VS commands
- [vs-async-threading](../handling-async-threading/SKILL.md) — async patterns for command execution handlers
- [vs-error-handling](../handling-extension-errors/SKILL.md) — wrapping command handlers in try/catch

## References

- [Commands (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/command/command)
- [Menus and Commands (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/extending-menus-and-commands)
- [Visual Studio Command Table (.vsct) Files](https://learn.microsoft.com/visualstudio/extensibility/internals/visual-studio-command-table-dot-vsct-files)
- [KnownMonikers (ImageLibrary)](https://learn.microsoft.com/visualstudio/extensibility/image-service-and-catalog#knownmonikers)
- [VSIX Community Toolkit Commands Recipe](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/menus-buttons-commands)
