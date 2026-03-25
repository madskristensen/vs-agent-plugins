---
name: vs-language-server
description: Add Language Server Protocol (LSP) support to Visual Studio extensions. Use when the user asks how to integrate a language server, create an LSP client, add language features via LSP, connect a language server to Visual Studio, implement ILanguageClient, create a LanguageServerProvider, add IntelliSense or diagnostics for a custom language via LSP, or wire up a language server executable. Covers VisualStudio.Extensibility (out-of-process), VSIX Community Toolkit (in-process), and legacy VSSDK (in-process) approaches.
---

# Language Server Protocol (LSP) Extensions in Visual Studio

The Language Server Protocol (LSP) enables extensions to provide language features — IntelliSense, diagnostics, go-to-definition, find references, formatting, code actions, and more — by connecting Visual Studio to an external language server process that speaks LSP (JSON-RPC v2.0).

LSP is intended for adding support for **new languages** not already built into Visual Studio. It is _not_ designed to extend existing built-in languages like C# or C++.

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

## Key links

> **Do NOT** use the legacy `LanguageService` base class (from `Microsoft.VisualStudio.Package`). It is a pre-LSP API that requires building custom scanners, parsers, and completion sources from scratch. It is far more complex, does not support the Language Server Protocol, and is not maintained. Use `ILanguageClient` (VSSDK) or `LanguageServerProvider` (Extensibility) instead. Old documentation and university course materials may still reference `LanguageService` — do not follow them.

> **Do NOT** use `ILanguageClientMiddleLayer` (non-generic). It is **obsolete**. Use `ILanguageClientMiddleLayer2<T>` instead, which provides strongly-typed middleware interception.

> **Do NOT** update `Newtonsoft.Json` or `StreamJsonRpc` NuGet packages beyond the versions shipped with your target Visual Studio version. These packages are used internally by VS for LSP communication. Version mismatches cause `MissingMethodException`, `TypeLoadException`, or silent protocol failures at runtime. Use binding redirects if your language server requires different versions.

> **Do NOT** forget the `MefComponent` asset type in `.vsixmanifest` for the VSSDK `ILanguageClient` approach. Without it, your MEF-exported `ILanguageClient` is silently ignored and the language server never activates.

> **Do NOT** use `ISuggestedAction` or custom taggers for diagnostics in languages that have an LSP server. Use `textDocument/publishDiagnostics` from LSP — it integrates with the Error List, provides squiggles, and supports code actions through `textDocument/codeAction`.

> **Do NOT** confuse LSP with extending built-in VS languages (C#, C++, F#). LSP is for adding support for **new** languages. To extend C#/VB, use Roslyn analyzers and code fix providers. To extend C++, use the vcpkg/MSBuild extensibility model.

- [Add an LSP extension (VSSDK)](https://learn.microsoft.com/visualstudio/extensibility/adding-an-lsp-extension)
- [Language Server Provider (VisualStudio.Extensibility)](https://learn.microsoft.com/visualstudio/extensibility/visualstudio.extensibility/language-server-provider/language-server-provider)
- [Language Configuration (for local editor features)](https://learn.microsoft.com/visualstudio/extensibility/language-configuration)
- [Language Server Protocol specification](https://github.com/Microsoft/language-server-protocol)
