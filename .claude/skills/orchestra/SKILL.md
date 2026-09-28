---
name: orchestra
description: Orchestrate a substantial build with Claude as planner/reviewer and an opencode worker (cheap model) as implementer. Use for multi-file features, refactors or new projects in this repo; skip trivial edits and questions.
---

# Claude plans. opencode implements. Claude accepts.

Claude's tokens go to decisions: design, contracts, acceptance. The worker's
tokens go to volume: discovery, code, tests, debug loops.

## 1. Classify
Trivial fix or question → just do it, no delegation. Substantial build → continue.

## 2. Design (Claude)
Write `docs/agent-work/<feature>/spec.md`: objective, non-goals, architecture,
interfaces/contracts, failure behaviour, risks, acceptance criteria (A1, A2…).
Security, data model, public APIs and dependency choices are decided HERE, never
left to the worker. Ask the user only about real product/risk decisions.

## 3. Plan + briefs (Claude)
Split into dependency-ordered bundles at real contract/acceptance boundaries —
prefer ONE coherent vertical bundle per phase, not micro-steps. For each, write
`docs/agent-work/<feature>/T<n>.md` from `orchestra/templates/task-brief.md`
with exact contracts, file scope and verification commands. Don't pre-write the
implementation.

Capture baseline: `git status --short && git rev-parse HEAD` (git init if absent).

### Visual assets (images, icons, sprites, textures, backgrounds)
Never stop to ask the user for an asset — generate it, but spend calls AND neurons wisely:
every call puts a preview in YOUR context, and the Cloudflare account has 10,000 neurons/day
(when exhausted EVERY model stops until 00:00 UTC; the tools then say "do not retry" — obey).
Each result ends with "today ~X/10000 neurons": check it before planning more images.
- Default model FLUX.2 klein 4B (`image_model` omitted): follows prompts well, ~104 neurons per
  1024² image (~90/day). `sdxl-lightning` is free but often ignores the prompt; `flux-2-klein-9b`
  (~1,360/image) and `phoenix-1.0` (~2,300) are expensive — only when the user asks.
- Plan all assets first, then generate them together:
  - many icons (named or not) → ONE `generate_icon_sheet`: with `items` (≤24 subjects, in order)
    FLUX draws them as a grid on a canvas shaped like the grid; icons are cut out and saved as
    <prefix>-NN.png in reading order. Look at the contact sheet ONCE, rename files to their
    subjects (`mv`), then ask again only for missing/wrong subjects in one more sheet.
    Cost: one generation (~80–104 neurons) for the whole set.
  - 2+ separate images that need their own size/composition → ONE `generate_assets` call.
  - a single hero/background image → `generate_asset`.
- Prompts: plain English sentences; FLUX follows them (subject, style, colours, "centered",
  "lots of empty space"). No negative prompt needed for FLUX.
- Transparency: ask for "solid plain green background" (magenta for green subjects) and use
  `remove_background: true` (+ `trim`) — the flat background is keyed out by colour. Sheets always do it.
- `seed` is honoured by flux-2-klein-9b only; other models give a new image per call.
- Workers: in the brief, give the exact CLI lines
  (`orchestra/asset_mcp.py sheet "<style>" <dir> --prefix day --item sun --item moon …`,
  `… batch assets.json`, `… generate "<prompt>" <path>`) and add the paths to "May change".
  Prefer generating key assets yourself during planning.
- Always reference the path the tool reports back. Keep text out of images (render it in HTML/CSS).
`orchestra/asset_mcp.py check` diagnoses config/connection problems.

## 4. Dispatch (worker)
```
orchestra/delegate.py docs/agent-work/<feature>/T1.md [--model opencode/<m>]
```
Run it from the project root with Bash `run_in_background: true` for long tasks and wait for the
notification — no polling, no parallel edits to the worker's files.

Progress visibility (so the user is not left in the dark):
- Right after dispatch, arm the Monitor tool on `orchestra/watch.py --events`
  (`timeout_ms` 1800000, re-arm on expiry while the worker runs). It emits only
  milestones — todo progress, files written, test runs, failures, stalls, finish —
  and exits when the worker ends. Relay nothing unless the user asks or it shows
  a failure/stall; the lines themselves are visible to the user.
- "How is it going?" → `orchestra/watch.py --status` (snapshot) and answer from it.
- Tell the user they can follow live in another terminal with `orchestra/watch.py`.
One writer at a time in the shared workspace. Default model:
`$ORCHESTRA_WORKER_MODEL` or `opencode/big-pickle`.

## 5. Review (Claude, one batched pass)
Worker "done" = ready for review. Read the report, then the real diff
(`git diff <baseline>` + untracked files). Two lenses: spec compliance, then
quality/security. Spot-check (run the tests once, try an edge case) — don't redo
the worker's whole loop. Don't read the full JSONL log unless something is off.

## 6. Correct (max 1 cycle)
Batch ALL findings into `docs/agent-work/<feature>/T<n>.review-1.md`, then send them
to the SAME session (`last` = session of this brief's latest run; never type ids by hand):
```
orchestra/delegate.py docs/agent-work/<feature>/T<n>.md --session last --message "$(cat docs/agent-work/<feature>/T<n>.review-1.md)"
```
If still wrong after one cycle: fix small things yourself or re-scope.

## 7. Integrate + close
Fill the review section of the report, commit only if the user allows it,
then summarise to the user: what was built, what actually passed, worker
token usage (from delegate.py output), open risks.
