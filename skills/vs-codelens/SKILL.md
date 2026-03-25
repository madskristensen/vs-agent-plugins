---
name: vs-codelens
description: Add custom CodeLens indicators that display inline information above code elements in the Visual Studio editor. Use when the user asks how to add a CodeLens indicator, show inline data above methods or classes, create a custom CodeLens provider, implement IAsyncCodeLensDataPointProvider, display git history or test status in CodeLens, or add a details popup to CodeLens entries. Covers VSSDK / VSIX Community Toolkit (in-process + out-of-process CodeLens service). VisualStudio.Extensibility (out-of-process) does not have a dedicated CodeLens API.
---

# Custom CodeLens Indicators in Visual Studio Extensions

CodeLens indicators display inline information above code elements (classes, methods, properties) in the editor — references, tests, git history, etc. Extensions can add custom indicators that show any data and respond to clicks.

CodeLens is one of the most visible integration points in VS — indicators appear directly in the code without requiring the developer to open a separate window. This makes them ideal for surfacing contextual metadata (ownership, test status, change frequency) at the point of relevance. The architecture is unique: the data provider runs **out-of-process** in a separate CodeLens service, while click handling and custom UI rendering run **in-process**. This split improves editor performance but requires a multi-project solution structure that trips up many first-time authors.

**When to use CodeLens vs. alternatives:**
- Inline metadata above code elements (methods, classes) → **CodeLens** (this skill)
- Hover tooltips on arbitrary text spans → Quick Info (see [vs-editor-quickinfo](../vs-editor-quickinfo/SKILL.md))
- Inline visual decorations (highlights, icons, overlays) → adornments (see [vs-editor-adornment](../vs-editor-adornment/SKILL.md))
- Actionable suggestions (lightbulb) → suggested actions (see [vs-editor-suggested-actions](../vs-editor-suggested-actions/SKILL.md))

## Architecture overview

CodeLens runs in a **separate out-of-process service** (not inside `devenv.exe`). This means a CodeLens extension has two parts:

1. **Out-of-process component** — a class library that implements `IAsyncCodeLensDataPointProvider` and `IAsyncCodeLensDataPoint`. This assembly is loaded by the CodeLens service process. It computes data for each code element.
2. **In-process VSIX component** — a `AsyncPackage` (or `ToolkitPackage`) that provides command handling for navigation clicks, and optional `IViewElementFactory` MEF exports for custom detail popup UI. This assembly runs inside `devenv.exe`.
3. **Shared library** (optional) — data types referenced by both projects, used for custom details data classes that need to cross the process boundary.

## VisualStudio.Extensibility (out-of-process)

**Not supported.** The new extensibility model does not provide a CodeLens API. CodeLens providers must use the `Microsoft.VisualStudio.Language.CodeLens.Remoting` APIs described below.

---

## VSSDK / VSIX Community Toolkit (in-process)

The Toolkit and VSSDK approaches are identical for CodeLens — the Toolkit's `ToolkitPackage` inherits from `AsyncPackage`, and the CodeLens data point provider is a standalone class library with no package dependency.

**NuGet packages:**

| Package | Where | Purpose |
|---------|-------|---------|
| `Microsoft.VisualStudio.Language` | OOP project | Contains `IAsyncCodeLensDataPointProvider`, `IAsyncCodeLensDataPoint`, descriptor types |
| `Microsoft.VisualStudio.CoreUtility` | OOP project | `ContentType`, `Name`, `Priority` attributes |
| `Microsoft.VisualStudio.Threading` | OOP project | `AsyncEventHandler` for invalidation |
| `Microsoft.VisualStudio.SDK` (≥ 17.0) | VSIX project | In-process package, command handling, MEF |
| `Newtonsoft.Json` | OOP project | Serialization for RPC (must match VS version) |

**Key types:**
- `IAsyncCodeLensDataPointProvider` — factory that creates data points per code element
- `IAsyncCodeLensDataPoint` — computes indicator text, tooltip, and details for one code element
- `CodeLensDescriptor` — describes the code element (file path, element name, project GUID, etc.)
- `CodeLensDescriptorContext` — contextual data passed alongside the descriptor
- `CodeLensDataPointDescriptor` — the indicator's display text, tooltip, and optional icon
- `CodeLensDetailsDescriptor` — the expandable details popup content (headers, entries, custom data, pane commands)
- `IViewElementFactory` — MEF export that converts custom data objects into WPF `FrameworkElement` for the details popup

### Solution structure

