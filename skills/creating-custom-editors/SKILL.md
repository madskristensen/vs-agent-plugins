---
name: creating-custom-editors
description: Create custom document editors for domain-specific file types in Visual Studio extensions. Use when the user asks how to create a custom editor, editor factory, document editor pane, open files with a custom UI, implement IVsEditorFactory, use LanguageBase to register a language with an editor, create an EditorPane with IVsPersistDocData, register an editor for a file extension with ProvideEditorFactory, handle document persistence and dirty state, or build a visual designer for a custom file format. Covers VSIX Community Toolkit (LanguageBase), VSSDK (IVsEditorFactory + WindowPane), and VisualStudio.Extensibility (no custom editor API yet).
---

# Creating Custom Document Editors in Visual Studio Extensions

A **custom editor** registers an **editor factory** so Visual Studio opens files of a given extension with your editor instead of the default text editor. There are two distinct scenarios:

1. **Text-based code editor for a custom language** — the Community Toolkit's `LanguageBase` handles the editor factory internally. You subclass `LanguageBase`, set file extensions, and configure language preferences. VS opens the file in a full code window with syntax highlighting, brace matching, and standard editor keybindings — no manual `IVsEditorFactory` implementation required.
2. **Custom designer / visual editor** — for entirely custom WPF or WinForms UI (designers, hex viewers, form builders), you implement `IVsEditorFactory` + `WindowPane` + `IVsPersistDocData` yourself using the VSSDK.

**When to use this vs. alternatives:**
- Text-based editor for a custom file type (`.pkgdef`, `.mylang`, etc.) with full code window support → **LanguageBase** (section 2)
- Fully custom WPF/WinForms designer UI for a domain-specific file → **VSSDK IVsEditorFactory + WindowPane** (section 3)
- Adding visual elements on top of the standard text editor (highlights, icons, overlays) → [adding-editor-adornments](../adding-editor-adornments/SKILL.md)
- Adding a gutter, side panel, or bottom bar to the text editor → [adding-editor-margins](../adding-editor-margins/SKILL.md)
- Persistent dockable panel that is not tied to a file → [adding-tool-windows](../adding-tool-windows/SKILL.md)
- Syntax highlighting for a custom language in the standard text editor → [adding-textmate-grammars](../adding-textmate-grammars/SKILL.md) or [adding-editor-classifiers](../adding-editor-classifiers/SKILL.md)
- Language features (IntelliSense, diagnostics) via Language Server Protocol → [integrating-language-servers](../integrating-language-servers/SKILL.md)

---

## 1. VisualStudio.Extensibility (out-of-process)

**VisualStudio.Extensibility does not currently support creating custom document editors.** The out-of-process SDK focuses on extending the existing text editor (margins, taggers, CodeLens, text manipulation) but does not provide an API for registering a new editor factory or creating a custom document pane.

If you need a custom editor, use the VSIX Community Toolkit (section 2) or VSSDK (section 3). For in-process VisualStudio.Extensibility extensions, you can access VSSDK services via `AsyncServiceProviderInjection` to bridge the gap, but the editor factory itself must be registered through VSSDK attributes.

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit provides `LanguageBase` — an abstract base class that **combines `LanguageService` and `IVsEditorFactory` into one class**. When you subclass `LanguageBase`, the editor factory is handled for you automatically — VS opens your file type in a full code window with syntax highlighting, brace matching, IntelliSense hooks, and standard editor keybindings. You don't implement `IVsEditorFactory` yourself.

For editors that need a completely custom WPF UI (a visual designer, not a code window), see section 3.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Using LanguageBase for text-based editors

`LanguageBase` implements `IVsEditorFactory` internally — it creates the text buffer, code window, and editor instance. You only need to provide the language name, file extensions, and editor preferences.

#### Step 1: Create your language class

