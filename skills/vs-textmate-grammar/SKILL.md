---
name: vs-textmate-grammar
description: Add lightweight syntax highlighting for custom languages in Visual Studio using TextMate grammars. Use when the user asks how to add colorization for a new language, ship a .tmlanguage file, create a TextMate bundle, register a grammar with a pkgdef, or provide basic editor support (syntax coloring, bracket matching) for a file extension without writing a full classifier. Covers VSSDK / VSIX Community Toolkit (in-process). VisualStudio.Extensibility (out-of-process) does not have a dedicated TextMate grammar API.
---

# TextMate Grammars in Visual Studio Extensions

TextMate grammars provide lightweight syntax highlighting, bracket matching, and basic statement completion for custom languages — without writing a full MEF classifier. Visual Studio uses the TextMate engine internally for dozens of languages (Rust, Go, Markdown, YAML, etc.).

A TextMate grammar is a `.tmlanguage`, `.plist`, or `.json` file that defines regex-based scope rules. You bundle it in a VSIX extension, register it with a `.pkgdef` file, and Visual Studio picks it up for any matching file extension.

## When to use TextMate vs. a full classifier

| Approach | Best for |
|----------|----------|
| **TextMate grammar** | Quick syntax coloring for a new file type; porting an existing VS Code / Sublime grammar; no compiled code needed |
| **MEF IClassifier** (see `vs-editor-classifier` skill) | Full control over classification spans; dynamic/context-dependent highlighting; custom classification types with user-configurable colors |
| **Language Server Protocol** | Full IntelliSense, diagnostics, go-to-definition, etc. — LSP extensions can also bundle a TextMate grammar for colorization |

## VisualStudio.Extensibility (out-of-process)

**Not directly supported.** The new extensibility model does not provide a TextMate grammar registration API. However, TextMate grammar files are loaded by the VS editor host, so an in-process hybrid extension (or a standalone VSIX that only contains the grammar + pkgdef) works alongside VisualStudio.Extensibility extensions. If you are building an LSP-based language extension with the new model, you can pair it with a TextMate grammar VSIX for colorization.

---

## VSSDK / VSIX Community Toolkit (in-process)

