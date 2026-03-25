---
name: creating-editor-taggers
description: Create taggers that mark text spans for squiggles, outlining, text markers, classification, and other editor features. Use when the user asks how to add squiggly underlines, error squiggles, warning markers, code folding, outlining regions, collapsible regions, text markers, tag spans, or ITagger. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Editor Taggers in Visual Studio Extensions

Taggers annotate text spans with tags that drive editor features: squiggles (error/warning underlines), outlining (code folding), text markers, classification, and more. The `ITagger<T>` / `ITaggerProvider` pattern is the core mechanism behind many editor visuals.

Common scenarios:

- Show error/warning squiggles under code spans
- Add collapsible outlining regions for custom languages
- Mark text spans with colored highlights (text markers)
- Provide structure tags for code block visualization

Taggers are the lowest-level building block in the VS editor extensibility model — classifiers, adornments, margins, and even some light bulb features depend on tag data. A tagger's `GetTags` method runs on the UI thread during every render pass, making performance the primary concern. The pattern of "parse on a background thread, cache results, read from cache in `GetTags`" is essential.

**When to use taggers vs. alternatives:**
- Squiggly underlines for errors/warnings → **tagger** with `IErrorTag` (this skill) — or Roslyn `DiagnosticAnalyzer` for C#/VB
- Code folding / outlining → **tagger** with `IOutliningRegionTag` (this skill)
- Text coloring / syntax highlighting → classifier (see [vs-editor-classifier](../adding-editor-classifiers/SKILL.md)) — built on taggers internally
- Visual decorations (highlights, overlays) → adornments (see [vs-editor-adornment](../adding-editor-adornments/SKILL.md))
- Gutter icons driven by tags → margin with `IGlyphFactory` (see [vs-editor-margin](../adding-editor-margins/SKILL.md))

## Implementation checklist

- [ ] Add the MEF asset type to `.vsixmanifest`
- [ ] Create the tagger class (implements `ITagger<T>`)
- [ ] Create the tagger provider (implements `IViewTaggerProvider` or `ITaggerProvider`)
- [ ] Define the content type and tag type the tagger applies to

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your tagger will not load.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently support custom taggers. Taggers are in-process MEF components.

For **diagnostics** (error/warning squiggles), the new model supports diagnostics through language server protocol (LSP) or Roslyn analyzers, which is the recommended approach for reporting errors in the new model.

**For custom taggers, use the VSSDK (in-process) MEF approach.**

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not wrap the tagger API — taggers use the standard VSSDK MEF pattern described below.

---

## 3. VSSDK (in-process, legacy)

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Editor`, `Microsoft.VisualStudio.Text.UI.Wpf`
**Key namespaces:** `Microsoft.VisualStudio.Text.Tagging`, `Microsoft.VisualStudio.Text.Editor`, `Microsoft.VisualStudio.Utilities`

### Error/Warning Squiggles with `IErrorTag`

#### Step 1: Implement the tagger

```csharp
using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Adornments;
using Microsoft.VisualStudio.Text.Tagging;

namespace MyExtension;

internal sealed class ErrorTagger : ITagger<IErrorTag>
{
    private readonly ITextBuffer _buffer;

    public ErrorTagger(ITextBuffer buffer)
    {
        _buffer = buffer;
        _buffer.Changed += (s, e) => OnBufferChanged(e);
    }

    public event EventHandler<SnapshotSpanEventArgs> TagsChanged;

    public IEnumerable<ITagSpan<IErrorTag>> GetTags(NormalizedSnapshotSpanCollection spans)
    {
        foreach (var span in spans)
        {
            string text = span.GetText();
            int index = 0;

            // Example: flag "FIXME" as warnings
            while ((index = text.IndexOf("FIXME", index, StringComparison.OrdinalIgnoreCase)) >= 0)
            {
                var errorSpan = new SnapshotSpan(span.Start + index, 5);
                yield return new TagSpan<IErrorTag>(
                    errorSpan,
                    new ErrorTag(PredefinedErrorTypeNames.Warning, "FIXME found — address this issue"));

                index += 5;
            }
        }
    }

    private void OnBufferChanged(TextContentChangedEventArgs e)
    {
        foreach (var change in e.Changes)
        {
            TagsChanged?.Invoke(this,
                new SnapshotSpanEventArgs(new SnapshotSpan(
                    e.After, change.NewSpan)));
        }
    }
}
```

#### Step 2: Implement the tagger provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(ITaggerProvider))]
[ContentType("text")]
[TagType(typeof(IErrorTag))]
internal sealed class ErrorTaggerProvider : ITaggerProvider
{
    public ITagger<T> CreateTagger<T>(ITextBuffer buffer) where T : ITag
    {
        return buffer.Properties.GetOrCreateSingletonProperty(
            () => new ErrorTagger(buffer)) as ITagger<T>;
    }
}
```

