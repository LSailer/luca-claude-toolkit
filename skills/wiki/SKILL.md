---
name: wiki
description: >
  Manage the project's LLM-Wiki — a persistent, compounding markdown knowledge base at `<project>/.claude/knowledge/` that accrues across sessions. Use this skill whenever the user wants to init/bootstrap a project knowledge base, ingest any source (article, paper, blog post, PDF, URL, file, code snippet, image, transcript) into the wiki, query the wiki to answer a question with citations, or lint/health-check it for contradictions, orphans, stale claims, or near-duplicate concepts. Also use it when the user says things like "ingest this", "add to my notes", "file this article", "summarize this and save it", "what does the wiki say about X", "what do we know about Y", "search my knowledge base", "find contradictions in my notes", "lint the wiki", or "set up a knowledge base for this project". Even if the user doesn't say "wiki" or "knowledge base" explicitly — if they want to durably store, retrieve, synthesize, or audit project-level knowledge, this is the skill to use. Co-owns `.claude/knowledge/` with the `session-recap` hook; schemas are compatible.
---

# Wiki

A persistent, structured markdown knowledge base that lives at `<project>/.claude/knowledge/` and compounds across sessions. The `session-recap` hook fills it automatically after each session; this skill lets the user fill, query, and curate it during a session.

## Routing — which operation does this map to?

Once the skill fires, decide which of four operations applies from the user's phrasing:

- **Init** — `.claude/knowledge/` doesn't exist, or the user is bootstrapping ("set up", "start a knowledge base", "init the wiki", "bootstrap notes dir").
- **Ingest** — the user is pointing at content to file ("ingest", "add to wiki", "save this", "file this article", "summarize and save").
- **Query** — the user is asking something whose answer should come from the wiki ("what does the wiki say about X", "search my notes for Y", "pull up what we know about Z").
- **Lint** — the user wants a health-check ("find contradictions", "what's stale", "find orphans", "lint the wiki").

If the user just says "wiki" with no clear operation: probe whether `.claude/knowledge/` exists. If it doesn't, propose Init. If it does, ask which of Ingest / Query / Lint they want — don't guess.

## Wiki layout

```
.claude/knowledge/
├── index.md           # ## Concepts, ## Recent Sessions (≤20), ## Sources, ## Recent Activity (≤20)
├── log.md             # append-only chronological log — ingest/query/lint events
├── recaps/<ts>-<slug>.md     # owned by the SessionEnd hook — IMMUTABLE, never edit
├── concepts/<concept>.md     # shared, evergreen — Edit-not-Write to extend
└── sources/<slug>.md         # owned by this skill — externally-ingested material
```

## Conventions

These keep the skill schema-compatible with the `session-recap` hook, so a wiki grows under both halves without forking.

- **Concept tags are kebab-case, and reused.** `Read` `index.md` first to see what already exists. Inventing `authentication` when `auth` is already a tag fragments the wiki and makes future queries miss half the relevant pages.
- **Edit, don't Write, when a file already exists.** Concept pages and `index.md` accrete over time — wholesale rewrites destroy that history. `Read` first, then `Edit` surgically.
- **`recaps/` is read-only for this skill.** Those files are session snapshots owned by the hook. If a recap is wrong or outdated, fix the linked concept page instead.
- **Frontmatter for sources** matches the recap shape so a `grep` over the whole wiki works:
  ```yaml
  ---
  date: YYYY-MM-DD
  source_type: article | paper | url | file | snippet | image
  source_ref: <url or absolute filepath>
  concepts: [concept-a, concept-b]
  ---
  ```
- **Concept pages: extend the hook's frontmatter, don't replace it.** The hook seeds concept pages with `concept`, `last_updated`, `sessions:`. On first ingest from this skill, *add* a `sources:` list if it's not there — never drop `sessions:`. The two fields coexist: one tracks session-derived knowledge, the other tracks externally-ingested material.
- **`log.md` entries start with `## [YYYY-MM-DD HH:MM] <op> | <title>`** so `grep "^## \[" log.md | tail -5` returns recent activity at a glance.
- **End every op with a one-line stdout summary** like the hook does (`<op>: <slug> | concepts: a,b | pages: <n>`). Keeps activity scannable and scriptable.

