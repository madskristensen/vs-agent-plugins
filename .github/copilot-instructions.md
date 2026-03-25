# Copilot Instructions for vs-agent-plugins

## Skill Authoring Requirements

Every skill in this repository targets **Visual Studio IDE** extension development. Each skill's `SKILL.md` must cover all three extensibility approaches:

1. **VisualStudio.Extensibility** (out-of-process, new model) — The recommended approach for new extensions using the `Microsoft.VisualStudio.Extensibility` SDK.
2. **VSIX Community Toolkit** (in-process) — The community-maintained helpers that simplify common VSSDK tasks (e.g., `VS.MessageBox`, `ex.Log()`).
3. **VSSDK** (in-process, legacy) — The low-level Visual Studio SDK APIs (e.g., `VsShellUtilities`, `IVsActivityLog`, `IServiceProvider`).

If a particular approach does not apply to a skill's topic, explicitly state that and explain why.

## Skill Structure

- Each skill must include working C# code examples for every approach listed above.
- Clearly label each section or code block with which approach it belongs to.
- Note any NuGet packages or namespaces required for each approach.
- Link to the official Microsoft Learn documentation where applicable.

## Anti-Patterns and "Do NOT" Guidance

Each skill should include a **"What NOT to do"** section (or inline warnings) that calls out common mistakes, deprecated patterns, and traps. This is especially important when:

- **Multiple APIs exist for the same task** and only one is recommended (e.g., async vs. legacy synchronous editor APIs). Explicitly state which API to avoid and why.
- **Old tutorials or documentation** still show a deprecated pattern (e.g., `ErrorListProvider`, `LanguageService` base class, legacy `ICompletionSource`). Warn against following them.
- **Threading mistakes** are likely — such as blocking the UI thread with `.Result`/`.Wait()`, using `Thread.Sleep()`, calling `ConfigureAwait(false)`, or accessing COM objects from a background thread.
- **Silent failures** can occur — such as forgetting the MEF asset type in `.vsixmanifest`, which causes components to simply not load with no error message.
- **Security or stability risks** exist — such as using `System.Windows.MessageBox` (doesn't parent to VS), hard-coding colors (breaks in Dark/High Contrast themes), or doing slow work in constructors.

Format these as clear, scannable warnings (e.g., `> **Do NOT** use ...` blockquotes or a dedicated subsection) so the agent can quickly identify what to avoid.

## Marketplace Registry

Any new skill, agent, MCP server, or instruction file must be added to and maintained in the `marketplace.json` file. When creating or removing any of these items, update `marketplace.json` accordingly to keep it in sync with the repository contents.
