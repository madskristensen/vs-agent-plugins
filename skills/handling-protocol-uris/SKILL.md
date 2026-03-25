---
name: handling-protocol-uris
description: Handle custom URI protocol deep links (e.g. myext://open/file) in Visual Studio extensions. Use when the user asks how to register a custom protocol, handle a URI scheme, launch Visual Studio from a URL, implement deep linking, or respond to command-line switches triggered by protocol associations. Covers VSSDK / VSIX Community Toolkit (in-process). VisualStudio.Extensibility (out-of-process) does not have a dedicated protocol handler API.
---

# Custom Protocol Handlers in Visual Studio Extensions

A protocol handler lets you register a custom URI scheme (e.g. `myext://action/param`) with Windows so that clicking such a link in a browser, email, or another app launches Visual Studio and passes the URI to your extension for processing.

Protocol handlers enable deep linking into your extension from external sources. This is useful for CI/CD dashboards that link to specific code locations, issue trackers that open VS with context, or onboarding flows that configure the IDE with one click. Without a protocol handler, users must manually open VS, navigate to the right file, and apply settings themselves.

**When to use this vs. alternatives:**
- Deep link from browser/email/external app into VS → **Protocol handler** (this skill)
- Respond to solution/project open/close events → [vs-solution-events](../handling-solution-events/SKILL.md)
- Add command-line launch arguments for automation → `ProvideAppCommandLine` (covered in this skill)
- Open files or documents programmatically from within VS → [vs-file-document-ops](../managing-files-documents/SKILL.md)

## How it works

1. A JSON manifest bundled in the VSIX registers the protocol with Windows during extension installation.
2. When a user clicks a link with the registered scheme, Windows starts `devenv.exe` with a command-line switch and appends the full URI.
3. The extension's `AsyncPackage` loads via `ProvideAppCommandLine`, reads the URI from `SVsAppCommandLine`, and acts on it.

## VisualStudio.Extensibility (out-of-process)

**Not supported.** The new extensibility model does not provide a protocol handler API. Protocol registration requires a per-machine VSIX with `AllUsers="true"` and direct access to `SVsAppCommandLine` — both of which are only available in-process. Use the VSSDK / Toolkit approach below.

---

## VSSDK / VSIX Community Toolkit (in-process)

The Toolkit and VSSDK approaches are identical for protocol handlers — the Toolkit's `AsyncPackage` base class inherits directly from the VSSDK `AsyncPackage`. The steps below work with both.

**NuGet packages:**
- `Community.VisualStudio.Toolkit.17` (or `.16` / `.15`)
- `Microsoft.VisualStudio.SDK` (≥ 17.0)

**Key types:** `AsyncPackage`, `ProvideAppCommandLineAttribute`, `SVsAppCommandLine`, `IVsAppCommandLine`

### File organization

```
MyExtension/
├── Protocol/
│   └── protocol.json          ← protocol registration manifest
├── MyExtensionPackage.cs      ← AsyncPackage with ProvideAppCommandLine
├── source.extension.vsixmanifest
└── MyExtension.csproj
```

### Step 1 — Create the protocol registration manifest

Add a JSON file to your project that declares the URI scheme. This file tells the VSIX installer to register the protocol with Windows.

**Protocol/protocol.json:**

```json
{
  "$schema": "http://json.schemastore.org/vsix-manifestinjection",
  "urlAssociations": [
    {
      "protocol": "myext",
      "displayName": "My Extension Protocol Handler",
      "progId": "VisualStudio.myext.[InstanceId]",
      "defaultProgramRegistrationPath": "Software\\Microsoft\\VisualStudio_[InstanceId]\\Capabilities"
    }
  ],
  "progIds": [
    {
      "id": "VisualStudio.myext.[InstanceId]",
      "displayName": "My Extension Protocol Handler",
      "path": "[InstallDir]\\Common7\\IDE\\devenv.exe",
      "arguments": "/MyExtHandler",
      "defaultIconPath": "[InstallDir]\\Common7\\IDE\\devenv.exe"
    }
  ]
}
```

**Replace** `myext` with your own protocol name and `/MyExtHandler` with your own command-line switch.

Set the file's properties in the `.csproj`:

```xml
<ItemGroup>
  <Content Include="Protocol\protocol.json">
    <IncludeInVSIX>true</IncludeInVSIX>
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    <!-- This Build Action is what makes VS process it during install -->
    <BuildAction>ContentManifest</BuildAction>
  </Content>
</ItemGroup>
```

> **Important:** In the Visual Studio Properties window, set **Build Action** to `ContentManifest`. This is what triggers VSIX installer to process the protocol registration.

### Step 2 — Require per-machine installation

Protocol handlers require the extension to be installed for all users (per-machine). In `source.extension.vsixmanifest`:

```xml
<Installation AllUsers="true">
  <InstallationTarget Id="Microsoft.VisualStudio.Community" Version="[17.0,)" />
</Installation>
```

### Step 3 — Handle the URI in your package

Add `ProvideAppCommandLine` to your package so it auto-loads when devenv is launched with your switch:

**MyExtensionPackage.cs:**

```csharp
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Community.VisualStudio.Toolkit;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace MyExtension;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[Guid(PackageGuids.MyExtensionPackageString)]
[ProvideAppCommandLine("MyExtHandler", typeof(MyExtensionPackage), Arguments = "1", DemandLoad = 1)]
public sealed class MyExtensionPackage : ToolkitPackage
{
    protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress)
    {
        await base.InitializeAsync(cancellationToken, progress);
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        if (await GetServiceAsync(typeof(SVsAppCommandLine)) is IVsAppCommandLine cmdLine)
        {
            ErrorHandler.ThrowOnFailure(
                cmdLine.GetOption("MyExtHandler", out int isPresent, out string optionValue));

            if (isPresent == 1 && !string.IsNullOrEmpty(optionValue))
            {
                // optionValue contains the full URI, e.g. "myext://open/some-resource?id=42"
                await HandleProtocolUriAsync(optionValue);
            }
        }
    }

    private async Task HandleProtocolUriAsync(string rawUri)
    {
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out Uri uri))
        {
            await VS.MessageBox.ShowErrorAsync("Invalid URI", $"Could not parse: {rawUri}");
            return;
        }

        // Route based on host/path
        switch (uri.Host.ToLowerInvariant())
        {
            case "open":
                string filePath = uri.AbsolutePath.TrimStart('/');
                await VS.Documents.OpenAsync(filePath);
                break;

            case "settings":
                await VS.Commands.ExecuteAsync(KnownCommands.Tools_Options);
                break;

            default:
                await VS.StatusBar.ShowMessageAsync($"Unknown protocol action: {uri.Host}");
                break;
        }
    }
}
```

### Step 4 — Parse URI parameters

Use standard `System.Uri` to extract path segments, query parameters, and fragments:

```csharp
private void ProcessUri(Uri uri)
{
    // myext://navigate/file?path=C%3A%5Ccode%5Capp.cs&line=42
    string action = uri.Host;                    // "navigate"
    string resource = uri.AbsolutePath.Trim('/'); // "file"

    var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
    string path = query["path"];                  // "C:/code/app.cs"
    string line = query["line"];                   // "42"
}
```

### ProvideAppCommandLine attribute parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `switchName` | `string` | The command-line switch name (without `/` prefix) |
| `packageType` | `Type` | The `AsyncPackage` type to auto-load |
| `Arguments` | `string` | `"0"` = no value expected; `"1"` = a value follows the switch |
| `DemandLoad` | `int` | `1` = force-load the package when the switch is present |

### Testing protocol handlers

During development, protocol URIs won't work with F5 debugging because the experimental hive doesn't register protocols with Windows. To test:

1. **Install the extension** in a regular VS instance (not experimental).
2. Open a browser and navigate to your protocol URI (e.g. `myext://open/test`).
3. Windows should prompt to open Visual Studio, which then loads your package.

Alternatively, test from a command prompt:

```
devenv.exe /MyExtHandler "myext://open/some-resource"
```

### Security considerations

- **Always validate and sanitize URIs.** Protocol URIs come from untrusted external sources (browsers, emails, etc.).
- Never use URI content directly in file paths without validation — prevent path traversal attacks.
- Consider restricting the set of allowed actions to a known allowlist.
- Use `Uri.TryCreate` with `UriKind.Absolute` to reject malformed input.

---

## Troubleshooting

- **Protocol link does nothing / Windows doesn't offer to open VS:** The VSIX hasn't been installed in a regular VS instance (not experimental hive). Protocol registration happens during VSIX installation, not during F5 debugging.
- **VS opens but extension doesn't activate:** Verify `[ProvideAppCommandLine]` switch name matches the switch in your `protocol.json` manifest. Ensure `DemandLoad = 1` is set so VS force-loads your package.
- **URI parameters are empty or garbled:** Use `Uri.TryCreate` with `UriKind.Absolute` and `HttpUtility.ParseQueryString` for query parameters. Don't try to parse URIs manually with string splitting.
- **Works in dev but not after publish:** Ensure `protocol.json` is included in the VSIX as content (Build Action = Content, Include in VSIX = true).

## What NOT to do

> **Do NOT** use URI parameters directly in file paths, process arguments, or SQL queries. Protocol URIs come from untrusted external sources — always validate against an allowlist of actions and sanitize paths to prevent traversal attacks.

> **Do NOT** test protocol handlers using F5 debugging. The experimental hive doesn't register protocols with Windows. Install the VSIX in a regular VS instance.

> **Do NOT** register generic protocol schemes that might conflict with other applications (e.g. `vs://`). Use a unique scheme that includes your extension name.

## See also

- [vs-solution-events](../handling-solution-events/SKILL.md) — detecting solution/folder open events triggered by protocol links
- [vs-file-document-ops](../managing-files-documents/SKILL.md) — opening files programmatically after protocol activation
- [vs-commands](../adding-commands/SKILL.md) — executing commands from protocol handler code

## Related documentation

- [VSSDK Protocol Handler sample](https://github.com/Microsoft/VSSDK-Extensibility-Samples/tree/master/ProtocolHandler)
- [Adding command-line switches](https://learn.microsoft.com/en-us/visualstudio/extensibility/adding-command-line-switches?view=vs-2022)