```
MyExtension.sln
├── MyCodeLensProvider/                 ← Out-of-process class library (.NET Framework 4.7.2+)
│   ├── MyDataPointProvider.cs
│   └── MyCodeLensProvider.csproj
├── MyCodeLensShared/                   ← (optional) Shared data types
│   ├── MyCustomDetailsData.cs
│   └── MyCodeLensShared.csproj
├── MyCodeLensVsix/                     ← VSIX project (in-process)
│   ├── MyCodeLensPackage.cs
│   ├── MyViewElementFactory.cs         ← (optional) Custom details UI
│   ├── MyCodeLensPackage.vsct
│   ├── source.extension.vsixmanifest
│   └── MyCodeLensVsix.csproj
```

---

### Step 1 — Implement the out-of-process CodeLens data point provider

This class library is loaded by the CodeLens service, not by devenv.exe. It exports `IAsyncCodeLensDataPointProvider` via MEF.

**MyCodeLensProvider/MyDataPointProvider.cs:**

```csharp
using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Core.Imaging;
using Microsoft.VisualStudio.Language.CodeLens;
using Microsoft.VisualStudio.Language.CodeLens.Remoting;
using Microsoft.VisualStudio.Threading;
using Microsoft.VisualStudio.Utilities;

namespace MyCodeLensProvider;

[Export(typeof(IAsyncCodeLensDataPointProvider))]
[Name(Id)]
[ContentType("code")]                              // Applies to all code files
[LocalizedName(typeof(Resources), "MyIndicator")]  // Display name in CodeLens options
[Priority(200)]                                    // Lower = appears further left
internal class MyDataPointProvider : IAsyncCodeLensDataPointProvider
{
    internal const string Id = "MyCompany.MyCodeLensProvider";

    public Task<bool> CanCreateDataPointAsync(
        CodeLensDescriptor descriptor,
        CodeLensDescriptorContext context,
        CancellationToken token)
    {
        // Return true for code elements you want to annotate.
        // descriptor.Kind tells you if it's a type, method, property, etc.
        return Task.FromResult(descriptor.Kind == CodeElementKinds.Method);
    }

    public Task<IAsyncCodeLensDataPoint> CreateDataPointAsync(
        CodeLensDescriptor descriptor,
        CodeLensDescriptorContext context,
        CancellationToken token)
    {
        return Task.FromResult<IAsyncCodeLensDataPoint>(
            new MyDataPoint(descriptor));
    }
}
```

### Step 2 — Implement the data point

Each data point computes the indicator text and optional details for a single code element.

```csharp
internal class MyDataPoint : IAsyncCodeLensDataPoint
{
    private static readonly CodeLensDetailEntryCommand NavigateCommand = new()
    {
        CommandSet = new Guid("YOUR-COMMAND-SET-GUID"),
        CommandId = 0x0100,
        CommandName = "MyCodeLens.Navigate",
    };

    private readonly CodeLensDescriptor descriptor;

    public MyDataPoint(CodeLensDescriptor descriptor)
    {
        this.descriptor = descriptor;
    }

    public event AsyncEventHandler InvalidatedAsync;

    public CodeLensDescriptor Descriptor => descriptor;

    /// <summary>
    /// Computes the indicator text shown inline in the editor.
    /// </summary>
    public Task<CodeLensDataPointDescriptor> GetDataAsync(
        CodeLensDescriptorContext context,
        CancellationToken token)
    {
        // Example: show a simple counter
        var response = new CodeLensDataPointDescriptor
        {
            Description = "3 issues",
            TooltipText = "3 open issues linked to this method",
            IntValue = 3,
            ImageId = null, // or use ImageId from KnownMonikers
        };

        return Task.FromResult(response);
    }

    /// <summary>
    /// Returns the expandable details shown when the user clicks the indicator.
    /// </summary>
    public Task<CodeLensDetailsDescriptor> GetDetailsAsync(
        CodeLensDescriptorContext context,
        CancellationToken token)
    {
        var details = new CodeLensDetailsDescriptor
        {
            Headers = new List<CodeLensDetailHeaderDescriptor>
            {
                new() { UniqueName = "Id", DisplayName = "ID", Width = 80 },
                new() { UniqueName = "Title", DisplayName = "Title", Width = 0.7 },  // fractional = relative
                new() { UniqueName = "Status", DisplayName = "Status", Width = 0.3 },
            },
            Entries = new List<CodeLensDetailEntryDescriptor>
            {
                CreateEntry("BUG-101", "Null reference in Foo()", "Open"),
                CreateEntry("BUG-102", "Timeout on large inputs", "In Progress"),
                CreateEntry("BUG-103", "Missing validation", "Open"),
            },
            PaneNavigationCommands = new List<CodeLensDetailPaneCommand>
            {
                new()
                {
                    CommandId = NavigateCommand,
                    CommandDisplayName = "Open Issue Tracker",
                },
            },
        };

        return Task.FromResult(details);
    }

    private static CodeLensDetailEntryDescriptor CreateEntry(
        string id, string title, string status)
    {
        return new CodeLensDetailEntryDescriptor
        {
            Fields = new List<CodeLensDetailEntryField>
            {
                new() { Text = id },
                new() { Text = title },
                new() { Text = status },
            },
            Tooltip = title,
            NavigationCommand = NavigateCommand,
            NavigationCommandArgs = new List<object> { id },
        };
    }

    /// <summary>
    /// Call this when underlying data changes to refresh the indicator.
    /// </summary>
    public void Invalidate()
    {
        InvalidatedAsync?.Invoke(this, EventArgs.Empty).ConfigureAwait(false);
    }
}
```

