---
name: integrating-language-servers
description: Add Language Server Protocol (LSP) support to Visual Studio extensions. Use when the user asks how to integrate a language server, create an LSP client, add language features via LSP, connect a language server to Visual Studio, implement ILanguageClient, create a LanguageServerProvider, add IntelliSense or diagnostics for a custom language via LSP, or wire up a language server executable. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Language Server Protocol (LSP) Extensions in Visual Studio

The Language Server Protocol (LSP) enables extensions to provide language features — IntelliSense, diagnostics, go-to-definition, find references, formatting, code actions, and more — by connecting Visual Studio to an external language server process that speaks LSP (JSON-RPC v2.0).

LSP is intended for adding support for **new languages** not already built into Visual Studio. It is _not_ designed to extend existing built-in languages like C# or C++.

LSP is the standard way to add full language support (completion, hover, diagnostics, navigation, formatting) for a language that VS doesn't natively support. The key benefit is architecture: your language server runs in a separate process and communicates over a well-defined protocol, meaning you can reuse the same server across VS Code, Sublime Text, and other editors. VS provides two integration models: in-process via MEF (`ILanguageClient`) and out-of-process via `LanguageServerProvider` (VisualStudio.Extensibility).

**When to use LSP vs. alternatives:**
- Full language support for a new language (completion, diagnostics, navigation, formatting) → **LSP** (this skill)
- Simple syntax coloring without full language support → TextMate grammar (see [vs-textmate-grammar](../adding-textmate-grammars/SKILL.md))
- Extending C#/VB with analyzers and code fixes → Roslyn `DiagnosticAnalyzer` / `CodeFixProvider`
- Adding completion to an existing language without a full server → [vs-editor-completion](../adding-intellisense-completion/SKILL.md)
- Inline metadata above code elements → CodeLens (see [vs-codelens](../adding-codelens-indicators/SKILL.md))

## File organization

```
MyExtension/
├── LanguageServer/
│   ├── MyLanguageServerProvider.cs    ← (VS.Extensibility) or MyLanguageClient.cs (VSSDK)
│   └── MyContentDefinition.cs         ← (VSSDK only) content type + file extension mapping
├── Grammars/                           ← optional TextMate grammar for syntax highlighting
│   ├── mylang.tmLanguage.json
│   └── mylang.tmTheme
├── Server/
│   └── my-language-server.exe          ← the LSP server binary (bundled or installed separately)
├── MyExtension.csproj
└── source.extension.vsixmanifest       ← (VSSDK only)
```

## Implementation checklist

- [ ] Create or obtain the language server executable
- [ ] Define the content type and file extension mapping
- [ ] Create the language server provider/client class
- [ ] Register in `.vsixmanifest` with MEF asset type (Toolkit/VSSDK only)
- [ ] Bundle the server binary in the VSIX

---

## 1. VisualStudio.Extensibility (out-of-process, recommended)

The VisualStudio.Extensibility SDK provides a `LanguageServerProvider` base class that runs out-of-process and communicates with the language server via an `IDuplexPipe`. No `.vsct` file, no MEF exports, no VSIX manifest assets — everything is declared in code.

> **Note:** This API is currently in preview. The `#pragma warning disable VSEXTPREVIEW_LSP` directive is required.

**NuGet package:** `Microsoft.VisualStudio.Extensibility`
**Key namespaces:** `Microsoft.VisualStudio.Extensibility.LanguageServer`, `Microsoft.VisualStudio.Extensibility.Editor`, `Microsoft.VisualStudio.RpcContracts.LanguageServerProvider`
**Additional dependency:** `Nerdbank.Streams` (for `FullDuplexStream` / `DuplexPipe`)

### Step 1: Define custom document types

If your language's file extensions are not natively recognized by Visual Studio, define custom document types inside your provider class:

```csharp
[VisualStudioContribution]
public static DocumentTypeConfiguration MyLangDocumentType => new("mylang")
{
    FileExtensions = [".mylang", ".ml"],
    BaseDocumentType = LanguageServerBaseDocumentType,
};
```

