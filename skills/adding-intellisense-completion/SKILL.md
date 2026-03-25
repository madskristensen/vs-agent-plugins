---
name: adding-intellisense-completion
description: Add custom IntelliSense completion items to the Visual Studio editor. Use when the user asks how to add IntelliSense, provide auto-complete suggestions, create a completion source, add custom completion items, build a completion provider, implement async completion, or extend IntelliSense for a language. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Custom IntelliSense Completion in Visual Studio Extensions

Completion sources provide IntelliSense auto-complete suggestions. Common scenarios:

- Add completion items for a custom language or DSL
- Inject additional completion items into an existing language (e.g., custom snippets in C#)
- Provide context-aware completions based on project state or external data

IntelliSense is one of the most visible and frequently used editor features — developers trigger it dozens of times per session. A poorly performing completion source (slow, blocking the UI thread) is immediately noticeable. The modern async completion API (`IAsyncCompletionSourceProvider`) runs `GetCompletionContextAsync` on a background thread, making it safe for I/O and network calls. The legacy synchronous API runs on the UI thread and should not be used for new extensions.

**When to use completion vs. alternatives:**
- Auto-complete suggestions in the editor → **completion** (this skill)
- Hover tooltips on symbols → Quick Info (see [vs-editor-quickinfo](../adding-quickinfo-tooltips/SKILL.md))
- Code fix/refactoring suggestions (lightbulb) → suggested actions (see [vs-editor-lightbulb](../adding-lightbulb-actions/SKILL.md))
- Full language support (completion + diagnostics + hover + navigation) → Language Server Protocol (see [vs-language-server](../integrating-language-servers/SKILL.md))

## Implementation checklist

- [ ] Add the MEF asset type to `.vsixmanifest`
- [ ] Create the completion source (implements `IAsyncCompletionSource`)
- [ ] Create the source provider (implements `IAsyncCompletionSourceProvider`)
- [ ] Define the content type the completion applies to

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your completion source will not load.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK does **not** currently support custom IntelliSense completion sources. Completion is provided by in-process MEF components.

**If you need custom completion, use the VSSDK (in-process) MEF approach.**

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not add a separate completion API — completion uses the same MEF-based VSSDK APIs described below. The toolkit can simplify package setup, but the completion components use standard MEF exports.

---

## 3. VSSDK (in-process)

Visual Studio has two completion APIs:

- **Modern Async Completion** (`IAsyncCompletionSourceProvider`) — Visual Studio 16.0+, preferred
- **Legacy Completion** (`ICompletionSourceProvider`) — older API, still works

### Modern Async Completion (recommended)

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion`
**Key namespace:** `Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion`

#### Step 1: Implement the completion source

```csharp
using System.Collections.Immutable;
using System.ComponentModel.Composition;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Core.Imaging;
using Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion;
using Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion.Data;
using Microsoft.VisualStudio.Language.StandardClassification;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Adornments;
using Microsoft.VisualStudio.Text.Editor;

namespace MyExtension;

internal sealed class MyCompletionSource : IAsyncCompletionSource
{
    private static readonly ImageElement Icon = new(
        KnownMonikers.Keyword.ToImageId(), "Keyword");

    public Task<CompletionContext> GetCompletionContextAsync(
        IAsyncCompletionSession session,
        CompletionTrigger trigger,
        SnapshotPoint triggerLocation,
        SnapshotSpan applicableToSpan,
        CancellationToken cancellationToken)
    {
        var items = ImmutableArray.CreateBuilder<CompletionItem>();

        // Add your completion items
        items.Add(new CompletionItem("MyKeyword1", this, Icon));
        items.Add(new CompletionItem("MyKeyword2", this, Icon));
        items.Add(new CompletionItem("MyFunction", this, Icon));

        return Task.FromResult(new CompletionContext(items.ToImmutable()));
    }

    public Task<object> GetDescriptionAsync(
        IAsyncCompletionSession session,
        CompletionItem item,
        CancellationToken cancellationToken)
    {
        // Return a tooltip description for the selected item
        return Task.FromResult<object>($"Description for {item.DisplayText}");
    }

    public CompletionStartData InitializeCompletion(
        CompletionTrigger trigger,
        SnapshotPoint triggerLocation,
        CancellationToken cancellationToken)
    {
        // Determine if completion should start and what span it applies to
        if (trigger.Reason == CompletionTriggerReason.Insertion
            && !char.IsLetterOrDigit(trigger.Character))
        {
            return CompletionStartData.DoesNotParticipateInCompletion;
        }

        // Find the start of the current word
        var line = triggerLocation.GetContainingLine();
        int start = triggerLocation.Position;
        while (start > line.Start.Position
               && char.IsLetterOrDigit((triggerLocation.Snapshot[start - 1])))
        {
            start--;
        }

        var applicableSpan = new SnapshotSpan(
            triggerLocation.Snapshot, start, triggerLocation.Position - start);

        return new CompletionStartData(
            CompletionParticipation.ProvidesItems, applicableSpan);
    }
}
```

#### Step 2: Implement the completion source provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(IAsyncCompletionSourceProvider))]
[ContentType("text")] // or your content type
[Name("MyCompletionSourceProvider")]
internal sealed class MyCompletionSourceProvider : IAsyncCompletionSourceProvider
{
    public IAsyncCompletionSource GetOrCreate(ITextView textView)
    {
        return textView.Properties.GetOrCreateSingletonProperty(
            () => new MyCompletionSource());
    }
}
```

### Legacy Completion API

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Language.Intellisense`
**Key namespace:** `Microsoft.VisualStudio.Language.Intellisense`

```csharp
using System.Collections.Generic;
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Operations;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(ICompletionSourceProvider))]
[ContentType("text")]
[Name("MyLegacyCompletionProvider")]
internal sealed class MyLegacyCompletionSourceProvider : ICompletionSourceProvider
{
    [Import]
    internal ITextStructureNavigatorSelectorService NavigatorService { get; set; }

