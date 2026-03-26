---
name: adding-tool-window-search
description: Add the native Visual Studio search bar to a tool window. Use when the user asks how to add a search box, search control, search functionality, or IVsWindowSearch to a Visual Studio tool window. Covers enabling the built-in search UI via ToolWindowPane.SearchEnabled, implementing search tasks with VsSearchTask, adding search options and filters, and customizing search behavior. Applies to the VSSDK and VSIX Community Toolkit (in-process) models. The VisualStudio.Extensibility (out-of-process) model does not currently support the native tool window search bar.
---

# Adding Search to a Tool Window in Visual Studio Extensions

Visual Studio has a built-in search control that can be added to any tool window. It provides:

- A search box in the tool window's toolbar area
- A progress indicator overlaid on the search box
- Instant search (as-you-type) or on-demand search (press Enter)
- A most-recently-used search terms list
- Search options (boolean checkboxes, command buttons)
- Search filters (predefined filter tokens)

The search infrastructure is driven by the `IVsWindowSearch` interface in `Microsoft.VisualStudio.Shell.Interop`. The `ToolWindowPane` class already implements this interface with a default (disabled) implementation — you override specific members to enable and customize search.

The native search bar gives your tool window a familiar, consistent search experience that matches VS's own tool windows (Error List, Solution Explorer). It handles MRU, keyboard navigation, progress indication, and accessibility automatically. Building a custom WPF TextBox for search misses all of these behaviors.

**When to use this vs. alternatives:**
- Filter/search content within a tool window → **Tool window search** (this skill)
- Add a toolbar with command buttons to a tool window → [vs-tool-window-toolbar](../adding-tool-window-toolbars/SKILL.md)
- Create the tool window itself → [vs-tool-window](../adding-tool-windows/SKILL.md)
- Search across the entire solution (files, symbols) → built-in VS search (not extensible)

---

## 1. VisualStudio.Extensibility (out-of-process) — NOT SUPPORTED

The new `VisualStudio.Extensibility` SDK's `ToolWindow` base class (`Microsoft.VisualStudio.Extensibility.ToolWindows.ToolWindow`) renders content via `RemoteUserControl` and does **not** expose `IVsWindowSearch` or any equivalent search API.

**The native tool window search bar is not available in out-of-process extensions.** If you need search functionality in a VisualStudio.Extensibility tool window, you must build your own search UI entirely within the `RemoteUserControl` XAML data template and handle filtering in the data context.

```xml
<!-- Example: custom search TextBox in a RemoteUserControl template -->
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:vs="http://schemas.microsoft.com/visualstudio/extensibility/2022/xaml">
    <StackPanel>
        <TextBox Text="{Binding SearchText, Mode=TwoWay}" />
        <ItemsControl ItemsSource="{Binding FilteredItems}" />
    </StackPanel>
</DataTemplate>
```

This is a manual approach and does not integrate with the native VS search chrome.

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit's `BaseToolWindow<T>` class requires an inner `Pane` class that derives from `ToolkitToolWindowPane` (which extends `ToolWindowPane`). Because `ToolWindowPane` implements `IVsWindowSearch`, you override the search members **on the inner Pane class** to enable the native search bar.

The toolkit does not provide any additional search helpers — you use the same VSSDK overrides directly.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespaces:** `Community.VisualStudio.Toolkit`, `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`, `Microsoft.VisualStudio.PlatformUI`

### Step 1: Enable search on the Pane