## Init

Run when `.claude/knowledge/` is missing OR exists but lacks `index.md` / `log.md`. Idempotent — running it on an already-initialized wiki should print a "nothing to do" message and stop, never overwrite.

1. **Probe state.** `Bash`: `test -d .claude/knowledge && echo exists || echo missing`. If exists, `Glob` `.claude/knowledge/{index,log}.md` — if both are present, print `init: already initialized at .claude/knowledge/` and exit.
2. **Create the layout.** Make any missing dirs: `recaps/`, `concepts/`, `sources/`. Drop a `.gitkeep` in any newly-created empty dir so git tracks it.
3. **If `index.md` is missing**, `Write`:
   ```markdown
   # <project-slug> — Wiki Index

   The persistent knowledge base for this project. Auto-maintained by the `session-recap` hook (passive) and the `wiki` skill (active). See `log.md` for chronological activity.

   ## Concepts

   <!-- One line per concept page: `- [name](concepts/name.md) — one-line summary (N sessions, M sources)` -->

   ## Recent Sessions

   <!-- Prepended by the session-recap hook. Trimmed to 20 most recent. -->

   ## Sources

   <!-- One line per ingested source: `- YYYY-MM-DD — [Title](sources/slug.md) — concept-a, concept-b` -->

   ## Recent Activity

   <!-- Skill-side feed (ingest/query/lint). Trimmed to 20 most recent. -->
   ```
