---
name: controlling-command-visibility
description: Control when commands are visible, enabled, or hidden in Visual Studio extensions. Use when the user asks how to show/hide commands conditionally, use VisibilityConstraints in .vsct, define UIContext rules, use ProvideUIContextRule, use BeforeQueryStatus for dynamic enable/disable, or delegate visibility back to a UIContext rule after package load with Command.Supported. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Controlling Command Visibility in Visual Studio Extensions

Command visibility determines **when** a command appears in menus, toolbars, or context menus. There are two layers:

1. **Before package load** — Declarative rules evaluated by the VS shell without loading the extension. Defined via `<VisibilityConstraints>` in `.vsct` (Toolkit/VSSDK) or `VisibleWhen` in code (VisualStudio.Extensibility).
2. **After package load** — Imperative logic in `BeforeQueryStatus` (Toolkit/VSSDK) or command state callbacks that run every time VS queries the command status.

Best practice: use declarative constraints for the initial visibility so the package is not loaded just to hide a command, then use `BeforeQueryStatus` for fine-grained runtime logic after the package is already loaded.

Visibility control prevents menu clutter and keeps the VS UI relevant to the user's current context. Without it, every extension's commands appear all the time, creating a noisy and confusing experience. The key architectural insight is that declarative constraints work *without loading your extension* — VS evaluates them from the `.vsct` metadata or `VisibleWhen` attributes at startup. Using only `BeforeQueryStatus` forces VS to load your package just to determine if a command should be hidden, degrading startup performance.

**When to use this vs. alternatives:**
- Show/hide commands based on file type, solution state, or UI context → **this skill**
- Add a new command to a menu → [vs-commands](../adding-commands/SKILL.md)
- Add a command to a right-click context menu → [vs-context-menu](../adding-context-menus/SKILL.md)
- Create commands that change their text or checked state dynamically → [vs-dynamic-commands](../creating-dynamic-commands/SKILL.md)

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

No `.vsct` file is needed. Visibility and enablement constraints are declared directly in `CommandConfiguration` using activation constraints.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility`, `Microsoft.VisualStudio.Extensibility.Commands`

### Declarative visibility with `VisibleWhen`

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Commands;

namespace MyExtension.Commands;

[VisualStudioContribution]
internal class AnalyzeCSharpCommand : Command
{
    public AnalyzeCSharpCommand(VisualStudioExtensibility extensibility)
        : base(extensibility) { }

    public override CommandConfiguration CommandConfiguration => new("Analyze C# File")
    {
        Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
        Icon = new(ImageMoniker.KnownValues.CSFileNode, IconSettings.IconAndText),
        // Visible only when the active file matches *.cs
        VisibleWhen = ActivationConstraint.ClientContext(
            ClientContextKey.Shell.ActiveSelectionFileName, @"\.cs$"),
    };

    public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
    {
        await this.Extensibility.Shell().ShowPromptAsync(
            "Analyzing C# file…", PromptOptions.OK, ct);
    }
}
```

### Declarative enablement with `EnabledWhen`

```csharp
public override CommandConfiguration CommandConfiguration => new("Debug Command")
{
    Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    // Enabled only when a solution is fully loaded
    EnabledWhen = ActivationConstraint.SolutionState(SolutionState.FullyLoaded),
};
```

### Combining multiple constraints

```csharp
public override CommandConfiguration CommandConfiguration => new("Run Tests")
{
    Placements = [CommandPlacement.KnownPlacements.ToolsMenu],
    VisibleWhen = ActivationConstraint.SolutionState(SolutionState.FullyLoaded)
                  & ActivationConstraint.ClientContext(
                        ClientContextKey.Shell.ActiveSelectionFileName, @"\.(cs|vb)$"),
};
```

### Runtime enable/disable