```csharp
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Community.VisualStudio.Toolkit;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Imaging;
using Microsoft.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

public class MySearchToolWindow : BaseToolWindow<MySearchToolWindow>
{
    public override string GetTitle(int toolWindowId) => "My Searchable Window";

    public override Type PaneType => typeof(Pane);

    public override async Task<FrameworkElement> CreateAsync(int toolWindowId, CancellationToken cancellationToken)
    {
        return new MySearchControl();
    }

    [Guid("YOUR-GUID-HERE")]
    internal class Pane : ToolkitToolWindowPane
    {
        public Pane()
        {
            BitmapImageMoniker = KnownMonikers.Search;
        }

        // --- Enable the search bar ---
        public override bool SearchEnabled => true;

        // --- Create a search task when the user types a query ---
        public override IVsSearchTask CreateSearch(
            uint dwCookie,
            IVsSearchQuery pSearchQuery,
            IVsSearchCallback pSearchCallback)
        {
            if (pSearchQuery == null || pSearchCallback == null)
                return null;

            return new SearchTask(dwCookie, pSearchQuery, pSearchCallback, this);
        }

        // --- Restore the original content when the user clears the search ---
        public override void ClearSearch()
        {
            var control = (MySearchControl)Content;
            control.SearchResultsTextBox.Text = control.OriginalContent;
        }

        // --- Customize search behavior (optional) ---
        public override void ProvideSearchSettings(IVsUIDataSource pSearchSettings)
        {
            // Enable instant (as-you-type) search
            Utilities.SetValue(pSearchSettings,
                SearchSettingsDataSource.SearchStartTypeProperty.Name,
                (uint)VSSEARCHSTARTTYPE.SST_INSTANT);

            // Show a determinate progress bar
            Utilities.SetValue(pSearchSettings,
                SearchSettingsDataSource.SearchProgressTypeProperty.Name,
                (uint)VSSEARCHPROGRESSTYPE.SPT_DETERMINATE);
        }

        // --- Inner search task ---
        private class SearchTask : VsSearchTask
        {
            private readonly Pane _pane;

            public SearchTask(
                uint dwCookie,
                IVsSearchQuery pSearchQuery,
                IVsSearchCallback pSearchCallback,
                Pane pane)
                : base(dwCookie, pSearchQuery, pSearchCallback)
            {
                _pane = pane;
            }

            protected override void OnStartSearch()
            {
                var control = (MySearchControl)_pane.Content;
                var lines = control.OriginalContent.Split(
                    new[] { Environment.NewLine }, StringSplitOptions.None);

                var sb = new StringBuilder();
                uint resultCount = 0;
                ErrorCode = VSConstants.S_OK;

                try
                {
                    string query = SearchQuery.SearchString;
                    uint progress = 0;

                    foreach (string line in lines)
                    {
                        if (line.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            sb.AppendLine(line);
                            resultCount++;
                        }
                        SearchCallback.ReportProgress(this, progress++, (uint)lines.Length);
                    }
                }
                catch (Exception)
                {
                    ErrorCode = VSConstants.E_FAIL;
                }
                finally
                {
                    ThreadHelper.Generic.Invoke(() =>
                    {
                        ((MySearchControl)_pane.Content).SearchResultsTextBox.Text = sb.ToString();
                    });
                    SearchResults = resultCount;
                }

                base.OnStartSearch();
            }

            protected override void OnStopSearch()
            {
                SearchResults = 0;
            }
        }
    }
}
```

### Step 2: The UserControl

```csharp
public partial class MySearchControl : UserControl
{
    public TextBox SearchResultsTextBox { get; set; }
    public string OriginalContent { get; set; }

    public MySearchControl()
    {
        InitializeComponent();
        SearchResultsTextBox = resultsTextBox;
        OriginalContent = "Line 1: Hello\r\nLine 2: World\r\nLine 3: Search me";
        SearchResultsTextBox.Text = OriginalContent;
    }
}
```

```xml
<!-- MySearchControl.xaml -->
<UserControl x:Class="MyExtension.MySearchControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <TextBox Name="resultsTextBox" IsReadOnly="True"
             VerticalScrollBarVisibility="Auto"
             HorizontalScrollBarVisibility="Auto" />
</UserControl>
```

### Adding search options (e.g., Match case)

Override `SearchOptionsEnum` on the Pane class:

```csharp
private WindowSearchBooleanOption _matchCaseOption;
public WindowSearchBooleanOption MatchCaseOption
    => _matchCaseOption ??= new WindowSearchBooleanOption("Match case", "Match case", false);

private IVsEnumWindowSearchOptions _optionsEnum;
public override IVsEnumWindowSearchOptions SearchOptionsEnum
{
    get
    {
        if (_optionsEnum == null)
        {
            var list = new List<IVsWindowSearchOption> { MatchCaseOption };
            _optionsEnum = new WindowSearchOptionEnumerator(list) as IVsEnumWindowSearchOptions;
        }
        return _optionsEnum;
    }
}
```

Then in the search task, read the option:

```csharp
bool matchCase = ((Pane)_pane).MatchCaseOption.Value;
var comparison = matchCase ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
```

### Adding search filters

Override `SearchFiltersEnum` on the Pane class:

```csharp
public override IVsEnumWindowSearchFilters SearchFiltersEnum
{
    get
    {
        var filters = new List<IVsWindowSearchFilter>
        {
            new WindowSearchSimpleFilter("Errors only", "Show only error lines", "type", "error")
        };
        return new WindowSearchFilterEnumerator(filters) as IVsEnumWindowSearchFilters;
    }
}
```

When the user selects the filter, the token `type:"error"` is appended to the search query. Parse it in `OnStartSearch` and remove it from the search string before matching.

---

## 3. VSSDK (in-process, legacy)

With the raw VSSDK, your tool window class derives directly from `ToolWindowPane`, which already implements `IVsWindowSearch`. Override the relevant virtual members.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`, `Microsoft.VisualStudio.PlatformUI`

### Step 1: Enable search

```csharp
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Controls;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

