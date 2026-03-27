# Visual Studio IDE Agent Skills

Agent skills for **Visual Studio IDE** extension development. These skills help AI coding agents (GitHub Copilot, Claude, etc.) build, debug, and maintain Visual Studio extensions using the correct APIs and best practices.

Each skill covers all three extensibility approaches:

- **VisualStudio.Extensibility** — the recommended out-of-process model
- **VSIX Community Toolkit** — community helpers that simplify common tasks
- **VSSDK** — the low-level, in-process legacy APIs

## Getting started

### Option 1 — Use the GitHub Node extension in Visual Studio (recommended)

The [GitHub Node](https://marketplace.visualstudio.com/items?itemName=MadsKristensen.githubnode) extension lets you register this repository as an **Agent Marketplace** and install skills directly from Solution Explorer.

1. **Install the extension**
   - In Visual Studio, go to **Extensions → Manage Extensions**
   - Search for **GitHub Node** and install it (requires VS 2022 17.0+)
   - Restart Visual Studio

2. **Register this repository as a marketplace**
   - Open a solution in Visual Studio
   - Right-click the **GitHub** node in Solution Explorer and select **Manage Marketplaces**
   - Click **Add** and enter:
     ```
     madsk/vs-agent-plugins
     ```
   - The extension clones the repository locally and caches it for 7 days

3. **Install skills into your project**
   - Right-click the **GitHub** node (or a subfolder like `skills`) and choose **Add Skill**
   - In the template dialog, select **vs-agent-plugins** from the provider dropdown
   - Browse and preview the available skills, then click **Create** to add the selected skill to your repository's `.github/skills/` folder

Once installed, Copilot in Visual Studio will automatically pick up the skills from the `.github` folder and use them when you ask it to help with extension development.

### Option 2 — Copy skills manually to your repository

No extension required. Copy the skills you need directly into your repo's `.github` folder:

1. **Clone this repository** (or download it as a ZIP):
   ```
   git clone https://github.com/madsk/vs-agent-plugins.git
   ```

2. **Copy the `skills` folder** into your project's `.github` directory:
   ```
   your-repo/
   └── .github/
       └── skills/
           ├── adding-commands/
           │   └── SKILL.md
           ├── adding-tool-windows/
           │   └── SKILL.md
           ├── handling-async-threading/
           │   └── SKILL.md
           └── ... (any skills you need)
   ```

   You can copy individual skill folders or the entire `skills/` directory — only include what's relevant to your project.

3. **Commit the `.github/skills/` folder** to your repository. GitHub Copilot in Visual Studio will automatically discover and use the skills when assisting with extension development tasks.

> **Tip:** You don't need to copy all skills. Pick only the ones that match the extensibility areas you're working on (e.g., `adding-commands`, `adding-tool-windows`, `handling-async-threading`).

## Available skills

| Skill | Description |
|-------|-------------|
| `adding-codelens-indicators` | Add CodeLens indicators above code elements |
| `adding-commands` | Register and handle commands in VS extensions |
| `adding-context-menus` | Add items to right-click context menus |
| `adding-editor-adornments` | Add visual adornments to the text editor |
| `adding-editor-classifiers` | Classify text spans for syntax coloring |
| `adding-editor-margins` | Add custom margins to the text editor |
| `adding-intellisense-completion` | Provide IntelliSense completion items |
| `adding-lightbulb-actions` | Add light bulb (quick action) suggestions |
| `adding-options-settings` | Create options pages and manage settings |
| `adding-quickinfo-tooltips` | Show QuickInfo tooltips on hover |
| `adding-solution-explorer-nodes` | Add custom nodes to Solution Explorer |
| `adding-suggested-actions` | Provide suggested actions in the editor |
| `adding-textmate-grammars` | Register TextMate grammars for syntax highlighting |
| `adding-tool-window-search` | Add search functionality to tool windows |
| `adding-tool-window-toolbars` | Add toolbars to tool windows |
| `adding-tool-windows` | Create custom tool windows |
| `controlling-command-visibility` | Control when commands are visible/enabled |
| `creating-custom-editors` | Build custom editor types |
| `creating-dynamic-commands` | Create menus with dynamic command lists |
| `creating-editor-taggers` | Tag text spans for adornments, outlining, etc. |
| `extending-open-folder` | Extend the Open Folder experience |
| `handling-async-threading` | Async patterns and thread management |
| `handling-build-events` | React to build start, end, and project events |
| `handling-extension-errors` | Error handling and logging in extensions |
| `handling-protocol-uris` | Handle custom protocol URIs (vsix://) |
| `handling-solution-events` | React to solution open, close, and project events |
| `integrating-error-list` | Add entries to the Error List window |
| `integrating-language-servers` | Integrate LSP language servers |
| `interacting-solution-explorer` | Interact with Solution Explorer programmatically |
| `intercepting-commands` | Intercept and override existing commands |
| `listening-text-view-events` | Listen to text editor view events |
| `managing-files-documents` | Open, read, write, and manage documents |
| `providing-consuming-services` | Create and consume VS services |
| `registering-fonts-colors` | Register custom fonts and colors |
| `showing-background-progress` | Show progress bars and status updates |
| `showing-info-bars` | Display info bars in tool windows and the editor |
| `showing-message-boxes` | Show message boxes and dialogs |
| `theming-extension-ui` | Theme your extension UI for Dark/Light/High Contrast |

## Repository structure

```
vs-agent-plugins/
├── .github/
│   └── copilot-instructions.md   # Repo-level Copilot instructions
├── .claude-plugin/
│   └── marketplace.json          # Agent marketplace manifest
├── skills/
│   └── <skill-name>/
│       └── SKILL.md              # Skill instructions and code examples
└── README.md
```

## License

[Apache License 2.0](LICENSE)
