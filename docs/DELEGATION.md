# Delegation policy

How to use subagents on this project without spending more context than they save.
The primary agent stays accountable for correctness, security, and architecture.

## This project

Module boundaries — independent enough to hand to separate agents in parallel:

- `Sources/CardScanner` (52 files) — the library itself
- `Tests/CardScannerTests` (24 files) — Swift Testing suites
- `Example` — sample app, independent of the library's internals

High-risk surfaces — an agent may gather evidence, but make the decision yourself and
verify it against the source:

- **The package's public API.** This is a library other repos consume, so anything `public` is a contract. Renames and signature changes break callers outside this repo.

Validation — delegated work is not finished until the relevant one of these has run:

```bash
swift build
swift test
```

## The rule that decides it

Delegate work whose output you consume as an **input**. Do not delegate a
**conclusion** you intend to act on.

- **Input — safe to delegate.** "Where is X defined and used." "Which files import Y."
  "Distill this build log down to the failing errors." "Does a helper for Z already
  exist here." You open the cited files next, so using the answer verifies it.
- **Conclusion — not safe.** "Nothing else calls this, it is safe to delete." "This
  schema change is backward compatible." "This is thread-safe." Confirming any of
  these costs what finding it cost, so the delegation saves nothing. Do it yourself.

A subagent starts with no conversation context and will re-derive everything you
already know unless you scope it tightly. That re-derivation, not the model, is the
real cost of a vague task.

## Tool primitives

Claude Code — the `Agent` tool:

- `subagent_type: Explore` — read-only fan-out search. Returns locations, not analysis.
- `subagent_type: Plan` — designs a change and returns a plan; makes no edits.
- `subagent_type: general-purpose` — multi-step work, including edits.
- `model` — `haiku` for search, inventory, and log triage; `sonnet` or `opus` for
  anything needing judgment. A cheap agent that finds the code does not thereby get to
  decide what to do about it.
- `run_in_background: true` for anything you are not blocked on. You are notified when
  it finishes, so do not poll for it.
- `isolation: "worktree"` when an agent will edit files and the diff should stay isolated.

Skills are cheaper than agents and often replace one outright. Relevant here:
`swift-api-design-guidelines-skill`, `swift-testing-pro`, `swift-concurrency-pro`.

Do not assume a subagent is cheaper than doing the work inline. Independent model
selection may be unavailable, and parallel agents may not run concurrently. When
models cannot differ, delegate only for a separate context window, a specialist
instruction set, or a genuinely independent review.

## Writing a delegated task

State the exact question, the files or modules in scope, what is explicitly out of
scope, the required output format, and the demand for evidence.

Good:

> In `Sources/CardScanner`, list every public symbol and its declaration. Report `file:line` for each, plus a
> one-line description. Do not propose changes and do not edit anything.

Poor:

> Look at the scanner API and improve it.

## Output discipline

Whatever an agent returns lands in the primary context, so cap it:

- `file:line` citations, never pasted file contents.
- A findings list, not a narrative of what the agent tried.
- Facts separated from assumptions, with uncertainty stated plainly.
- If authoritative evidence could not be found, say so instead of guessing. "This
  appears safe" and "there do not seem to be any callers" are not findings.

## Verifying what comes back

Treat delegated output as untrusted until checked, in proportion to what it decides.

| Kind of finding | Verification |
| --- | --- |
| Locations, inventories, summaries | Confirm the paths exist and spot-check two or three. Using them verifies them. |
| Anything shaping the design or the diff | Read the cited source yourself before acting on it. |
| High-risk surfaces (listed above) | Independent review, not a reread of the summary. Run the strongest check available and validate the failure path, not only the success path. |

Never present a delegated finding as established fact without checking it.

## Parallel work

Parallel agents pay off when the workstreams touch different files — use the module
boundaries above. Do not run agents in parallel over the same files, the same
SwiftData schema, the same shared types, or the same migration sequence. Sequence
those and integrate them yourself.

## When not to delegate

- A direct search answers the question.
- You already have the context loaded.
- The change is one or two files.
- Coordinating and re-verifying would cost more than doing the work.
- The work cannot be meaningfully split.

Prefer the fewest agents that produce a real gain in speed, context isolation, or
review independence.

## Escalation

A delegated agent stops and reports rather than improvising when the task turns
ambiguous, scope grows beyond what was assigned, evidence is missing or contradictory,
a design decision is required, it finds a security, privacy, data-integrity, or
compatibility problem, or validation fails. Preserve the findings; do not invent a
solution.

## Completion

Delegated work is done when the primary agent has read the diff or findings, verified
the consequential claims against source, run the validation above, and stated plainly
what could not be verified.
