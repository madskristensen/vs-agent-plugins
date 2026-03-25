---
name: vs-solution-explorer-nodes
description: Add custom nodes to Solution Explorer in Visual Studio extensions using MEF. Use when the user asks about adding custom tree nodes, virtual items, workspace files, or attached collections to the Solution Explorer tree view. Covers the IAttachedCollectionSourceProvider MEF pattern used by both VSSDK and VSIX Community Toolkit (in-process). VisualStudio.Extensibility (out-of-process) does not support this scenario.
---

# Adding Custom Nodes to Solution Explorer

Extensions can add custom nodes (virtual items) to the Solution Explorer tree using the `IAttachedCollectionSourceProvider` MEF pattern. This allows injecting nodes under the solution node, project nodes, or other existing hierarchy items.

---

## VisualStudio.Extensibility (out-of-process) — Not Supported

The new out-of-process extensibility model does **not** support adding custom nodes to Solution Explorer. The Project Query API provides read/write access to projects and files but cannot inject custom tree nodes into the Solution Explorer UI. Use the in-process MEF approach described below instead.

---

## VSSDK and VSIX Community Toolkit (in-process, MEF)

Both VSSDK and the Community Toolkit use the same MEF-based approach. The toolkit doesn't add any specific helpers for this scenario, so the implementation is identical regardless of which package you reference. The examples below use `Community.VisualStudio.Toolkit` helpers where convenient (e.g., `VS.GetRequiredService`, `ThreadHelper`), but the core MEF contracts come from VSSDK assemblies.

**NuGet packages:** `Microsoft.VisualStudio.SDK` (VSSDK) or `Community.VisualStudio.Toolkit` (which includes the SDK)
**Key namespace:** `Microsoft.Internal.VisualStudio.PlatformUI`

### Architecture overview

Adding custom nodes requires three pieces:

1. **`IAttachedCollectionSourceProvider`** — A MEF export that tells Solution Explorer which items support your custom nodes and creates the collection sources.
2. **Node classes** — Classes implementing `IAttachedCollectionSource`, `ITreeDisplayItem`, `ITreeDisplayItemWithImages`, and `IInteractionPatternProvider` that represent your custom nodes.
3. **Relationships** — `IAttachedRelationship` instances for `Contains` (parent→children) and optionally `ContainedBy` (child→parent, needed for search support).

### Step 1: Create the source provider

The source provider is the MEF entry point. It determines which existing items get your custom children and creates the collection sources.

```csharp
using System.Collections.Generic;
using System.ComponentModel.Composition;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Utilities;

[Export(typeof(IAttachedCollectionSourceProvider))]
[Name(nameof(MyNodeSourceProvider))]
[Order(Before = HierarchyItemsProviderNames.Contains)]
internal class MyNodeSourceProvider : IAttachedCollectionSourceProvider
{
    private MyRootNode _rootNode;

    public IEnumerable<IAttachedRelationship> GetRelationships(object item)
    {
        // Add children under the solution node
        if (item is IVsHierarchyItem hierarchyItem
            && HierarchyUtilities.IsSolutionNode(hierarchyItem.HierarchyIdentity))
        {
            yield return Relationships.Contains;
        }
        // Custom nodes can also have children and a parent (for search)
        else if (item is MyItemNode)
        {
            yield return Relationships.Contains;
            yield return Relationships.ContainedBy;
        }
        else if (item is MyRootNode)
        {
            yield return Relationships.Contains;
            yield return Relationships.ContainedBy;
        }
    }

    public IAttachedCollectionSource CreateCollectionSource(object item, string relationshipName)
    {
        if (relationshipName == KnownRelationships.Contains)
        {
            // When Solution Explorer asks for children of the solution node,
            // return the root node (which is itself an IAttachedCollectionSource)
            if (item is IVsHierarchyItem hierarchyItem
                && HierarchyUtilities.IsSolutionNode(hierarchyItem.HierarchyIdentity))
            {
                return _rootNode ??= new MyRootNode(hierarchyItem);
            }
            else if (item is MyItemNode node)
            {
                return node; // Node is its own collection source
            }
        }
        else if (relationshipName == KnownRelationships.ContainedBy)
        {
            // ContainedBy enables Solution Explorer search to trace back to parents
            if (item is MyItemNode node)
            {
                return new ContainedByCollection(node, node.ParentItem);
            }
            else if (item is MyRootNode rootNode)
            {
                return new ContainedByCollection(rootNode, rootNode.ParentItem);
            }
        }

        return null;
    }
}
```

