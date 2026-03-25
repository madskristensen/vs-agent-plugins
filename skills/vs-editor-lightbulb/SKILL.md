---
name: vs-editor-lightbulb
description: Add light bulb code actions, quick fixes, and suggested actions to the Visual Studio editor. Use when the user asks how to add a light bulb, create quick fixes, add suggested actions, implement code actions, show a refactoring suggestion, or add an ISuggestedAction. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Light Bulb Code Actions (Suggested Actions) in Visual Studio Extensions

Light bulb actions appear when the user clicks the light bulb icon or presses Ctrl+. — they offer quick fixes, refactorings, and suggestions. Common scenarios:

- Offer a quick fix for a custom diagnostic or warning
- Provide a refactoring action (e.g., extract method, rename pattern)
- Suggest code generation based on context
- Add custom actions to the existing light bulb menu

The light bulb is VS's primary mechanism for presenting actionable code suggestions at the cursor position. It's the standard UX for "something can be improved here" — users learn to look for it and press Ctrl+. as a reflex. For C#/VB, Roslyn's `CodeFixProvider` and `CodeRefactoringProvider` are preferred because they integrate with the analyzer pipeline. For other languages or non-Roslyn scenarios, the MEF-based `ISuggestedAction` API is the way to contribute actions.

**When to use light bulb actions vs. alternatives:**
- Actionable code fix or refactoring at the cursor → **light bulb** (this skill)
- Diagnostic squiggles and warnings → taggers (see [vs-editor-tagger](../vs-editor-tagger/SKILL.md))
- Hover tooltips with information → Quick Info (see [vs-editor-quickinfo](../vs-editor-quickinfo/SKILL.md))
- Errors surfaced in the Error List → [vs-error-list](../vs-error-list/SKILL.md)

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your suggested actions will not appear.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** directly support suggested actions / light bulb actions through its own APIs.