Override the command state callback to toggle enabled state at runtime:

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
{
    // After executing, disable the command
    this.DisableCommand();
    // ...
    this.EnableCommand();
}
```

### Note on UIContext and .vsct

VisualStudio.Extensibility does **not** use `.vsct` files or `ProvideUIContextRule`. All visibility logic is expressed through `ActivationConstraint` in `CommandConfiguration`. There is no equivalent of `Command.Supported` or `BeforeQueryStatus` in this model — the framework handles visibility declaratively.

---

## 2. VSIX Community Toolkit (in-process)

Visibility is controlled in three layers:

1. **`.vsct` `<VisibilityConstraints>`** — hides/shows commands before the package loads, using a UIContext GUID.
2. **`[ProvideUIContextRule]`** on the package class — defines the rule that activates or deactivates that UIContext GUID.
3. **`BeforeQueryStatus`** — imperative logic that runs after the package is loaded for dynamic enable/disable.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Step 1: Define the UIContext GUID in the .vsct `<Symbols>`

Store the GUID for your UIContext rule in the `.vsct` file so it is the single source of truth. The Toolkit's build-time code generator produces a `PackageGuids` class from the `.vsct` symbols, so you do **not** need to duplicate the GUID value in C# code.

```xml
<Symbols>
  <GuidSymbol name="guidMyExtensionPackage" value="{YOUR-PACKAGE-GUID}" />

  <GuidSymbol name="guidMyExtensionCmdSet" value="{YOUR-CMDSET-GUID}">
    <IDSymbol name="MyMenuGroup" value="0x1020" />
    <IDSymbol name="RunTestsCommandId" value="0x0100" />
  </GuidSymbol>

  <!-- UIContext GUID — single source of truth for the rule -->
  <GuidSymbol name="guidCSharpFileActiveContext" value="{11111111-2222-3333-4444-555555555555}" />
</Symbols>
```

### Step 2: Add `<VisibilityConstraints>` in the .vsct file

The `<VisibilityConstraints>` block tells the VS shell to show or hide a command based on the active state of a UIContext — **without loading the package**.

Add the `<CommandFlag>DynamicVisibility</CommandFlag>` to the button so VS knows the visibility can change, and add `<CommandFlag>DefaultInvisible</CommandFlag>` so the command starts hidden.

```xml
<Commands package="guidMyExtensionPackage">
  <Groups>
    <Group guid="guidMyExtensionCmdSet" id="MyMenuGroup" priority="0x0600">
      <Parent guid="guidSHLMainMenu" id="IDM_VS_MENU_TOOLS"/>
    </Group>
  </Groups>

  <Buttons>
    <Button guid="guidMyExtensionCmdSet" id="RunTestsCommandId" priority="0x0100" type="Button">
      <Parent guid="guidMyExtensionCmdSet" id="MyMenuGroup"/>
      <Icon guid="ImageCatalogGuid" id="RunOutline"/>
      <CommandFlag>IconIsMoniker</CommandFlag>
      <CommandFlag>DynamicVisibility</CommandFlag>
      <CommandFlag>DefaultInvisible</CommandFlag>
      <Strings>
        <ButtonText>Run Tests</ButtonText>
      </Strings>
    </Button>
  </Buttons>
</Commands>

<VisibilityConstraints>
  <!-- Show the command when the UIContext guidCSharpFileActiveContext is active -->
  <VisibilityItem guid="guidMyExtensionCmdSet" id="RunTestsCommandId"
                  context="guidCSharpFileActiveContext"/>
</VisibilityConstraints>
```

**Important command flags:**

| Flag | Purpose |
|------|---------|
| `DynamicVisibility` | Allows the command's visibility to change at runtime. Required for `<VisibilityConstraints>` and `BeforeQueryStatus` visibility toggling to work. |
| `DefaultInvisible` | The command starts hidden until its UIContext becomes active (or `BeforeQueryStatus` sets `Visible = true`). |
| `DefaultDisabled` | The command starts disabled (grayed out). Useful when you want the button visible but not clickable until a condition is met. |

### Step 3: Define the UIContext rule on the package class

Use `[ProvideUIContextRule]` on the package class to define the boolean expression that activates the UIContext. Reference the GUID from the `.vsct` file via the generated `PackageGuids` class — no need to duplicate the GUID string.

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration(Vsix.Name, Vsix.Description, Vsix.Version)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[Guid(PackageGuids.guidMyExtensionPackageString)]
[ProvideUIContextRule(
    PackageGuids.guidCSharpFileActiveContextString,   // The UIContext GUID from the .vsct symbols
    name: "C# File Active",
    expression: "CSharpFile",                         // Boolean expression using term names
    termNames: new[] { "CSharpFile" },
    termValues: new[] { "HierSingleSelectionName:.cs$" })]  // Regex match on active selection
public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await this.RegisterCommandsAsync();
    }
}
```

The `PackageGuids.guidCSharpFileActiveContextString` constant is auto-generated from the `.vsct` `<GuidSymbol name="guidCSharpFileActiveContext">` entry. This keeps the GUID in one place.