You can also attach nodes under project nodes instead of (or in addition to) the solution node by checking for project hierarchy items:

```csharp
public IEnumerable<IAttachedRelationship> GetRelationships(object item)
{
    if (item is IVsHierarchyItem hierarchyItem
        && HierarchyUtilities.IsProjectNode(hierarchyItem.HierarchyIdentity))
    {
        yield return Relationships.Contains;
    }
}
```

### Step 2: Define the relationship helpers

```csharp
using Microsoft.Internal.VisualStudio.PlatformUI;

internal static class Relationships
{
    public static IAttachedRelationship Contains { get; } = new ContainsRelationship();
    public static IAttachedRelationship ContainedBy { get; } = new ContainedByRelationship();

    private sealed class ContainsRelationship : IAttachedRelationship
    {
        public string Name => KnownRelationships.Contains;
        public string DisplayName => KnownRelationships.Contains;
    }

    private sealed class ContainedByRelationship : IAttachedRelationship
    {
        public string Name => KnownRelationships.ContainedBy;
        public string DisplayName => KnownRelationships.ContainedBy;
    }
}
```

### Step 3: Create the ContainedBy collection

This simple collection enables the `ContainedBy` relationship for search support — it returns the parent(s) of a given child item.

```csharp
using System.Collections;
using Microsoft.Internal.VisualStudio.PlatformUI;

internal sealed class ContainedByCollection(object child, object parent) : IAttachedCollectionSource
{
    private readonly object[] _items = parent != null ? [parent] : [];

    public object SourceItem { get; } = child;
    public bool HasItems => _items.Length > 0;
    public IEnumerable Items => _items;
}
```

### Step 4: Create the root node

The root node appears as a top-level item under the solution. It implements `IAttachedCollectionSource` so it can provide children, and display interfaces so Solution Explorer can render it.

```csharp
using System.Collections;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Imaging;
using Microsoft.VisualStudio.Imaging.Interop;

internal class MyRootNode :
    IAttachedCollectionSource,
    ITreeDisplayItem,
    ITreeDisplayItemWithImages,
    IInteractionPatternProvider,
    IPrioritizedComparable,
    IBrowsablePattern,
    INotifyPropertyChanged
{
    private readonly ObservableCollection<MyItemNode> _children = [];
    private readonly IVsHierarchyItem _solutionHierarchyItem;

    public MyRootNode(IVsHierarchyItem solutionHierarchyItem)
    {
        _solutionHierarchyItem = solutionHierarchyItem;
        LoadChildren();
    }

    // ITreeDisplayItem
    public string Text => "My Custom Items";
    public string ToolTipText => "Custom items added by my extension";
    public object ToolTipContent => null;
    public FontWeight FontWeight => FontWeights.Normal;
    public FontStyle FontStyle => FontStyles.Normal;
    public bool IsCut => false;

    // ITreeDisplayItemWithImages — use KnownMonikers for standard icons
    public ImageMoniker IconMoniker => KnownMonikers.LinkedFolderOpened;
    public ImageMoniker ExpandedIconMoniker => KnownMonikers.LinkedFolderOpened;
    public ImageMoniker OverlayIconMoniker => default;
    public ImageMoniker StateIconMoniker => default;
    public string StateToolTipText => string.Empty;

    // IAttachedCollectionSource
    public object SourceItem => this;
    public bool HasItems => _children.Count > 0;
    public IEnumerable Items => _children;

    // Parent for ContainedBy relationship (points to solution node)
    public object ParentItem => _solutionHierarchyItem;

    // IInteractionPatternProvider — declare which patterns this node supports
    private static readonly HashSet<Type> _supportedPatterns =
    [
        typeof(ITreeDisplayItem),
        typeof(ITreeDisplayItemWithImages),
        typeof(IBrowsablePattern),
    ];

    public TPattern GetPattern<TPattern>() where TPattern : class
    {
        return _supportedPatterns.Contains(typeof(TPattern)) ? this as TPattern : null;
    }

    // IPrioritizedComparable — controls sort order among sibling nodes
    public int Priority => 0;
    public int CompareTo(object obj) => 1; // Appear at end

    // IBrowsablePattern
    public object GetBrowseObject() => null;

    // INotifyPropertyChanged
    public event PropertyChangedEventHandler PropertyChanged;

    protected void RaisePropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private void LoadChildren()
    {
        // Populate _children with your custom items
        _children.Add(new MyItemNode(this, "Item 1"));
        _children.Add(new MyItemNode(this, "Item 2"));
        RaisePropertyChanged(nameof(HasItems));
    }
}
```

