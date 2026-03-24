# Visual Studio IDE Agent Plugins

A repository of [Agent Skills](https://agentskills.io/) for **Visual Studio IDE** (not VS Code) extension development.

## Overview

This repo provides agent skills that help AI coding agents build, debug, and maintain Visual Studio IDE extensions. Skills are packaged using the open [Agent Skills](https://agentskills.io/specification) format and exposed through a `.claude-plugin/marketplace.json` manifest.

## Repository structure

```
vs-agent-plugins/
├── .claude-plugin/
│   └── marketplace.json    # Plugin marketplace manifest
├── skills/                 # Agent skills (each in its own folder)
│   └── <skill-name>/
│       ├── SKILL.md        # Required: metadata + instructions
│       ├── scripts/        # Optional: executable code
│       ├── references/     # Optional: documentation
│       └── assets/         # Optional: templates, resources
├── template/
│   └── SKILL.md            # Starter template for new skills
└── README.md
```

## Usage

### Claude Code

Register this repo as a plugin marketplace:

```
/plugin marketplace add <owner>/vs-agent-plugins
```

Then browse and install skills:

```
/plugin install <skill-name>@vs-agent-plugins
```

### Other compatible agents

Any agent that supports the [Agent Skills](https://agentskills.io/) format can discover skills from this repo. Clone or add the `skills/` directory to your agent's skill search paths.

## Creating a new skill

1. Copy `template/SKILL.md` into a new folder under `skills/`:
   ```
   skills/my-new-skill/SKILL.md
   ```
2. Edit the frontmatter (`name`, `description`) and write your instructions.
3. The `name` must match the folder name (lowercase, hyphens only).
4. Add the skill path to a plugin entry in `.claude-plugin/marketplace.json`.

See the [Agent Skills specification](https://agentskills.io/specification) for the full format reference.

## Roadmap

- [ ] Skills for Visual Studio extensibility APIs (VSIX, MEF, async packages)
- [ ] MCP servers for VS-specific tooling
- [ ] Custom agent instructions for extension debugging workflows

## License

TBD
