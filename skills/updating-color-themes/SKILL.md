---
name: updating-color-themes
description: 'Add Fluent design system color support to VS theme (.vstheme) files. Use for: vstheme, color theme, fluent theme colors, Shell category, ShellInternal category, AccentFillDefault, EnvironmentBackground, theme pack, custom theme, theme extension, add fluent colors, missing shell colors, theme color tokens.'
---

# Adding Fluent Color Support to VS Themes

## When to Use

- A custom `.vstheme` file (e.g., in the VisualStudioThemePack repo) needs Fluent design system colors.
- A theme is missing the `Shell` and/or `ShellInternal` categories in the file.
- VS controls render with wrong or fallback colors in a custom theme because Fluent tokens are absent.

## Background

VS Fluent controls read colors from two categories that did **not** exist in the legacy theme format:

| Category        | GUID                                     | Purpose                                                                                                      |
| --------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `Shell`         | `{73708ded-2d56-4aad-b8eb-73b20d3f4bff}` | Public Fluent design tokens (accent fills, control fills, text fills, strokes, surfaces, system fills, etc.) |
| `ShellInternal` | `{5af241b7-5627-4d12-bfb1-2b67d11127d7}` | Internal tokens (environment chrome colors, status bar fills, caption controls)                              |

### FallbackId

A custom theme's `<Theme>` element can specify a `FallbackId` attribute pointing to a built-in theme GUID. Any color token the custom theme does **not** define will fall back to that built-in theme's value. This means a custom theme only needs to define the subset of Shell/ShellInternal colors that differ from the fallback.

Built-in theme GUIDs for fallback:

| Theme | GUID                                     |
| ----- | ---------------------------------------- |
| Light | `{de3dbbcd-f642-433c-8353-8f1df4370aba}` |
| Dark  | `{1ded0138-47ce-435e-84ef-9ec1f439b749}` |

If the theme does not have a `FallbackId`, add one. Choose the built-in theme whose overall luminosity is closest to the custom theme (dark-background themes fall back to Dark, light-background themes fall back to Light).

## Procedure

### Step 1: Determine the Theme Variant

Check the `EnvironmentBackground` color in the Environment category (`{624ed9c3-bdfd-41fa-96c3-7c824ea32e3d}`). A dark background means the theme is dark-variant; a light background means light-variant. This determines:

- Which `FallbackId` to use if one is needed.

### Step 2: Ensure FallbackId Is Set

If the `<Theme>` element does not already have a `FallbackId` attribute, add one:

```xml
<Theme Name="MyTheme" GUID="{...}" FallbackId="{1ded0138-47ce-435e-84ef-9ec1f439b749}">
```

With a fallback, the theme inherits all Shell/ShellInternal colors from the built-in theme by default. You then only need to override the tokens that should differ.

### Step 3: Add the Shell Category

Add a `<Category Name="Shell" GUID="{73708ded-2d56-4aad-b8eb-73b20d3f4bff}">` block near the bottom of the file (before `</Theme>`). Include at minimum the following tokens, which are the ones most visible in the Fluent chrome:

#### Required Shell Tokens

| Token Name                      | How to Derive                                                                                                                                     | Notes                                           |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `AccentFillDefault`             | Take the `MainWindowActiveCaption` color (from the Environment category), but use the inverse luminosity of `EnvironmentBackground` in HSL space. | This is the theme's primary accent/brand color. |
| `AccentFillSecondary`           | Same RGB as `AccentFillDefault` but with alpha `E5`.                                                                                              | Hover state of accent.                          |
| `AccentFillTertiary`            | Same RGB as `AccentFillDefault` but with alpha `CC`.                                                                                              | Pressed state of accent.                        |
| `SolidBackgroundFillTertiary`   | Copy from Environment → `ToolWindowBackground`.                                                                                                   | Tool window surface.                            |
| `SolidBackgroundFillQuaternary` | Copy from Environment → `EnvironmentBackground`.                                                                                                  | Main IDE background.                            |
| `SurfaceBackgroundFillDefault`  | Copy from Environment → `CommandBarMenuBackgroundGradientBegin`.                                                                                  | Popup/flyout surface.                           |

