---
name: managing-files-documents
description: Work with files and documents programmatically in Visual Studio extensions. Use when the user asks how to open files, read or modify document text, listen for document events, get the active document, use ITextDocument, DocumentsExtensibility, VS.Documents, IVsInvisibleEditorManager, or manipulate file contents in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Working with Files and Documents in Visual Studio Extensions

A *document* is the in-memory representation of a file opened in Visual Studio. Extensions commonly need to open files, read or edit text, and react to document lifecycle events (open, save, close).

Document operations are fundamental to nearly every extension — whether you're formatting on save, analyzing text changes, or opening files programmatically. The key abstraction is the Running Document Table (RDT), which tracks all open documents in VS. The VisualStudio.Extensibility model simplifies this with `IDocumentEventsListener` and `EditorExtensibility`, while the VSSDK/Toolkit approaches give direct access to `ITextBuffer` and the RDT.

**When to use this vs. alternatives:**
- Open, read, edit, or save files programmatically → **this skill**
- React to document open/save/close events → **this skill**
- React to text content changes in the editor → combine with [vs-editor-text-view-listener](../listening-text-view-events/SKILL.md)
- Intercept the Save command before it runs → [vs-command-intercept](../intercepting-commands/SKILL.md)
- Surface errors from file analysis → [vs-error-list](../integrating-error-list/SKILL.md)

## Decision guide

| Task | VisualStudio.Extensibility | Community Toolkit | VSSDK |
|------|---------------------------|-------------------|-------|
| Open a file | `DocumentsExtensibility.OpenDocumentAsync` | `VS.Documents.OpenAsync` | `VsShellUtilities.OpenDocument` |
| Get active document text | `context.GetActiveTextViewAsync` | `VS.Documents.GetActiveDocumentViewAsync` | `IVsTextManager.GetActiveView` |
| Edit text | `EditorExtensibility.EditAsync` | `DocumentView.TextBuffer.Insert/Replace/Delete` | `ITextBuffer.Insert/Replace/Delete` |
| Listen for events | `IDocumentEventsListener` | `VS.Events.DocumentEvents` | `IVsRunningDocTableEvents` |

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

Documents are accessed via `DocumentsExtensibility` and text editing via `EditorExtensibility`. The extension runs out-of-process, so document access is through snapshots.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility`, `Microsoft.VisualStudio.Extensibility.Editor`

### Open a document

```csharp
DocumentsExtensibility documents = this.Extensibility.Documents();

Uri uri = new Uri(@"C:/path/to/File.cs", UriKind.Absolute);
DocumentSnapshot document = await documents.OpenDocumentAsync(uri, cancellationToken);
```

### Get and read the active document

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
{
    using ITextViewSnapshot textView = await context.GetActiveTextViewAsync(ct);
    if (textView is null) return;

    // Read the full document text
    ITextDocumentSnapshot document = textView.Document;
    string fullText = document.Text;

    // Read line by line
    foreach (ITextLineSnapshot line in document)
    {
        string lineText = line.Text;
    }
}
```

### Edit document text

```csharp
public override async Task ExecuteCommandAsync(IClientContext context, CancellationToken ct)
{
    using ITextViewSnapshot textView = await context.GetActiveTextViewAsync(ct);
    EditorExtensibility editor = this.Extensibility.Editor();

    await editor.EditAsync(
        batch =>
        {
            ITextDocumentSnapshot doc = textView.Document;

            // Insert text at a position
            doc.AsEditable(batch).Insert(0, "// Auto-generated header\n");

            // Replace selected text
            doc.AsEditable(batch).Replace(textView.Selection.Extent, "replaced text");

            // Delete a range
            doc.AsEditable(batch).Delete(new Span(0, 10));
        },
        ct);
}
```

### Get a document by URI (without opening it in the editor)

```csharp
DocumentsExtensibility documents = this.Extensibility.Documents();

Uri moniker = await context.GetSelectedPathAsync(cancellationToken);
DocumentSnapshot document = await documents.GetDocumentAsync(moniker, cancellationToken);
ITextDocumentSnapshot snapshot = await document.AsTextDocumentAsync(this.Extensibility, cancellationToken);

string text = snapshot.Text;
bool isDirty = document.IsDirty;
```

### Listen for document events

Implement `IDocumentEventsListener` and subscribe via `DocumentsExtensibility.SubscribeAsync`:

```csharp
internal class DocumentEventSubscription : IDisposable, IDocumentEventsListener
{
    private IDisposable? _subscription;

    public static async Task<DocumentEventSubscription> CreateAsync(
        VisualStudioExtensibility extensibility, CancellationToken ct)
    {
        var instance = new DocumentEventSubscription();
        DocumentsExtensibility documents = extensibility.Documents();
        instance._subscription = await documents.SubscribeAsync(
            instance,
            filterRegex: null,  // null = all documents; use regex to filter by URI pattern
            ct);
        return instance;
    }

    public void Dispose() => _subscription?.Dispose();

    Task IDocumentEventsListener.OpenedAsync(DocumentEventArgs e, CancellationToken ct)
    {
        // A document was opened
        Uri moniker = e.Moniker;
        return Task.CompletedTask;
    }

    Task IDocumentEventsListener.ClosedAsync(DocumentEventArgs e, CancellationToken ct)
        => Task.CompletedTask;

    Task IDocumentEventsListener.SavingAsync(DocumentEventArgs e, CancellationToken ct)
        => Task.CompletedTask;  // Before save — can inspect but not cancel

    Task IDocumentEventsListener.SavedAsync(DocumentEventArgs e, CancellationToken ct)
        => Task.CompletedTask;  // After save completed

    Task IDocumentEventsListener.RenamedAsync(RenamedDocumentEventArgs e, CancellationToken ct)
    {
        Uri oldUri = e.OldMoniker;
        Uri newUri = e.Moniker;
        return Task.CompletedTask;
    }

    Task IDocumentEventsListener.ShownAsync(DocumentEventArgs e, CancellationToken ct)
        => Task.CompletedTask;

    Task IDocumentEventsListener.HiddenAsync(DocumentEventArgs e, CancellationToken ct)
        => Task.CompletedTask;
}
```

---

## 2. VSIX Community Toolkit (in-process)

The Toolkit wraps VSSDK document APIs with friendly helpers on the `VS.Documents` static class. Documents are represented by `DocumentView`, which combines the `IWpfTextView` and `ITextBuffer`.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Open a file

```csharp
// Open in the main document well
await VS.Documents.OpenAsync(@"C:/path/to/File.cs");

// Open in the Preview (provisional) tab
await VS.Documents.OpenInPreviewTabAsync(@"C:/path/to/File.cs");

// Open via the project system (respects custom editors)
await VS.Documents.OpenViaProjectAsync(@"C:/path/to/File.cs");
```

### Get the active document and its text

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    DocumentView docView = await VS.Documents.GetActiveDocumentViewAsync();
    if (docView?.TextView == null) return;  // Not a text window

    // Full document text
    string fullText = docView.TextBuffer?.CurrentSnapshot.GetText();

    // File path
    string filePath = docView.FilePath;

    // Caret position
    SnapshotPoint caretPos = docView.TextView.Caret.Position.BufferPosition;
    int line = caretPos.GetContainingLine().LineNumber;
    int column = caretPos.Position - caretPos.GetContainingLine().Start.Position;
}
```

### Insert text at the caret

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    DocumentView docView = await VS.Documents.GetActiveDocumentViewAsync();
    if (docView?.TextView == null) return;

    SnapshotPoint position = docView.TextView.Caret.Position.BufferPosition;
    docView.TextBuffer?.Insert(position, DateTime.Now.ToString("yyyy-MM-dd"));
}
```

### Replace selected text

```csharp
protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
{
    DocumentView docView = await VS.Documents.GetActiveDocumentViewAsync();
    if (docView?.TextView == null) return;

    var selection = docView.TextView.Selection;
    if (selection.IsEmpty) return;

    var span = selection.SelectedSpans[0];
    string selectedText = span.GetText();

    docView.TextBuffer?.Replace(span, selectedText.ToUpperInvariant());
}
```

### Read text from a specific file (without opening it visibly)

```csharp
// Get a file's content as a SolutionItem
PhysicalFile file = await PhysicalFile.FromFileAsync(@"C:/path/to/File.cs");
```

### Get the ITextDocument from a buffer

```csharp
DocumentView docView = await VS.Documents.GetActiveDocumentViewAsync();
string filePath = docView.TextBuffer?.GetFileName();
```

### Listen for document events

