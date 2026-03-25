---
name: vs-theming
description: Theme custom WPF UI in Visual Studio extensions to match the current IDE color theme (Light, Dark, Blue, High Contrast). Use when the user asks about theming tool windows, dialogs, EnvironmentColors, VsBrushes, VSColorTheme, UseVsTheme, themed resource keys, or making UI follow VS theme changes in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Theming Visual Studio Extension UI

Any custom WPF UI (tool windows, dialogs, user controls) must respect the active Visual Studio color theme. Without theming, your UI will look broken in Dark or High Contrast themes. Visual Studio ships Light, Dark, Blue, and High Contrast themes — your extension should work in all of them.

**Rule #1:** Never hard-code hex or RGB colors. Always use theme-aware resource keys or the toolkit's auto-theming.

---

## 1. VSIX Community Toolkit (in-process) — `Themes.UseVsTheme`

The simplest approach. A single attached property applies official VS styling to all standard WPF controls in the visual tree.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### UserControl (tool window content)

```xml
<UserControl x:Class="MyExtension.MyToolWindowControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:toolkit="clr-namespace:Community.VisualStudio.Toolkit;assembly=Community.VisualStudio.Toolkit"
             toolkit:Themes.UseVsTheme="True">

    <StackPanel Margin="10">
        <TextBlock Text="Hello, themed world!" />
        <TextBox Margin="0,5" />
        <Button Content="Click Me" />
    </StackPanel>
</UserControl>
```

`toolkit:Themes.UseVsTheme="True"` automatically styles all child controls (buttons, text boxes, labels, list boxes, etc.) using the current VS theme. When the user switches themes, the UI updates immediately — no reload needed.

### DialogWindow

For standalone dialog windows, use `Microsoft.VisualStudio.PlatformUI.DialogWindow` as the base and apply the same attribute:

```xml
<platform:DialogWindow
    x:Class="MyExtension.MyDialog"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:platform="clr-namespace:Microsoft.VisualStudio.PlatformUI;assembly=Microsoft.VisualStudio.Shell.15.0"
    xmlns:toolkit="clr-namespace:Community.VisualStudio.Toolkit;assembly=Community.VisualStudio.Toolkit"
    toolkit:Themes.UseVsTheme="True"
    Title="My Dialog"
    Width="400"
    Height="300">

    <StackPanel Margin="10">
        <TextBlock Text="This dialog is themed." />
    </StackPanel>
</platform:DialogWindow>
```

### Using specific environment colors alongside UseVsTheme

`UseVsTheme="True"` handles standard WPF controls (buttons, text boxes, labels, list boxes, etc.), but it does not cover every scenario. You will need explicit `EnvironmentColors` or `VsBrushes` bindings when:

- You have custom-drawn elements (borders, separators, panels with specific semantic colors)
- You use non-standard controls that `UseVsTheme` doesn't restyle
- You need different background/foreground pairs for distinct UI regions (e.g., a sidebar vs. a content area)
- You want to match a specific VS element like the Info Bar, search box, or tree view

Since toolkit extensions run in-process, they have full access to all the VSSDK theming classes described in the next section. A typical toolkit control combines both:

```xml
<UserControl x:Class="MyExtension.MyToolWindowControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:toolkit="clr-namespace:Community.VisualStudio.Toolkit;assembly=Community.VisualStudio.Toolkit"
             xmlns:platformUI="clr-namespace:Microsoft.VisualStudio.PlatformUI;assembly=Microsoft.VisualStudio.Shell.15.0"
             xmlns:shell="clr-namespace:Microsoft.VisualStudio.Shell;assembly=Microsoft.VisualStudio.Shell.15.0"
             toolkit:Themes.UseVsTheme="True">

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>

        <!-- Header with explicit Info Bar background -->
        <Border Grid.Row="0"
                Background="{DynamicResource {x:Static platformUI:EnvironmentColors.InfoBarBackgroundBrushKey}}"
                Padding="8">
            <TextBlock Text="Status"
                       Foreground="{DynamicResource {x:Static platformUI:EnvironmentColors.InfoBarTextBrushKey}}" />
        </Border>

        <!-- Separator using environment border color -->
        <Border Grid.Row="0" VerticalAlignment="Bottom" Height="1"
                Background="{DynamicResource {x:Static platformUI:EnvironmentColors.ToolWindowBorderBrushKey}}" />

        <!-- Main content — standard controls auto-themed by UseVsTheme -->
        <StackPanel Grid.Row="1" Margin="10">
            <TextBlock Text="Search:" />
            <TextBox Margin="0,5" />
            <ListBox Margin="0,5" />
            <Button Content="Run" HorizontalAlignment="Left" />
        </StackPanel>
    </Grid>
</UserControl>
```

