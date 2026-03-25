---
name: vs-open-folder
description: Extend Visual Studio's Open Folder mode with custom file scanners, file context providers, file actions, and workspace settings. Use when the user asks how to support Open Folder, add context menu actions to files without a project system, provide symbol scanning for Go To, supply build contexts for custom file types, or store per-folder settings in .vs/VSWorkspaceSettings.json. Covers VSSDK / VSIX Community Toolkit (in-process). VisualStudio.Extensibility (out-of-process) does not have a dedicated Open Folder workspace API.
---

# Open Folder Extensibility in Visual Studio

Open Folder lets users open any codebase in Visual Studio without a project or solution file. Extensions can enhance this experience by providing:

- **File context providers** — supply build, debug, or language contexts for files
- **File context actions** — attach right-click actions to custom file types
- **File scanners** — scan files for symbols that appear in Go To (Ctrl+,)
- **Workspace settings** — read and write per-folder settings stored in `.vs/VSWorkspaceSettings.json`

All Open Folder APIs are in the `Microsoft.VisualStudio.Workspace.*` namespaces and are MEF-based.

## VisualStudio.Extensibility (out-of-process)

**Not supported.** The new extensibility model does not have Open Folder workspace APIs. The `Microsoft.VisualStudio.Workspace.*` APIs require in-process MEF composition. If your VisualStudio.Extensibility extension needs Open Folder support, use an in-process hybrid component.

---

## VSSDK / VSIX Community Toolkit (in-process)

The Toolkit and VSSDK approaches are identical for Open Folder — all workspace extensibility uses the same MEF-based `Microsoft.VisualStudio.Workspace.*` APIs.

**NuGet packages:**
- `Microsoft.VisualStudio.SDK` (≥ 17.0)
- `Microsoft.VisualStudio.Workspace.Extensions` (contains the workspace API types)

**Key namespaces:**
- `Microsoft.VisualStudio.Workspace`
- `Microsoft.VisualStudio.Workspace.Build`
- `Microsoft.VisualStudio.Workspace.Extensions.VS`
- `Microsoft.VisualStudio.Workspace.Indexing`
- `Microsoft.VisualStudio.Workspace.Settings`

### File organization

```
MyExtension/
├── OpenFolder/
│   ├── MyFileContextProvider.cs
│   ├── MyFileActionProvider.cs
│   ├── MyFileScanner.cs
│   └── MySettingsProvider.cs
├── MyExtensionPackage.cs
├── source.extension.vsixmanifest
└── MyExtension.csproj
```

### VSIX manifest — MEF asset

Open Folder providers are discovered through MEF. Add the MefComponent asset to your `source.extension.vsixmanifest`:

```xml
<Assets>
  <Asset Type="Microsoft.VisualStudio.MefComponent" d:Source="Project" d:ProjectName="%CurrentProject%" Path="|%CurrentProject%|" />
</Assets>
```

---

## 1. File Context Providers

File context providers supply metadata about files — build contexts, debug contexts, or custom data. The workspace matches consumer requests to providers based on the context type GUID.

**OpenFolder/MyFileContextProvider.cs:**

```csharp
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Workspace;

namespace MyExtension.OpenFolder;

// The factory creates a provider instance per workspace
[ExportFileContextProvider(
    ProviderType,
    PackageIds.BuildContextTypeGuid)]  // The context type GUID this provider produces
internal class MyBuildContextProviderFactory : IWorkspaceProviderFactory<IFileContextProvider>
{
    private const string ProviderType = "9A31D832-5AB2-4E1A-A446-5B4E5AC58A3A";

    public IFileContextProvider CreateProvider(IWorkspace workspace)
    {
        return new MyBuildContextProvider(workspace);
    }
}

internal class MyBuildContextProvider : IFileContextProvider
{
    private readonly IWorkspace workspace;

    public MyBuildContextProvider(IWorkspace workspace)
    {
        this.workspace = workspace;
    }

    public async Task<IReadOnlyCollection<FileContext>> GetContextsForFileAsync(
        string filePath,
        CancellationToken cancellationToken)
    {
        // Only provide context for .mylang files
        if (!filePath.EndsWith(".mylang", StringComparison.OrdinalIgnoreCase))
        {
            return Array.Empty<FileContext>();
        }

        var context = new FileContext(
            new Guid("9A31D832-5AB2-4E1A-A446-5B4E5AC58A3A"),  // Provider GUID
            BuildContextTypes.BuildContextType,                   // Context type
            filePath,
            new[] { filePath });

        return new[] { context };
    }
}
```

