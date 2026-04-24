---
name: what-would-i-skip
description: Generate 10 high-leverage tasks the user would never do manually because the time cost isn't worth it, each with a concrete Claude Code playbook. Use when the user asks for task ideas, wants to find leverage in their workflow, asks "what should I automate", or references the "10 tasks you'd skip" framing.
---

# What Would I Skip

Produce 10 tasks that would meaningfully improve the user's project, that a typical person in their role would never do because the manual time isn't worth it, but that Claude Code can make tractable. For each, provide a concrete playbook grounded in this specific project's files and tools.

## Step 1 — Ground yourself in the project

Before generating anything, gather context. Read in this order, stopping as soon as you have enough:

1. The nearest `CLAUDE.md` (project) and `~/.claude/CLAUDE.md` (global) — role, style rules, conventions.
2. `MEMORY.md` in the project's auto-memory directory — prior user preferences and feedback.
3. `git log --oneline -20` and `ls` of the project root — what kind of work is happening.
4. Any `docs/`, `wiki/`, `README.md`, or equivalent knowledge base — the canonical source of truth.
5. Which MCP servers are available this session (Zotero, W&B, Gmail, Calendar, Drive, etc.) — playbooks must only call tools that exist.

If the user passed `$ARGUMENTS`, treat it as a domain hint (e.g. "writing", "before defense", "infra", "pre-launch") and bias task selection accordingly.

If the project's purpose is genuinely unclear after the reads above, ask the user one short question before proceeding. Otherwise proceed silently.

## Step 2 — Generate 10 tasks

Bias the mix toward these four archetypes (they are the highest-value ones):

- **Consistency / terminology audits** — catching drift in names, spellings, acronyms, units, API shapes, schema fields across files. Manual version requires reading everything in one sitting.
- **Gap scans** — what's missing that should be there (uncited recent work, untested code paths, undocumented configs, orphan labels, unused assets). Requires crossing two sources.
- **Rigor / claim-strength audits** — every strong claim either backed by a number/citation/test or softened. Every hedge word justified. Every "TODO" either resolved or tracked.
- **Adversarial rehearsal** — simulate a skeptical reviewer, examiner, auditor, or oncall. Generate the questions and the model answers before the real event.

Fill the remaining slots with tasks that fit the project. Good candidates: reproducibility packets, meeting/status auto-briefs, recurring digests, cross-repo diff reports, triage dashboards.

## Step 3 — For each task, write

- **One-line task title** — action verb first.
- **Why skipped** — one sentence naming the specific manual cost (e.g. "two hours of grep across 40 files").
- **Playbook** — a self-contained prompt the user could paste back, naming real files, real MCP tools, real output paths. No placeholders. If the task is naturally recurring, say "cron via `/schedule`" or "loop via `/loop`" and give a cadence.

## Step 4 — Close with a meta-playbook

End the response with a short "applies to all ten" section covering:

1. Scope with a question, not a command — produce triage lists, not silent edits.
2. Ground in the canonical source (wiki, spec, tests), not the artifact being audited.
3. Output a diff or markdown report the user approves before anything lands.
4. Make recurring ones cron jobs.
5. Preflight any generated artifact against the project's style rules from `CLAUDE.md`.

Then ask which one or two to turn into slash commands under `.claude/commands/`. Do not implement until the user picks.

## Anti-patterns — do not produce

- Generic tasks that could apply to any project ("add more tests", "improve documentation"). Every task must reference real files or real domain terms from this project.
- Tasks Claude Code can't actually do in this environment (calls to MCP servers not loaded this session).
- Tasks that silently rewrite the artifact. Every playbook must produce a report the user reviews.
- More than ~120 words per task. Be terse. The list is a menu, not a manual.