```csharp
using System.Runtime.InteropServices;
using Microsoft.VisualStudio.Package;

[ComVisible(true)]
[Guid(PackageGuids.EditorFactoryString)] // unique GUID for your language
internal sealed class MyLanguage : LanguageBase
{
    public MyLanguage(object site) : base(site)
    { }

    public override string Name => Constants.LanguageName;

    public override string[] FileExtensions { get; } =
        new[] { Constants.FileExtension };

    public override void SetDefaultPreferences(LanguagePreferences preferences)
    {
        preferences.EnableCodeSense = true;
        preferences.EnableMatchBraces = true;
        preferences.EnableMatchBracesAtCaret = true;
        preferences.EnableShowMatchingBrace = true;
        preferences.EnableCommenting = true;
        preferences.EnableFormatSelection = true;
        preferences.LineNumbers = true;
        preferences.MaxErrorMessages = 100;
        preferences.MaxRegionTime = 2000;
        preferences.InsertTabs = false;
        preferences.IndentSize = 4;
        preferences.IndentStyle = IndentingStyle.Smart;
        preferences.ShowNavigationBar = true;
    }
}
```

#### Step 2: Register in your package

The `LanguageBase` subclass is both an editor factory and a language service. Register it as both:

```csharp
[ProvideLanguageService(typeof(MyLanguage), Constants.LanguageName, 0,
    EnableLineNumbers = true,
    EnableAsyncCompletion = true,
    ShowCompletion = true,
    ShowDropDownOptions = true)]
[ProvideLanguageExtension(typeof(MyLanguage), Constants.FileExtension)]

[ProvideEditorFactory(typeof(MyLanguage), 738,
    CommonPhysicalViewAttributes = (int)__VSPHYSICALVIEWATTRIBUTES.PVA_SupportsPreview,
    TrustLevel = __VSEDITORTRUSTLEVEL.ETL_AlwaysTrusted)]
[ProvideEditorExtension(typeof(MyLanguage), Constants.FileExtension, 65535,
    NameResourceID = 738)]
[ProvideEditorLogicalView(typeof(MyLanguage), VSConstants.LOGVIEWID.TextView_string,
    IsTrusted = true)]

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid(PackageGuids.PackageString)]
public sealed class MyPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync();

        // Create and register as both editor factory and language service
        var language = new MyLanguage(this);
        RegisterEditorFactory(language);
        ((IServiceContainer)this).AddService(
            typeof(MyLanguage), language, true);
    }
}
```

### Key points about LanguageBase

- **Implements `IVsEditorFactory` for you**: You never write `CreateEditorInstance`, `MapLogicalView`, or `SetSite` — `LanguageBase` handles all of that internally.
- **Combines two roles**: `LanguageService` (syntax, preferences) + `IVsEditorFactory` (creating the editor window) in a single class.
- **Handles text buffer creation**: The `GetTextBuffer` method creates `IVsTextLines` when opening a new file, or reuses an existing buffer.
- **Creates a VS code window**: The `CreateCodeView` method creates an `IVsCodeWindow` using `IVsEditorAdaptersFactoryService` — you get the full VS editor experience.
- **Override `CreateCodeWindowManager`** to provide a custom `CodeWindowManager` (e.g., to add document outline support via `IVsDocOutlineProvider`).
- **Override `CreateDropDownHelper`** to provide navigation bar dropdowns (`TypeAndMemberDropdownBars`) for symbol navigation.
- **Override `PromptEncodingOnLoad`** to `true` if you want VS to prompt the user for file encoding when opening files.

---

## 3. VSSDK — Custom Designer / Visual Editor (in-process)

Use this approach **only** when you need a fully custom WPF or WinForms UI — a visual designer, hex viewer, form builder, or other non-text editor. For text-based code editors, use `LanguageBase` (section 2) instead.

The VSSDK `IVsEditorFactory` + `WindowPane` pattern gives you full control over the editor pane UI and document persistence.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell`, `Microsoft.VisualStudio.Shell.Interop`, `Microsoft.VisualStudio.OLE.Interop`

### Step 1: Create the editor factory

The editor factory creates your editor pane when VS opens a file of the registered type:

```csharp
using System;
using System.Runtime.InteropServices;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using IOleServiceProvider = Microsoft.VisualStudio.OLE.Interop.IServiceProvider;