### Built-in context type GUIDs

| Constant | Purpose |
|----------|---------|
| `BuildContextTypes.BuildContextType` | Build contexts for the Build menu |
| `BuildContextTypes.RebuildContextType` | Rebuild contexts |
| `BuildContextTypes.CleanContextType` | Clean contexts |

---

## 2. File Context Actions

File context actions add entries to the right-click context menu for files in Solution Explorer (Open Folder mode).

**OpenFolder/MyFileActionProvider.cs:**

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Workspace;
using Microsoft.VisualStudio.Workspace.Extensions.VS;

namespace MyExtension.OpenFolder;

[ExportFileContextActionProvider(
    (FileContextActionProviderOptions)0,   // No special options
    ProviderType,
    PackageIds.BuildContextTypeGuid)]       // Apply to build contexts
internal class MyFileActionProviderFactory : IWorkspaceProviderFactory<IFileContextActionProvider>
{
    private const string ProviderType = "B1C3F8A5-2D4E-4F6A-8B9C-1E2D3F4A5B6C";

    public IFileContextActionProvider CreateProvider(IWorkspace workspace)
    {
        return new MyFileActionProvider();
    }
}

internal class MyFileActionProvider : IFileContextActionProvider
{
    public Task<IReadOnlyList<IFileContextAction>> GetActionsAsync(
        string filePath,
        FileContext fileContext,
        CancellationToken cancellationToken)
    {
        var actions = new List<IFileContextAction>
        {
            new WordCountAction(filePath)
        };

        return Task.FromResult<IReadOnlyList<IFileContextAction>>(actions);
    }
}

internal class WordCountAction : IFileContextAction
{
    private readonly string filePath;

    public WordCountAction(string filePath)
    {
        this.filePath = filePath;
    }

    public string DisplayName => "Count Words";

    public async Task<IFileContextActionResult> ExecuteAsync(
        IProgress<IFileContextActionProgressUpdate> progress,
        CancellationToken cancellationToken)
    {
        string text = File.ReadAllText(filePath);
        int wordCount = text.Split(
            new[] { ' ', '\t', '\r', '\n' },
            StringSplitOptions.RemoveEmptyEntries).Length;

        // Show result — use VS.MessageBox if using Toolkit, or
        // IVsUIShell message box for pure VSSDK
        System.Windows.Forms.MessageBox.Show(
            $"Word count: {wordCount}",
            "Word Count",
            System.Windows.Forms.MessageBoxButtons.OK,
            System.Windows.Forms.MessageBoxIcon.Information);

        return new FileContextActionResult(true);
    }
}
```

---

## 3. File Scanners (Symbol Providers)

File scanners extract symbol information from custom file types so they appear in **Go To** (Ctrl+,) and **Navigate To**.

**OpenFolder/MyFileScanner.cs:**

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Workspace;
using Microsoft.VisualStudio.Workspace.Indexing;

namespace MyExtension.OpenFolder;

[ExportFileScannerProvider(
    ProviderType,
    "File")]                    // Scanner attribute type
internal class MyFileScannerProviderFactory : IWorkspaceProviderFactory<IFileScanner>
{
    private const string ProviderType = "D4E5F6A7-8B9C-1D2E-3F4A-5B6C7D8E9F10";

    public IFileScanner CreateProvider(IWorkspace workspace)
    {
        return new MyFileScanner();
    }
}

internal class MyFileScanner : IFileScanner
{
    // Declare which kinds of data this scanner produces
    public IReadOnlyCollection<FileDataValue> ReadableFileDataTypes { get; } = new[]
    {
        FileDataValue.FileSymbolType
    };

    public async Task<T[]> ReadFileAsync<T>(string filePath, CancellationToken cancellationToken)
        where T : class
    {
        // Only scan .mylang files
        if (!filePath.EndsWith(".mylang", StringComparison.OrdinalIgnoreCase))
        {
            return Array.Empty<T>();
        }

        if (typeof(T) != typeof(FileSymbol))
        {
            return Array.Empty<T>();
        }

        var symbols = new List<FileSymbol>();
        string[] lines = await Task.Run(() => File.ReadAllLines(filePath), cancellationToken);

        // Simple pattern: lines starting with "func " define a function symbol
        var funcPattern = new Regex(@"^func\s+(\w+)", RegexOptions.Compiled);

        for (int i = 0; i < lines.Length; i++)
        {
            var match = funcPattern.Match(lines[i]);
            if (match.Success)
            {
                symbols.Add(new FileSymbol(
                    match.Groups[1].Value,          // Symbol name
                    SymbolKind.Function,
                    new TextSpan(i, 0, i, lines[i].Length),
                    filePath));
            }
        }

        return symbols.Cast<T>().ToArray();
    }
}
```

