---
name: adding-suggested-actions
description: Add suggested actions (code fixes, refactorings) to the Visual Studio editor lightbulb using the MEF-based ISuggestedAction API. Use when the user asks how to create a suggested action provider, implement IAsyncSuggestedActionsSource, add lightbulb code fixes for non-Roslyn languages, implement ISuggestedActionsSourceProvider, or stream suggested actions asynchronously. Covers the legacy ISuggestedActionsSource, the ISuggestedActionsSource2 category-based API, and the recommended IAsyncSuggestedActionsSource streaming API. The VSIX Community Toolkit does not wrap this API — Toolkit and VSSDK use the same pattern.
---

# Suggested Actions (Editor Lightbulb Code Fixes) in Visual Studio Extensions

Suggested actions are the MEF-based API for contributing items to the Visual Studio editor lightbulb (Ctrl+.). They let extensions offer quick fixes, refactorings, and code suggestions for **any language** — not just Roslyn-based languages. The lightbulb appears when the caret is on a relevant span and the extension reports available actions.

Common scenarios:

- Offer a quick fix for a custom warning or error
- Provide a refactoring action (e.g., extract/rename/convert)
- Suggest code generation or transformation based on context
- Add custom actions to the lightbulb menu for any content type

This skill covers the `ISuggestedAction` interface family in depth. The API has evolved across VS versions (`ISuggestedAction` → `ISuggestedAction2` → `ISuggestedAction3`, and `ISuggestedActionsSource` → `ISuggestedActionsSource2` → `IAsyncSuggestedActionsSource`). Using the newest interface your minimum target supports gives you async support, priority control, and incremental results — which significantly improves lightbulb responsiveness.

**When to use this vs. alternatives:**
- Language-agnostic code actions for the lightbulb → **this skill** (`ISuggestedAction`)
- C#/VB code fixes through Roslyn → `CodeFixProvider` / `CodeRefactoringProvider`
- High-level light bulb overview and patterns → [vs-editor-lightbulb](../adding-lightbulb-actions/SKILL.md)
- Diagnostic squiggles that light bulb fixes pair with → [vs-editor-tagger](../creating-editor-taggers/SKILL.md)

---

## Interface Evolution Overview

The suggested actions API has evolved across Visual Studio versions. **Use the newest interface your minimum-supported VS version allows.**

| Interface | Available Since | Key Addition |
|-----------|----------------|--------------|
| `ISuggestedActionsSource` | VS 2015 | Original: `HasSuggestedActionsAsync` + synchronous `GetSuggestedActions` |
| `ISuggestedActionsSource2` | VS 2017 | Adds `GetSuggestedActionCategoriesAsync` (supersedes `HasSuggestedActionsAsync`) |
| `ISuggestedActionsSource3` | VS 2019 | Adds `GetSuggestedActions` overload with `IUIThreadOperationContext` for progress |
| **`IAsyncSuggestedActionsSource`** | **VS 2022** | **Recommended.** Async streaming via `ISuggestedActionSetCollector`. Requires `SuggestedActionPriorityAttribute`. |

| Interface | Available Since | Key Addition |
|-----------|----------------|--------------|
| `ISuggestedAction` | VS 2015 | Base action: `Invoke`, `GetPreviewAsync`, `GetActionSetsAsync` |
| `ISuggestedAction2` | VS 2015 | Adds `DisplayTextSuffix` property |
| `ISuggestedAction3` | VS 2019 | Adds `Invoke(IUIThreadOperationContext)` for progress reporting |

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

## 1. VisualStudio.Extensibility (out-of-process, recommended for new extensions)

The VisualStudio.Extensibility SDK does **not** have its own suggested actions API. The MEF-based `ISuggestedAction` interfaces are only available in-process.

Use the VSSDK in-process approach (sections below) to implement suggested actions.

---

## 2. VSIX Community Toolkit / 3. VSSDK (in-process)