[Guid("your-editor-factory-guid-here")]
public sealed class MyEditorFactory : IVsEditorFactory, IDisposable
{
    private ServiceProvider _serviceProvider;

    public int SetSite(IOleServiceProvider psp)
    {
        _serviceProvider = new ServiceProvider(psp);
        return VSConstants.S_OK;
    }

    public int MapLogicalView(ref Guid logicalView, out string physicalView)
    {
        physicalView = null;

        // Support the primary view only
        if (logicalView == VSConstants.LOGVIEWID_Primary ||
            logicalView == VSConstants.LOGVIEWID_TextView)
        {
            return VSConstants.S_OK;
        }

        return VSConstants.E_NOTIMPL;
    }

    public int CreateEditorInstance(
        uint grfCreateDoc,
        string pszMkDocument,
        string pszPhysicalView,
        IVsHierarchy pvHier,
        uint itemid,
        IntPtr punkDocDataExisting,
        out IntPtr ppunkDocView,
        out IntPtr ppunkDocData,
        out string pbstrEditorCaption,
        out Guid pguidCmdUI,
        out int pgrfCDW)
    {
        ppunkDocView = IntPtr.Zero;
        ppunkDocData = IntPtr.Zero;
        pbstrEditorCaption = string.Empty;
        pguidCmdUI = Guid.Empty;
        pgrfCDW = 0;

        // Validate inputs
        if ((grfCreateDoc & (VSConstants.CEF_OPENFILE | VSConstants.CEF_SILENT)) == 0)
            return VSConstants.E_INVALIDARG;

        // If doc data already exists and is incompatible, reject
        if (punkDocDataExisting != IntPtr.Zero)
            return VSConstants.VS_E_INCOMPATIBLEDOCDATA;

        // Create the editor pane (serves as both doc view and doc data)
        var editorPane = new MyEditorPane();
        ppunkDocView = Marshal.GetIUnknownForObject(editorPane);
        ppunkDocData = Marshal.GetIUnknownForObject(editorPane);
        pbstrEditorCaption = "";

        return VSConstants.S_OK;
    }

    public int Close() => VSConstants.S_OK;

    public void Dispose()
    {
        _serviceProvider?.Dispose();
        _serviceProvider = null;
    }
}
```

### Step 2: Create the editor pane

The editor pane inherits from `WindowPane` and implements `IVsPersistDocData` (for RDT integration) and `IPersistFileFormat` (for load/save):

```csharp
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Controls;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

