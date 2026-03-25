---
name: vs-error-list
description: Push custom errors, warnings, and messages into the Visual Studio Error List window. Use when the user asks about adding items to the Error List, creating an ErrorListProvider, using TableDataSource, reporting diagnostics, validation errors, or navigating to error locations in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Error List Integration in Visual Studio Extensions

The Error List is one of Visual Studio's most prominent tool windows. Extensions can push custom errors, warnings, and messages into it so users can click through to the relevant source location.

---

## 1. VSIX Community Toolkit (in-process)

The toolkit wraps the complex `ITableDataSource` plumbing into two simple classes: `TableDataSource` and `ErrorListItem`.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Create a TableDataSource

Create one `TableDataSource` per extension. Give it a unique display name.

```csharp
private static readonly TableDataSource _errorList = new("MyExtension");
```

### Add errors

```csharp
var errors = new List<ErrorListItem>
{
    new ErrorListItem
    {
        ProjectName = "MyProject",
        FileName = @"C:\repos\MyProject\Program.cs",
        Line = 10,
        Column = 5,
        Message = "Missing semicolon",
        ErrorCode = "EXT001",
        Severity = __VSERRORCATEGORY.EC_ERROR,
        BuildTool = "MyExtension"
    },
    new ErrorListItem
    {
        ProjectName = "MyProject",
        FileName = @"C:\repos\MyProject\Program.cs",
        Line = 25,
        Message = "Unused variable 'x'",
        ErrorCode = "EXT002",
        Severity = __VSERRORCATEGORY.EC_WARNING,
        BuildTool = "MyExtension"
    }
};

_errorList.AddErrors(errors);
```

### Severity values

| Value | Icon |
|---|---|
| `__VSERRORCATEGORY.EC_ERROR` | Red error |
| `__VSERRORCATEGORY.EC_WARNING` | Yellow warning |
| `__VSERRORCATEGORY.EC_MESSAGE` | Blue message |

Setting `Line` and `Column` makes the entry clickable — double-clicking navigates to that location.

### Clear errors

```csharp
_errorList.CleanAllErrors();
```

### Full example — refresh on document save

```csharp
[Command(PackageIds.ValidateCommand)]
internal sealed class ValidateCommand : BaseCommand<ValidateCommand>
{
    private static readonly TableDataSource _errorList = new("MyExtension");

    protected override async Task InitializeCompletedAsync()
    {
        VS.Events.DocumentEvents.Saved += OnDocumentSaved;
    }

    private void OnDocumentSaved(string filePath)
    {
        _errorList.CleanAllErrors();

        IEnumerable<ErrorListItem> errors = ValidateFile(filePath);
        _errorList.AddErrors(errors);
    }

    private static IEnumerable<ErrorListItem> ValidateFile(string filePath)
    {
        // Your validation logic here
        yield break;
    }

    protected override Task ExecuteAsync(OleMenuCmdEventArgs e)
    {
        return Task.CompletedTask;
    }
}
```

### ErrorListItem properties reference

| Property | Type | Description |
|---|---|---|
| `ProjectName` | `string` | Project name shown in the Error List |
| `FileName` | `string` | Full path to the file (required for click navigation) |
| `Line` | `int` | 0-based line number |
| `Column` | `int` | 0-based column number |
| `Message` | `string` | The error/warning message text |
| `ErrorCode` | `string` | Short error code (e.g. "EXT001") |
| `ErrorCodeToolTip` | `string` | Tooltip shown when hovering the error code |
| `ErrorCategory` | `string` | Category string |
| `Severity` | `__VSERRORCATEGORY` | Error, Warning, or Message |
| `HelpLink` | `string` | URL for the help link |
| `BuildTool` | `string` | Name of the tool that generated the error |
| `Icon` | `ImageMoniker` | Custom icon moniker |

---

## 2. VSSDK (in-process, legacy)

> **Do not use `ErrorListProvider` / `ErrorTask`.** These older `TaskProvider`-based APIs predate the modern Error List table infrastructure (VS 2015+). They are deprecated in favor of the `ITableDataSource` / `ITableEntriesSnapshot` pattern that the new Error List is built on. The toolkit's `TableDataSource` wraps this modern infrastructure; if you're not using the toolkit, implement the interfaces directly as shown below.

The modern VSSDK Error List is backed by the **ITableManager** infrastructure. There are no base classes — you must implement all the interfaces yourself.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell.TableManager`, `Microsoft.VisualStudio.Shell.TableControl`

You need to implement three interfaces:

1. **`ITableDataSource`** — registers with the Error List's `ITableManager` and creates snapshots.
2. **`ITableDataSink`** — provided by VS; you call its methods to notify the Error List that data changed.
3. **`ITableEntriesSnapshot`** — an immutable snapshot of your current error items; VS reads column values from it.

### Implement ITableDataSource

```csharp
using Microsoft.VisualStudio.Shell.TableManager;