    public ICompletionSource TryCreateCompletionSource(ITextBuffer textBuffer)
    {
        return new MyLegacyCompletionSource(textBuffer, NavigatorService);
    }
}

internal sealed class MyLegacyCompletionSource : ICompletionSource
{
    private readonly ITextBuffer _buffer;
    private readonly ITextStructureNavigatorSelectorService _navigatorService;
    private bool _disposed;

    public MyLegacyCompletionSource(
        ITextBuffer buffer,
        ITextStructureNavigatorSelectorService navigatorService)
    {
        _buffer = buffer;
        _navigatorService = navigatorService;
    }

    public void AugmentCompletionSession(
        ICompletionSession session,
        IList<CompletionSet> completionSets)
    {
        var completions = new List<Completion>
        {
            new Completion("MyKeyword1", "MyKeyword1", "Description 1", null, null),
            new Completion("MyKeyword2", "MyKeyword2", "Description 2", null, null),
            new Completion("MyFunction", "MyFunction()", "Description 3", null, null),
        };

        var navigator = _navigatorService.GetTextStructureNavigator(_buffer);
        var extent = navigator.GetExtentOfWord(
            session.GetTriggerPoint(_buffer).GetPoint(_buffer.CurrentSnapshot));

        var trackingSpan = _buffer.CurrentSnapshot.CreateTrackingSpan(
            extent.Span, SpanTrackingMode.EdgeInclusive);

        completionSets.Add(new CompletionSet(
            "MyCompletions",
            "My Completions",
            trackingSpan,
            completions,
            null));
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            GC.SuppressFinalize(this);
            _disposed = true;
        }
    }
}
```

### Triggering completion from a command handler

If you need to programmatically trigger completion (e.g., after typing a `.`), register a command handler:

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Commanding;
using Microsoft.VisualStudio.Language.Intellisense.AsyncCompletion;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Editor.Commanding.Commands;
using Microsoft.VisualStudio.Utilities;

[Export(typeof(ICommandHandler))]
[ContentType("text")]
[Name("MyCompletionTriggerHandler")]
internal sealed class CompletionTriggerHandler : ICommandHandler<TypeCharCommandArgs>
{
    [Import]
    internal IAsyncCompletionBroker CompletionBroker { get; set; }

    public string DisplayName => "My Completion Trigger";

    public bool ExecuteCommand(TypeCharCommandArgs args, CommandExecutionContext executionContext)
    {
        if (args.TypedChar == '.')
        {
            // Trigger completion after '.'
            var trigger = new CompletionTrigger(
                CompletionTriggerReason.Insertion, args.TextView.TextSnapshot, '.');
            CompletionBroker.TriggerCompletion(
                args.TextView, trigger, args.TextView.Caret.Position.BufferPosition, default);
        }

        return false; // Let the character be typed
    }

    public CommandState GetCommandState(TypeCharCommandArgs args)
    {
        return CommandState.Unspecified;
    }
}
```