```csharp
protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
{
    await this.RegisterCommandsAsync();

    VS.Events.DocumentEvents.Opened += OnDocumentOpened;
    VS.Events.DocumentEvents.Closed += OnDocumentClosed;
    VS.Events.DocumentEvents.Saved += OnDocumentSaved;
    VS.Events.DocumentEvents.BeforeDocumentWindowShow += OnBeforeShow;
    VS.Events.DocumentEvents.AfterDocumentWindowHide += OnAfterHide;
}

private void OnDocumentOpened(string filePath) { /* Document was opened */ }
private void OnDocumentClosed(string filePath) { /* Document was closed */ }
private void OnDocumentSaved(string filePath) { /* Document was saved */ }
private void OnBeforeShow(DocumentView docView) { /* About to become visible */ }
private void OnAfterHide(DocumentView docView) { /* Just became hidden */ }
```

---

## 3. VSSDK (in-process, legacy)

The low-level VSSDK provides full control via `IVsTextManager`, `IVsInvisibleEditorManager`, `ITextBuffer`, and `IVsRunningDocTableEvents`.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`, `Microsoft.VisualStudio.Text`, `Microsoft.VisualStudio.TextManager.Interop`

### Open a document

```csharp
// Simple approach using VsShellUtilities
VsShellUtilities.OpenDocument(ServiceProvider.GlobalProvider, @"C:/path/to/File.cs");
```

With full control (get the view and buffer):

```csharp
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

VsShellUtilities.OpenDocument(
    ServiceProvider.GlobalProvider,
    @"C:/path/to/File.cs",
    Guid.Empty,           // logical view GUID (Empty = default)
    out IVsUIHierarchy hierarchy,
    out uint itemId,
    out IVsWindowFrame windowFrame,
    out IVsTextView textView);

windowFrame.Show();
```

### Get the active text view and buffer

```csharp
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

var textManager = (IVsTextManager)await package.GetServiceAsync(typeof(SVsTextManager));
textManager.GetActiveView(1, null, out IVsTextView activeView);

// Get the ITextBuffer via the adapter service
var adapterService = package.GetService<SVsEditorAdaptersFactoryService, IVsEditorAdaptersFactoryService>();
ITextBuffer buffer = adapterService.GetDataBuffer((IVsTextBuffer)activeView.GetBuffer(out var vsBuffer));
```

### Edit text via ITextBuffer

```csharp
// Must be on the UI thread for ITextBuffer edits
ITextBuffer buffer = /* obtained from adapter or MEF */;

// Use an edit session for multiple edits as a single undo unit
using (ITextEdit edit = buffer.CreateEdit())
{
    edit.Insert(0, "// Auto-generated header\n");
    edit.Replace(new Span(10, 5), "replaced");
    edit.Delete(new Span(100, 20));
    edit.Apply();  // Commits all changes as one undo step
}
```

### Read a file's text without opening it in the editor

Use `IVsInvisibleEditorManager` to get an `ITextBuffer` without showing a tab:

```csharp
await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

var invisibleEditorManager = (IVsInvisibleEditorManager)
    await package.GetServiceAsync(typeof(SVsInvisibleEditorManager));

invisibleEditorManager.RegisterInvisibleEditor(
    @"C:/path/to/File.cs",
    pProject: null,
    dwFlags: 0,
    pFactory: null,
    out IVsInvisibleEditor invisibleEditor);

// Get the text buffer from the invisible editor
var docDataGuid = typeof(IVsTextLines).GUID;
invisibleEditor.GetDocData(fEnsureWritable: 0, ref docDataGuid, out IntPtr docDataPtr);
var vsTextLines = (IVsTextLines)Marshal.GetObjectForIUnknown(docDataPtr);
Marshal.Release(docDataPtr);

var adapterService = package.GetService<SVsEditorAdaptersFactoryService, IVsEditorAdaptersFactoryService>();
ITextBuffer buffer = adapterService.GetDocumentBuffer(vsTextLines);

string text = buffer.CurrentSnapshot.GetText();
```

### Listen for document events via the Running Document Table

```csharp
public class MyRunningDocTableEvents : IVsRunningDocTableEvents3
{
    private readonly RunningDocumentTable _rdt;
    private readonly uint _cookie;

    public MyRunningDocTableEvents(IServiceProvider serviceProvider)
    {
        _rdt = new RunningDocumentTable(serviceProvider);
        _cookie = _rdt.Advise(this);
    }

    public int OnAfterSave(uint docCookie)
    {
        RunningDocumentInfo info = _rdt.GetDocumentInfo(docCookie);
        string filePath = info.Moniker;
        // React to save
        return VSConstants.S_OK;
    }