### Error type constants

Use `PredefinedErrorTypeNames` for squiggle styles:

| Constant | Squiggle Color |
|----------|---------------|
| `PredefinedErrorTypeNames.SyntaxError` | Red squiggle |
| `PredefinedErrorTypeNames.CompilerError` | Red squiggle |
| `PredefinedErrorTypeNames.Warning` | Green squiggle |
| `PredefinedErrorTypeNames.Suggestion` | Gray dots |
| `PredefinedErrorTypeNames.HintedSuggestion` | Faint dots |

### Code Folding / Outlining with `IOutliningRegionTag`

```csharp
using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Tagging;

namespace MyExtension;

internal sealed class OutliningTagger : ITagger<IOutliningRegionTag>
{
    private readonly ITextBuffer _buffer;

    public OutliningTagger(ITextBuffer buffer)
    {
        _buffer = buffer;
        _buffer.Changed += (s, e) => TagsChanged?.Invoke(this,
            new SnapshotSpanEventArgs(new SnapshotSpan(e.After, 0, e.After.Length)));
    }

    public event EventHandler<SnapshotSpanEventArgs> TagsChanged;

    public IEnumerable<ITagSpan<IOutliningRegionTag>> GetTags(
        NormalizedSnapshotSpanCollection spans)
    {
        if (spans.Count == 0)
            yield break;

        ITextSnapshot snapshot = spans[0].Snapshot;
        string startToken = "#region";
        string endToken = "#endregion";

        var startLines = new Stack<ITextSnapshotLine>();

        foreach (ITextSnapshotLine line in snapshot.Lines)
        {
            string text = line.GetText().TrimStart();

            if (text.StartsWith(startToken, StringComparison.OrdinalIgnoreCase))
            {
                startLines.Push(line);
            }
            else if (text.StartsWith(endToken, StringComparison.OrdinalIgnoreCase)
                     && startLines.Count > 0)
            {
                var startLine = startLines.Pop();
                var regionSpan = new SnapshotSpan(startLine.Start, line.End);

                // Collapsed text shown when region is folded
                string headerText = startLine.GetText().Trim();

                yield return new TagSpan<IOutliningRegionTag>(
                    regionSpan,
                    new OutliningRegionTag(
                        isDefaultCollapsed: false,
                        isImplementation: true,
                        collapsedForm: headerText,
                        collapsedHintForm: regionSpan.GetText()));
            }
        }
    }
}
```

#### Outlining tagger provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(ITaggerProvider))]
[ContentType("text")]
[TagType(typeof(IOutliningRegionTag))]
internal sealed class OutliningTaggerProvider : ITaggerProvider
{
    public ITagger<T> CreateTagger<T>(ITextBuffer buffer) where T : ITag
    {
        return buffer.Properties.GetOrCreateSingletonProperty(
            () => new OutliningTagger(buffer)) as ITagger<T>;
    }
}
```

### Text Marker Tags with `TextMarkerTag`

Text marker tags highlight spans with a background/foreground color using a predefined format:

```csharp
using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Tagging;

namespace MyExtension;

internal sealed class HighlightTagger : ITagger<TextMarkerTag>
{
    private readonly ITextBuffer _buffer;
    private readonly string _searchWord;

    public HighlightTagger(ITextBuffer buffer, string searchWord)
    {
        _buffer = buffer;
        _searchWord = searchWord;
    }

    public event EventHandler<SnapshotSpanEventArgs> TagsChanged;