#### Common `ProvideUIContextRule` term values

| Term value pattern | Matches when… |
|---|---|
| `HierSingleSelectionName:.cs$` | A single item with name ending in `.cs` is selected |
| `ActiveProjectCapability:CSharp` | The active project has the C# capability |
| `ActiveProjectCapability:VB` | The active project has the VB capability |
| `SolutionHasProjectCapability:CSharp` | Any project in the solution has C# capability |
| `ActiveEditorContentType:CSharp` | The active editor has C# content type |
| `SolutionExistsAndNotBuildingAndNotDebugging` | A solution is loaded and no build/debug is running |

#### Complex boolean expressions

```csharp
[ProvideUIContextRule(
    PackageGuids.guidMyContextString,
    name: "C# or VB project loaded",
    expression: "(CSharp | VB) & SolutionLoaded",
    termNames: new[] { "CSharp", "VB", "SolutionLoaded" },
    termValues: new[] {
        "SolutionHasProjectCapability:CSharp",
        "SolutionHasProjectCapability:VB",
        "SolutionExistsAndNotBuildingAndNotDebugging"
    })]
```

### Step 4: Use `BeforeQueryStatus` for post-load logic

Once the package has loaded, you can use `BeforeQueryStatus` for fine-grained, imperative visibility or enablement logic. This runs every time VS queries the command status (e.g., when the user opens the menu).

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.RunTestsCommandId)]
internal sealed class RunTestsCommand : BaseCommand<RunTestsCommand>
{
    protected override void BeforeQueryStatus(EventArgs e)
    {
        // Example: only enable when the active document is a .cs file
        ThreadHelper.JoinableTaskFactory.Run(async () =>
        {
            var doc = await VS.Documents.GetActiveDocumentViewAsync();
            Command.Enabled = doc?.FilePath?.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) == true;
        });
    }

    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Running tests…");
    }
}
```

You can also toggle visibility in `BeforeQueryStatus`:

```csharp
protected override void BeforeQueryStatus(EventArgs e)
{
    Command.Visible = SomeCondition();
    Command.Enabled = SomeOtherCondition();
}
```

### Step 5: Delegate visibility back to the UIContext rule with `Command.Supported`

By default, once the package loads and the command handler is initialized, VS delegates all visibility/enablement decisions to `BeforeQueryStatus`. If you want VS to **continue respecting the `<VisibilityConstraints>` UIContext rule** even after the package has loaded, set `Command.Supported = false` in the `AfterInitializeAsync` override.

Setting `Supported` to `false` tells VS: "this command handler does not manage its own visibility — defer to the declarative UIContext rule."

```csharp
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

[Command(PackageIds.RunTestsCommandId)]
internal sealed class RunTestsCommand : BaseCommand<RunTestsCommand>
{
    protected override Task AfterInitializeAsync()
    {
        // Delegate visibility/enablement back to the UIContext rule
        // defined in ProvideUIContextRule on the package class.
        Command.Supported = false;
        return Task.CompletedTask;
    }

    protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        await VS.MessageBox.ShowAsync("Running tests…");
    }
}
```

When `Command.Supported = false`:
- The `<VisibilityConstraints>` UIContext rule remains in control of visibility **at all times**, even after the package loads.
- `BeforeQueryStatus` is still called but cannot override the UIContext visibility decision.
- This is useful when the UIContext rule is the **only** source of truth for visibility and you don't need additional imperative logic in `BeforeQueryStatus`.

---

## 3. VSSDK (in-process, legacy)

The `.vsct` file and `[ProvideUIContextRule]` work identically to the Toolkit approach. The difference is in how commands are registered and how `BeforeQueryStatus` is wired up.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`, `System.ComponentModel.Design`

### Step 1: .vsct file

Use the same `.vsct` structure shown in section 2. The `<VisibilityConstraints>`, `DynamicVisibility`, `DefaultInvisible` flags, and `<GuidSymbol>` for the UIContext GUID are all identical.

### Step 2: Define the UIContext rule on the package class

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[InstalledProductRegistration("#110", "#112", "1.0")]
[ProvideMenuResource("Menus.ctmenu", 1)]
[Guid("YOUR-PACKAGE-GUID")]
[ProvideUIContextRule(
    "11111111-2222-3333-4444-555555555555",
    name: "C# File Active",
    expression: "CSharpFile",
    termNames: new[] { "CSharpFile" },
    termValues: new[] { "HierSingleSelectionName:.cs$" })]