internal class MyErrorDataSource : ITableDataSource
{
    private readonly List<ITableDataSink> _sinks = new();
    private MyErrorSnapshot _currentSnapshot = new(Array.Empty<MyError>());

    // These identify your source in the Error List filter dropdown
    public string SourceTypeIdentifier => StandardTableDataSources.ErrorTableDataSource;
    public string Identifier => "MyExtension";
    public string DisplayName => "My Extension";

    public IDisposable Subscribe(ITableDataSink sink)
    {
        _sinks.Add(sink);
        sink.AddSnapshot(_currentSnapshot);
        return new DisposableAction(() => _sinks.Remove(sink));
    }

    public void UpdateErrors(IReadOnlyList<MyError> errors)
    {
        _currentSnapshot = new MyErrorSnapshot(errors);
        foreach (var sink in _sinks)
        {
            sink.ReplaceSnapshot(_currentSnapshot, _currentSnapshot);
        }
    }

    public void ClearErrors() => UpdateErrors(Array.Empty<MyError>());
}
```

### Implement ITableEntriesSnapshot

```csharp
internal class MyErrorSnapshot : ITableEntriesSnapshot
{
    private readonly IReadOnlyList<MyError> _errors;

    public MyErrorSnapshot(IReadOnlyList<MyError> errors) => _errors = errors;

    public int Count => _errors.Count;
    public int VersionNumber { get; } = 0;

    public bool TryGetValue(int index, string keyName, out object content)
    {
        if (index < 0 || index >= _errors.Count)
        {
            content = null;
            return false;
        }

        var error = _errors[index];
        switch (keyName)
        {
            case StandardTableKeyNames.Text:
                content = error.Message;
                return true;
            case StandardTableKeyNames.DocumentName:
                content = error.FileName;
                return true;
            case StandardTableKeyNames.Line:
                content = error.Line;
                return true;
            case StandardTableKeyNames.Column:
                content = error.Column;
                return true;
            case StandardTableKeyNames.ErrorSeverity:
                content = error.Severity;
                return true;
            case StandardTableKeyNames.ErrorCode:
                content = error.ErrorCode;
                return true;
            case StandardTableKeyNames.BuildTool:
                content = error.BuildTool;
                return true;
            case StandardTableKeyNames.ProjectName:
                content = error.ProjectName;
                return true;
            default:
                content = null;
                return false;
        }
    }

    // Required stubs
    public void Dispose() { }
    public void StartCaching() { }
    public void StopCaching() { }
    public int IndexOf(int currentIndex, ITableEntriesSnapshot newSnapshot) => currentIndex;
}
```

### Register with the Error List table manager

```csharp
// During package initialization
ITableManagerProvider tableManagerProvider =
    GetService(typeof(SComponentModel)) is IComponentModel componentModel
        ? componentModel.GetService<ITableManagerProvider>()
        : null;

ITableManager errorTableManager =
    tableManagerProvider.GetTableManager(StandardTables.ErrorsTable);

var dataSource = new MyErrorDataSource();
errorTableManager.AddSource(dataSource, StandardTableColumnDefinitions.ErrorSeverity,
    StandardTableColumnDefinitions.ErrorCode, StandardTableColumnDefinitions.Text,
    StandardTableColumnDefinitions.DocumentName, StandardTableColumnDefinitions.Line,
    StandardTableColumnDefinitions.Column, StandardTableColumnDefinitions.ProjectName,
    StandardTableColumnDefinitions.BuildTool);
```

> **Note:** The `ITableDataSource` approach is significantly more code than the toolkit's `TableDataSource`. Use it when you need fine-grained control over snapshots, custom columns, or high-frequency updates where snapshot-based diffing is important. For most extensions, prefer the toolkit wrapper.

---

## 3. VisualStudio.Extensibility (out-of-process)

The VisualStudio.Extensibility SDK does **not** currently provide a direct API for writing to the Error List. Error List integration is an in-process feature that relies on `ITableDataSource` or `ErrorListProvider`, both of which require in-process access to the VS shell.

If you need Error List support from an out-of-process extension, your options are:

1. **Use the Output Window instead** — write diagnostics to a custom output channel:
   ```csharp
   OutputChannel? channel = await this.Extensibility.Views().Output
       .CreateOutputChannelAsync("My Extension", cancellationToken);
   await channel.Writer.WriteLineAsync("Error: Missing semicolon at line 10");
   ```

2. **Use a mixed in-proc/out-of-proc extension** — keep your main logic out-of-process but add an in-process companion component that hosts the `ErrorListProvider` or `TableDataSource`. See the [VisualStudio.Extensibility documentation on in-proc extensions](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/inside-the-sdk/advanced-remote-ui).

---

## Additional resources

- [VSIX Cookbook — Error List integration](https://www.vsixcookbook.com/recipes/error-list.html)
- [ErrorListProvider class reference](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.errorlistprovider)
- [VisualStudio.Extensibility — Output Window](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/output-window/output-window)