### Key points

- Prefer the **modern async completion** API (`IAsyncCompletionSourceProvider`) for new extensions.
- `InitializeCompletion` determines whether your source participates and defines the applicable span.
- `GetCompletionContextAsync` returns the actual items — it runs on a background thread, so it's safe to do I/O.
- The legacy `ICompletionSource.AugmentCompletionSession` runs synchronously.
- Use `[ContentType]` to scope completion to specific file types.
- For image icons, use `KnownMonikers` from `Microsoft.VisualStudio.Imaging`.
- **Remember to add the MEF asset type to your `.vsixmanifest`** — see the top of this document.

---

## Key guidance

- **VisualStudio.Extensibility** does not support custom IntelliSense completion.
- **VSSDK / Community Toolkit** — Use `IAsyncCompletionSourceProvider` (modern) or `ICompletionSourceProvider` (legacy) via MEF exports.
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest`.
- Use the async API for better performance and background-thread safety.
- Scope your provider with `[ContentType]` to avoid interfering with other languages.

## Troubleshooting

- **Completion items don't appear at all:** Check the MEF asset type in `.vsixmanifest`. Also verify `[ContentType]` matches the file type. For async completion, ensure `InitializeCompletion` returns a valid `CompletionStartData` (not `DoesNotParticipateInCompletion`).
- **Completion appears for the wrong file types:** Missing or incorrect `[ContentType]` attribute on the provider. Without it, completion activates for all file types.
- **Items appear but the wrong ones are selected / filtered:** Check your `ApplicableToSpan` calculation. The span determines which text VS uses to filter the completion list as the user types.
- **Completion is slow / editor freezes on invoke:** You're using the legacy synchronous `ICompletionSource` or doing I/O in `GetCompletionContextAsync`. Move heavy work to background caching or use the async API.
- **Items from your source and another source are mixed unexpectedly:** Multiple completion sources for the same content type are merged by VS. Use `CompletionItem.SortText` and `FilterText` to control ordering and filtering.

## What NOT to do

> **Do NOT** use the legacy synchronous `ICompletionSourceProvider` / `ICompletionSource` API for new extensions targeting VS 2019+. Use the modern async `IAsyncCompletionSourceProvider` / `IAsyncCompletionSource` instead. The legacy API runs `AugmentCompletionSession` synchronously on the UI thread — any I/O, parsing, or network call will freeze the editor. Many old tutorials and walkthroughs still show the legacy API; do not follow them for new code.

> **Do NOT** do expensive work (file I/O, HTTP requests, large allocations) inside `GetCompletionContextAsync`. This method is called on every keystroke while the completion list is open. Pre-compute or cache data in `InitializeCompletion` or on a background thread triggered by document changes.

> **Do NOT** forget to return `CompletionStartData.DoesNotParticipateInCompletion` from `InitializeCompletion` when your source should not contribute to the current completion session. Returning items when you shouldn't adds unnecessary overhead and pollutes the completion list.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest`. Without it, your MEF-exported provider is **silently ignored** — no error, no log, completion simply doesn't appear. This is the #1 cause of "my completion provider doesn't load."

> **Do NOT** omit the `[ContentType]` attribute on your provider. Without it, your completion source may activate for every file type in VS, causing unexpected items to appear in languages you didn't intend to support.

## See also

- [vs-editor-quickinfo](../adding-quickinfo-tooltips/SKILL.md) — hover tooltips that complement completion
- [vs-editor-lightbulb](../adding-lightbulb-actions/SKILL.md) — code actions and quick fixes
- [vs-language-server](../integrating-language-servers/SKILL.md) — LSP provides completion as part of a full language service
- [vs-editor-tagger](../creating-editor-taggers/SKILL.md) — taggers can provide context data that completion sources use

## References

- [Implementing Custom IntelliSense Completion (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-displaying-statement-completion)
- [IAsyncCompletionSource](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.asynccompletion.iasynccompletionsource)
- [ICompletionSource (Legacy)](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.icompletionsource)