In code-behind, toolkit extensions can also use `VSColorTheme` to read colors and respond to theme changes:

```csharp
using Microsoft.VisualStudio.PlatformUI;

// Read a themed color
var bg = VSColorTheme.GetThemedColor(EnvironmentColors.ToolWindowBackgroundColorKey);

// React to theme switches
VSColorTheme.ThemeChanged += (e) => RefreshCustomDrawing();
```

---

## 2. VSSDK (in-process, legacy) — Environment Colors, Brushes, and Fonts

The VSSDK provides several key classes for theme integration. These classes are also available to VSIX Community Toolkit extensions — the toolkit is built on top of the VSSDK.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.PlatformUI`, `Microsoft.VisualStudio.Shell`

### EnvironmentColors — WPF DynamicResource keys

`EnvironmentColors` provides `ResourceKey` properties for every standard VS UI color. Use them as `DynamicResource` bindings in XAML so colors update automatically on theme changes.

```xml
<UserControl xmlns:platformUI="clr-namespace:Microsoft.VisualStudio.PlatformUI;assembly=Microsoft.VisualStudio.Shell.15.0">

    <Grid Background="{DynamicResource {x:Static platformUI:EnvironmentColors.ToolWindowBackgroundBrushKey}}">
        <TextBlock
            Text="Themed text"
            Foreground="{DynamicResource {x:Static platformUI:EnvironmentColors.ToolWindowTextBrushKey}}" />
    </Grid>
</UserControl>
```

**Commonly used EnvironmentColors keys:**

| Key | Usage |
|---|---|
| `ToolWindowBackgroundBrushKey` | Tool window background |
| `ToolWindowTextBrushKey` | Tool window text |
| `ToolWindowBorderBrushKey` | Tool window borders |
| `CommandBarMenuBackgroundGradientBrushKey` | Menu backgrounds |
| `CommandBarTextActiveBrushKey` | Active command text |
| `PanelHyperlinkBrushKey` | Hyperlink text |
| `AccentMediumBrushKey` | Accent borders |
| `ControlEditHintTextBrushKey` | Watermark/hint text |
| `SystemButtonFaceColorKey` | Dialog button faces |

**Color vs Brush keys:** Most properties come in pairs — `*ColorKey` (returns a `Color`) and `*BrushKey` (returns a `SolidColorBrush`). Use `BrushKey` for XAML bindings.

### VsBrushes — Legacy brush resource keys

`VsBrushes` is an older static class that exposes `ResourceKey` objects for environment brushes. It predates `EnvironmentColors` but is still functional. Prefer `EnvironmentColors` for new code as it has a wider set of keys.

```xml
<UserControl xmlns:shell="clr-namespace:Microsoft.VisualStudio.Shell;assembly=Microsoft.VisualStudio.Shell.15.0">

    <Border Background="{DynamicResource {x:Static shell:VsBrushes.ToolWindowBackgroundKey}}">
        <TextBlock
            Text="Using VsBrushes"
            Foreground="{DynamicResource {x:Static shell:VsBrushes.ToolWindowTextKey}}" />
    </Border>
</UserControl>
```

**Commonly used VsBrushes keys:**

| Key | Usage |
|---|---|
| `ToolWindowBackgroundKey` | Tool window background |
| `ToolWindowTextKey` | Tool window text |
| `WindowKey` | General window background |
| `WindowTextKey` | General window text |
| `CaptionTextKey` | Title/caption text |
| `ToolWindowBorderKey` | Tool window border |
| `CommandBarGradientBeginKey` | Command bar gradient start |
| `EnvironmentBackgroundKey` | IDE background |

### VsColors — GDI colors for WinForms / code-behind

If you need `System.Drawing.Color` values (e.g., for WinForms controls or custom painting), use `VsColors`:

```csharp
using Microsoft.VisualStudio.Shell;

System.Drawing.Color bgColor = VsColors.GetThemedGDIColor(
    EnvironmentColors.ToolWindowBackgroundColorKey);
```

### VSColorTheme — Runtime color access and change notification

`VSColorTheme` provides cached `System.Drawing.Color` lookups and a `ThemeChanged` event for responding to theme switches in code-behind:

```csharp
using Microsoft.VisualStudio.PlatformUI;

public MyControl()
{
    InitializeComponent();
    VSColorTheme.ThemeChanged += OnThemeChanged;
    ApplyThemeColors();
}

private void OnThemeChanged(ThemeChangedEventArgs e)
{
    ApplyThemeColors();
}

