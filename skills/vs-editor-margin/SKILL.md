---
name: vs-editor-margin
description: Add custom margins to the Visual Studio text editor (gutter icons, side panels, bottom bars). Use when the user asks how to add a gutter, editor margin, side panel, bottom bar, line number gutter, custom glyph margin, or editor chrome. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Custom Editor Margins in Visual Studio Extensions

Editor margins are UI panels attached to the edges of the text editor — left (gutter), right, top, or bottom. Common scenarios:

- Add a custom glyph/icon gutter (e.g., bookmarks, breakpoint indicators, coverage markers)
- Show a minimap or overview panel on the right side
- Display a status bar or info panel below the editor
- Add line-level annotations in the left margin

---

## MEF Asset Type Requirement

**Any extension that uses MEF editor exports must declare the MEF asset type in the `.vsixmanifest` file.** Without this, Visual Studio will not discover your MEF components and your margin will not load.

Add this inside the `<Assets>` element of `source.extension.vsixmanifest`:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

> **Note:** The VisualStudio.Extensibility approach does NOT require this MEF asset entry.

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK supports editor margins via `VisualStudioContribution` and Remote UI (XAML).

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespace:** `Microsoft.VisualStudio.Extensibility.Editor`

### Define an editor margin with Remote UI

```csharp
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Editor;
using Microsoft.VisualStudio.RpcContracts.RemoteUI;

namespace MyExtension;

[VisualStudioContribution]
internal sealed class MyEditorMargin : ExtensionPart, ITextViewMarginProvider
{
    public TextViewMarginProviderConfiguration TextViewMarginProviderConfiguration => new(
        marginContainer: ContainerMarginPlacement.KnownValues.BottomControl)
    {
        Before = new[] { MarginPlacement.KnownValues.RowMargin },
    };

    public TextViewExtensionConfiguration TextViewExtensionConfiguration => new()
    {
        AppliesTo = new[]
        {
            DocumentFilter.FromDocumentType("CSharp"),
        },
    };

    public Task<IRemoteUserControl> CreateVisualElementAsync(
        ITextViewSnapshot textView,
        CancellationToken cancellationToken)
    {
        return Task.FromResult<IRemoteUserControl>(
            new MyMarginControl(textView));
    }
}
```

### The Remote UI control

```csharp
using Microsoft.VisualStudio.Extensibility.UI;

namespace MyExtension;

internal sealed class MyMarginControl : RemoteUserControl
{
    private readonly ITextViewSnapshot _textView;

    public MyMarginControl(ITextViewSnapshot textView)
        : base(new MyMarginData())
    {
        _textView = textView;
    }

    public override Task<string> GetXamlAsync(CancellationToken cancellationToken)
    {
        return Task.FromResult("""
            <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
                <Border Background="#1E1E1E" Padding="4">
                    <TextBlock Text="{Binding Message}"
                               Foreground="LightGray"
                               FontSize="11" />
                </Border>
            </DataTemplate>
            """);
    }
}

internal sealed class MyMarginData : NotifyPropertyChangedObject
{
    private string _message = "Custom margin loaded";
    public string Message
    {
        get => _message;
        set => SetProperty(ref _message, value);
    }
}
```

### Margin container placements

| Placement | Description |
|-----------|-------------|
| `ContainerMarginPlacement.KnownValues.BottomControl` | Below the editor |
| `ContainerMarginPlacement.KnownValues.TopControl` | Above the editor |
| `ContainerMarginPlacement.KnownValues.LeftControl` | Left of the editor (gutter area) |
| `ContainerMarginPlacement.KnownValues.RightControl` | Right of the editor |

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not wrap the margin API — margins use the same MEF-based VSSDK pattern described below.

---

## 3. VSSDK (in-process, legacy)

**NuGet packages:** `Microsoft.VisualStudio.SDK`, `Microsoft.VisualStudio.Editor`, `Microsoft.VisualStudio.Text.UI.Wpf`
**Key namespaces:** `Microsoft.VisualStudio.Text.Editor`, `Microsoft.VisualStudio.Utilities`

### Step 1: Implement the margin

```csharp
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.VisualStudio.Text.Editor;

namespace MyExtension;

internal sealed class MyMargin : Canvas, IWpfTextViewMargin
{
    public const string MarginName = "MyCustomMargin";
    private readonly IWpfTextView _textView;
    private bool _disposed;
    private readonly TextBlock _label;

    public MyMargin(IWpfTextView textView)
    {
        _textView = textView;

        Height = 25;
        ClipToBounds = true;
        Background = new SolidColorBrush(Color.FromRgb(0x2D, 0x2D, 0x2D));

        _label = new TextBlock
        {
            Text = "Custom Margin",
            Foreground = Brushes.LightGray,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 4, 0, 0),
            FontSize = 11,
        };

        Children.Add(_label);

        _textView.Caret.PositionChanged += OnCaretPositionChanged;
    }

    private void OnCaretPositionChanged(object sender, CaretPositionChangedEventArgs e)
    {
        var line = _textView.Caret.Position.BufferPosition.GetContainingLine();
        _label.Text = $"Line {line.LineNumber + 1}, Col {_textView.Caret.Position.BufferPosition.Position - line.Start.Position + 1}";
    }

    // IWpfTextViewMargin
    public FrameworkElement VisualElement => this;

    public double MarginSize => ActualHeight;

    public bool Enabled => true;

    public ITextViewMargin GetTextViewMargin(string marginName)
    {
        return string.Equals(marginName, MarginName, StringComparison.OrdinalIgnoreCase)
            ? this
            : null;
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _textView.Caret.PositionChanged -= OnCaretPositionChanged;
            _disposed = true;
        }
    }
}
```