---

## 4. Workspace Settings

Open Folder stores per-folder settings in `.vs/VSWorkspaceSettings.json`. Extensions can read and write these settings.

### Reading settings

```csharp
using Microsoft.VisualStudio.Workspace;
using Microsoft.VisualStudio.Workspace.Settings;

private void ReadSettings(IWorkspace workspace)
{
    IWorkspaceSettingsManager settingsManager = workspace.GetSettingsManager();
    IWorkspaceSettings settings = settingsManager.GetAggregatedSettings(SettingsTypes.Generic);

    // Read typed values
    WorkspaceSettingsResult result = settings.GetProperty("myext.maxItems", out int maxItems);
    if (result == WorkspaceSettingsResult.Success)
    {
        // Use maxItems
    }

    // Extension method with default
    string outputDir = settings.Property("myext.outputDir", /* default */ "bin");
}
```

### Providing dynamic settings

Implement `IWorkspaceSettingsProviderFactory` to provide settings programmatically:

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Workspace;
using Microsoft.VisualStudio.Workspace.Settings;

[Export(typeof(IWorkspaceSettingsProviderFactory))]
internal class MySettingsProviderFactory : IWorkspaceSettingsProviderFactory
{
    public int Priority => 200;  // Lower = higher priority; built-in is ~100

    public IWorkspaceSettingsProvider CreateSettingsProvider(IWorkspace workspace)
    {
        return new MySettingsProvider(workspace);
    }
}
```

### Settings scope hierarchy

Settings are aggregated across scopes (highest to lowest priority):

1. `.vs/` folder ("local settings") at workspace root
2. The requested file's directory
3. Parent directories up to workspace root
4. User-global settings directory

---

## Auto-loading packages in Open Folder mode

To auto-load your package when a folder is opened (instead of a solution), use the Open Folder UI context:

```csharp
[ProvideAutoLoad(
    "4646B819-1AE0-4E79-97F4-8A8176FDD664",  // Open Folder UI context GUID
    PackageAutoLoadFlags.BackgroundLoad)]
public sealed class MyExtensionPackage : ToolkitPackage
{
    // ...
}
```

You can also implement `IVsSolutionEvents7` for folder open/close events:

```csharp
public void OnAfterOpenFolder(string folderPath)
{
    // Folder was opened — initialize workspace-related features
}

public void OnAfterCloseFolder(string folderPath)
{
    // Folder was closed — clean up
}
```

---

## Troubleshooting

### "The SourceExplorerPackage package did not load correctly"

This usually means a MEF composition error. Check the error log at:

```
%LOCALAPPDATA%\Microsoft\VisualStudio\17.0_<id>\ComponentModelCache\Microsoft.VisualStudio.Default.err
```

Common causes:
- Export attribute type doesn't match the implemented interface (e.g. exporting `IFileContextProvider` but implementing `IFileContextActionProvider`)
- Missing MEF asset in `source.extension.vsixmanifest`

### Grammar/colorization not working in Open Folder

TextMate grammars work in Open Folder out of the box. If colorization isn't appearing, see the `vs-textmate-grammar` skill for registration steps.

---

## Related documentation

- [Open Folder extensibility overview](https://learn.microsoft.com/en-us/visualstudio/extensibility/open-folder?view=vs-2022)
- [Workspaces API](https://learn.microsoft.com/en-us/visualstudio/extensibility/workspaces?view=vs-2022)
- [File contexts and actions](https://learn.microsoft.com/en-us/visualstudio/extensibility/workspace-file-contexts?view=vs-2022)
- [Workspace indexing](https://learn.microsoft.com/en-us/visualstudio/extensibility/workspace-indexing?view=vs-2022)
- [Workspace build support](https://learn.microsoft.com/en-us/visualstudio/extensibility/workspace-build?view=vs-2022)
- [Workspace language services](https://learn.microsoft.com/en-us/visualstudio/extensibility/workspace-language-services?view=vs-2022)
- [VSSDK Open Folder sample](https://github.com/Microsoft/VSSDK-Extensibility-Samples/tree/master/Open_Folder_Extensibility)