#### Example (dark red theme)

```xml
<Category Name="Shell" GUID="{73708ded-2d56-4aad-b8eb-73b20d3f4bff}">
  <!-- Based from Environment category: MainWindowActiveCaption but the inverse luminosity of the EnvironmentBackground when in the HSL space -->
  <Color Name="AccentFillDefault">
    <Background Type="CT_RAW" Source="FFCC0000" />
  </Color>
  <!-- Copied from AccentFillDefault but with E5 alpha -->
  <Color Name="AccentFillSecondary">
    <Background Type="CT_RAW" Source="E5CC0000" />
  </Color>
  <!-- Copied from AccentFillDefault but with CC alpha -->
  <Color Name="AccentFillTertiary">
    <Background Type="CT_RAW" Source="CCCC0000" />
  </Color>
  <!-- Copied from Environment category: ToolWindowBackground -->
  <Color Name="SolidBackgroundFillTertiary">
    <Background Type="CT_RAW" Source="FF390000" />
  </Color>
  <!-- Copied from Environment category: EnvironmentBackground -->
  <Color Name="SolidBackgroundFillQuaternary">
    <Background Type="CT_RAW" Source="FF330000" />
  </Color>
  <!-- Copied from Environment category: CommandBarMenuBackgroundGradientBegin -->
  <Color Name="SurfaceBackgroundFillDefault">
    <Background Type="CT_RAW" Source="FF580000" />
  </Color>
</Category>
```

### Step 4: Add the ShellInternal Category

Add a `<Category Name="ShellInternal" GUID="{5af241b7-5627-4d12-bfb1-2b67d11127d7}">` block immediately after the Shell category. Include the following tokens:

#### Required ShellInternal Tokens

| Token Name                    | How to Derive                                                                                                        | Notes                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `EnvironmentBackground`       | Copy from Environment → `MainWindowActiveCaption` (background).                                                      | Used for active window chrome. |
| `EnvironmentBody`             | Copy from Environment → `EnvironmentBackground`.                                                                     | Used for main body area.       |
| `EnvironmentBorder`           | Same value as `AccentFillDefault`.                                                                                   | Active window border accent.   |
| `EnvironmentHeader`           | Copy from Environment → `TitleBarActiveGradientBegin`.                                                               | Active title bar surface.      |
| `EnvironmentHeaderInactive`   | Copy from Environment → `TitleBarInactiveGradientBegin`.                                                             | Inactive title bar surface.    |
| `EnvironmentIndicator`        | Copy from Environment → `AutoHideTabBorder`. If not defined, use `TitleBarInactiveGradientBegin`.                    | Auto-hide tab indicator.       |
| `EnvironmentLogo`             | Copy from Environment → `MainWindowInactiveIconDefault`. If not defined, use `MainWindowActiveCaption` (foreground). | VS logo color in title bar.    |
| `EnvironmentTab`              | Copy from Environment → `FileTabSelectedBackground`.                                                                 | Active document tab.           |
| `EnvironmentTabInactive`      | Copy from Environment → `FileTabInactiveGradientTop`.                                                                | Inactive document tab.         |
| `StatusBarBackgroundFillRest` | Copy from Environment → `StatusBarDefault` (background).                                                             | Status bar background at rest. |
| `StatusBarTextFillRest`       | Copy from Environment → `StatusBarDefault` (foreground).                                                             | Status bar text at rest.       |

#### Example (dark red theme)

