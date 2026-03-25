---
name: adding-editor-classifiers
description: Add custom syntax highlighting and text classification to the Visual Studio editor. Use when the user asks how to colorize text, add syntax highlighting, create a classifier, highlight keywords, change text colors in the editor, create a custom language colorizer, or implement classification types. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Custom Text Classification (Syntax Highlighting) in Visual Studio Extensions

Classifiers assign classification types (keyword, comment, string, etc.) to spans of text. Visual Studio maps these types to colors and styles. Common scenarios:

- Syntax-highlight a custom language or DSL
- Add extra coloring to existing languages (e.g., highlight specific identifiers)
- Mark diagnostic regions with distinct formatting

Classifiers are the foundation of syntax highlighting in VS. They run on every editor render pass, so performance is critical — a slow classifier makes typing feel laggy across the entire editor. Classifiers also integrate with the VS Fonts & Colors system, allowing users to customize your classification colors through Tools > Options.

**When to use classifiers vs. alternatives:**
- Syntax coloring for a custom language or DSL → **classifier** (this skill)
- Simple keyword/syntax coloring via grammar file (no code) → TextMate grammar (see [vs-textmate-grammar](../adding-textmate-grammars/SKILL.md))
- Visual decorations, highlights, or overlays on text → adornments (see [vs-editor-adornment](../adding-editor-adornments/SKILL.md))
- Custom fonts/colors settings that users can configure → [vs-fonts-and-colors](../registering-fonts-colors/SKILL.md)

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your classifier will not load.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

If you are using a multi-project solution, replace `%CurrentProject%` with the project name that contains the MEF exports.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently support custom classifiers or classification types. Text classification relies on MEF-exported `IClassifier` components which must run in-process.

**If you need custom syntax highlighting, use the VSSDK (in-process) MEF approach.**

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not add a separate classification API — classifiers use the same MEF-based VSSDK APIs. The code below is the standard VSSDK approach, which works in a Community Toolkit extension.

---

## 3. VSSDK (in-process, legacy)

Custom classification involves three MEF exports:

1. **Classification type definition** — defines a new classification type name
2. **Classification format definition** — maps the type to visual styling (color, bold, etc.)
3. **Classifier provider** — creates `IClassifier` instances for each text buffer

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Editor`, `Microsoft.VisualStudio.Language.StandardClassification`
**Key namespaces:** `Microsoft.VisualStudio.Text.Classification`, `Microsoft.VisualStudio.Utilities`

### Step 1: Define a classification type

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

internal static class ClassificationTypes
{
    [Export(typeof(ClassificationTypeDefinition))]
    [Name("MyKeyword")]
    internal static ClassificationTypeDefinition MyKeywordType = null;

    [Export(typeof(ClassificationTypeDefinition))]
    [Name("MyComment")]
    internal static ClassificationTypeDefinition MyCommentType = null;
}
```

### Step 2: Define the format (colors / styles)

```csharp
using System.ComponentModel.Composition;
using System.Windows.Media;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(EditorFormatDefinition))]
[ClassificationType(ClassificationTypeNames = "MyKeyword")]
[Name("MyKeyword")]
[UserVisible(true)]
[Order(Before = Priority.Default)]
internal sealed class MyKeywordFormat : ClassificationFormatDefinition
{
    public MyKeywordFormat()
    {
        DisplayName = "My Keyword";
        ForegroundColor = Colors.CornflowerBlue;
        IsBold = true;
    }
}

[Export(typeof(EditorFormatDefinition))]
[ClassificationType(ClassificationTypeNames = "MyComment")]
[Name("MyComment")]
[UserVisible(true)]
[Order(Before = Priority.Default)]
internal sealed class MyCommentFormat : ClassificationFormatDefinition
{
    public MyCommentFormat()
    {
        DisplayName = "My Comment";
        ForegroundColor = Colors.Green;
        IsItalic = true;
    }
}
```

### Step 3: Implement the classifier provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(IClassifierProvider))]
[ContentType("text")] // or your custom content type
internal sealed class MyClassifierProvider : IClassifierProvider
{
    [Import]
    internal IClassificationTypeRegistryService ClassificationRegistry { get; set; }

    public IClassifier GetClassifier(ITextBuffer textBuffer)
    {
        return textBuffer.Properties.GetOrCreateSingletonProperty(
            () => new MyClassifier(textBuffer, ClassificationRegistry));
    }
}
```

### Step 4: Implement the classifier

```csharp
using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;

namespace MyExtension;

internal sealed class MyClassifier : IClassifier
{
    private readonly ITextBuffer _buffer;
    private readonly IClassificationType _keywordType;
    private readonly IClassificationType _commentType;