4. **If `log.md` is missing**, `Write`:
   ```markdown
   # Wiki Activity Log

   Append-only. Each entry begins with `## [YYYY-MM-DD HH:MM] <op> | <title>` so it can be tail-grepped.

   ## [<now>] init | wiki bootstrapped
   - dir: .claude/knowledge/
   - layout: recaps/, concepts/, sources/, index.md, log.md
   ```
5. **Ask once whether to gitignore.** `.claude/knowledge/` can be committed (shared knowledge) or gitignored (private). Don't assume — ask, then optionally append the line to `.gitignore` if requested.
6. **One-line summary:** `init: .claude/knowledge/ | created: index.md, log.md, recaps/, concepts/, sources/`

## Ingest

Filing an external source. Stay interactive — the value of the wiki comes from the *user's* judgment of what's important, not silent summarization.

1. **Resolve the source.** URL → `WebFetch`. File path → `Read`. Image → `Read` (multimodal). Pasted snippet → use as-is. If the source is large, summarize its structure first and confirm with the user what to focus on before reading deeply.
2. **Read existing context.** `Read` `.claude/knowledge/index.md` to see existing concept tags. `Glob` `concepts/*.md` to know which concept pages already exist. This is what prevents near-duplicate concept tags.
3. **Discuss takeaways with the user** — 3–6 bullets of what's important, what's surprising, what overlaps with existing concepts. Let the user steer emphasis. This is the step that makes the knowledge compound rather than pile up; don't skip it.
4. **Pick a kebab-case slug** (2–5 words). Pick concept tags, **reusing existing ones** wherever applicable.
5. **Write `sources/<slug>.md`:**
   ```markdown
   ---
   date: <today>
   source_type: <type>
   source_ref: <url-or-path>
   concepts: [concept-a, concept-b]
   ---

   # <Source title>

   ## Why this is in the wiki
   <1–2 sentences on why we ingested this and what it adds.>

   ## Key claims
   - <claim 1, with page/section reference if available>
   - <claim 2>

   ## What it changes in our understanding
   - <how this updates, contradicts, or extends existing concept pages>

   ## Open threads
   - <unresolved questions worth a follow-up source or query>
   ```
6. **Update concept pages.** For each tagged concept:
   - **Page exists** → `Read` it, `Edit` to extend the relevant section, append the source filename to the `sources:` frontmatter list (add the field if it's not there — see Conventions). Bump `last_updated`.
   - **Page doesn't exist** → `Write` it using the hook's skeleton (`concept`, `last_updated`, `sessions:`, `sources:`, body sections).
7. **Update `index.md`.** Prepend lines to `## Sources` and `## Recent Activity`. If a concept page was created, add a line to `## Concepts`. Trim `## Recent Activity` to 20 entries.
8. **Append to `log.md`:**
   ```
   ## [<now>] ingest | <source title>
   - source: <ref>
   - concepts: <a,b>
   - pages updated: index.md, sources/<slug>.md, concepts/<a>.md, concepts/<b>.md
   ```
9. **One-line summary:** `ingest: <slug> | concepts: a,b | pages: <n>`

## Query

The wiki is the source. When the wiki covers the topic, don't answer from general knowledge — read the wiki and synthesize.

1. **`Read` `index.md` first.** It's the catalog. Match the user's question to concept entries, source entries, or recent recaps.
2. **Drill selectively.** `Read` the matched concept page(s) and source page(s); open referenced recaps if the question is session-historical. Stay focused — pulling 10+ pages usually means the question is too broad, or the wiki needs a Lint pass to consolidate.
3. **Synthesize with citations.** Use `path:line` references (e.g. `concepts/auth.md:14`) so the user can jump straight to the source. Quote sparingly — pointing is usually enough.
4. **Flag gaps honestly.** If the wiki has thin or no coverage, say so. Don't paper over it. Suggest a source to ingest or a concept page to flesh out.
5. **Offer to file the answer back.** Comparison tables, analyses, and connections discovered during a query are valuable artifacts. Offer (don't auto-do): *"want me to file this as `concepts/<new>.md` or `sources/<slug>.md` so it compounds?"* If yes, follow Ingest steps 5–8.
6. **Append a `query` entry to `log.md`** with the question and the pages consulted. Keep it short.
7. **One-line summary:** `query: <topic> | pages read: <n> | filed back: yes|no`

## Lint

Periodic health-check. Always report-then-fix — silently mutating the wiki breaks the user's mental model of what's there.

1. **Run these passes:**
   - **Orphan pages** — for each page in `concepts/` and `sources/`, `Grep` its basename across the rest of the wiki. Zero inbound matches → orphan.
   - **Missing concept pages** — concepts referenced in recap or source frontmatter that don't have a page in `concepts/`.
   - **Near-duplicate concepts** — pairs like `auth`/`authentication`, `caching`/`cache`. Propose a merge with the canonical name.
   - **Stale claims** — when two pages on the same concept disagree, surface the contradiction with `path:line` for both sides.
   - **Frontmatter drift** — sources missing required fields (`date`, `source_type`, `concepts`); concept pages missing `last_updated`; `index.md` entries pointing at non-existent files.
   - **Index hygiene** — `## Recent Sessions` and `## Recent Activity` longer than 20 entries.
2. **Report findings as a structured list**, grouped by pass, each with a `path:line` and a proposed fix. Do not edit yet.
3. **Ask the user which to fix.** Apply only what they approve. For merges, confirm the canonical name before rewriting links.
4. **Append a `lint` entry to `log.md`** summarizing what was found and what was fixed.
5. **One-line summary:** `lint: <n> findings | fixed: <m> | pages touched: <k>`

## Hard rules

These four are non-negotiable — everything else above is guidance, but these are bright lines:

- **Don't write outside `.claude/knowledge/`.** Blast radius is bounded to that one directory.
- **Don't modify `recaps/*.md`.** They are immutable session snapshots owned by the hook.
- **Don't auto-fix during Lint.** Always report → confirm → apply.
- **Don't ingest silently.** The interactive takeaways step (Ingest §3) is where the value compounds; skipping it produces a pile of summaries, not a knowledge base.