`LanguageServerBaseDocumentType` is a built-in base type available to all language server providers.

### Step 2: Create the language server provider

```csharp
using System.Diagnostics;
using System.IO;
using System.IO.Pipelines;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.Extensibility;
using Microsoft.VisualStudio.Extensibility.Editor;
using Microsoft.VisualStudio.Extensibility.LanguageServer;
using Microsoft.VisualStudio.RpcContracts.LanguageServerProvider;
using Nerdbank.Streams;

namespace MyExtension;

#pragma warning disable VSEXTPREVIEW_LSP // Type is for evaluation purposes only and is subject to change or removal in future updates.

[VisualStudioContribution]
internal class MyLanguageServerProvider : LanguageServerProvider
{
    [VisualStudioContribution]
    public static DocumentTypeConfiguration MyLangDocumentType => new("mylang")
    {
        FileExtensions = [".mylang", ".ml"],
        BaseDocumentType = LanguageServerBaseDocumentType,
    };

    public override LanguageServerProviderConfiguration LanguageServerProviderConfiguration =>
        new("My Language Server",
            [DocumentFilter.FromDocumentType(MyLangDocumentType)]);

    public override Task<IDuplexPipe?> CreateServerConnectionAsync(CancellationToken cancellationToken)
    {
        ProcessStartInfo info = new()
        {
            FileName = Path.Combine(
                Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!,
                "Server",
                "my-language-server.exe"),
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        Process process = new() { StartInfo = info };

        if (process.Start())
        {
            return Task.FromResult<IDuplexPipe?>(new DuplexPipe(
                PipeReader.Create(process.StandardOutput.BaseStream),
                PipeWriter.Create(process.StandardInput.BaseStream)));
        }

        return Task.FromResult<IDuplexPipe?>(null);
    }

    public override Task OnServerInitializationResultAsync(
        ServerInitializationResult startState,
        LanguageServerInitializationFailureInfo? initializationFailureInfo,
        CancellationToken cancellationToken)
    {
        if (startState == ServerInitializationResult.Failed)
        {
            // Disable the server so it won't try to activate again.
            this.Enabled = false;
        }

        return base.OnServerInitializationResultAsync(startState, initializationFailureInfo, cancellationToken);
    }
}

#pragma warning restore VSEXTPREVIEW_LSP
```

### Sending initialization options

Pass custom data to the server's `initialize` message by setting `LanguageServerOptions.InitializationOptions` in the constructor:

```csharp
public MyLanguageServerProvider(ExtensionCore container, VisualStudioExtensibility extensibilityObject, TraceSource traceSource)
    : base(container, extensibilityObject)
{
    this.LanguageServerOptions.InitializationOptions = JToken.Parse(@"{""myOption"": true}");
}
```

### Enabling / disabling at runtime

The `Enabled` property (default `true`) controls whether Visual Studio activates your server. Setting it to `false` sends a stop message to any running server and prevents future activations until set back to `true`.

### Localized display name

Use a `string-resources.json` file for localization:

```json
{
  "MyExtension.MyLanguageServerProvider.DisplayName": "My Language Server"
}
```

Then reference the token in your configuration:

```csharp
public override LanguageServerProviderConfiguration LanguageServerProviderConfiguration =>
    new("%MyExtension.MyLanguageServerProvider.DisplayName%",
        [DocumentFilter.FromDocumentType(MyLangDocumentType)]);
```

### Official sample

