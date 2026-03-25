---
name: vs-fonts-and-colors
description: Register custom font and color categories on the Tools > Options > Fonts and Colors page. Use when the user asks about user-customizable syntax colors, creating a Fonts and Colors category, BaseFontAndColorCategory, IVsFontAndColorDefaults, ColorDefinition, or reading configured font/color settings at runtime in a Visual Studio IDE extension. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Fonts & Colors in Visual Studio Extensions

Extensions can register custom font and color categories that appear on the **Tools > Options > Environment > Fonts and Colors** page. Users can then customize foreground, background, and font styles for each item your extension defines.

This is different from general theming (matching VS's Light/Dark theme). This is about letting users customize *your extension's* display items — like a custom editor's syntax colors.

---

## 1. VSIX Community Toolkit (in-process)

The toolkit wraps the complex VSSDK registration with three building blocks:

1. `BaseFontAndColorCategory<T>` — defines a category with its default font and color items.
2. `BaseFontAndColorProvider` — discovers categories and serves them to Visual Studio.
3. `VS.FontsAndColors` — reads the user's configured colors at runtime.

**NuGet package:** `Community.VisualStudio.Toolkit`
**Key namespace:** `Community.VisualStudio.Toolkit`

### Step 1 — Define a category

Create a class inheriting from `BaseFontAndColorCategory<T>`. Give it a unique `[Guid]`, a display `Name`, and one or more `ColorDefinition` properties.

```csharp
using System.Runtime.InteropServices;
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio.Shell.Interop;

[Guid("e977c587-c06e-4c1d-8a3a-cbf9da1bdafa")]
public class MyColorCategory : BaseFontAndColorCategory<MyColorCategory>
{
    // Default font. Use FontDefinition.Automatic to inherit the user's editor font.
    public MyColorCategory() : base(new FontDefinition("Consolas", 10)) { }

    // This name appears in the category drop-down on the Fonts and Colors page.
    public override string Name => "My Extension Colors";

    public ColorDefinition Keyword { get; } = new(
        "Keyword",
        defaultForeground: VisualStudioColor.Indexed(COLORINDEX.CI_BLUE),
        defaultBackground: VisualStudioColor.Automatic()
    );

    public ColorDefinition Comment { get; } = new(
        "Comment",
        defaultForeground: VisualStudioColor.Indexed(COLORINDEX.CI_DARKGREEN),
        defaultBackground: VisualStudioColor.Automatic(),
        fontStyle: FontStyle.Italic
    );

    public ColorDefinition Error { get; } = new(
        "Error",
        defaultForeground: VisualStudioColor.Indexed(COLORINDEX.CI_RED),
        defaultBackground: VisualStudioColor.Automatic(),
        fontStyle: FontStyle.Bold
    );
}
```

Each `ColorDefinition` property is automatically discovered. The `name` parameter passed to the constructor is what appears on the options page.

#### Color values

| Factory method | Description |
|---|---|
| `VisualStudioColor.Indexed(COLORINDEX.CI_*)` | Standard VS color index |
| `VisualStudioColor.VsColor(__VSSYSCOLOREX.VSCOLOR_*)` | VS themed system color |
| `VisualStudioColor.Automatic()` | Let VS choose based on the current theme |

#### Color options

Control what the user can customize:

```csharp
public ColorDefinition Literal { get; } = new(
    "Literal",
    defaultForeground: VisualStudioColor.Indexed(COLORINDEX.CI_MAROON),
    options: ColorOptions.AllowForegroundChange | ColorOptions.AllowBoldChange
);
```

### Step 2 — Define a provider

Create a class inheriting from `BaseFontAndColorProvider`. It needs its own `[Guid]`. The provider automatically discovers all `BaseFontAndColorCategory<T>` classes in the same assembly.

```csharp
[Guid("26442428-2cd7-4d79-8498-f9b14087ca50")]
public class MyFontAndColorProvider : BaseFontAndColorProvider { }
```

### Step 3 — Register in the package

Add the `[ProvideFontsAndColors]` attribute to your package class and call `RegisterFontAndColorProvidersAsync()` during initialization.

```csharp
[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid(PackageGuids.MyPackageString)]
[ProvideFontsAndColors(typeof(MyFontAndColorProvider))]
public sealed class MyPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await this.RegisterFontAndColorProvidersAsync();
    }
}
```

### Reading configured colors at runtime

```csharp
ConfiguredFontAndColorSet config =
    await VS.FontsAndColors.GetConfiguredFontAndColorsAsync<MyColorCategory>();

// Read the current font
ConfiguredFont font = config.Font;
string fontFamily = font.FamilyName;
ushort fontSize = font.Size;

// Read a specific color
MyColorCategory category = MyColorCategory.Instance;
ConfiguredColor keywordColor = config.GetColor(category.Keyword);
System.Drawing.Color foreground = keywordColor.ForegroundColor;
System.Drawing.Color background = keywordColor.BackgroundColor;
```

The returned `ConfiguredFontAndColorSet` is live — it raises change notifications when the user modifies colors while your extension is running.

### Listening for changes

```csharp
// The ConfiguredFontAndColorSet always reflects the latest user choices.
// Re-read colors whenever you need to repaint.
ConfiguredColor latest = config.GetColor(category.Keyword);
```

---

## 2. VSSDK (in-process, legacy)

The VSSDK requires implementing `IVsFontAndColorDefaults` and registering via the registry.

**NuGet package:** `Microsoft.VisualStudio.SDK`
**Key namespaces:** `Microsoft.VisualStudio.Shell.Interop`, `Microsoft.VisualStudio.Shell`

### Implement IVsFontAndColorDefaults

Your VSPackage must implement `IVsFontAndColorDefaultsProvider` and return an `IVsFontAndColorDefaults` instance for each category GUID.

Each `IVsFontAndColorDefaults` implementation must provide:
- Lists of display items in the category
- Localizable names for display items
- Display information for each member (foreground, background, font flags)

### Register the category

In your `.pkgdef` or via registry attributes:

```
[$RootKey$\FontAndColors\My Extension Colors]
"Category"="{e977c587-c06e-4c1d-8a3a-cbf9da1bdafa}"
"Package"="{your-package-guid}"
```

### Read stored settings via IVsFontAndColorStorage

```csharp
IVsFontAndColorStorage storage = (IVsFontAndColorStorage)
    GetService(typeof(SVsFontAndColorStorage));

Guid categoryGuid = new Guid("e977c587-c06e-4c1d-8a3a-cbf9da1bdafa");
storage.OpenCategory(ref categoryGuid, (uint)__FCSTORAGEFLAGS.FCSF_READONLY);

ColorableItemInfo[] itemInfo = new ColorableItemInfo[1];
storage.GetItem("Keyword", itemInfo);
uint foreground = itemInfo[0].crForeground;

storage.CloseCategory();
```

### Respond to changes

Implement `IVsFontAndColorEvents` or poll via `IVsFontAndColorStorage`. Use `IVsFontAndColorCacheManager` to flush stale caches before reading.

> **Note:** The raw VSSDK approach is significantly more boilerplate than the toolkit. Use the Community Toolkit's `BaseFontAndColorCategory<T>` when possible.

---

## 3. VisualStudio.Extensibility (out-of-process)

The VisualStudio.Extensibility SDK does **not** currently provide an API for registering custom Fonts and Colors categories. This feature requires in-process registration via COM interfaces.

If you need Fonts and Colors support from an out-of-process extension, use a mixed in-proc/out-of-proc extension pattern with an in-process companion that handles the registration.

---

## Additional resources

- [VSIX Cookbook — Fonts & Colors](https://www.vsixcookbook.com/recipes/fonts-and-colors.html)
- [Font and Color Overview](https://learn.microsoft.com/previous-versions/visualstudio/visual-studio-2015/extensibility/font-and-color-overview)
- [Colors and Styling for Visual Studio](https://learn.microsoft.com/visualstudio/extensibility/ux-guidelines/colors-and-styling-for-visual-studio)