```xml
<Category Name="ShellInternal" GUID="{5af241b7-5627-4d12-bfb1-2b67d11127d7}">
  <!-- Copied from Environment category: MainWindowActiveCaption -->
  <Color Name="EnvironmentBackground">
    <Background Type="CT_RAW" Source="FF770000" />
  </Color>
  <!-- Copied from Environment category: EnvironmentBackground -->
  <Color Name="EnvironmentBody">
    <Background Type="CT_RAW" Source="FF330000" />
  </Color>
  <!-- Same as AccentFillDefault -->
  <Color Name="EnvironmentBorder">
    <Background Type="CT_RAW" Source="FFCC0000" />
  </Color>
  <!-- Copied from Environment category: TitleBarActiveGradientBegin -->
  <Color Name="EnvironmentHeader">
    <Background Type="CT_RAW" Source="FF330000" />
  </Color>
  <!-- Copied from Environment category: TitleBarInactiveGradientBegin -->
  <Color Name="EnvironmentHeaderInactive">
    <Background Type="CT_RAW" Source="FF770000" />
  </Color>
  <!-- Copied from Environment category: AutoHideTabBorder or TitleBarInactiveGradientBegin if the previous is not defined -->
  <Color Name="EnvironmentIndicator">
    <Background Type="CT_RAW" Source="FF770000" />
  </Color>
  <!-- Copied from Environment category: MainWindowInactiveIconDefault or MainWindowActiveCaption (foreground) if the previous is not defined -->
  <Color Name="EnvironmentLogo">
    <Background Type="CT_RAW" Source="FFCCCCCC" />
  </Color>
  <!-- Copied from Environment category: FileTabSelectedBackground -->
  <Color Name="EnvironmentTab">
    <Background Type="CT_RAW" Source="FF490000" />
  </Color>
  <!-- Copied from Environment category: FileTabInactiveGradientTop -->
  <Color Name="EnvironmentTabInactive">
    <Background Type="CT_RAW" Source="FF300A0A" />
  </Color>
  <!-- Copied from Environment category: StatusBarDefault (background) -->
  <Color Name="StatusBarBackgroundFillRest">
    <Background Type="CT_RAW" Source="FF700000" />
  </Color>
  <!-- Copied from Environment category: StatusBarDefault (foreground) -->
  <Color Name="StatusBarTextFillRest">
    <Background Type="CT_RAW" Source="FFFFFFFF" />
  </Color>
</Category>
```

### Step 5: Add Comments

Every `<Color>` entry in Shell and ShellInternal **must** have an XML comment above it explaining how the color was derived. This is critical for future maintenance — without the comment, nobody knows how to update the color if the source color changes. Use the exact comment format shown in the examples above.

## Deriving the Accent Color (Inverse Luminosity)

The `AccentFillDefault` color is derived from `MainWindowActiveCaption` but uses the inverse luminosity of `EnvironmentBackground` in HSL color space. The procedure:

1. Parse the `EnvironmentBackground` ARGB hex value (e.g., `FF330000` → R=0x33, G=0x00, B=0x00).
2. Convert RGB to HSL to get the luminosity L.
3. Invert the L component: `L_new = 1.0 - L_old`.
4. Parse the `MainWindowActiveCaption` ARGB hex value and convert to HSL to get the hue H and saturation S.
5. Combine H and S from `MainWindowActiveCaption` with the inverted L from step 3.
6. Convert back to RGB.
7. Format as `AARRGGBB` with alpha `FF`.

For `AccentFillSecondary` and `AccentFillTertiary`, use the same RGB but change the alpha byte:

- Secondary: `E5` (≈90% opaque)
- Tertiary: `CC` (≈80% opaque)

## Color Format

All colors use the `CT_RAW` type with `AARRGGBB` hex format:

- `AA` = alpha (FF = fully opaque, 00 = fully transparent)
- `RR` = red
- `GG` = green
- `BB` = blue

## Testing

After adding the colors, install the theme extension in VS and verify:

1. The title bar, window borders, and status bar use the expected accent color.
2. Tool window backgrounds match the theme.
3. Document tabs (active and inactive) look correct.
4. Fluent controls (buttons, checkboxes, text boxes) render with proper accent colors rather than falling back to the built-in theme's accent.

## Anti-Patterns

| Anti-Pattern                                         | Why It's Wrong                                                                           |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Copying all ~90 Shell tokens from the built-in theme | Unnecessary — use `FallbackId` and only override what differs.                           |
| Using `CT_SYSCOLOR` or `CT_VSCOLOR` for Shell tokens | Shell/ShellInternal tokens must use `CT_RAW` — they are absolute colors, not references. |
| Hardcoding accent colors without HSL derivation      | The accent should be a luminosity-inverted version of the background to ensure contrast. |
