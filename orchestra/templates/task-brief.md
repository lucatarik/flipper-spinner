# <Task ID>: <reviewable deliverable>

Workspace: <absolute path>
Baseline: <git commit / "clean" / notes on pre-existing changes>
Depends on: <accepted task IDs, or none>
Report path: docs/agent-work/<feature>/<Task ID>.report.md

## Goal
<The whole coherent bundle, not one micro-step.>

## Non-goals
- <...>

## Done when
- <observable behaviour, with acceptance ID>
- <negative / boundary behaviour>
- <verification commands pass>

## Contracts (fixed — do not change)
<Exact signatures, data shapes, error behaviour, CLI flags, file formats.>

## Files
May change: <literal paths>
Must not change: everything else (see AGENTS.md defaults).

## Freedom
<Internal decisions left to the worker.>

## Verification
Working dir: <path>
- `<command>` -> <expected result>
Required test cases: <happy / negative / boundary>

## Stop rules
Iterate autonomously. Report `blocked` for missing contracts, unavailable
environment or the same failure 3 times in a row.