### CodeLensDataPointDescriptor properties

| Property | Type | Description |
|----------|------|-------------|
| `Description` | `string` | The text shown inline in the editor (e.g. "3 issues") |
| `TooltipText` | `string` | Hover tooltip for the indicator |
| `IntValue` | `int?` | Optional numeric value (used for sorting/display) |
| `ImageId` | `ImageId?` | Optional icon from the VS image catalog |

### CodeLensDetailsDescriptor properties

| Property | Type | Description |
|----------|------|-------------|
| `Headers` | `List<CodeLensDetailHeaderDescriptor>` | Column definitions. `Width` as int = fixed pixels; as double 0–1 = fraction of remaining space |
| `Entries` | `List<CodeLensDetailEntryDescriptor>` | Rows of data. Each entry has `Fields`, `Tooltip`, `NavigationCommand`, `NavigationCommandArgs` |
| `CustomData` | `IReadOnlyList<object>` | Custom objects rendered by an `IViewElementFactory` (see Step 5) |
| `PaneNavigationCommands` | `List<CodeLensDetailPaneCommand>` | Buttons at the bottom of the details pane |

---

### Step 3 — Register the OOP assembly in the VSIX manifest

The critical step: the VSIX manifest must declare the OOP library as a `Microsoft.VisualStudio.CodeLensComponent` asset. Without this, the CodeLens service won't discover and load your provider.

**source.extension.vsixmanifest:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0"
  xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"
  xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Id="MyCodeLens.guid-here" Version="1.0" Language="en-US" Publisher="MyCompany" />
    <DisplayName>My CodeLens Extension</DisplayName>
    <Description>Adds custom CodeLens indicators.</Description>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Community" Version="[17.0,)" />
  </Installation>
  <Assets>
    <!-- OOP CodeLens provider — loaded by the CodeLens service process -->
    <Asset Type="Microsoft.VisualStudio.CodeLensComponent"
           d:Source="Project"
           d:ProjectName="MyCodeLensProvider"
           Path="|MyCodeLensProvider|" />

    <!-- In-process package for command handling -->
    <Asset Type="Microsoft.VisualStudio.VsPackage"
           d:Source="Project"
           d:ProjectName="%CurrentProject%"
           Path="|%CurrentProject%;PkgdefProjectOutputGroup|" />

    <!-- MEF component for IViewElementFactory -->
    <Asset Type="Microsoft.VisualStudio.MefComponent"
           d:Source="Project"
           d:ProjectName="%CurrentProject%"
           Path="|%CurrentProject%|" />
  </Assets>