### Step 5: Create the child node

Each child node also implements `IAttachedCollectionSource` (if it can have children) plus the display and interaction interfaces.

```csharp
using System.Collections;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Imaging;
using Microsoft.VisualStudio.Imaging.Interop;

internal class MyItemNode :
    IAttachedCollectionSource,
    ITreeDisplayItem,
    ITreeDisplayItemWithImages,
    IPrioritizedComparable,
    IBrowsablePattern,
    IInteractionPatternProvider,
    IContextMenuPattern,
    IInvocationPattern,
    INotifyPropertyChanged
{
    private ObservableCollection<MyItemNode> _children;

    public MyItemNode(object parent, string displayText)
    {
        ParentItem = parent;
        Text = displayText;
    }

    // ITreeDisplayItem
    public string Text { get; }
    public string ToolTipText => Text;
    public object ToolTipContent => null;
    public FontWeight FontWeight => FontWeights.Normal;
    public FontStyle FontStyle => FontStyles.Normal;
    public bool IsCut => false;

    // ITreeDisplayItemWithImages
    public ImageMoniker IconMoniker => KnownMonikers.StatusInformation;
    public ImageMoniker ExpandedIconMoniker => KnownMonikers.StatusInformation;
    public ImageMoniker OverlayIconMoniker => default;
    public ImageMoniker StateIconMoniker => default;
    public string StateToolTipText => string.Empty;

    // IAttachedCollectionSource — node can have children
    public object SourceItem => this;
    public bool HasItems => _children?.Count > 0;
    public IEnumerable Items => _children ??= [];

    // Parent for ContainedBy support
    public object ParentItem { get; }

    // IContextMenuPattern — show context menu on right-click
    public IContextMenuController ContextMenuController { get; } = new MyContextMenuController();

    // IInvocationPattern — handle double-click / Enter
    public IInvocationController InvocationController { get; } = new MyInvocationController();

    // IInteractionPatternProvider
    private static readonly HashSet<Type> _supportedPatterns =
    [
        typeof(ITreeDisplayItem),
        typeof(ITreeDisplayItemWithImages),
        typeof(IBrowsablePattern),
        typeof(IContextMenuPattern),
        typeof(IInvocationPattern),
    ];

    public TPattern GetPattern<TPattern>() where TPattern : class
    {
        return _supportedPatterns.Contains(typeof(TPattern)) ? this as TPattern : null;
    }

    // IPrioritizedComparable
    public int Priority => 0;
    public int CompareTo(object obj) => 0;

    // IBrowsablePattern
    public object GetBrowseObject() => null;

    // INotifyPropertyChanged
    public event PropertyChangedEventHandler PropertyChanged;

    protected void RaisePropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
```

### Step 6: Implement interaction controllers (optional)

**Context menu controller** — shows a VS context menu when the user right-clicks the node:

```csharp
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using Microsoft.Internal.VisualStudio.PlatformUI;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell.Interop;

internal class MyContextMenuController : IContextMenuController
{
    public bool ShowContextMenu(IEnumerable<object> items, Point location)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        var nodes = items.OfType<MyItemNode>().ToList();
        if (nodes.Count == 0) return false;

        IVsUIShell shell = VS.GetRequiredService<SVsUIShell, IVsUIShell>();
        Guid menuGroup = /* your package command group GUID */;

        shell.ShowContextMenu(
            0,
            ref menuGroup,
            /* your menu ID */,
            new POINTS[] { new() { x = (short)location.X, y = (short)location.Y } },
            pCmdTrgtActive: null);

        return true;
    }
}
```