See the [Rust Language Server Provider sample](https://github.com/microsoft/VSExtensibility/tree/main/New_Extensibility_Model/Samples/RustLanguageServerProvider) for a complete working example.

---

## 2. VSIX Community Toolkit (in-process)

The Community Toolkit does not add a separate LSP API. Language server integration uses the same VSSDK `ILanguageClient` MEF-based approach described below. The toolkit can simplify package setup, but the LSP components are standard VSSDK APIs.

---

## 3. VSSDK (in-process)

### ⚠️ Use `ILanguageClient` — do NOT use the legacy `LanguageService` base class

Visual Studio has two approaches for language integration:

- **`ILanguageClient`** (LSP-based, current) — Uses the Language Server Protocol. You implement a thin MEF client that launches and connects to an external language server. **Use this approach.**
- **`Microsoft.VisualStudio.Package.LanguageService`** (legacy, pre-LSP) — Requires building a custom scanner/parser with `IScanner`, `ParseSource`, COM interop, and registry entries. **Do not use this approach for new extensions.** It predates LSP and is far more complex with no LSP interoperability.

### NuGet package and namespaces

**NuGet package:** [`Microsoft.VisualStudio.LanguageServer.Client`](https://www.nuget.org/packages/Microsoft.VisualStudio.LanguageServer.Client)
**Key namespace:** `Microsoft.VisualStudio.LanguageServer.Client`

> The package also brings in `Newtonsoft.Json` and `StreamJsonRpc`. **Do not** update these transitive packages beyond the versions shipped with your target Visual Studio version — the assemblies are loaded from the VS install directory, not from your VSIX.

### Step 1: Define the content type

Map your file extension to a content type. The base definition **must** derive from `CodeRemoteContentTypeName`:

```csharp
using System.ComponentModel.Composition;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

public static class MyLangContentDefinition
{
    [Export]
    [Name("mylang")]
    [BaseDefinition(CodeRemoteContentDefinition.CodeRemoteContentTypeName)]
    internal static ContentTypeDefinition MyLangContentTypeDefinition = null!;

    [Export]
    [FileExtension(".mylang")]
    [ContentType("mylang")]
    internal static FileExtensionToContentTypeDefinition MyLangFileExtensionDefinition = null!;
}
```

### Step 2: Implement `ILanguageClient`

```csharp
using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Threading;
using Microsoft.VisualStudio.Utilities;

namespace MyExtension;

[ContentType("mylang")]
[Export(typeof(ILanguageClient))]
public class MyLanguageClient : ILanguageClient
{
    public string Name => "My Language Extension";

    public IEnumerable<string>? ConfigurationSections => null;

    public object? InitializationOptions => null;

    public IEnumerable<string>? FilesToWatch => null;

    public event AsyncEventHandler<EventArgs>? StartAsync;
    public event AsyncEventHandler<EventArgs>? StopAsync;

    public async Task OnLoadedAsync()
    {
        if (StartAsync != null)
        {
            await StartAsync.InvokeAsync(this, EventArgs.Empty);
        }
    }

    public Task<Connection?> ActivateAsync(CancellationToken token)
    {
        var info = new ProcessStartInfo
        {
            FileName = Path.Combine(
                Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!,
                "Server",
                "my-language-server.exe"),
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        var process = new Process { StartInfo = info };

        if (process.Start())
        {
            return Task.FromResult<Connection?>(
                new Connection(
                    process.StandardOutput.BaseStream,
                    process.StandardInput.BaseStream));
        }

        return Task.FromResult<Connection?>(null);
    }

    public Task OnServerInitializedAsync()
    {
        return Task.CompletedTask;
    }

    public Task OnServerInitializeFailedAsync(Exception e)
    {
        return Task.CompletedTask;
    }
}
```

### Step 3: Register the MEF asset

In `source.extension.vsixmanifest`, add this inside the `<Assets>` element:

```xml
<Asset Type="Microsoft.VisualStudio.MefComponent"
       d:Source="Project"
       d:ProjectName="%CurrentProject%"
       Path="|%CurrentProject%|" />
```

Without this, Visual Studio will not discover your MEF-exported `ILanguageClient`.

### Activation lifecycle

1. Visual Studio calls `OnLoadedAsync()`.
2. Your code invokes the `StartAsync` event to signal "ready to start."
3. Visual Studio calls `ActivateAsync()` — you launch the server process and return a `Connection` wrapping stdin/stdout streams.
4. Visual Studio sends `initialize` / `initialized` LSP messages over the connection.
5. Visual Studio calls `OnServerInitializedAsync()` (or `OnServerInitializeFailedAsync` on failure).

### Transport options

The `Connection` class accepts any pair of streams. Common transports:

| Transport | How to connect |
|-----------|---------------|
| **stdio** | Redirect `StandardInput` / `StandardOutput` of the server process |
| **Named pipe** | Use `NamedPipeClientStream` for both read and write |
| **TCP socket** | Use `TcpClient.GetStream()` |

### Providing settings to the language server

1. Implement `ConfigurationSections` to return setting prefixes (e.g., `"mylang"`).
2. Bundle a default settings JSON file (e.g., `MyLangSettings.json`) as VSIX content.
3. Add a `.pkgdef` file registering the settings file:
   ```
   [$RootKey$\OpenFolder\Settings\VSWorkspaceSettings\MyLangExtension]
   @="$PackageFolder$\MyLangSettings.json"
   ```
4. Register the `.pkgdef` as a `Microsoft.VisualStudio.VsPackage` asset in the VSIX manifest.

Users override settings by creating a `.vs/VSWorkspaceSettings.json` file in their workspace.

### Custom messages (beyond standard LSP)

Implement `ILanguageClientCustomMessage2` on your language client class for custom JSON-RPC messages:

```csharp
[ContentType("mylang")]
[Export(typeof(ILanguageClient))]
public class MyLanguageClient : ILanguageClient, ILanguageClientCustomMessage2
{
    private JsonRpc? customMessageRpc;

    public object? CustomMessageTarget { get; } = new MyCustomMessageTarget();

    public Task AttachForCustomMessageAsync(JsonRpc rpc)
    {
        this.customMessageRpc = rpc;
        return Task.CompletedTask;
    }

    // ... rest of ILanguageClient implementation
}
```

### Middle layer (intercepting LSP messages)

Use `ILanguageClientMiddleLayer2<T>` to intercept and modify LSP messages between VS and the server. **Do not** use the obsolete `ILanguageClientMiddleLayer` interface — it will be removed in a future version.

```csharp
public class MyMiddleLayer : ILanguageClientMiddleLayer2<JToken>
{
    public bool CanHandle(string methodName) =>
        methodName == "textDocument/publishDiagnostics";

    public Task HandleNotificationAsync(string methodName, JToken methodParam, Func<JToken, Task> sendNotification)
    {
        // Filter or modify diagnostics before they reach VS
        return sendNotification(methodParam);
    }

    public Task<JToken?> HandleRequestAsync(string methodName, JToken methodParam, Func<JToken, Task<JToken?>> sendRequest)
    {
        return sendRequest(methodParam);
    }
}
```

### TextMate grammar for syntax highlighting

LSP does not define syntax colorization. To provide highlighting, bundle a TextMate grammar:

1. Add a `Grammars/` folder with `.tmLanguage.json` (or `.tmLanguage`, `.plist`) and optional `.tmTheme` files.
2. Add a `.pkgdef` to register the grammar repository:
   ```
   [$RootKey$\TextMate\Repositories]
   "MyLang"="$PackageFolder$\Grammars"
   ```
3. Set all grammar files and the `.pkgdef` to **Build Action = Content** and **Include in VSIX = true**.

### Supported LSP features in Visual Studio

| LSP feature | Supported |
|---|---|
| `initialize` / `initialized` / `shutdown` / `exit` | Yes |
| `textDocument/completion` + `completionItem/resolve` | Yes |
| `textDocument/hover` | Yes |
| `textDocument/signatureHelp` | Yes |
| `textDocument/definition` | Yes |
| `textDocument/references` | Yes |
| `textDocument/documentHighlight` | Yes |
| `textDocument/documentSymbol` | Yes |
| `textDocument/codeAction` | Yes |
| `textDocument/formatting` / `rangeFormatting` | Yes |
| `textDocument/rename` | Yes |
| `textDocument/publishDiagnostics` | Yes |
| `workspace/symbol` | Yes |
| `workspace/executeCommand` | Yes |
| `workspace/applyEdit` | Yes |
| `window/showMessage` / `showMessageRequest` / `logMessage` | Yes |
| `textDocument/codeLens` / `codeLens/resolve` | No |
| `textDocument/documentLink` / `documentLink/resolve` | No |
| `textDocument/onTypeFormatting` | No |

### Official samples

- VSSDK sample: [VSSDK-Extensibility-Samples/LanguageServerProtocol](https://github.com/Microsoft/VSSDK-Extensibility-Samples/tree/master/LanguageServerProtocol)

---

## Troubleshooting

- **Language server doesn't activate:** For VSSDK, verify the `MefComponent` asset type is in `.vsixmanifest`. For Extensibility, confirm your `LanguageServerProvider` has the correct `[VisualStudioContribution]` attribute and `DocumentFilter` matches your content type.
- **`MissingMethodException` or `TypeLoadException` at runtime:** You've updated `Newtonsoft.Json` or `StreamJsonRpc` beyond the version shipped with your target VS. Pin to the VS-bundled version and use binding redirects if your server needs a different version.
- **Diagnostics not appearing in Error List:** Ensure your server publishes `textDocument/publishDiagnostics` notifications. Verify the `ContentType` on your `ILanguageClient` matches the file type, and that the document URI format matches what VS expects (file:///C:/...).
- **Completion items show but selecting one inserts wrong text:** Check `completionItem/resolve` — VS calls resolve lazily. If your server doesn't implement it, VS uses the `label` field as the insert text.
- **Server starts but no features work:** Check the LSP `initialize` response capabilities. VS only activates features your server declares in its capabilities object.
- **Syntax highlighting missing even though LSP is working:** LSP doesn't define syntax colorization. Bundle a TextMate grammar (see [vs-textmate-grammar](../adding-textmate-grammars/SKILL.md)).

## See also

- [vs-textmate-grammar](../adding-textmate-grammars/SKILL.md)
- [vs-editor-completion](../adding-intellisense-completion/SKILL.md)
- [vs-codelens](../adding-codelens-indicators/SKILL.md)
- [vs-error-list](../integrating-error-list/SKILL.md)
- [vs-editor-quickinfo](../adding-quickinfo-tooltips/SKILL.md)

## Key links

> **Do NOT** use the legacy `LanguageService` base class (from `Microsoft.VisualStudio.Package`) — pre-LSP, far more complex, and unmaintained. Use `ILanguageClient` (VSSDK) or `LanguageServerProvider` (Extensibility). Old docs may reference it; do not follow.

> **Do NOT** use `ILanguageClientMiddleLayer` (non-generic) — obsolete. Use `ILanguageClientMiddleLayer2<T>` instead.

> **Do NOT** update `Newtonsoft.Json` or `StreamJsonRpc` beyond VS-shipped versions — version mismatches cause `MissingMethodException` or silent protocol failures.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest` for VSSDK `ILanguageClient` — without it, the language server never activates.

> **Do NOT** use `ISuggestedAction` or custom taggers for diagnostics in LSP languages — use `textDocument/publishDiagnostics` and `textDocument/codeAction` instead.

> **Do NOT** confuse LSP with extending built-in VS languages (C#, C++, F#) — LSP is for **new** languages. Use Roslyn analyzers for C#/VB.

- [Add an LSP extension (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/adding-an-lsp-extension)
- [Language Server Provider (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/language-server-provider/language-server-provider)
- [Language Configuration (for local editor features)](https://learn.microsoft.com/visualstudio/extensibility/language-configuration)
- [Language Server Protocol specification](https://github.com/Microsoft/language-server-protocol)
