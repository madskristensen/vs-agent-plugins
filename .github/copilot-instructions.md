# Copilot Instructions for vs-agent-plugins

## Skill Authoring Requirements

Every skill in this repository targets **Visual Studio IDE** extension development. Each skill's `SKILL.md` must cover all three extensibility approaches:

1. **VisualStudio.Extensibility** (out-of-process, new model) — The recommended approach for new extensions using the `Microsoft.VisualStudio.Extensibility` SDK.
2. **VSIX Community Toolkit** (in-process) — The community-maintained helpers that simplify common VSSDK tasks (e.g., `VS.MessageBox`, `ex.Log()`).
3. **VSSDK** (in-process, legacy) — The low-level Visual Studio SDK APIs (e.g., `VsShellUtilities`, `IVsActivityLog`, `IServiceProvider`).

If a particular approach does not apply to a skill's topic, explicitly state that and explain why.

## Skill Structure

Each `SKILL.md` follows this section order:

1. **Frontmatter** — YAML with `name` and `description` (used for agent skill matching).
2. **H1 heading + enriched introduction** — A concise definition of the concept, followed by 1-2 sentences explaining *why* this matters (the problem it solves, consequences of not doing it). Do not restate information that is already covered in the approach section headings or subsequent tables. End the intro with a **"When to use this vs. alternatives"** bulleted list that cross-references related skills by relative path (e.g., `[vs-commands](../vs-commands/SKILL.md)`).
3. **Approach sections** — Numbered `## 1. VisualStudio.Extensibility`, `## 2. VSIX Community Toolkit`, `## 3. VSSDK` sections with working C# code examples, NuGet packages, and key namespaces for each approach.
4. **Key guidance** — A short bulleted summary of best practices.
5. **Troubleshooting** — 3-6 bullet points in **symptom → cause → fix** format covering common "it doesn't work" scenarios specific to the skill's topic.
6. **What NOT to do** — Blockquote warnings (`> **Do NOT** ...`) calling out anti-patterns, deprecated APIs, and common mistakes. Keep each entry to one or two concise clauses using em-dashes — state what to avoid and why, not the full diagnostic walkthrough (that belongs in Troubleshooting).
7. **See also** — Cross-references to related skills as bare links without descriptions (the intro's "When to use" list already explains each relationship). Format: `- [vs-foo](../vs-foo/SKILL.md)`.
8. **References** — Links to official Microsoft Learn documentation.

Additional requirements for each section:
- Each approach section must include working C# code examples.
- Clearly label each section or code block with which approach it belongs to.
- Note any NuGet packages or namespaces required for each approach.
- The enriched introduction, troubleshooting, and see-also sections serve dual purposes: they provide context for agents *and* act as the source of truth for generating human-centric documentation. Keep them factual and concise (bullets, not prose paragraphs) so a doc generator can expand them without inventing facts.

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