### Step 2: Implement the margin provider

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(IWpfTextViewMarginProvider))]
[Name(MyMargin.MarginName)]
[Order(After = PredefinedMarginNames.HorizontalScrollBar)]
[MarginContainer(PredefinedMarginNames.Bottom)]
[ContentType("text")]
[TextViewRole(PredefinedTextViewRoles.Interactive)]
internal sealed class MyMarginProvider : IWpfTextViewMarginProvider
{
    public IWpfTextViewMargin CreateMargin(
        IWpfTextViewHost wpfTextViewHost,
        IWpfTextViewMargin marginContainer)
    {
        return new MyMargin(wpfTextViewHost.TextView);
    }
}
```

### Left gutter margin (glyph-style)

For a left-side gutter with per-line glyphs, use `IGlyphFactory` and `IGlyphFactoryProvider`:

```csharp
using System.ComponentModel.Composition;
using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Formatting;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[Export(typeof(IGlyphFactoryProvider))]
[Name("MyGlyphFactory")]
[Order(After = "VsTextMarker")]
[ContentType("text")]
[TagType(typeof(MyGlyphTag))]
internal sealed class MyGlyphFactoryProvider : IGlyphFactoryProvider
{
    public IGlyphFactory GetGlyphFactory(IWpfTextView view, IWpfTextViewMargin margin)
    {
        return new MyGlyphFactory();
    }
}

internal sealed class MyGlyphFactory : IGlyphFactory
{
    public UIElement GenerateGlyph(IWpfTextViewLine line, ITag tag)
    {
        if (tag is not MyGlyphTag)
            return null;

        return new Ellipse
        {
            Width = 12,
            Height = 12,
            Fill = Brushes.OrangeRed,
        };
    }
}

// Custom tag to trigger glyph display — use with ITaggerProvider
internal sealed class MyGlyphTag : IGlyphTag { }
```

You'll also need a tagger that produces `MyGlyphTag` spans — see the **vs-editor-tagger** skill for tagger implementation details.

### Predefined margin containers

| Container | Description |
|-----------|-------------|
| `PredefinedMarginNames.Bottom` | Below the horizontal scrollbar |
| `PredefinedMarginNames.Top` | Above the editor |
| `PredefinedMarginNames.Left` | Left gutter area |
| `PredefinedMarginNames.Right` | Right of the editor |
| `PredefinedMarginNames.BottomControl` | Below editor, above bottom margin |
| `PredefinedMarginNames.LeftSelection` | Left of selection margin |
| `PredefinedMarginNames.Glyph` | The glyph margin (breakpoints, etc.) |
| `PredefinedMarginNames.LineNumber` | Line number margin |

### Key points

- Margins are WPF `FrameworkElement` instances — you have full WPF control.
- For bottom/top margins, set `Height`. For left/right margins, set `Width`.
- Implement `Dispose` to clean up event subscriptions.
- Use `[MarginContainer]` to specify where the margin is placed.
- Use `[Order]` to control position relative to other margins.
- For per-line glyphs in the gutter, use `IGlyphFactory` with a custom tag.
- **Remember to add the MEF asset type to your `.vsixmanifest`** for the VSSDK approach.

---

## Key guidance

- **VisualStudio.Extensibility** — Use `ITextViewMarginProvider` with Remote UI for out-of-process margins. Supports bottom, top, left, and right placements.
- **VSSDK / Community Toolkit** — Export `IWpfTextViewMarginProvider` via MEF. Implement `IWpfTextViewMargin`. For gutter glyphs, use `IGlyphFactoryProvider`.
- Always declare the **MEF component asset type** in `source.extension.vsixmanifest` for the VSSDK approach.
- Clean up event subscriptions in `Dispose` to avoid memory leaks.

## References

- [Editor Margins (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/editor/editor-margin)
- [Walkthrough: Creating a Margin Glyph (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-creating-a-margin-glyph)
- [IWpfTextViewMarginProvider](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.editor.iwpftextviewmarginprovider)
- [IGlyphFactoryProvider](https://learn.microsoft.com/dotnet/api/microsoft.visualstudio.text.editor.iglyphfactoryprovider)