</PackageManifest>
```

> **Important:** `Microsoft.VisualStudio.CodeLensComponent` is the magic asset type that makes the CodeLens service discover your OOP assembly.

---

### Step 4 — Handle navigation commands in-process

When a user clicks an entry in the details pane, the `NavigationCommand` fires. Handle it in your `AsyncPackage` via `IOleCommandTarget`:

**MyCodeLensVsix/MyCodeLensPackage.cs:**

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Task = System.Threading.Tasks.Task;

namespace MyCodeLensVsix;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[Guid(PackageGuidString)]
[ProvideBindingPath]
public sealed class MyCodeLensPackage : AsyncPackage, IOleCommandTarget
{
    public const string PackageGuidString = "YOUR-PACKAGE-GUID";

    private static readonly Guid CommandSetGuid = new("YOUR-COMMAND-SET-GUID");
    private const uint NavigateCmdId = 0x0100;

    private IOleCommandTarget packageCommandTarget;

    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await base.InitializeAsync(cancellationToken, progress);
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        packageCommandTarget = await GetServiceAsync(typeof(IOleCommandTarget))
            as IOleCommandTarget;
    }

    int IOleCommandTarget.QueryStatus(
        ref Guid pguidCmdGroup, uint cCmds,
        OLECMD[] prgCmds, IntPtr pCmdText)
    {
        if (pguidCmdGroup == CommandSetGuid && prgCmds[0].cmdID == NavigateCmdId)
        {
            prgCmds[0].cmdf |= (uint)(OLECMDF.OLECMDF_SUPPORTED
                | OLECMDF.OLECMDF_ENABLED
                | OLECMDF.OLECMDF_INVISIBLE);
            return VSConstants.S_OK;
        }

        return packageCommandTarget.QueryStatus(ref pguidCmdGroup, cCmds, prgCmds, pCmdText);
    }

    int IOleCommandTarget.Exec(
        ref Guid pguidCmdGroup, uint nCmdID,
        uint nCmdexecopt, IntPtr pvaIn, IntPtr pvaOut)
    {
        if (pguidCmdGroup == CommandSetGuid && nCmdID == NavigateCmdId)
        {
            if (pvaIn != IntPtr.Zero)
            {
                object arg = Marshal.GetObjectForNativeVariant(pvaIn);
                if (arg is string issueId && !string.IsNullOrEmpty(issueId))
                {
                    HandleNavigate(issueId);
                }
            }

            return VSConstants.S_OK;
        }

        return packageCommandTarget.Exec(
            ref pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);
    }

    private void HandleNavigate(string issueId)
    {
        VsShellUtilities.ShowMessageBox(
            this,
            $"Navigate to issue: {issueId}",
            "My CodeLens",
            OLEMSGICON.OLEMSGICON_INFO,
            OLEMSGBUTTON.OLEMSGBUTTON_OK,
            OLEMSGDEFBUTTON.OLEMSGDEFBUTTON_FIRST);
    }
}
```

### .vsct file for the navigation command

The command must be declared in a `.vsct` file even though it's invisible — CodeLens needs a registered command to route clicks:

**MyCodeLensVsix/MyCodeLensPackage.vsct:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<CommandTable xmlns="http://schemas.microsoft.com/VisualStudio/2005-10-18/CommandTable"
              xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <Extern href="stdidcmd.h"/>
  <Extern href="vsshlids.h"/>

  <Commands package="guidMyCodeLensPackage">
    <Buttons>
      <Button guid="guidMyCodeLensCmdSet" id="cmdidNavigate" type="Button">
        <CommandFlag>DefaultInvisible</CommandFlag>
        <CommandFlag>DynamicVisibility</CommandFlag>
        <Strings>
          <ButtonText>Navigate to Issue</ButtonText>
        </Strings>
      </Button>
    </Buttons>
  </Commands>

  <Symbols>
    <GuidSymbol name="guidMyCodeLensPackage" value="{YOUR-PACKAGE-GUID}" />
    <GuidSymbol name="guidMyCodeLensCmdSet" value="{YOUR-COMMAND-SET-GUID}">
      <IDSymbol name="cmdidNavigate" value="0x0100" />
    </GuidSymbol>
  </Symbols>
</CommandTable>
```

---

### Step 5 — Custom details UI (optional)

For richer detail panes beyond simple text columns, provide custom data objects and an `IViewElementFactory` that converts them to WPF elements.

**Shared data class (MyCodeLensShared/MyCustomDetailsData.cs):**

```csharp
namespace MyCodeLensShared;

public class MyCustomDetailsData
{
    public string Summary { get; set; }
    public string Author { get; set; }
    public int Priority { get; set; }
}
```

**In the OOP provider, add custom data to the details descriptor:**

```csharp
var details = new CodeLensDetailsDescriptor
{
    Headers = CreateHeaders(),
    Entries = CreateEntries(),
    CustomData = new List<MyCustomDetailsData>
    {
        new()
        {
            Summary = "Critical bug in authentication flow",
            Author = "jsmith",
            Priority = 1,
        },
    },
};
```

**In-process view element factory (MyCodeLensVsix/MyViewElementFactory.cs):**

```csharp
using System;
using System.ComponentModel.Composition;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Microsoft.VisualStudio.Text.Adornments;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;
using MyCodeLensShared;