private void ApplyThemeColors()
{
    var bgColor = VSColorTheme.GetThemedColor(EnvironmentColors.ToolWindowBackgroundColorKey);
    var fgColor = VSColorTheme.GetThemedColor(EnvironmentColors.ToolWindowTextColorKey);

    this.Background = new SolidColorBrush(Color.FromArgb(bgColor.A, bgColor.R, bgColor.G, bgColor.B));
    this.Foreground = new SolidColorBrush(Color.FromArgb(fgColor.A, fgColor.R, fgColor.G, fgColor.B));
}

protected override void Dispose(bool disposing)
{
    if (disposing)
    {
        VSColorTheme.ThemeChanged -= OnThemeChanged;
    }
    base.Dispose(disposing);
}
```

### Environment fonts — matching the VS font

Bind to the environment font so your UI respects the user's font settings:

```xml
<TextBlock
    FontFamily="{DynamicResource {x:Static shell:VsFonts.EnvironmentFontFamilyKey}}"
    FontSize="{DynamicResource {x:Static shell:VsFonts.EnvironmentFontSizeKey}}"
    Text="Matching VS environment font" />
```

Or from a `ResourceDictionary`:

```xml
<Style TargetType="{x:Type TextBlock}">
    <Setter Property="FontFamily"
            Value="{DynamicResource {x:Static shell:VsFonts.EnvironmentFontFamilyKey}}" />
    <Setter Property="FontSize"
            Value="{DynamicResource {x:Static shell:VsFonts.EnvironmentFontSizeKey}}" />
</Style>
```

### IVsUIShell5.GetThemedColor — Low-level color access

For scenarios requiring the most direct access (e.g., custom rendering):

```csharp
IVsUIShell5 shell5 = (IVsUIShell5)ServiceProvider.GetService(typeof(SVsUIShell));
Guid category = environmentColorCategory;
uint rgbaColor = shell5.GetThemedColor(ref category, "ToolWindowBackground", (uint)__THEMEDCOLORTYPE.TCT_Background);
byte[] components = BitConverter.GetBytes(rgbaColor);
var color = System.Drawing.Color.FromArgb(components[3], components[0], components[1], components[2]);
```

---

## 3. VisualStudio.Extensibility (out-of-process) — Remote UI

Out-of-process extensions use **Remote UI** for tool windows and dialogs. Remote UI runs WPF in the Visual Studio process while your extension logic runs out-of-process.

Remote UI XAML automatically inherits Visual Studio theme colors when you use standard WPF controls. The VS host applies its theme styles to the Remote UI content.

### Tool window with themed content

```csharp
[VisualStudioContribution]
internal class MyToolWindow : ToolWindow
{
    public MyToolWindow(VisualStudioExtensibility extensibility)
        : base(extensibility)
    {
        Title = "My Tool Window";
    }

    public override ToolWindowConfiguration ToolWindowConfiguration => new()
    {
        Placement = ToolWindowPlacement.DocumentWell,
    };

    public override async Task<IRemoteUserControl> GetContentAsync(CancellationToken cancellationToken)
    {
        return new MyToolWindowControl();
    }
}
```

In the Remote UI XAML, standard WPF controls receive VS theme styling automatically. For explicit theme color binding, you can reference VS theme resources via the styles the host injects.

> **Note:** Fine-grained `EnvironmentColors` or `VsBrushes` bindings are not available in Remote UI XAML. If you need pixel-level color control, consider using an in-process extension component or designing your UI so that standard WPF control styling is sufficient.

---

## Quick reference: which class to use

| Need | Class | Returns |
|---|---|---|
| Auto-theme all controls in XAML | `toolkit:Themes.UseVsTheme="True"` | N/A (applied to tree) |
| WPF `DynamicResource` brush bindings | `EnvironmentColors.*BrushKey` | `ResourceKey` |
| WPF `DynamicResource` color bindings | `EnvironmentColors.*ColorKey` | `ResourceKey` |
| Legacy WPF brush resource keys | `VsBrushes.*Key` | `ResourceKey` |
| `System.Drawing.Color` in code | `VSColorTheme.GetThemedColor()` | `System.Drawing.Color` |
| WPF Color in code | `IVsUIShell5.GetThemedColor()` | `uint` (RGBA) |
| Theme change notification | `VSColorTheme.ThemeChanged` | Event |
| Environment font | `VsFonts.EnvironmentFontFamilyKey` / `EnvironmentFontSizeKey` | `ResourceKey` |

---

## Additional resources

- [VSIX Cookbook — Theming](https://www.vsixcookbook.com/recipes/theming.html)
- [Colors and Styling for Visual Studio](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/colors-and-styling-for-visual-studio)
- [Shared Colors for Visual Studio](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/shared-colors-for-visual-studio)
- [Color Value Reference](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/color-value-reference-for-visual-studio)