public sealed class MyEditorPane : WindowPane,
    IVsPersistDocData,
    IPersistFileFormat
{
    private const uint MyFileFormat = 0;
    private const string MyFileExtension = ".myext";
    private string _fileName;
    private bool _isDirty;

    // Your custom WPF control
    private MyEditorControl _editorControl;

    public MyEditorPane() : base(null)
    {
        _editorControl = new MyEditorControl();
        _editorControl.ContentChanged += (s, e) =>
        {
            if (!_isDirty)
            {
                _isDirty = true;
            }
        };
    }

    // WindowPane: return your custom UI
    public override object Content
    {
        get => _editorControl;
        set => base.Content = value;
    }

    #region IVsPersistDocData

    int IVsPersistDocData.GetGuidEditorType(out Guid pClassID)
    {
        pClassID = typeof(MyEditorFactory).GUID;
        return VSConstants.S_OK;
    }

    int IVsPersistDocData.IsDocDataDirty(out int pfDirty)
    {
        pfDirty = _isDirty ? 1 : 0;
        return VSConstants.S_OK;
    }

    int IVsPersistDocData.IsDocDataReloadable(out int pfReloadable)
    {
        pfReloadable = 1;
        return VSConstants.S_OK;
    }

    int IVsPersistDocData.LoadDocData(string pszMkDocument)
    {
        return ((IPersistFileFormat)this).Load(pszMkDocument, 0, 0);
    }

    int IVsPersistDocData.SetUntitledDocPath(string pszDocDataPath)
    {
        return ((IPersistFileFormat)this).InitNew(MyFileFormat);
    }

    int IVsPersistDocData.SaveDocData(
        VSSAVEFLAGS dwSave,
        out string pbstrMkDocumentNew,
        out int pfSaveCanceled)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        pbstrMkDocumentNew = null;
        pfSaveCanceled = 0;

        switch (dwSave)
        {
            case VSSAVEFLAGS.VSSAVE_Save:
            case VSSAVEFLAGS.VSSAVE_SilentSave:
                // Query Edit/Query Save check
                var qeqs = (IVsQueryEditQuerySave2)GetService(typeof(SVsQueryEditQuerySave));
                uint result;
                int hr = qeqs.QuerySaveFile(_fileName, 0, null, out result);
                if (ErrorHandler.Failed(hr))
                    return hr;

                if ((tagVSQuerySaveResult)result == tagVSQuerySaveResult.QSR_NoSave_Cancel)
                {
                    pfSaveCanceled = 1;
                    return VSConstants.S_OK;
                }

                // Delegate to the shell for Save
                var uiShell = (IVsUIShell)GetService(typeof(SVsUIShell));
                return uiShell.SaveDocDataToFile(
                    dwSave, this, _fileName,
                    out pbstrMkDocumentNew, out pfSaveCanceled);

            case VSSAVEFLAGS.VSSAVE_SaveAs:
            case VSSAVEFLAGS.VSSAVE_SaveCopyAs:
                var uiShellSaveAs = (IVsUIShell)GetService(typeof(SVsUIShell));
                return uiShellSaveAs.SaveDocDataToFile(
                    dwSave, this, _fileName,
                    out pbstrMkDocumentNew, out pfSaveCanceled);

            default:
                return VSConstants.E_INVALIDARG;
        }
    }

    int IVsPersistDocData.Close() => VSConstants.S_OK;

    int IVsPersistDocData.OnRegisterDocData(
        uint docCookie, IVsHierarchy pHierNew, uint itemidNew)
        => VSConstants.S_OK;

    int IVsPersistDocData.RenameDocData(
        uint grfAttribs, IVsHierarchy pHierNew,
        uint itemidNew, string pszMkDocumentNew)
        => VSConstants.S_OK;

    int IVsPersistDocData.ReloadDocData(uint grfFlags)
    {
        return ((IPersistFileFormat)this).Load(null, grfFlags, 0);
    }

    #endregion

    #region IPersistFileFormat

    int IPersist.GetClassID(out Guid pClassID)
    {
        pClassID = typeof(MyEditorFactory).GUID;
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.GetClassID(out Guid pClassID)
    {
        return ((IPersist)this).GetClassID(out pClassID);
    }

    int IPersistFileFormat.GetCurFile(out string ppszFilename, out uint pnFormatIndex)
    {
        ppszFilename = _fileName;
        pnFormatIndex = MyFileFormat;
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.GetFormatList(out string ppszFormatList)
    {
        ppszFormatList = $"My File (*{MyFileExtension})\n*{MyFileExtension}\n\n";
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.InitNew(uint nFormatIndex)
    {
        _isDirty = false;
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.IsDirty(out int pfIsDirty)
    {
        pfIsDirty = _isDirty ? 1 : 0;
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.Load(string pszFilename, uint grfMode, int fReadOnly)
    {
        if (pszFilename != null)
            _fileName = pszFilename;

        // Load your file content into the editor control
        string content = File.ReadAllText(_fileName);
        _editorControl.LoadContent(content);

        _isDirty = false;
        return VSConstants.S_OK;
    }

    int IPersistFileFormat.Save(string pszFilename, int fRemember, uint nFormatIndex)
    {
        string targetFile = pszFilename ?? _fileName;

        // Save content from your editor control
        string content = _editorControl.GetContent();
        File.WriteAllText(targetFile, content);

        if (fRemember != 0 || pszFilename == null)
        {
            _fileName = targetFile;
            _isDirty = false;
        }

        return VSConstants.S_OK;
    }

    int IPersistFileFormat.SaveCompleted(string pszFilename) => VSConstants.S_OK;

    #endregion

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _editorControl = null;
        }
        base.Dispose(disposing);
    }
}
```

### Step 3: Register the editor factory in your package

```csharp
[ProvideEditorFactory(typeof(MyEditorFactory), 0,
    TrustLevel = __VSEDITORTRUSTLEVEL.ETL_AlwaysTrusted)]
[ProvideEditorExtension(typeof(MyEditorFactory), ".myext", 50)]
[ProvideEditorLogicalView(typeof(MyEditorFactory), VSConstants.LOGVIEWID.Primary_string)]
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid("your-package-guid-here")]
public sealed class MyPackage : AsyncPackage
{
    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await base.InitializeAsync(cancellationToken, progress);

        // Must switch to UI thread to register the editor factory
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);
        RegisterEditorFactory(new MyEditorFactory());
    }
}
```

### Registration attributes explained

| Attribute | Purpose |
|-----------|---------|
| `[ProvideEditorFactory]` | Registers the factory GUID so VS knows it exists |
| `[ProvideEditorExtension]` | Associates a file extension (e.g., `.myext`) with the factory; the priority number (50) determines precedence when multiple editors can open the same extension |
| `[ProvideEditorLogicalView]` | Declares which logical views the editor supports (Primary, Code, Designer, Debugging, etc.) |

### Document data vs. document view

In the VSSDK model, VS separates the concepts of:
- **Document data** (`ppunkDocData`) — the in-memory representation of the file content, registered in the Running Document Table (RDT)
- **Document view** (`ppunkDocView`) — the UI that displays and edits the data

For simple editors, one object serves as both (as shown above: both `ppunkDocView` and `ppunkDocData` point to the same `EditorPane`). For editors that support multiple views (e.g., a code view and a design view), you separate them into different objects.

---

## Key guidance

- **Use `LanguageBase`** (Community Toolkit) for text-based code editors — it implements the editor factory internally and gives you the full VS code window with syntax highlighting, brace matching, navigation bars, and standard editor keybindings out of the box. You never implement `IVsEditorFactory` yourself.
- **Use `WindowPane` + `IVsEditorFactory`** (VSSDK) only when you need a completely custom WPF/WinForms UI (visual designers, hex viewers, form builders) — not for text-based editors.
- **Always implement `IVsPersistDocData`** — VS uses this interface to integrate with the Running Document Table, track dirty state, and handle save operations.
- **Always implement `IPersistFileFormat`** — this provides the actual load/save logic.
- **Call `RegisterEditorFactory()`** in your package's `InitializeAsync` on the UI thread — without this runtime registration, the `[ProvideEditorFactory]` attribute alone is not enough.
- **Use `SVsQueryEditQuerySave`** before saving — this integrates with source control so VS can check out files before writing.
- **Set the priority number** in `[ProvideEditorExtension]` carefully: higher values take precedence over lower values. The standard text editor uses priority 50, so use a higher number to override it for your file type.

## Troubleshooting

- **Files open in the default text editor instead of your custom editor:** The editor factory isn't registered at runtime. Ensure you call `RegisterEditorFactory(new MyEditorFactory())` in `InitializeAsync` on the UI thread. The `[ProvideEditorFactory]` attribute alone only writes to the registry — you still need runtime registration.
- **Editor factory is registered but `CreateEditorInstance` is never called:** The file extension mapping is missing. Verify `[ProvideEditorExtension(typeof(MyEditorFactory), ".myext", 50)]` is on the package class and the extension string includes the leading dot.
- **"Incompatible document data" error when opening a file:** You are returning `VS_E_INCOMPATIBLEDOCDATA` when `punkDocDataExisting != IntPtr.Zero`. If you want to support reopening already-open documents, check whether the existing doc data is compatible with your editor instead of rejecting it outright.
- **Dirty indicator (dot on tab) doesn't appear after editing:** Your `IVsPersistDocData.IsDocDataDirty` or `IPersistFileFormat.IsDirty` isn't returning 1 when the document has unsaved changes. Ensure you set your dirty flag in response to content changes in your editor control.
- **Save doesn't work / file stays dirty after save:** You're not clearing the `isDirty` flag after a successful save in `IPersistFileFormat.Save`. Also verify you handle the `fRemember` parameter correctly — only update `_fileName` and clear dirty state when `fRemember != 0`.
- **Editor pane is blank / control doesn't show:** For WPF editors, override the `Content` property of `WindowPane` to return your WPF control. For WinForms editors, override the `Window` property to return your `IWin32Window` control. Don't implement both.

## What NOT to do

> **Do NOT** forget to call `RegisterEditorFactory()` at runtime — the `[ProvideEditorFactory]` registration attribute writes to the registry, but VS also requires the factory to be registered programmatically through the `Package.RegisterEditorFactory()` method during initialization.

> **Do NOT** create editor factories in the VisualStudio.Extensibility out-of-process model — it has no custom editor API. Use VSSDK or the Community Toolkit's `LanguageBase` for custom editors.

> **Do NOT** skip `IVsPersistDocData` implementation — without it, VS cannot track your document in the Running Document Table, meaning save, dirty tracking, and tab management will not work correctly.

> **Do NOT** save files without calling `SVsQueryEditQuerySave.QuerySaveFile` first — this breaks source control integration and can silently fail to write read-only files.

> **Do NOT** use a WPF `ToolBar` control inside your editor pane — use the VS command system (VSCT) for toolbars. See [adding-tool-window-toolbars](../adding-tool-window-toolbars/SKILL.md) for the correct pattern.

> **Do NOT** hard-code colors in your editor UI — use VS theme brushes so the editor looks correct in Light, Dark, and High Contrast themes. See [theming-extension-ui](../theming-extension-ui/SKILL.md).

## See also

- [adding-editor-adornments](../adding-editor-adornments/SKILL.md)
- [adding-editor-margins](../adding-editor-margins/SKILL.md)
- [adding-tool-windows](../adding-tool-windows/SKILL.md)
- [adding-textmate-grammars](../adding-textmate-grammars/SKILL.md)
- [adding-editor-classifiers](../adding-editor-classifiers/SKILL.md)
- [theming-extension-ui](../theming-extension-ui/SKILL.md)
- [adding-tool-window-toolbars](../adding-tool-window-toolbars/SKILL.md)
- [managing-files-documents](../managing-files-documents/SKILL.md)
- [providing-consuming-services](../providing-consuming-services/SKILL.md)

## References

- [Create custom editors and designers (Microsoft Learn)](https://learn.microsoft.com/visualstudio/extensibility/creating-custom-editors-and-designers)
- [Editor factories (Microsoft Learn)](https://learn.microsoft.com/previous-versions/visualstudio/visual-studio-2015/extensibility/editor-factories)
- [How to: Register editor file types (Microsoft Learn)](https://learn.microsoft.com/previous-versions/visualstudio/visual-studio-2015/extensibility/how-to-register-editor-file-types)
- [Document data and document view in custom editors (Microsoft Learn)](https://learn.microsoft.com/visualstudio/extensibility/document-data-and-document-view-in-custom-editors)
- [LanguageBase source (Community Toolkit GitHub)](https://github.com/VsixCommunity/Community.VisualStudio.Toolkit/blob/master/src/toolkit/Community.VisualStudio.Toolkit.Shared/LanguageService/LanguageBase.cs)
- [Editor_With_Toolbox sample (VSSDK-Extensibility-Samples)](https://github.com/microsoft/VSSDK-Extensibility-Samples/tree/master/Editor_With_Toolbox)