namespace MyCodeLensVsix;

[Export(typeof(IViewElementFactory))]
[Name("My custom CodeLens details factory")]
[TypeConversion(from: typeof(MyCustomDetailsData), to: typeof(FrameworkElement))]
[Order]
internal class MyViewElementFactory : IViewElementFactory
{
    public TView CreateViewElement<TView>(ITextView textView, object model)
        where TView : class
    {
        if (typeof(TView) != typeof(FrameworkElement))
            throw new ArgumentException($"Unsupported conversion to {typeof(TView)}");

        if (model is MyCustomDetailsData data)
        {
            var panel = new StackPanel { Margin = new Thickness(8) };
            panel.Children.Add(new TextBlock(new Bold(new Run(data.Summary)))
            {
                FontSize = 14,
                Margin = new Thickness(0, 0, 0, 4),
            });
            panel.Children.Add(new TextBlock
            {
                Text = $"Author: {data.Author} | Priority: {data.Priority}",
            });

            return panel as TView;
        }

        return null;
    }
}
```

---

### Provider attribute reference

| Attribute | Purpose |
|-----------|---------|
| `[Export(typeof(IAsyncCodeLensDataPointProvider))]` | Registers the provider with MEF |
| `[Name("UniqueId")]` | Unique identifier for the provider |
| `[ContentType("code")]` | Content types to apply to. Use `"CSharp"`, `"Basic"`, `"code"`, etc. |
| `[LocalizedName(typeof(Resources), "Key")]` | Display name shown in Tools > Options > Text Editor > All Languages > CodeLens |
| `[Priority(200)]` | Ordering of indicators. Lower = further left. Built-in indicators use 100–199 |

### CodeElementKinds (descriptor.Kind)

| Kind | Description |
|------|-------------|
| `CodeElementKinds.Type` | Class, struct, enum, interface |
| `CodeElementKinds.Method` | Method, constructor, destructor |
| `CodeElementKinds.Property` | Property |
| `CodeElementKinds.Event` | Event |

---

### Refreshing indicators

When the underlying data changes (e.g. a file is saved, a background service detects new issues), call `Invalidate()` on the data point to signal CodeLens to re-query `GetDataAsync`:

```csharp
public void Invalidate()
{
    InvalidatedAsync?.Invoke(this, EventArgs.Empty).ConfigureAwait(false);
}
```

You can trigger this from file system watchers, timers, or service events in your OOP assembly.

---

### StreamJsonRpc version considerations

The OOP CodeLens provider communicates with devenv.exe via **StreamJsonRpc**. Version mismatches cause failures:

- The **in-process** assembly (VSIX project) must use the StreamJsonRpc version bundled with VS. Check `devenv.exe.config` for binding redirects.
- The **out-of-process** assembly can use the latest 2.x StreamJsonRpc.
- Keep `Microsoft.VisualStudio.Language` aligned with the VS version you target.

---

### Troubleshooting

**Indicator doesn't appear:**
- Verify `Microsoft.VisualStudio.CodeLensComponent` asset is in the VSIX manifest
- Check that `CanCreateDataPointAsync` returns `true` for the code element
- Ensure CodeLens is enabled: Tools > Options > Text Editor > All Languages > CodeLens
- The OOP assembly must target .NET Framework 4.7.2+ (not .NET 6+)

**Details pane click does nothing:**
- Verify the `NavigationCommand.CommandSet` GUID and `CommandId` match your .vsct file
- Ensure the in-process package handles `IOleCommandTarget.Exec` for that command
- The `NavigationCommandArgs` items are passed via COM marshaling — use simple types (string, int)

**Custom details UI doesn't render:**
- Verify the `IViewElementFactory` is exported with the correct `TypeConversion` attribute matching the custom data type
- Ensure the MefComponent asset is in the VSIX manifest
- The shared assembly must be referenced by both OOP and VSIX projects

---

## See also

- [vs-editor-adornment](../vs-editor-adornment/SKILL.md) — visual decorations on the editor surface
- [vs-editor-quickinfo](../vs-editor-quickinfo/SKILL.md) — hover tooltips for contextual information
- [vs-editor-tagger](../vs-editor-tagger/SKILL.md) — taggers that CodeLens providers may depend on for span identification
- [vs-commands](../vs-commands/SKILL.md) — CodeLens navigation clicks are routed as VS commands

## Related documentation

- [VSSDK CodeLens OOP sample](https://github.com/microsoft/VSSDK-Extensibility-Samples/tree/master/CodeLensOopSample)