public sealed class MyExtensionPackage : AsyncPackage
{
    // UIContext GUID must match the GuidSymbol value in the .vsct Symbols block
    private const string UIContextGuid = "11111111-2222-3333-4444-555555555555";
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await RunTestsCommand.InitializeAsync(this);
    }
}
```

> **Note:** In raw VSSDK you must keep the UIContext GUID string in sync manually between the `.vsct` `<GuidSymbol>` and the `[ProvideUIContextRule]` attribute. Unlike the Toolkit, there is no auto-generated `PackageGuids` class (unless you set up your own T4/code-gen). Declare the GUID as a `const` in the package and reference it from both places.

### Step 3: Create the command with `BeforeQueryStatus`

Use `OleMenuCommand` (not `MenuCommand`) to get access to `BeforeQueryStatus`.

```csharp
using System;
using System.ComponentModel.Design;
using Microsoft.VisualStudio.Shell;

namespace MyExtension.Commands;

internal sealed class RunTestsCommand
{
    public static readonly Guid CommandSet = new("YOUR-CMDSET-GUID");
    public const int CommandId = 0x0100;

    private readonly AsyncPackage _package;

    private RunTestsCommand(AsyncPackage package, OleMenuCommandService commandService)
    {
        _package = package ?? throw new ArgumentNullException(nameof(package));
        commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

        var menuCommandId = new CommandID(CommandSet, CommandId);
        var menuItem = new OleMenuCommand(Execute, menuCommandId);

        menuItem.BeforeQueryStatus += OnBeforeQueryStatus;

        commandService.AddCommand(menuItem);
    }