[Guid("YOUR-GUID-HERE")]
public class MySearchToolWindow : ToolWindowPane
{
    public MySearchToolWindow() : base(null)
    {
        Caption = "My Searchable Window";
        Content = new MySearchControl();
    }

    // Enable the search bar
    public override bool SearchEnabled => true;

    // Create a search task
    public override IVsSearchTask CreateSearch(
        uint dwCookie,
        IVsSearchQuery pSearchQuery,
        IVsSearchCallback pSearchCallback)
    {
        if (pSearchQuery == null || pSearchCallback == null)
            return null;

        return new MySearchTask(dwCookie, pSearchQuery, pSearchCallback, this);
    }

    // Restore content when search is cleared
    public override void ClearSearch()
    {
        var control = (MySearchControl)Content;
        control.SearchResultsTextBox.Text = control.OriginalContent;
    }

    // Customize search settings
    public override void ProvideSearchSettings(IVsUIDataSource pSearchSettings)
    {
        Utilities.SetValue(pSearchSettings,
            SearchSettingsDataSource.SearchStartTypeProperty.Name,
            (uint)VSSEARCHSTARTTYPE.SST_INSTANT);

        Utilities.SetValue(pSearchSettings,
            SearchSettingsDataSource.SearchProgressTypeProperty.Name,
            (uint)VSSEARCHPROGRESSTYPE.SPT_DETERMINATE);
    }
}
```

### Step 2: Implement the search task

```csharp
internal class MySearchTask : VsSearchTask
{
    private readonly MySearchToolWindow _toolWindow;

    public MySearchTask(
        uint dwCookie,
        IVsSearchQuery pSearchQuery,
        IVsSearchCallback pSearchCallback,
        MySearchToolWindow toolWindow)
        : base(dwCookie, pSearchQuery, pSearchCallback)
    {
        _toolWindow = toolWindow;
    }

    protected override void OnStartSearch()
    {
        var control = (MySearchControl)_toolWindow.Content;
        var lines = control.OriginalContent.Split(
            new[] { Environment.NewLine }, StringSplitOptions.None);

        var sb = new StringBuilder();
        uint resultCount = 0;
        ErrorCode = VSConstants.S_OK;

        try
        {
            string query = SearchQuery.SearchString;
            uint progress = 0;

            foreach (string line in lines)
            {
                if (line.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    sb.AppendLine(line);
                    resultCount++;
                }

                // Report progress for the determinate progress bar
                SearchCallback.ReportProgress(this, progress++, (uint)lines.Length);
            }
        }
        catch (Exception)
        {
            ErrorCode = VSConstants.E_FAIL;
        }
        finally
        {
            // Update UI on the main thread
            ThreadHelper.Generic.Invoke(() =>
            {
                ((MySearchControl)_toolWindow.Content).SearchResultsTextBox.Text = sb.ToString();
            });

            SearchResults = resultCount;
        }

        // Report completion to the search host
        base.OnStartSearch();
    }

    protected override void OnStopSearch()
    {
        SearchResults = 0;
    }
}
```

### Step 3: Register the tool window

```csharp
[ProvideToolWindow(typeof(MySearchToolWindow))]
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid("YOUR-PACKAGE-GUID-HERE")]
public sealed class MyPackage : AsyncPackage
{
    // ...
}
```

### Adding search options

```csharp
// In MySearchToolWindow:
private WindowSearchBooleanOption _matchCaseOption;
public WindowSearchBooleanOption MatchCaseOption
    => _matchCaseOption ??= new WindowSearchBooleanOption("Match case", "Match case", false);