    public IEnumerable<ITagSpan<TextMarkerTag>> GetTags(
        NormalizedSnapshotSpanCollection spans)
    {
        foreach (var span in spans)
        {
            string text = span.GetText();
            int index = 0;

            while ((index = text.IndexOf(_searchWord, index, StringComparison.OrdinalIgnoreCase)) >= 0)
            {
                var matchSpan = new SnapshotSpan(span.Start + index, _searchWord.Length);

                // Use a built-in format name or define your own EditorFormatDefinition
                yield return new TagSpan<TextMarkerTag>(
                    matchSpan,
                    new TextMarkerTag("MarkerFormatDefinition/HighlightWordFormatDefinition"));

                index += _searchWord.Length;
            }
        }
    }
}
```

### Common tag types

| Tag Interface | Purpose |
|--------------|---------|
| `IErrorTag` | Error/warning squiggles |
| `IOutliningRegionTag` | Code folding regions |
| `TextMarkerTag` | Background/foreground text highlights |
| `IClassificationTag` | Classification-based coloring (alternative to `IClassifier`) |
| `IUrlTag` | Clickable URL hyperlinks |
| `ITextMarkerTag` | General-purpose text markers |
| `IStructureTag` | Code block structure visualization |

### Key points

- `GetTags` is called frequently during scrolling and editing — keep it fast.
- Fire `TagsChanged` only for the specific spans that changed, not the entire document.
- Use `buffer.Properties.GetOrCreateSingletonProperty` to ensure one tagger per buffer.
- The `[TagType]` attribute on the provider tells the editor which tag type your tagger produces.
- The `[ContentType]` attribute scopes your tagger to specific file types.
- For view-level taggers (that need access to `ITextView`), implement `IViewTaggerProvider` instead.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key guidance

- **VisualStudio.Extensibility** does not support custom taggers. Use Roslyn analyzers or LSP for diagnostics.
- **VSSDK / Community Toolkit** — Implement `ITagger<T>` and export `ITaggerProvider` via MEF. Choose the tag type based on the visual you need (squiggles, outlining, markers).
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest`.
- `GetTags` runs on the UI thread — avoid expensive computation. Parse on a background thread and cache results.
- Fire `TagsChanged` to signal the editor to re-query your tagger.

## Troubleshooting

- **Tags don't appear at all:** Check the MEF asset type in `.vsixmanifest`. Verify `[ContentType]` and `[TagType]` attributes on the provider match the file type and tag type.
- **Squiggles/markers appear but are stale or don't update:** You're not firing `TagsChanged` when your cached data updates. The editor won't re-query without this event.
- **Editor is slow after adding tagger:** `GetTags` is doing too much work. Parse on a background thread and read from cache in `GetTags`.
- **Tags appear on wrong spans after edits:** You're not translating spans to the current snapshot. Use `ITrackingSpan` or translate with `snapshot.CreateTrackingSpan`.
- **Duplicate taggers created:** You're using `IViewTaggerProvider` when `ITaggerProvider` would suffice. `IViewTaggerProvider` creates one tagger per view; `ITaggerProvider` creates one per buffer.

## What NOT to do

> **Do NOT** use custom `ITagger<IErrorTag>` taggers to produce diagnostic squiggles for C#, VB, or any language with Roslyn or LSP support. Use **Roslyn analyzers** (`DiagnosticAnalyzer` + `CodeFixProvider`) or **Language Server Protocol** (LSP `textDocument/publishDiagnostics`) instead. These approaches are architecturally correct, run out-of-process, integrate with the Error List, and support code fixes. Custom error taggers bypass all of that infrastructure.

> **Do NOT** do parsing, regex matching, file I/O, or allocations inside `GetTags`. This method runs on the **UI thread during every scroll, edit, and layout pass**. Expensive work here causes visible jank and typing lag. Instead, parse on a background thread (e.g., triggered by `ITextBuffer.Changed`) and cache the results. `GetTags` should only read from the cache.

> **Do NOT** fire `TagsChanged` for the entire document when only a few spans changed. Pass only the affected `SnapshotSpan` to the `TagsChanged` event — firing it for the whole buffer forces the editor to re-query and re-render all visible lines unnecessarily.

> **Do NOT** forget to raise `TagsChanged` when your cached data updates. Without this event, the editor has no reason to re-query your tagger, and stale or missing squiggles/markers will remain on screen.

> **Do NOT** forget the `[TagType]` or `[ContentType]` attribute on your `ITaggerProvider`. Missing attributes cause the tagger to **silently not load** for your target file type.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest`. Without it, your MEF-exported tagger provider is **silently ignored** — no error, no log, tags simply don't appear.

> **Do NOT** confuse `ITaggerProvider` (buffer-level) with `IViewTaggerProvider` (view-level). Use `IViewTaggerProvider` only when your tagger needs access to the `ITextView` (e.g., for viewport-relative calculations). Using the wrong one can result in missing tags or unnecessary duplicate tagger instances.

## See also

- [vs-editor-classifier](../adding-editor-classifiers/SKILL.md) — classifiers built on the tagger infrastructure
- [vs-editor-adornment](../adding-editor-adornments/SKILL.md) — adornments that visualize tagged spans
- [vs-editor-margin](../adding-editor-margins/SKILL.md) — glyph margins that render icons for tagged spans
- [vs-editor-lightbulb](../adding-lightbulb-actions/SKILL.md) — light bulb actions paired with diagnostic tags
- [vs-error-list](../integrating-error-list/SKILL.md) — surfacing tagged errors in the Error List

## References

- [Walkthrough: Creating a Margin Glyph (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-creating-a-margin-glyph)
- [ITagger Interface](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.tagging.itagger-1)
- [ITaggerProvider Interface](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.tagging.itaggerprovider)
- [Walkthrough: Outlining (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-outlining)
