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

## Marketplace Registry

Any new skill, agent, MCP server, or instruction file must be added to and maintained in the `marketplace.json` file. When creating or removing any of these items, update `marketplace.json` accordingly to keep it in sync with the repository contents.