The Community Toolkit does not wrap the suggested actions API — it uses the same MEF-based VSSDK pattern. Both approaches are identical for this feature.

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Language.Intellisense`
**Key namespace:** `Microsoft.VisualStudio.Language.Intellisense`

---

### Recommended: IAsyncSuggestedActionsSource (VS 2022+)

This is the recommended approach for Visual Studio 2022 and later. It enables **asynchronous streaming** of suggested action sets via collectors, allowing the lightbulb to display high-priority actions before lower-priority ones finish computing.

#### Step 1: Implement the suggested action

Implement `ISuggestedAction` (or `ISuggestedAction3` if you need progress reporting). Each action represents one menu item in the lightbulb.

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
        string text = span.GetText(span.TextBuffer.CurrentSnapshot);
        _display = $"Convert '{text}' to UPPER CASE";
    }

    public string DisplayText => _display;
    public bool HasActionSets => false;
    public bool HasPreview => true;
    public string IconAutomationText => null;
    public ImageMoniker IconMoniker => KnownMonikers.Transform;
    public string InputGestureText => null;

    public Task<IEnumerable<SuggestedActionSet>> GetActionSetsAsync(
        CancellationToken cancellationToken)
    {
        return Task.FromResult<IEnumerable<SuggestedActionSet>>(null);
    }

    public Task<object> GetPreviewAsync(CancellationToken cancellationToken)
    {
        string upper = _span.GetText(_span.TextBuffer.CurrentSnapshot).ToUpperInvariant();
        return Task.FromResult<object>(upper);
    }

    public void Invoke(CancellationToken cancellationToken)
    {
        var snapshot = _span.TextBuffer.CurrentSnapshot;
        var spanToReplace = _span.GetSpan(snapshot);
        _span.TextBuffer.Replace(spanToReplace, spanToReplace.GetText().ToUpperInvariant());
    }

    public bool TryGetTelemetryId(out Guid telemetryId)
    {
        telemetryId = Guid.Empty;
        return false;
    }

    public void Dispose() { }
}
```

#### Step 2: Implement the async suggested actions source

Implement `IAsyncSuggestedActionsSource`. This is the core of the async pattern — you receive an `ImmutableArray<ISuggestedActionSetCollector>` (one per declared priority), add action sets to each collector, and call `Complete()` when done.

```csharp
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Operations;

namespace MyExtension;

internal sealed class MyAsyncActionsSource : IAsyncSuggestedActionsSource
{
    private readonly ITextStructureNavigatorSelectorService _navigatorService;
    private readonly ITextView _textView;
    private readonly ITextBuffer _textBuffer;

    public MyAsyncActionsSource(
        ITextStructureNavigatorSelectorService navigatorService,
        ITextView textView,
        ITextBuffer textBuffer)
    {
        _navigatorService = navigatorService;
        _textView = textView;
        _textBuffer = textBuffer;
    }

    public event EventHandler<EventArgs> SuggestedActionsChanged;

    // --- IAsyncSuggestedActionsSource ---

    /// <summary>
    /// Streams suggested action sets into collectors, one per declared priority.
    /// Called from any thread.
    /// </summary>
    public async Task GetSuggestedActionsAsync(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        ImmutableArray<ISuggestedActionSetCollector> collectors,
        CancellationToken cancellationToken)
    {
        // Each collector corresponds to a priority declared via
        // [SuggestedActionPriority(...)] on the provider.
        // Add action sets to the appropriate collector, then Complete() it.
        foreach (var collector in collectors)
        {
            try
            {
                if (TryGetWordUnderCaret(out var extent) && extent.IsSignificant)
                {
                    var trackingSpan = range.Snapshot.CreateTrackingSpan(
                        extent.Span, SpanTrackingMode.EdgeInclusive);

                    var action = new ConvertToUpperCaseAction(trackingSpan);

                    collector.Add(new SuggestedActionSet(
                        categoryName: PredefinedSuggestedActionCategoryNames.Refactoring,
                        actions: new[] { action }));
                }
            }
            finally
            {
                collector.Complete();
            }
        }
    }

    // --- ISuggestedActionsSource2 ---

    /// <summary>
    /// Returns the set of categories that have available actions.
    /// Supersedes HasSuggestedActionsAsync.
    /// </summary>
    public Task<ISuggestedActionCategorySet> GetSuggestedActionCategoriesAsync(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        if (TryGetWordUnderCaret(out var extent) && extent.IsSignificant)
        {
            // Import ISuggestedActionCategoryRegistryService via MEF to create sets,
            // or return a well-known set.
            return Task.FromResult(requestedActionCategories);
        }

        return Task.FromResult<ISuggestedActionCategorySet>(null);
    }

    // --- ISuggestedActionsSource (inherited, legacy members) ---

    public Task<bool> HasSuggestedActionsAsync(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        // Superseded by GetSuggestedActionCategoriesAsync, but must still be implemented.
        return Task.FromResult(
            TryGetWordUnderCaret(out var extent) && extent.IsSignificant);
    }

    public IEnumerable<SuggestedActionSet> GetSuggestedActions(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        // Superseded by GetSuggestedActionsAsync, but must still be implemented.
        if (TryGetWordUnderCaret(out var extent) && extent.IsSignificant)
        {
            var trackingSpan = range.Snapshot.CreateTrackingSpan(
                extent.Span, SpanTrackingMode.EdgeInclusive);

            return new[]
            {
                new SuggestedActionSet(
                    categoryName: PredefinedSuggestedActionCategoryNames.Refactoring,
                    actions: new[] { new ConvertToUpperCaseAction(trackingSpan) })
            };
        }

        return Enumerable.Empty<SuggestedActionSet>();
    }

    // --- Helper ---

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

#### Step 3: Implement the provider with priority attributes

When your source implements `IAsyncSuggestedActionsSource`, the provider **must** declare one or more `SuggestedActionPriority` attributes for deterministic ordering. The lightbulb will create one `ISuggestedActionSetCollector` per declared priority.

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Operations;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(ISuggestedActionsSourceProvider))]
[Name("My Async Suggested Actions")]
[ContentType("text")]
[SuggestedActionPriority(DefaultOrderings.Default)]
internal sealed class MyAsyncActionsSourceProvider : ISuggestedActionsSourceProvider
{
    [Import]
    internal ITextStructureNavigatorSelectorService NavigatorService { get; set; }

    public ISuggestedActionsSource CreateSuggestedActionsSource(
        ITextView textView, ITextBuffer textBuffer)
    {
        if (textBuffer == null || textView == null)
            return null;

        return new MyAsyncActionsSource(NavigatorService, textView, textBuffer);
    }
}
```