The Toolkit and VSSDK approaches are identical — TextMate grammar registration is purely declarative (no compiled C# code needed beyond the VSIX project shell).

**NuGet packages:** `Microsoft.VisualStudio.SDK` (≥ 17.0) — only needed for the VSIX project infrastructure. No runtime API calls are required.

### File organization

```
MyLanguageGrammar/
├── Grammars/
│   ├── mylang.tmLanguage.json    ← TextMate grammar definition
│   └── mylang.tmTheme            ← (optional) custom theme mapping
├── Resources/
│   └── LICENSE
├── languages.pkgdef              ← registers grammar + file associations
├── source.extension.vsixmanifest
└── MyLanguageGrammar.csproj
```

### Step 1 — Create the TextMate grammar file

Place your `.tmLanguage.json` (or `.tmlanguage`, `.plist`, `.json`) file in a `Grammars/` folder.

**Grammars/mylang.tmLanguage.json:**

```json
{
  "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  "name": "MyLang",
  "scopeName": "source.mylang",
  "fileTypes": ["mylang", "ml"],
  "patterns": [
    { "include": "#comments" },
    { "include": "#keywords" },
    { "include": "#strings" },
    { "include": "#numbers" }
  ],
  "repository": {
    "comments": {
      "patterns": [
        {
          "name": "comment.line.double-slash.mylang",
          "match": "//.*$"
        },
        {
          "name": "comment.block.mylang",
          "begin": "/\\*",
          "end": "\\*/"
        }
      ]
    },
    "keywords": {
      "patterns": [
        {
          "name": "keyword.control.mylang",
          "match": "\\b(if|else|while|for|return|func|var|let|const)\\b"
        },
        {
          "name": "keyword.other.mylang",
          "match": "\\b(import|export|module)\\b"
        }
      ]
    },
    "strings": {
      "patterns": [
        {
          "name": "string.quoted.double.mylang",
          "begin": "\"",
          "end": "\"",
          "patterns": [
            {
              "name": "constant.character.escape.mylang",
              "match": "\\\\."
            }
          ]
        },
        {
          "name": "string.quoted.single.mylang",
          "begin": "'",
          "end": "'",
          "patterns": [
            {
              "name": "constant.character.escape.mylang",
              "match": "\\\\."
            }
          ]
        }
      ]
    },
    "numbers": {
      "patterns": [
        {
          "name": "constant.numeric.mylang",
          "match": "\\b[0-9]+(\\.[0-9]+)?\\b"
        }
      ]
    }
  }
}
```

### Common TextMate scope names

Use standard scope names so VS maps them to built-in classification colors automatically:

| Scope name | VS color |
|------------|----------|
| `comment.line.*` | Green (comment) |
| `comment.block.*` | Green (comment) |
| `keyword.control.*` | Blue (keyword) |
| `keyword.other.*` | Blue (keyword) |
| `string.quoted.*` | Red/brown (string) |
| `constant.numeric.*` | Light green (number) |
| `constant.language.*` | Blue (true/false/null) |
| `entity.name.function.*` | Yellow (method name) |
| `entity.name.type.*` | Teal (type name) |
| `variable.other.*` | Default text |
| `storage.type.*` | Blue (int, string, etc.) |
| `support.function.*` | Yellow (built-in functions) |

### Step 2 — Create the pkgdef registration file

The `.pkgdef` file tells Visual Studio where to find the grammar and which file extensions to associate.

**languages.pkgdef:**

```
// Register the Grammars folder as a TextMate repository
[$RootKey$\TextMate\Repositories]
"MyLang"="$PackageFolder$\Grammars"

// Associate file extensions with a language name and icon
[$RootKey$\Languages\Language Services\MyLang]
"Package"="{e0d8864a-d944-4100-a278-5c29ae219e4d}"

// Map file extensions to the language
[$RootKey$\Languages\File Extensions\.mylang]
@="MyLang"

[$RootKey$\Languages\File Extensions\.ml]
@="MyLang"
```

The first entry (`TextMate\Repositories`) is the critical one — it points VS to the folder containing `.tmlanguage` / `.json` grammar files. VS will scan all files in that folder.

### Step 3 — Set file properties in the .csproj

All grammar files and the pkgdef must be included in the VSIX as content:

```xml
<ItemGroup>
  <!-- TextMate grammar files -->
  <Content Include="Grammars\mylang.tmLanguage.json">
    <IncludeInVSIX>true</IncludeInVSIX>
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  </Content>

  <!-- pkgdef registration -->
  <Content Include="languages.pkgdef">
    <IncludeInVSIX>true</IncludeInVSIX>
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  </Content>
</ItemGroup>
```

### Step 4 — Add pkgdef as an asset in the VSIX manifest

In `source.extension.vsixmanifest`, add the pkgdef as a `VsPackage` asset:

```xml
<Assets>
  <Asset Type="Microsoft.VisualStudio.VsPackage" d:Source="File" Path="languages.pkgdef" />
</Assets>
```

### Optional — Custom theme mapping

If you want to customize how scopes map to VS classification colors, add a `.tmTheme` file:

**Grammars/mylang.tmTheme:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key>
  <string>MyLang Theme</string>
  <key>settings</key>
  <array>
    <dict>
      <key>scope</key>
      <string>keyword.control.mylang</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>#569CD6</string>
      </dict>
    </dict>
    <dict>
      <key>scope</key>
      <string>entity.name.function.mylang</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>#DCDCAA</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

Place it in the `Grammars/` folder alongside the grammar — VS discovers it automatically.

### Step 5 — Add a language-configuration.json file (optional but recommended)

A `language-configuration.json` file tells Visual Studio how to handle editor behaviors — comment toggling, bracket matching, auto-closing pairs, and indentation — for your language. Without it, you get colorization but no smart editing behaviors.

**Grammars/language-configuration.json:**

```json
{
  "comments": {
    "lineComment": "//",
    "blockComment": ["/*", "*/"]
  },
  "brackets": [
    ["{", "}"],
    ["[", "]"],
    ["(", ")"]
  ],
  "autoClosingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "(", "close": ")" },
    { "open": "\"", "close": "\"", "notIn": ["string"] },
    { "open": "'", "close": "'", "notIn": ["string"] }
  ],
  "surroundingPairs": [
    ["{", "}"],
    ["[", "]"],
    ["(", ")"],
    ["\"", "\""],
    ["'", "'"]
  ]
}
```

#### Language configuration properties

| Property | Description |
|----------|-------------|
| `comments.lineComment` | The character(s) that toggle a line comment (Ctrl+K, Ctrl+C) |
| `comments.blockComment` | Start/end tokens for block comments |
| `brackets` | Bracket pairs for matching and highlighting |
| `autoClosingPairs` | Pairs that auto-close when the opening character is typed. Use `notIn` to suppress inside `"string"` or `"comment"` scopes |
| `surroundingPairs` | Pairs used when wrapping a selection |
| `wordPattern` | Regex defining what constitutes a "word" for double-click selection and word navigation |
| `indentationRules` | `increaseIndentPattern` / `decreaseIndentPattern` regexes for auto-indent |
| `onEnterRules` | Rules that run when Enter is pressed (e.g. continue line comments) |

#### Register the language configuration in your pkgdef

Add a `GrammarMapping` entry that maps your grammar's `scopeName` to the configuration file:

```
[$RootKey$\TextMate\LanguageConfiguration\GrammarMapping]
"source.mylang"="$PackageFolder$\Grammars\language-configuration.json"
```

This goes in the same `languages.pkgdef` file alongside the `TextMate\Repositories` entry.

#### Include in the VSIX

In the `.csproj`, add the file as content:

```xml
<Content Include="Grammars\language-configuration.json">
  <IncludeInVSIX>true</IncludeInVSIX>
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
</Content>
```

---

### Pairing TextMate grammars with Language Server Protocol

When building an LSP extension, TextMate provides the colorization layer while the language server provides IntelliSense, diagnostics, etc. In your LSP extension project:

1. Add a `Grammars/` folder with your `.tmlanguage.json` file.
2. Add the `languages.pkgdef` with the `TextMate\Repositories` registration.
3. Define a `ContentTypeDefinition` for the file extension (required by the LSP client).

The LSP docs cover the TextMate + LSP pairing pattern in detail: [Adding an LSP extension — TextMate grammar files](https://learn.microsoft.com/en-us/visualstudio/extensibility/adding-an-lsp-extension?view=vs-2022).

### Porting a VS Code grammar

Most VS Code language extensions contain a `syntaxes/` folder with `.tmLanguage.json` files that are directly compatible with Visual Studio:

1. Copy the `.tmLanguage.json` file into your `Grammars/` folder.
2. Verify `scopeName` and `fileTypes` are correct.
3. Create the `languages.pkgdef` to register extensions.
4. VS Code `.tmTheme` files are also compatible — copy them into `Grammars/` if needed.

> **Note:** VS Code snippets, commands, and `package.json` contributions are NOT compatible — only the grammar and theme files work in VS.

### User-local grammars (no extension required)

Users can add TextMate grammars without installing a VSIX by dropping files into:

```
%userprofile%\.vs\Extensions\<language-name>\Syntaxes\
```

This is useful for personal use but not for distribution.

### Testing

1. Press **Ctrl+F5** to launch the experimental instance.
2. Open or create a file with your registered extension (e.g. `.mylang`).
3. Verify syntax highlighting appears correctly.
4. If colors don't show, close and reopen the file — the grammar is loaded on first file open.

---

## Related documentation

- [Add Visual Studio editor support for other languages](https://learn.microsoft.com/en-us/visualstudio/ide/adding-visual-studio-editor-support-for-other-languages?view=vs-2022)
- [VSSDK TextMate Grammar sample](https://github.com/Microsoft/VSSDK-Extensibility-Samples/tree/master/TextmateGrammar)
- [TextMate Grammar Template (Marketplace)](https://marketplace.visualstudio.com/items?itemName=MadsKristensen.TextmateGrammarTemplate)
- [TextMate language grammar reference](https://manual.macromates.com/en/language_grammars)
- [Language Configuration for editor behaviors](https://learn.microsoft.com/en-us/visualstudio/extensibility/language-configuration?view=vs-2022)