**Invocation controller** — handles double-click or Enter on a node:

```csharp
using System.Collections.Generic;
using System.Linq;
using Microsoft.Internal.VisualStudio.PlatformUI;

internal class MyInvocationController : IInvocationController
{
    public bool Invoke(IEnumerable<object> items, InputSource inputSource, bool preview)
    {
        foreach (MyItemNode item in items.OfType<MyItemNode>())
        {
            // Handle activation — open a document, show a tool window, etc.
        }
        return true;
    }
}
```

**Drag-and-drop source controller** — enables dragging nodes out of the tree:

```csharp
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Linq;
using System.Windows;
using Microsoft.Internal.VisualStudio.PlatformUI;

internal class MyDragDropSourceController : IDragDropSourceController
{
    public bool DoDragDrop(IEnumerable<object> items)
    {
        var nodes = items.OfType<MyItemNode>().ToArray();
        if (!nodes.Any()) return false;

        var dataObj = new DataObject();
        var paths = new StringCollection();
        // Add data to the DataObject based on your node type
        // paths.AddRange(nodes.Select(n => n.FilePath).ToArray());
        // dataObj.SetFileDropList(paths);

        DependencyObject source = Application.Current.MainWindow;
        DragDrop.DoDragDrop(source, dataObj, DragDropEffects.Copy | DragDropEffects.Move);
        return true;
    }
}
```

To enable drag-drop, add `IDragDropSourcePattern` to your node's interface list and `_supportedPatterns`, then expose the controller:

```csharp
public IDragDropSourceController DragDropSourceController { get; } = new MyDragDropSourceController();
```

### Key interfaces reference

| Interface | Purpose |
|---|---|
| `IAttachedCollectionSourceProvider` | MEF entry point — maps items to relationships and creates collection sources |
| `IAttachedCollectionSource` | Provides `Items` and `HasItems` for a node in the tree |
| `ITreeDisplayItem` | Display text, tooltip, font weight/style, cut state |
| `ITreeDisplayItemWithImages` | Icons (collapsed, expanded, overlay, state) via `ImageMoniker` |
| `IInteractionPatternProvider` | Declares which interaction patterns the node supports |
| `IPrioritizedComparable` | Sort order among sibling nodes |
| `IBrowsablePattern` | Properties window integration |
| `IContextMenuPattern` | Right-click context menu |
| `IInvocationPattern` | Double-click / Enter activation |
| `IDragDropSourcePattern` | Drag items out of the tree |
| `IDragDropTargetPattern` | Drop items onto the node |
| `IRefreshPattern` | Enables the node to be refreshed |
| `ISupportDisposalNotification` | Notification when node is disposed |
| `INotifyPropertyChanged` | Standard WPF change notification for UI updates |

### Important notes

- The `[Order(Before = HierarchyItemsProviderNames.Contains)]` attribute on the source provider ensures your nodes are processed before the default hierarchy provider.
- Use `ObservableCollection<T>` (or `BulkObservableCollection<T>` for batch updates) for children so the tree updates automatically.
- Implement `INotifyPropertyChanged` and raise `PropertyChanged` for `HasItems` and `Items` when the children collection changes.
- Use `KnownMonikers` from `Microsoft.VisualStudio.Imaging` for standard icons, or register custom image monikers.
- All UI-thread access must go through `ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync()` or `ThreadHelper.ThrowIfNotOnUIThread()`.

---

## Additional resources

- [IAttachedCollectionSourceProvider API](https://learn.microsoft.com/dotnet/api/microsoft.internal.visualstudio.platformui.iattachedcollectionsourceprovider)
- [WorkspaceFiles extension (reference implementation)](https://github.com/madskristensen/WorkspaceFiles)
- [VSIX Cookbook — Solution Explorer](https://www.vsixcookbook.com/recipes/solution-explorer.html)