    // Keywords to highlight
    private static readonly HashSet<string> Keywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "JOIN", "ON"
    };

    public MyClassifier(ITextBuffer buffer, IClassificationTypeRegistryService registry)
    {
        _buffer = buffer;
        _keywordType = registry.GetClassificationType("MyKeyword");
        _commentType = registry.GetClassificationType("MyComment");
    }

    public event EventHandler<ClassificationChangedEventArgs> ClassificationChanged;

    public IList<ClassificationSpan> GetClassificationSpans(SnapshotSpan span)
    {
        var classifications = new List<ClassificationSpan>();
        string text = span.GetText();
        int lineStart = span.Start.Position;

        // Simple line-based classification
        foreach (var line in span.Snapshot.Lines)
        {
            if (line.Start < span.Start || line.Start >= span.End)
                continue;

            string lineText = line.GetText();

            // Classify comments (lines starting with --)
            if (lineText.TrimStart().StartsWith("--"))
            {
                classifications.Add(new ClassificationSpan(
                    line.Extent, _commentType));
                continue;
            }

            // Classify keywords
            var words = lineText.Split(new[] { ' ', '\t', ',', '(', ')' },
                StringSplitOptions.RemoveEmptyEntries);
            int pos = 0;
            foreach (string word in words)
            {
                int idx = lineText.IndexOf(word, pos, StringComparison.OrdinalIgnoreCase);
                if (idx >= 0 && Keywords.Contains(word))
                {
                    var wordSpan = new SnapshotSpan(
                        span.Snapshot, line.Start + idx, word.Length);
                    classifications.Add(new ClassificationSpan(wordSpan, _keywordType));
                }
                pos = idx + word.Length;
            }
        }

        return classifications;
    }
}
```

### Defining a custom content type

If you're creating a classifier for a new file type, define a content type and file extension:

```csharp
internal static class MyContentType
{
    [Export]
    [Name("myLanguage")]
    [BaseDefinition("code")]
    internal static ContentTypeDefinition MyLanguageContentType = null;

    [Export]
    [FileExtension(".mylang")]
    [ContentType("myLanguage")]
    internal static FileExtensionToContentTypeDefinition MyLanguageFileExtension = null;
}
```

Then change your classifier provider's `[ContentType("text")]` to `[ContentType("myLanguage")]`.

### Augmenting existing classifiers

To add classifications on top of an existing language (e.g., highlight custom identifiers in C#), use `[ContentType("CSharp")]` on your provider. Your classifier's spans will merge with the built-in C# classifier.

### Key points

- `GetClassificationSpans` is called frequently — keep it fast. Avoid allocations and complex parsing.
- Fire `ClassificationChanged` when your classification data changes (e.g., after a background parse completes).
- Use `IClassificationTypeRegistryService` to look up classification types.
- `[UserVisible(true)]` on the format definition makes the classification appear in **Tools > Options > Fonts and Colors**.
- Use `[Order]` on the format to control priority when multiple classifiers produce overlapping spans.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key guidance

- **VisualStudio.Extensibility** does not support custom text classifiers.
- **VSSDK / Community Toolkit** — Export `ClassificationTypeDefinition`, `ClassificationFormatDefinition`, and `IClassifierProvider` via MEF. Implement `IClassifier.GetClassificationSpans` to return classified text spans.
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest`.
- For new languages, also define a content type and file extension mapping.
- Keep `GetClassificationSpans` fast — it runs on every render pass.

## Troubleshooting

- **Classifier doesn't load / text isn't colored:** Check the MEF asset type in `.vsixmanifest`. Also verify `[ContentType]` matches the file type you're testing with.
- **Classification format definition doesn't appear in Fonts & Colors settings:** Ensure `[UserVisible(true)]` is set on the `ClassificationFormatDefinition`. Without it, the classification exists internally but isn't exposed in Tools > Options.
- **Colors look wrong or disappear in Dark theme:** You're hard-coding RGB colors. Use `ClassificationFormatDefinition` properties that respect VS theme tokens, or define separate colors for Light/Dark/High Contrast. See [vs-theming](../theming-extension-ui/SKILL.md).
- **Editor becomes sluggish after adding classifier:** `GetClassificationSpans` is doing too much parsing. Pre-parse on a background thread (triggered by `ITextBuffer.Changed`) and cache results; return from cache in `GetClassificationSpans`.
- **`ClassificationChanged` event causes infinite loop:** Your `ClassificationChanged` handler is triggering a re-classification. Guard against re-entrancy.

## What NOT to do

> **Do NOT** do heavy parsing or I/O in `GetClassificationSpans`. It runs synchronously on every render pass — any delay is directly visible as editor lag. Parse on a background thread and cache the results.

> **Do NOT** hard-code colors in `ClassificationFormatDefinition` without considering Dark and High Contrast themes. Use VS theme-aware color tokens or define per-theme overrides.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest`. Without it, your classifier provider and format definitions are silently ignored.

> **Do NOT** forget to fire `ClassificationChanged` when your cached parse results update. Without it, the editor won't re-query your classifier and stale highlighting persists until the user scrolls.

## See also

- [vs-textmate-grammar](../adding-textmate-grammars/SKILL.md) — lightweight syntax coloring without writing a classifier
- [vs-editor-tagger](../creating-editor-taggers/SKILL.md) — taggers as a lower-level alternative to classifiers
- [vs-editor-adornment](../adding-editor-adornments/SKILL.md) — visual decorations beyond text coloring
- [vs-fonts-and-colors](../registering-fonts-colors/SKILL.md) — integrating with the VS Fonts & Colors settings
- [vs-theming](../theming-extension-ui/SKILL.md) — theme-aware color definitions

## References

- [Walkthrough: Highlighting Text (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-highlighting-text)
- [IClassifier Interface](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.classification.iclassifier)
- [ClassificationFormatDefinition](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.classification.classificationformatdefinition)
- [Defining Content Types and File Extensions](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-linking-a-content-type-to-a-file-name-extension)
