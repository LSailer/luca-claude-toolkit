# luca-claude-toolkit

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin hosted on GitHub so it can be installed on any device with two commands.

This repo is both a **plugin** and a **single-plugin marketplace**: adding the repo as a marketplace exposes one plugin (`luca-toolkit`) that ships skills, agents, hooks, and scripts.

---

## What's in this plugin

| Component | Name | Description |
|-----------|------|-------------|
| Skill | `pencil-design` | Generate UI mockups, slides, dashboards, and marketing visuals using the [Pencil](https://www.npmjs.com/package/@pencil.dev/cli) CLI. |
| Script | `statusline.sh` | Status line showing model, folder, and a 10-segment context-usage bar (green / yellow / red, scaled to 1M tokens). |
| Hook | `session-recap` | `SessionEnd` hook that runs Claude headlessly to turn the transcript into a Karpathy-style wiki at `<project>/.claude/knowledge/` (per-session recaps + evergreen concept pages + index). |

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
/plugin marketplace add LSailer/luca-claude-toolkit
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

## Enable the bundled statusline

This plugin ships `scripts/statusline.sh` — a context-usage bar (`▰▰▰▱▱▱▱▱▱▱`) that fills as tokens grow and switches from green → yellow → red at the 100k and 500k thresholds (scaled to a 1M-token context).

`statusLine` is a per-device *settings* feature — the plugin can ship the script but cannot auto-wire it. Paste this block into `~/.claude/settings.json` once per device:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/plugins/marketplaces/luca-claude-toolkit/plugins/luca-toolkit/scripts/statusline.sh"
}
```

If that path turns out to be unstable across Claude Code versions, symlink it from `~/.claude/` and point settings at the symlink.

### Ship your own statusline instead

Drop a new script in `scripts/`, make it executable (`chmod +x`), bump `plugin.json` version, push. Point `settings.json` at the new filename.

---

## The bundled `session-recap` hook

`hooks/session-recap.sh` is wired to `SessionEnd` via `hooks/hooks.json` — it auto-activates when the plugin installs. No per-device settings changes needed.

On every meaningful session end, the hook runs `claude -p` headlessly (Sonnet 4.6 by default, $1 budget cap) with a tightly scoped toolset (`Read,Write,Edit,Glob`) and asks it to read the transcript and update a Karpathy-style wiki at `<project>/.claude/knowledge/`:

- `recaps/<timestamp>-<slug>.md` — immutable per-session recap (key takeaways, concepts touched, files changed, what worked, what we learned)
- `concepts/<concept>.md` — evergreen concept pages that accrete across sessions
- `index.md` — tag directory + recent-sessions feed (trimmed to last 20)

**Gates that keep it cheap and safe:**
- Only runs in git repos (no recaps for `$HOME` or scratch dirs).
- Skips throwaway sessions (< 5 user messages *and* < 10 tool calls).
- `CLAUDE_RECAP_RUNNING` guard prevents the inner `claude -p` from retriggering the hook.
- Errors go to `~/.claude/knowledge/_errors.log` — it never blocks session shutdown.

**Per-device overrides** (optional env vars):
- `CLAUDE_RECAP_MODEL` — defaults to `claude-sonnet-4-6`. Set to `claude-opus-4-7` for richer synthesis.
- `CLAUDE_RECAP_BUDGET` — defaults to `1.00` (USD).

**Recommended:** add `.claude/knowledge/` to each project's `.gitignore` unless you want the wiki committed.

### Migrating from a local copy

If you already have `session-recap.sh` wired up in `~/.claude/settings.json` from a previous manual install, remove the `hooks.SessionEnd` block from that file after `/plugin update luca-toolkit` — otherwise the hook fires twice. You can delete `~/.claude/hooks/session-recap.sh` and `~/.claude/hooks/session-recap-prompt.md` too; the plugin now owns those.

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
