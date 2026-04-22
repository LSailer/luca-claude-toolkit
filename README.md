# luca-claude-toolkit

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin hosted on GitHub so it can be installed on any device with two commands.

This repo is both a **plugin** and a **single-plugin marketplace**: adding the repo as a marketplace exposes one plugin (`luca-toolkit`) that ships skills, agents, hooks, and scripts.

---

## What's in this plugin

| Component | Name | Description |
|-----------|------|-------------|
| Skill | `pencil-design` | Generate UI mockups, slides, dashboards, and marketing visuals using the [Pencil](https://www.npmjs.com/package/@pencil.dev/cli) CLI. |

More skills, agents, and hooks will land in `skills/`, `agents/`, `hooks/` over time.

---

## Prerequisites

Some skills wrap external CLIs and need those installed on each device **once** before use. Claude Code does **not** install CLIs for you at plugin-install time.

### `pencil-design`

```bash
npm install -g @pencil.dev/cli
pencil login --email you@example.com
```

Only required the first time you use `pencil-design` on a device. Add a local fallback (`npm install @pencil.dev/cli` + `npx pencil ...`) if your global npm prefix needs sudo.

---

## Install on a new device

```
/plugin marketplace add <your-github-user>/luca-claude-toolkit
/plugin install luca-toolkit@luca-claude-toolkit
```

Restart Claude Code so the new skills and agents are discovered. Verify with `/plugin list`.

---

## Update on a device

Whenever you push new content to this repo (and bump the `version` in `.claude-plugin/plugin.json`), update the installed copy:

```
/plugin marketplace update luca-claude-toolkit
/plugin update luca-toolkit
```

Then restart Claude Code.

---

## Add a new skill

Skills are Markdown files with YAML frontmatter. Claude Code auto-discovers every folder under `skills/` — no manifest changes needed.

### 1. Create the folder

```
skills/<skill-name>/SKILL.md
```

Supporting docs (`REFERENCE.md`, examples, etc.) can live alongside it in the same folder.

### 2. Write `SKILL.md`

```markdown
---
name: my-skill
description: >
  One paragraph that teaches Claude *when* to invoke this skill. Be trigger-heavy:
  list the user phrases, task shapes, and keywords that should fire it. Even if
  the user does not mention the skill by name, the description is what makes
  Claude reach for it.
---

# My Skill

Instructions for Claude. Describe the workflow, the commands to run, the
expected outputs, and failure modes. Treat Claude as a capable engineer who
has never seen this task before.
```

### 3. Bump version and push

```bash
# Edit .claude-plugin/plugin.json: "version": "0.1.0" -> "0.2.0"
git add skills/my-skill/
git commit -m "add my-skill"
git push
```

### 4. Pull it on every device

```
/plugin marketplace update luca-claude-toolkit
/plugin update luca-toolkit
```

---

## Add a new agent

```
agents/<agent-name>.md
```

```markdown
---
name: my-agent
description: One-liner so Claude knows when to spawn this subagent.
model: sonnet
color: cyan
---

You are a focused agent for X. Your job is to ...
```

Agents get their own context window. Use them for focused, independent tasks (code review, test writing, targeted refactors).

---

## Add a hook

Hooks run shell commands on Claude Code lifecycle events (`PostToolUse`, `UserPromptSubmit`, `SessionStart`, etc.).

### 1. Drop the script in `scripts/`

```bash
#!/usr/bin/env bash
# scripts/format-on-save.sh
jq -r '.tool_input.file_path // empty' | xargs -r prettier --write
```

`chmod +x scripts/format-on-save.sh` so it's executable.

### 2. Wire it up in `hooks/hooks.json`

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format-on-save.sh"
          }
        ]
      }
    ]
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's install path at runtime, so the path survives `/plugin update`.

---

## Bundle a statusline script

`statusLine` is a per-device *settings* feature — the plugin can ship the script but cannot auto-wire it. Each device still needs one line in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/plugins/marketplaces/luca-claude-toolkit/plugins/luca-toolkit/scripts/<your-script>.sh"
}
```

If that path turns out to be unstable across Claude Code versions, symlink it from `~/.claude/` and point settings at the symlink.

---

## Add another plugin to this repo (later)

Create a second plugin folder (e.g. `plugins/other-toolkit/.claude-plugin/plugin.json`) and add an entry to `.claude-plugin/marketplace.json`:

```json
{
  "plugins": [
    { "name": "luca-toolkit",   "source": "./" },
    { "name": "other-toolkit",  "source": "./plugins/other-toolkit" }
  ]
}
```

Users can then install each plugin independently from the same marketplace.

---

## Verify locally before pushing

```bash
# From the repo root
jq . .claude-plugin/plugin.json .claude-plugin/marketplace.json   # JSON is valid
claude --plugin-dir ./                                              # load as live plugin
```

Inside the launched session:

```
/plugin list
/plugin validate ./
```

Both should show `luca-toolkit` loaded with `pencil-design` available.

---

## Versioning

- Bump `plugin.json` `version` on every change. Without a bump, `/plugin update` silently does nothing.
- Use SemVer: patch for doc/content tweaks, minor for new skills/agents, major for breaking changes to an existing skill's behaviour.
- For external-tool wrapper skills (like `pencil-design`), track the upstream CLI version in the skill URL (`@0.2.5`) rather than `@latest`, so upgrades are intentional.

---

## Why this layout works

Claude Code uses **convention over configuration** — `skills/`, `agents/`, and `hooks/` are auto-discovered. `plugin.json` only needs `name`; everything else is optional metadata. That's why adding a new skill is "drop a folder, bump version, push" with no manifest edits.

The single-repo marketplace + plugin pattern (`"source": "./"`) is the simplest way to distribute one plugin. If this grows, each plugin moves into its own subfolder and the marketplace.json grows with it — no need to split repos.