However, for **Roslyn-based languages** (C#, VB), you can create **Roslyn code fix providers** and **code refactoring providers** which appear as light bulb actions. These use the `Microsoft.CodeAnalysis` APIs and are the recommended approach for C#/VB light bulb actions:

```csharp
using System.Collections.Immutable;
using System.Composition;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeFixes;

[ExportCodeFixProvider(LanguageNames.CSharp, Name = nameof(MyCodeFixProvider))]
[Shared]
public sealed class MyCodeFixProvider : CodeFixProvider
{
    public override ImmutableArray<string> FixableDiagnosticIds =>
        ImmutableArray.Create("MY001");

    public override FixAllProvider GetFixAllProvider() =>
        WellKnownFixAllProviders.BatchFixer;

    public override async Task RegisterCodeFixesAsync(CodeFixContext context)
    {
        var diagnostic = context.Diagnostics[0];
        var diagnosticSpan = diagnostic.Location.SourceSpan;

        context.RegisterCodeFix(
            CodeAction.Create(
                title: "Fix this issue",
                createChangedDocument: ct => FixDocumentAsync(context.Document, diagnosticSpan, ct),
                equivalenceKey: "MyFix"),
            diagnostic);
    }

    private async Task<Document> FixDocumentAsync(
        Document document, TextSpan span, CancellationToken cancellationToken)
    {
        // Implement the fix by modifying the syntax tree
        var root = await document.GetSyntaxRootAsync(cancellationToken);
        // ... modify root ...
        return document.WithSyntaxRoot(root);
    }
}
```

For non-Roslyn languages, use the VSSDK in-process approach.

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not wrap the suggested actions API — it uses the same MEF-based VSSDK pattern described below.

---

## 3. VSSDK (in-process, legacy)

Light bulb actions use the `ISuggestedActionsSourceProvider` and `ISuggestedAction` APIs.

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Language.Intellisense`
**Key namespace:** `Microsoft.VisualStudio.Language.Intellisense`

### Step 1: Implement the suggested action

```csharp
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Imaging;
using Microsoft.VisualStudio.Imaging.Interop;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;

namespace MyExtension;

internal sealed class ConvertToUpperCaseAction : ISuggestedAction
{
    private readonly ITrackingSpan _span;
    private readonly string _display;

    public ConvertToUpperCaseAction(ITrackingSpan span)
    {
        _span = span;
        _display = $"Convert '{span.GetText(span.TextBuffer.CurrentSnapshot)}' to UPPER CASE";
    }

    public string DisplayText => _display;
    public string IconAutomationText => null;
    public ImageMoniker IconMoniker => KnownMonikers.Transform;
    public string InputGestureText => null;
    public bool HasActionSets => false;
    public bool HasPreview => true;

    public Task<IEnumerable<SuggestedActionSet>> GetActionSetsAsync(CancellationToken cancellationToken)
    {
        return Task.FromResult<IEnumerable<SuggestedActionSet>>(null);
    }

    public Task<object> GetPreviewAsync(CancellationToken cancellationToken)
    {
        string currentText = _span.GetText(_span.TextBuffer.CurrentSnapshot);
        return Task.FromResult<object>(currentText.ToUpperInvariant());
    }

    public void Invoke(CancellationToken cancellationToken)
    {
        var snapshot = _span.TextBuffer.CurrentSnapshot;
        var spanToReplace = _span.GetSpan(snapshot);
        string upperText = spanToReplace.GetText().ToUpperInvariant();

        _span.TextBuffer.Replace(spanToReplace, upperText);
    }

    public bool TryGetTelemetryId(out Guid telemetryId)
    {
        telemetryId = Guid.Empty;
        return false;
    }

    public void Dispose() { }
}
```

### Step 2: Implement the suggested actions source

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Operations;

namespace MyExtension;

internal sealed class MyActionsSource : ISuggestedActionsSource
{
    private readonly ITextStructureNavigatorSelectorService _navigatorService;
    private readonly ITextView _textView;
    private readonly ITextBuffer _textBuffer;

    public MyActionsSource(
        ITextStructureNavigatorSelectorService navigatorService,
        ITextView textView,
        ITextBuffer textBuffer)
    {
        _navigatorService = navigatorService;
        _textView = textView;
        _textBuffer = textBuffer;
    }

    public event EventHandler<EventArgs> SuggestedActionsChanged;

    public IEnumerable<SuggestedActionSet> GetSuggestedActions(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        if (TryGetWordUnderCaret(out var extent) && extent.IsSignificant)
        {
            var trackingSpan = range.Snapshot.CreateTrackingSpan(
                extent.Span, SpanTrackingMode.EdgeInclusive);

            var upperCaseAction = new ConvertToUpperCaseAction(trackingSpan);

            return new[]
            {
                new SuggestedActionSet(
                    categoryName: PredefinedSuggestedActionCategoryNames.Refactoring,
                    actions: new[] { upperCaseAction })
            };
        }

        return Enumerable.Empty<SuggestedActionSet>();
    }

    public Task<bool> HasSuggestedActionsAsync(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(
            TryGetWordUnderCaret(out var extent) && extent.IsSignificant);
    }

    private bool TryGetWordUnderCaret(out TextExtent wordExtent)
    {
        var caret = _textView.Caret.Position;
        var point = caret.Point.GetPoint(_textBuffer, caret.Affinity);

        if (point.HasValue)
        {
            var navigator = _navigatorService.GetTextStructureNavigator(_textBuffer);
            wordExtent = navigator.GetExtentOfWord(point.Value);
            return true;
        }

        wordExtent = default;
        return false;
    }

    public bool TryGetTelemetryId(out Guid telemetryId)
    {
        telemetryId = Guid.Empty;
        return false;
    }

    public void Dispose() { }
}
```

### Step 3: Implement the provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Operations;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(ISuggestedActionsSourceProvider))]
[Name("My Suggested Actions")]
[ContentType("text")]
internal sealed class MyActionsSourceProvider : ISuggestedActionsSourceProvider
{
    [Import]
    internal ITextStructureNavigatorSelectorService NavigatorService { get; set; }

    public ISuggestedActionsSource CreateSuggestedActionsSource(
        ITextView textView, ITextBuffer textBuffer)
    {
        if (textBuffer == null || textView == null)
            return null;

        return new MyActionsSource(NavigatorService, textView, textBuffer);
    }
}
```

### Suggested action categories

Use categories to control where your actions appear:

| Category | Purpose |
|----------|---------|
| `PredefinedSuggestedActionCategoryNames.CodeFix` | Error/warning fixes |
| `PredefinedSuggestedActionCategoryNames.Refactoring` | Refactoring operations |
| `PredefinedSuggestedActionCategoryNames.Any` | All categories |

### Nested action sets

You can group related actions under a parent:

```csharp
public Task<IEnumerable<SuggestedActionSet>> GetActionSetsAsync(
    CancellationToken cancellationToken)
{
    var childActions = new ISuggestedAction[]
    {
        new ConvertToUpperCaseAction(_span),
        new ConvertToLowerCaseAction(_span),
    };

    return Task.FromResult<IEnumerable<SuggestedActionSet>>(
        new[] { new SuggestedActionSet(actions: childActions) });
}
```

Set `HasActionSets => true` on the parent action.

### Key points

- `HasSuggestedActionsAsync` is called frequently as the caret moves — keep it fast.
- `GetSuggestedActions` returns the actual action objects — also should be fast.
- `Invoke` is where the actual code modification happens.
- Set `HasPreview = true` and implement `GetPreviewAsync` to show a preview diff.
- Use `KnownMonikers` for action icons.
- For C#/VB, prefer Roslyn `CodeFixProvider` / `CodeRefactoringProvider` over `ISuggestedAction`.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key guidance

- **VisualStudio.Extensibility** — Use Roslyn `CodeFixProvider` / `CodeRefactoringProvider` for C#/VB. Not supported for other languages via the new model.
- **VSSDK / Community Toolkit** — Export `ISuggestedActionsSourceProvider` via MEF. Implement `ISuggestedAction` for each action. Use `ISuggestedActionsSource` to decide when actions are available.
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest`.
- Keep `HasSuggestedActionsAsync` lightweight — it runs on every caret movement.

## Troubleshooting

- **Light bulb never appears:** Check the MEF asset type in `.vsixmanifest`. Verify `[ContentType]` matches the file type. Also check that `HasSuggestedActionsAsync` returns `true` for the current caret position.
- **Actions appear but `Invoke` doesn't modify the document:** Ensure you're applying edits via `ITextBuffer.Replace` or Roslyn workspace APIs. If using Roslyn, verify your `CodeAction` returns non-empty change sets.
- **`HasSuggestedActionsAsync` causes editor lag:** This method fires on every caret movement. It must be very fast. Move any parsing or analysis to a background thread and cache the result; just check the cache in `HasSuggestedActionsAsync`.
- **Preview diff doesn't appear:** Ensure `HasPreview` returns `true` and `GetPreviewAsync` returns a valid `Task<object>`. For Roslyn code fixes, preview is automatic.
- **Light bulb shows for wrong file types:** Missing `[ContentType]` attribute on the provider.

## What NOT to do

> **Do NOT** do expensive work in `HasSuggestedActionsAsync`. It runs on every caret movement and keystroke. Pre-compute action availability on a background thread and return a cached result.

> **Do NOT** use the `ISuggestedAction` MEF API for C#/VB code fixes when Roslyn `CodeFixProvider` / `CodeRefactoringProvider` is available. Roslyn providers integrate with the analyzer pipeline, support preview, and work with `FixAll` automatically.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest`. Without it, your suggested actions provider is silently ignored.

> **Do NOT** forget to implement `IDisposable` on your `ISuggestedActionsSource`. VS creates and disposes sources as the caret moves; leaked sources accumulate memory.

## See also

- [vs-editor-suggested-actions](../vs-editor-suggested-actions/SKILL.md) — the complementary skill covering the `ISuggestedAction` interface in detail
- [vs-editor-tagger](../vs-editor-tagger/SKILL.md) — taggers that produce diagnostic squiggles light bulbs can fix
- [vs-editor-quickinfo](../vs-editor-quickinfo/SKILL.md) — hover tooltips as complementary information
- [vs-error-list](../vs-error-list/SKILL.md) — surfacing diagnostics in the Error List alongside light bulb fixes

## References

- [Walkthrough: Displaying Light Bulb Suggestions (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-displaying-light-bulb-suggestions)
- [ISuggestedActionsSourceProvider](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedactionssourceprovider)
- [ISuggestedAction](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedaction)
- [Roslyn Code Fix Providers](https://learn.microsoft.com/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix)
