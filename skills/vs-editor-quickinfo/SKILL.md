---
name: vs-editor-quickinfo
description: Add custom hover tooltips (Quick Info) to the Visual Studio editor. Use when the user asks how to show a hover tooltip, add Quick Info content, display information on mouse hover, create a QuickInfo source, or implement IAsyncQuickInfoSourceProvider. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Custom Quick Info (Hover Tooltips) in Visual Studio Extensions

Quick Info provides hover tooltips when the user mouses over text in the editor. Common scenarios:

- Show documentation or type information for custom keywords
- Display live data (e.g., variable values, API docs) on hover
- Add extra tooltip content to an existing language
- Show color previews, image previews, or rich content on hover

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your Quick Info source will not load.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently support custom Quick Info sources. Hover tooltips are provided by in-process MEF components.

**If you need custom Quick Info, use the VSSDK (in-process) MEF approach.**

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not wrap the Quick Info API — use the standard VSSDK MEF pattern below.

---

## 3. VSSDK (in-process, legacy)

Visual Studio has two Quick Info APIs:

- **Modern Async Quick Info** (`IAsyncQuickInfoSourceProvider`) — Visual Studio 15.6+, preferred
- **Legacy Quick Info** (`IQuickInfoSourceProvider`) — older API, deprecated

### Modern Async Quick Info (recommended)

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Language.Intellisense`
**Key namespace:** `Microsoft.VisualStudio.Language.Intellisense`

#### Step 1: Implement the Quick Info source

```csharp
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Adornments;

namespace MyExtension;

internal sealed class MyQuickInfoSource : IAsyncQuickInfoSource
{
    private readonly ITextBuffer _buffer;

    public MyQuickInfoSource(ITextBuffer buffer)
    {
        _buffer = buffer;
    }

    public Task<QuickInfoItem> GetQuickInfoItemAsync(
        IAsyncQuickInfoSession session,
        CancellationToken cancellationToken)
    {
        var triggerPoint = session.GetTriggerPoint(_buffer.CurrentSnapshot);
        if (triggerPoint == null)
            return Task.FromResult<QuickInfoItem>(null);

        // Get the word under the cursor
        var line = triggerPoint.Value.GetContainingLine();
        string lineText = line.GetText();
        int column = triggerPoint.Value.Position - line.Start.Position;

        // Find word boundaries
        int start = column;
        while (start > 0 && char.IsLetterOrDigit(lineText[start - 1]))
            start--;

        int end = column;
        while (end < lineText.Length && char.IsLetterOrDigit(lineText[end]))
            end++;

        string word = lineText.Substring(start, end - start);

        // Look up tooltip content for the word
        string tooltip = GetTooltip(word);
        if (tooltip == null)
            return Task.FromResult<QuickInfoItem>(null);

        var applicableSpan = _buffer.CurrentSnapshot.CreateTrackingSpan(
            line.Start + start, end - start, SpanTrackingMode.EdgeInclusive);

        // Return a ContainerElement with rich content
        var content = new ContainerElement(
            ContainerElementStyle.Stacked,
            new ClassifiedTextElement(
                new ClassifiedTextRun(
                    PredefinedClassificationTypeNames.Keyword, word)),
            new ClassifiedTextElement(
                new ClassifiedTextRun(
                    PredefinedClassificationTypeNames.NaturalLanguage, tooltip)));

        return Task.FromResult(new QuickInfoItem(applicableSpan, content));
    }

    private string GetTooltip(string word)
    {
        return word.ToUpperInvariant() switch
        {
            "SELECT" => "SQL keyword: Retrieves data from one or more tables.",
            "FROM" => "SQL keyword: Specifies the table(s) to query.",
            "WHERE" => "SQL keyword: Filters rows based on a condition.",
            _ => null,
        };
    }

    public void Dispose() { }
}
```

#### Step 2: Implement the provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(IAsyncQuickInfoSourceProvider))]
[Name("My Quick Info Source")]
[ContentType("text")]
[Order]
internal sealed class MyQuickInfoSourceProvider : IAsyncQuickInfoSourceProvider
{
    public IAsyncQuickInfoSource TryCreateQuickInfoSource(ITextBuffer textBuffer)
    {
        return textBuffer.Properties.GetOrCreateSingletonProperty(
            () => new MyQuickInfoSource(textBuffer));
    }
}
```

### Rich tooltip content

Quick Info supports rich content via `ContainerElement` and classified text:

```csharp
using Microsoft.VisualStudio.Text.Adornments;

// Stacked (vertical) layout
var content = new ContainerElement(
    ContainerElementStyle.Stacked,
    new ClassifiedTextElement(
        new ClassifiedTextRun(PredefinedClassificationTypeNames.Keyword, "MyKeyword"),
        new ClassifiedTextRun(PredefinedClassificationTypeNames.WhiteSpace, " "),
        new ClassifiedTextRun(PredefinedClassificationTypeNames.Type, "MyType")),
    new ClassifiedTextElement(
        new ClassifiedTextRun(
            PredefinedClassificationTypeNames.NaturalLanguage,
            "This is the description of the keyword.")),
    new ImageElement(KnownMonikers.StatusInformation.ToImageId()));

// Wrapped (horizontal) layout
var horizontal = new ContainerElement(
    ContainerElementStyle.Wrapped,
    new ImageElement(KnownMonikers.Method.ToImageId()),
    new ClassifiedTextElement(
        new ClassifiedTextRun(PredefinedClassificationTypeNames.Identifier, "MyMethod()")));
```

### Available classified text run types

| Classification | Typical Color |
|---------------|---------------|
| `PredefinedClassificationTypeNames.Keyword` | Blue |
| `PredefinedClassificationTypeNames.Type` | Teal |
| `PredefinedClassificationTypeNames.Identifier` | Default text |
| `PredefinedClassificationTypeNames.Comment` | Green |
| `PredefinedClassificationTypeNames.StringLiteral` | Red/brown |
| `PredefinedClassificationTypeNames.NaturalLanguage` | Default text |
| `PredefinedClassificationTypeNames.Number` | Light green |

### Key points

- `GetQuickInfoItemAsync` runs on a background thread — safe to do I/O or computation.
- Return `null` to show no tooltip (let other providers handle it).
- Use `ContainerElement` and `ClassifiedTextElement` for rich, themed content.
- Use `ImageElement` with `KnownMonikers` for icons.
- The `[Order]` attribute controls priority when multiple Quick Info sources exist.
- Multiple Quick Info sources can contribute to the same tooltip — they are combined.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key guidance

- **VisualStudio.Extensibility** does not support custom Quick Info sources.
- **VSSDK / Community Toolkit** — Export `IAsyncQuickInfoSourceProvider` via MEF. Implement `IAsyncQuickInfoSource.GetQuickInfoItemAsync` to return tooltip content.
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest`.
- Use the modern async API (`IAsyncQuickInfoSourceProvider`), not the legacy `IQuickInfoSourceProvider`.
- Return `null` when your source has nothing to contribute.

## References

- [Walkthrough: Displaying Quick Info Tooltips (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-displaying-quickinfo-tooltips)
- [IAsyncQuickInfoSource](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.iasyncquickinfosource)
- [IAsyncQuickInfoSourceProvider](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.iasyncquickinfosourceprovider)
