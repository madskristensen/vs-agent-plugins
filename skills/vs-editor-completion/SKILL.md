---
name: vs-editor-completion
description: Add custom IntelliSense completion items to the Visual Studio editor. Use when the user asks how to add IntelliSense, provide auto-complete suggestions, create a completion source, add custom completion items, build a completion provider, implement async completion, or extend IntelliSense for a language. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Custom IntelliSense Completion in Visual Studio Extensions

Completion sources provide IntelliSense auto-complete suggestions. Common scenarios:

- Add completion items for a custom language or DSL
- Inject additional completion items into an existing language (e.g., custom snippets in C#)
- Provide context-aware completions based on project state or external data

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

## References

- [Implementing Custom IntelliSense Completion (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-displaying-statement-completion)
- [IAsyncCompletionSource](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.asynccompletion.iasynccompletionsource)
- [ICompletionSource (Legacy)](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.language.intellisense.icompletionsource)