private IVsEnumWindowSearchOptions _optionsEnum;
public override IVsEnumWindowSearchOptions SearchOptionsEnum
{
    get
    {
        if (_optionsEnum == null)
        {
            var list = new List<IVsWindowSearchOption> { MatchCaseOption };
            _optionsEnum = new WindowSearchOptionEnumerator(list) as IVsEnumWindowSearchOptions;
        }
        return _optionsEnum;
    }
}
```

### Adding search filters

```csharp
// In MySearchToolWindow:
public override IVsEnumWindowSearchFilters SearchFiltersEnum
{
    get
    {
        var filters = new List<IVsWindowSearchFilter>
        {
            new WindowSearchSimpleFilter("Errors only", "Show only error lines", "type", "error")
        };
        return new WindowSearchFilterEnumerator(filters) as IVsEnumWindowSearchFilters;
    }
}
```

---

## Key members of IVsWindowSearch

All of these are virtual on `ToolWindowPane` and can be overridden:

| Member | Purpose |
|--------|---------|
| `SearchEnabled` | Return `true` to show the search bar |
| `CreateSearch(dwCookie, query, callback)` | Create and return an `IVsSearchTask` (typically a `VsSearchTask` subclass) |
| `ClearSearch()` | Restore the original (unfiltered) content |
| `ProvideSearchSettings(IVsUIDataSource)` | Configure instant vs. on-demand search, progress bar, watermark text, etc. |
| `SearchOptionsEnum` | Provide checkboxes/buttons (e.g., Match case, Match whole word) |
| `SearchFiltersEnum` | Provide predefined filter tokens (appear in a dropdown) |
| `SearchHost` | The `IVsWindowSearchHost` automatically created by the shell |

## Key members of VsSearchTask

| Member | Purpose |
|--------|---------|
| `OnStartSearch()` | Runs on a background thread — implement your search logic here. Call `base.OnStartSearch()` at the end to report completion. |
| `OnStopSearch()` | Called when the search is cancelled. Set `SearchResults = 0`. |
| `SearchQuery.SearchString` | The user's query text |
| `SearchCallback.ReportProgress(task, current, total)` | Drive the progress bar |
| `SearchResults` | Set to the result count before calling `base.OnStartSearch()` |
| `ErrorCode` | Set to `VSConstants.S_OK` on success or `VSConstants.E_FAIL` on error |

## SearchSettingsDataSource properties

Use `Utilities.SetValue()` inside `ProvideSearchSettings` to configure:

| Property | Values |
|----------|--------|
| `SearchStartTypeProperty` | `SST_INSTANT` (as-you-type) or `SST_DELAYED` (on Enter) |
| `SearchProgressTypeProperty` | `SPT_DETERMINATE` (shows percentage) or `SPT_INDETERMINATE` (animated) or `SPT_NONE` |
| `SearchWatermarkProperty` | Custom placeholder text for the search box |
| `SearchPopupAutoDropdownProperty` | Whether the MRU list auto-drops down |
| `SearchUseMRUProperty` | Enable/disable MRU history |

## Key guidance

- **VisualStudio.Extensibility** does not support the native tool window search bar. Build custom search UI in your `RemoteUserControl` if needed.
- For **VSSDK** and **Community Toolkit** extensions, override `SearchEnabled => true` on the `ToolWindowPane` (or the inner `Pane` class) — the shell automatically creates the search host.
- `OnStartSearch()` runs on a **background thread**. Use `ThreadHelper.Generic.Invoke()` to update WPF controls.
- `CreateSearch()` and `ClearSearch()` run on the **UI thread**.
- Always call `base.OnStartSearch()` at the end of your `OnStartSearch` override to report task completion.
- Set `SearchResults` before calling `base.OnStartSearch()` so the search host can display the count.

## Troubleshooting

- **Search box doesn't appear:** Verify `SearchEnabled` returns `true` on the `ToolWindowPane` class (or the inner `Pane` class if using Toolkit's `BaseToolWindow<T>`). The property must be an override, not a new property.
- **Search runs but UI doesn't update:** `OnStartSearch()` runs on a background thread. Use `ThreadHelper.Generic.Invoke()` or `Dispatcher.Invoke()` to update WPF controls from within the search task.
- **Results count shows 0:** Set `SearchResults` property *before* calling `base.OnStartSearch()`. The base method reports the task as complete and reads the count at that point.
- **Search options/filters don't appear:** Override `SearchOptionsEnum` and/or `SearchFiltersEnum` on the `ToolWindowPane` to return your custom `IVsEnumWindowSearchOptions`/`IVsEnumWindowSearchFilters`.
- **MRU dropdown doesn't show previous searches:** Ensure `SearchUseMRUProperty` is not explicitly set to `false` in your `SearchSettingsDataSource`. MRU is enabled by default.

## What NOT to do

> **Do NOT** build a custom WPF `TextBox` for search — the native `IVsWindowSearch` control handles MRU, keyboard navigation, progress, accessibility, and styling for free.

> **Do NOT** do heavy work synchronously in `CreateSearch()`/`ClearSearch()` — they run on the UI thread. Offload work to `VsSearchTask.OnStartSearch()` which runs on a background thread.

> **Do NOT** forget to call `base.OnStartSearch()` at the end of your override — without it, the search progress indicator never completes.

## See also

- [vs-tool-window](../adding-tool-windows/SKILL.md)
- [vs-tool-window-toolbar](../adding-tool-window-toolbars/SKILL.md)
- [vs-commands](../adding-commands/SKILL.md)

## References

- [Adding Search to a Tool Window (VSSDK walkthrough)](https://learn.microsoft.com/visualstudio/extensibility/adding-search-to-a-tool-window)
- [IVsWindowSearch Interface](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.interop.ivswindowsearch)
- [ToolWindowPane Class](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.toolwindowpane)
- [VsSearchTask Class](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.shell.vssearchtask)
- [SearchSettingsDataSource Class](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.platformui.searchsettingsdatasource)
- [Create Tool Windows (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/tool-window/tool-window)
- [Custom Tool Windows (Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/recipes/custom-tool-windows)