    public static async Task InitializeAsync(AsyncPackage package)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);

        var commandService = await package.GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
        _ = new RunTestsCommand(package, commandService);
    }

    private void OnBeforeQueryStatus(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        if (sender is OleMenuCommand command)
        {
            // Example: enable only when a .cs file is active
            var dte = (EnvDTE.DTE)Package.GetGlobalService(typeof(EnvDTE.DTE));
            var activeDoc = dte?.ActiveDocument;
            command.Enabled = activeDoc?.Name.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) == true;
        }
    }

    private void Execute(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        VsShellUtilities.ShowMessageBox(
            _package,
            "Running tests…",
            "Run Tests",
            OLEMSGICON.OLEMSGICON_INFO,
            OLEMSGBUTTON.OLEMSGBUTTON_OK,
            OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
    }
}
```

### Step 4: Delegate visibility back to the UIContext rule with `Supported`

Same concept as the Toolkit: set `Supported = false` on the `OleMenuCommand` so the shell defers to the `<VisibilityConstraints>` UIContext rule even after the package loads.

```csharp
private RunTestsCommand(AsyncPackage package, OleMenuCommandService commandService)
{
    _package = package ?? throw new ArgumentNullException(nameof(package));
    commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

    var menuCommandId = new CommandID(CommandSet, CommandId);
    var menuItem = new OleMenuCommand(Execute, menuCommandId);

    // Delegate visibility back to the UIContext rule.
    // The shell will continue using the VisibilityConstraints even after load.
    menuItem.Supported = false;

    commandService.AddCommand(menuItem);
}
```

When `Supported = false`:
- The command stays under control of the `<VisibilityConstraints>` UIContext rule for visibility.
- `BeforeQueryStatus` is still invoked but the UIContext rule governs visibility.

---

## Summary: which mechanism to use when

| Goal | Before package load | After package load |
|------|--------------------|--------------------|
| Show/hide command based on file type or project capability | `<VisibilityConstraints>` + `[ProvideUIContextRule]` (Toolkit/VSSDK) or `VisibleWhen` (VS.Extensibility) | `BeforeQueryStatus` setting `Command.Visible` |
| Enable/disable command | `DefaultDisabled` flag in `.vsct` | `BeforeQueryStatus` setting `Command.Enabled` |
| Keep UIContext rule in control after load | Set `Command.Supported = false` in `AfterInitializeAsync` (Toolkit) or on the `OleMenuCommand` instance (VSSDK) | UIContext rule continues to govern visibility |
| Complex boolean conditions | `[ProvideUIContextRule]` with compound expressions | `BeforeQueryStatus` with arbitrary C# logic |

### Key rules

- **Always store the UIContext GUID in the `.vsct` `<Symbols>` block.** For Toolkit extensions, the build generates `PackageGuids` / `PackageIds` from the `.vsct`, keeping the GUID in one place. For raw VSSDK, declare a `const string` and reference it from both `.vsct` and the `[ProvideUIContextRule]` attribute.
- **Use `DynamicVisibility` and `DefaultInvisible`** on any button whose visibility is controlled by a UIContext or `BeforeQueryStatus`.
- **`Command.Supported = false`** means "this command does not claim to manage its own visibility — defer to the UIContext rule." Despite the name, it does **not** mean the command is unsupported.
- **Prefer declarative constraints** (`<VisibilityConstraints>` / `VisibleWhen`) for initial visibility. This avoids loading the package just to hide a command.
- **Use `BeforeQueryStatus`** only for conditions that cannot be expressed declaratively (e.g., checking runtime state, inspecting file contents).

## Troubleshooting

- **Command appears briefly then disappears (flash):** The command is missing `DefaultInvisible` in `.vsct`. Without it, the command starts visible and then hides when `BeforeQueryStatus` runs — causing a visible flash on startup.
- **Command stays hidden even when UIContext is active:** Check that both `DynamicVisibility` and the correct `VisibilityConstraints` entry are present. Without `DynamicVisibility`, VS ignores runtime visibility changes entirely.
- **`BeforeQueryStatus` never fires:** The command needs `DynamicVisibility` in `.vsct`. Also verify the package is loaded — `BeforeQueryStatus` only runs after the package is initialized.
- **`Command.Supported = false` doesn't hide the command:** `Supported` doesn't mean "visible." Setting `Supported = false` delegates visibility back to the UIContext rule associated with the command. Setting `Visible = false` actually hides it.
- **UIContext rule never activates:** Verify the expression syntax in `[ProvideUIContextRule]`. Terms must match the `termNames` and `termValues` arrays exactly. A typo in the GUID or an invalid operator causes silent failure.

## What NOT to do

> **Do NOT** use `BeforeQueryStatus` as the **sole** visibility mechanism. It forces the package to load just to evaluate whether a command should be visible. Use **declarative** `<VisibilityConstraints>` (Toolkit/VSSDK) or `VisibleWhen` (Extensibility) for initial show/hide — these work **before** the package loads. Reserve `BeforeQueryStatus` for conditions that require runtime logic.

> **Do NOT** confuse `Command.Supported = false` with `Command.Visible = false`. Setting `Supported = false` means "this command defers its visibility to the UIContext rule" — the command may still be visible. Setting `Visible = false` actually hides it. Despite the misleading name, `Supported` is about **who controls visibility**, not whether the command works.

> **Do NOT** forget `DynamicVisibility` and `DefaultInvisible` command flags in `.vsct` when using UIContext rules or `BeforeQueryStatus` for visibility. Without `DynamicVisibility`, VS ignores visibility changes at runtime. Without `DefaultInvisible`, the command starts visible and then disappears (a flash).

> **Do NOT** hard-code UIContext GUIDs in multiple places. Store the GUID in `.vsct` `<Symbols>` (the Toolkit auto-generates it into `PackageGuids`) and reference it from there. Duplicate GUIDs that drift apart cause visibility rules to silently stop working.

> **Do NOT** use `DTE.Commands` or `EnvDTE.CommandEvents` to manage visibility in new extensions. These are legacy automation APIs that require COM reference management and don't participate in the modern UIContext/activation constraint system.

## See also

- [vs-commands](../adding-commands/SKILL.md) — defining commands that visibility rules control
- [vs-context-menu](../adding-context-menus/SKILL.md) — context menus where visibility is especially important
- [vs-dynamic-commands](../creating-dynamic-commands/SKILL.md) — changing command text or checked state at runtime
- [vs-command-intercept](../intercepting-commands/SKILL.md) — intercepting commands vs. hiding them

## References

- [VisibilityConstraints element (.vsct)](https://learn.microsoft.com/visualstudio/extensibility/visibilityconstraints-element)
- [VisibilityItem element (.vsct)](https://learn.microsoft.com/visualstudio/extensibility/visibilityitem-element)
- [ProvideUIContextRule attribute](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.provideuicontextruleattribute)
- [Using Rule-based UI Context for VS Extensions](https://learn.microsoft.com/visualstudio/extensibility/how-to-use-rule-based-ui-context-for-visual-studio-extensions)
- [Commands (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/command/command)
- [VSIX Community Toolkit Commands](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/menus-buttons-commands)