    public int OnBeforeSave(uint docCookie) => VSConstants.S_OK;
    public int OnAfterFirstDocumentLock(uint docCookie, uint dwRDTLockType, uint dwReadLocksRemaining, uint dwEditLocksRemaining) => VSConstants.S_OK;
    public int OnBeforeLastDocumentUnlock(uint docCookie, uint dwRDTLockType, uint dwReadLocksRemaining, uint dwEditLocksRemaining) => VSConstants.S_OK;
    public int OnAfterAttributeChange(uint docCookie, uint grfAttribs) => VSConstants.S_OK;
    public int OnAfterAttributeChangeEx(uint docCookie, uint grfAttribs, IVsHierarchy pHierOld, uint itemidOld, string pszMkDocumentOld, IVsHierarchy pHierNew, uint itemidNew, string pszMkDocumentNew) => VSConstants.S_OK;
    public int OnBeforeDocumentWindowShow(uint docCookie, int fFirstShow, IVsWindowFrame pFrame) => VSConstants.S_OK;
    public int OnAfterDocumentWindowHide(uint docCookie, IVsWindowFrame pFrame) => VSConstants.S_OK;

    public void Dispose()
    {
        _rdt.Unadvise(_cookie);
    }
}
```

---

## Key guidance

- **New extensions** → use `DocumentsExtensibility` + `EditorExtensibility.EditAsync()` for safe, out-of-process document manipulation.
- **Existing Toolkit extensions** → use `VS.Documents.GetActiveDocumentViewAsync()` and `VS.Documents.OpenAsync()` for the simplest API surface.
- **Legacy VSSDK** → use `ITextBuffer.CreateEdit()` for batched edits and `IVsInvisibleEditorManager` for reading files without opening a visible tab.
- Always check for `null` when getting the active document — the user may not have a text file open.
- When editing text, group multiple changes into a single edit session (`ITextEdit` in VSSDK/Toolkit, `EditAsync` batch in Extensibility) so they form one undo unit.
- Use document events rather than polling to react to save/open/close.
- Never assume the active document is a text document — it could be a designer, image, or binary file.

## Troubleshooting

- **Document events don't fire:** For Toolkit, verify `VS.Events.DocumentEvents` is being subscribed to in `InitializeAsync`. For VSSDK, ensure you're advising on `IVsRunningDocTableEvents` via `IVsRunningDocumentTable.AdviseRunningDocTableEvents`.
- **Text edits are lost / don't persist:** You're editing a snapshot rather than the live buffer. Use `ITextBuffer.Replace()` (VSSDK/Toolkit) or `EditorExtensibility.EditAsync` (Extensibility) to apply changes to the live document.
- **Multiple edits create multiple undo entries:** Group related edits in a single `ITextEdit` session (`ITextBuffer.CreateEdit()` → apply changes → `edit.Apply()`) so they're treated as one undo unit.
- **File path is null or wrong:** Not all documents have file paths (e.g., unsaved "Untitled" files). Always check for null. Use `ITextDocument.FilePath` or the RDT's moniker.
- **Document opened but not visible:** `OpenDocumentAsync` / `VS.Documents.OpenAsync` opens the document but may not bring the window to the foreground. Call `IVsWindowFrame.Show()` or activate the document view.

## What NOT to do

> **Do NOT** use `System.IO.File.ReadAllText` for files open in VS — the in-memory buffer may have unsaved changes. Use VS document/text buffer APIs.

> **Do NOT** modify files on disk while open in VS without going through document APIs — causes out-of-sync warnings and corrupts undo history.

> **Do NOT** forget to dispose `ITextEdit` objects — always use `using` blocks for text edit sessions.

> **Do NOT** assume the active document is a text document — it could be a designer, binary, or image file.

## See also

- [vs-editor-text-view-listener](../listening-text-view-events/SKILL.md)
- [vs-command-intercept](../intercepting-commands/SKILL.md)
- [vs-solution-events](../handling-solution-events/SKILL.md)
- [vs-error-list](../integrating-error-list/SKILL.md)
- [vs-async-threading](../handling-async-threading/SKILL.md)

## References

- [Extend Visual Studio documents (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/document/documents)
- [Working with files and documents (Community Toolkit)](https://learn.microsoft.com/visualstudio/extensibility/vsix/tips/files)
- [Editor API overview](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/editor/editor)
- [Running Document Table](https://learn.microsoft.com/visualstudio/extensibility/internals/running-document-table)