**Priority values** (from `DefaultOrderings`):

| Constant | Use case |
|----------|----------|
| `DefaultOrderings.Highest` | Actions that should appear first (e.g., error fixes) |
| `DefaultOrderings.High` | High-priority suggestions |
| `DefaultOrderings.Default` | Standard priority |
| `DefaultOrderings.Low` | Lower-priority suggestions |
| `DefaultOrderings.Lowest` | Background / low-urgency actions |

You can declare **multiple priorities** on one provider to receive multiple collectors:

```csharp
[SuggestedActionPriority(DefaultOrderings.High)]
[SuggestedActionPriority(DefaultOrderings.Default)]
```

---

### Legacy: ISuggestedActionsSource (VS 2015+)

Use this if you need to support Visual Studio versions before 2022. The pattern uses synchronous `GetSuggestedActions` and async `HasSuggestedActionsAsync`.

#### Step 1: Implement the suggested action

Same as above — implement `ISuggestedAction`.

#### Step 2: Implement the suggested actions source

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

    public Task<bool> HasSuggestedActionsAsync(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(
            TryGetWordUnderCaret(out var extent) && extent.IsSignificant);
    }

    public IEnumerable<SuggestedActionSet> GetSuggestedActions(
        ISuggestedActionCategorySet requestedActionCategories,
        SnapshotSpan range,
        CancellationToken cancellationToken)
    {
        if (TryGetWordUnderCaret(out var extent) && extent.IsSignificant)
        {
            var trackingSpan = range.Snapshot.CreateTrackingSpan(
                extent.Span, SpanTrackingMode.EdgeInclusive);

            var action = new ConvertToUpperCaseAction(trackingSpan);

            return new[]
            {
                new SuggestedActionSet(
                    categoryName: PredefinedSuggestedActionCategoryNames.Refactoring,
                    actions: new[] { action })
            };
        }

        return Enumerable.Empty<SuggestedActionSet>();
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

#### Step 3: Implement the provider

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

---

## Suggested Action Categories

Categories control where your actions appear in the lightbulb and enable VS to filter which providers to query.

| Category | Purpose |
|----------|---------|
| `PredefinedSuggestedActionCategoryNames.CodeFix` | Fixes for code issues |
| `PredefinedSuggestedActionCategoryNames.ErrorFix` | Fixes for errors |
| `PredefinedSuggestedActionCategoryNames.Refactoring` | Refactoring operations |
| `PredefinedSuggestedActionCategoryNames.StyleFix` | Style violation fixes |
| `PredefinedSuggestedActionCategoryNames.Any` | Matches all categories |

When constructing a `SuggestedActionSet`, pass the `categoryName` parameter:

```csharp
new SuggestedActionSet(
    categoryName: PredefinedSuggestedActionCategoryNames.CodeFix,
    actions: new[] { myAction })
```

---

## Nested Action Sets

Group related actions under a parent by returning child action sets from `GetActionSetsAsync`:

```csharp
internal sealed class ConvertCaseParentAction : ISuggestedAction
{
    private readonly ITrackingSpan _span;

    public ConvertCaseParentAction(ITrackingSpan span) => _span = span;

    public string DisplayText => "Convert case...";
    public bool HasActionSets => true;
    public bool HasPreview => false;
    public string IconAutomationText => null;
    public ImageMoniker IconMoniker => KnownMonikers.Transform;
    public string InputGestureText => null;

    public Task<IEnumerable<SuggestedActionSet>> GetActionSetsAsync(
        CancellationToken cancellationToken)
    {
        var children = new ISuggestedAction[]
        {
            new ConvertToUpperCaseAction(_span),
            new ConvertToLowerCaseAction(_span),
        };

        return Task.FromResult<IEnumerable<SuggestedActionSet>>(
            new[] { new SuggestedActionSet(actions: children) });
    }

    public Task<object> GetPreviewAsync(CancellationToken cancellationToken) =>
        Task.FromResult<object>(null);

    public void Invoke(CancellationToken cancellationToken) { }

    public bool TryGetTelemetryId(out Guid telemetryId)
    {
        telemetryId = Guid.Empty;
        return false;
    }

    public void Dispose() { }
}
```

---

## ISuggestedAction3: Progress Reporting (VS 2019+)

`ISuggestedAction3` adds an `Invoke(IUIThreadOperationContext)` overload that lets your action report progress and show a description while it runs. Use this for long-running fix operations:

```csharp
using Microsoft.VisualStudio.Utilities;

internal sealed class SlowFixAction : ISuggestedAction3
{
    // ... ISuggestedAction members ...

    public string DisplayText => "Apply slow fix";
    public string DisplayTextSuffix => "(may take a moment)"; // ISuggestedAction2
    public bool HasActionSets => false;
    public bool HasPreview => false;
    public string IconAutomationText => null;
    public ImageMoniker IconMoniker => default;
    public string InputGestureText => null;

    // Legacy Invoke — still required
    public void Invoke(CancellationToken cancellationToken) =>
        ApplyFix(cancellationToken);

    // ISuggestedAction3 Invoke with progress
    public void Invoke(IUIThreadOperationContext operationContext)
    {
        using var scope = operationContext.AddScope(
            allowCancellation: true, description: "Applying slow fix...");

        for (int i = 0; i < 10; i++)
        {
            operationContext.UserCancellationToken.ThrowIfCancellationRequested();
            scope.Progress.Report(new ProgressInfo(i + 1, 10));
            // ... do partial work ...
        }
    }

    private void ApplyFix(CancellationToken cancellationToken)
    {
        // Fallback implementation
    }

    public Task<IEnumerable<SuggestedActionSet>> GetActionSetsAsync(
        CancellationToken cancellationToken) =>
        Task.FromResult<IEnumerable<SuggestedActionSet>>(null);

    public Task<object> GetPreviewAsync(CancellationToken cancellationToken) =>
        Task.FromResult<object>(null);

    public bool TryGetTelemetryId(out Guid telemetryId)
    {
        telemetryId = Guid.Empty;
        return false;
    }

    public void Dispose() { }
}
```

---

## Refreshing the Lightbulb

Raise `SuggestedActionsChanged` when your source detects new or removed actions (e.g., after a background analysis completes). This tells the lightbulb to re-query your source:

```csharp
// Inside your ISuggestedActionsSource / IAsyncSuggestedActionsSource:
public event EventHandler<EventArgs> SuggestedActionsChanged;

private void OnAnalysisCompleted()
{
    SuggestedActionsChanged?.Invoke(this, EventArgs.Empty);
}
```

---

## Key Performance Guidelines

- **`HasSuggestedActionsAsync` / `GetSuggestedActionCategoriesAsync`** is called frequently as the caret moves — keep it fast. Avoid heavy computation or file I/O.
- **`GetSuggestedActions` / `GetSuggestedActionsAsync`** is called when the lightbulb is expanded — can be slightly more expensive, but still should not block.
- **`Invoke`** is where the actual code modification happens — called on the UI thread unless you manage threading yourself.
- For `IAsyncSuggestedActionsSource`, always call `collector.Complete()` — use a `try/finally` to ensure it is called even on cancellation or error.
- Use `KnownMonikers` for action icons (from `Microsoft.VisualStudio.Imaging`).
- Set `HasPreview = true` and implement `GetPreviewAsync` to show a preview pane.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key Guidance

| Approach | Guidance |
|----------|----------|
| **VisualStudio.Extensibility** | No suggested actions API. Use Roslyn `CodeFixProvider` / `CodeRefactoringProvider` for C#/VB. Use the VSSDK in-process approach for other languages. |
| **VSSDK / Community Toolkit** | Export `ISuggestedActionsSourceProvider` via MEF. Return `IAsyncSuggestedActionsSource` (VS 2022+) for async streaming, or `ISuggestedActionsSource` for older versions. |

## What NOT to do

> **Do NOT** use `ISuggestedActionsSourceProvider` / `ISuggestedActionsSource` for **C# or VB.NET** code fixes and refactorings. Use Roslyn `CodeFixProvider` and `CodeRefactoringProvider` instead — they integrate with the Roslyn compiler pipeline, support Fix All, work with the Extensibility model, and are the architecturally correct approach. The MEF-based `ISuggestedAction` API is for **non-Roslyn languages only** (custom languages, text files, XML, etc.).

> **Do NOT** implement the legacy `ISuggestedActionsSource` for new extensions targeting VS 2022+. Use `IAsyncSuggestedActionsSource` instead — it enables async streaming of action sets via collectors, so high-priority fixes appear instantly while lower-priority ones compute in the background. The legacy interface uses a synchronous `GetSuggestedActions` method that blocks the lightbulb UI.

> **Do NOT** forget to add `[SuggestedActionPriority]` on the provider when using `IAsyncSuggestedActionsSource`. Without it, the lightbulb infrastructure won't create collectors for your source, and no actions will appear.

> **Do NOT** do heavy computation in `HasSuggestedActionsAsync` or `GetSuggestedActionCategoriesAsync`. These methods run on **every caret movement** — expensive parsing, file I/O, or network calls here will cause visible editor lag. Pre-compute results on a background thread and cache them.

> **Do NOT** forget to call `collector.Complete()` in `GetSuggestedActionsAsync`. Use `try/finally` to guarantee it runs even on cancellation or exceptions. Forgetting this call causes the lightbulb to spin indefinitely.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest`. Without it, your MEF-exported provider is **silently ignored** — no error, no log, the lightbulb simply doesn't show your actions.

## Troubleshooting

- **Light bulb never appears:** Check the MEF asset type in `.vsixmanifest`. Verify `[ContentType]` matches the file type. Ensure `HasSuggestedActionsAsync` or `GetSuggestedActionSetsAsync` returns results.
- **Actions appear but `Invoke` does nothing:** Ensure you're applying edits via `ITextBuffer` or Roslyn APIs. If you return from `Invoke` without modifying anything, the action appears to do nothing.
- **Editor becomes sluggish when moving the caret:** `HasSuggestedActionsAsync` is doing too much work. Move analysis to a background thread and cache results.
- **Lightbulb spins indefinitely:** You forgot to call `collector.Complete()` in `GetSuggestedActionsAsync`. Use `try/finally` to guarantee it runs.
- **Nested/sub-actions don't appear:** Set `HasActionSets = true` on the parent `ISuggestedAction` and return the sub-actions from `ActionSets`.

## See also

- [vs-editor-lightbulb](../adding-lightbulb-actions/SKILL.md) — high-level light bulb patterns and overview
- [vs-editor-tagger](../creating-editor-taggers/SKILL.md) — taggers that produce diagnostic squiggles light bulbs can fix
- [vs-editor-quickinfo](../adding-quickinfo-tooltips/SKILL.md) — hover tooltips as complementary information
- [vs-error-list](../integrating-error-list/SKILL.md) — surfacing errors alongside light bulb fixes

## References

- [Walkthrough: Displaying Light Bulb Suggestions (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-displaying-light-bulb-suggestions)
- [ISuggestedActionsSourceProvider](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedactionssourceprovider)
- [IAsyncSuggestedActionsSource](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.iasyncsuggestedactionssource)
- [ISuggestedActionsSource2](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedactionssource2)
- [ISuggestedAction](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedaction)
- [ISuggestedAction3](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedaction3)
- [ISuggestedActionSetCollector](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.isuggestedactionsetcollector)
- [SuggestedActionPriorityAttribute](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.suggestedactionpriorityattribute)
- [PredefinedSuggestedActionCategoryNames](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.predefinedsuggestedactioncategorynames)
