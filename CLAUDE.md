# CLAUDE.md

Project-level guide for Claude Code sessions working in this repository.
The real spec lives in [AGENTS.md](AGENTS.md) — read that first. This file
is an index: what skills are available and what each project doc is for.

## Project docs

| File | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Canonical spec — mission, product story, tech stack, visual source of truth, demo data, required architecture, demo flow, AI safety rules, plans/entitlements, hackathon scope (P0–P3), engineering rules, definition of done. Read in full before implementation work. |
| [docs/FULL_DEVELOPMENT_PLAN.md](docs/FULL_DEVELOPMENT_PLAN.md) | The forward roadmap from the current demo to a production-ready app: Phase 0 (stabilize current demo) through later phases covering service boundaries, Supabase persistence, RevenueCat, Apple Health sync, safe AI and launch QA. This is the active, phase-by-phase plan. |
| [docs/STATUS.md](docs/STATUS.md) | Live status log. Checkpoints, verification runs (`swift test`, simulator build, demo walkthroughs) with PASS/NOT COMPLETE markers, and the next action. Update this after every meaningful phase, per AGENTS.md's engineering rules. |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Short engineering decision log — the *why* behind architectural choices (portable Swift package, Observation-based AppState, demo preview markers vs. real entitlements, reset semantics). Append here when making a non-obvious technical call. |
| [docs/LOVABLE_REFERENCE.md](docs/LOVABLE_REFERENCE.md) | Pointer to the Lovable prototype (visual/product reference only — do not port its React/Tailwind implementation). |
| [docs/reference/README.md](docs/reference/README.md) | Screen-by-screen native-translation notes from inspecting the Lovable reference. |
| [docs/reference/PROGRESS_REVIEW.md](docs/reference/PROGRESS_REVIEW.md) | Notes from the most recent pass reviewing the Lovable preview against the native build. |

## Available skills

### gstack

Invoke with `/office-hours`, `/plan-ceo-review`, etc. Router: `/gstack` or `_gstack-command`.

`/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`,
`/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`,
`/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`,
`/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`,
`/setup-gbrain`, `/retro`, `/investigate`, `/document-release`,
`/document-generate`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`,
`/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`,
`/learn`

Also present but not in the primary CLAUDE.md list: `gstack.bak`, `health`,
`impeccable`, `improve-animations`, `landing-report`, `pair-agent`,
`plan-tune`, `scrape`, `setup-browser-cookies`, `skillify`, `spec`,
`sync-gbrain`.

Skill routing rules for this project (see the parent-directory CLAUDE.md):

- Product ideas/brainstorming → `/office-hours`
- Strategy/scope → `/plan-ceo-review`
- Architecture → `/plan-eng-review`
- Design system/plan review → `/design-consultation` or `/plan-design-review`
- Full review pipeline → `/autoplan`
- Bugs/errors → `/investigate`
- QA/testing site behavior → `/qa` or `/qa-only`
- Code review/diff check → `/review`
- Visual polish → `/design-review`
- Ship/deploy/PR → `/ship` or `/land-and-deploy`
- Save progress → `/context-save`
- Resume context → `/context-restore`
- Author a backlog-ready spec/issue → `/spec`

### superpowers

Process and implementation skills, invoked via the Skill tool by name
(`superpowers:<name>`).

- `using-superpowers` — always active; how to find and use skills.
- `brainstorming` — required before any creative/feature work.
- `systematic-debugging` — required before proposing a fix for a bug/test failure.
- `test-driven-development` — required before writing implementation code for a feature/bugfix.
- `writing-plans` — turn a spec/requirements into a multi-step plan.
- `executing-plans` — execute a written plan in a separate session with review checkpoints.
- `subagent-driven-development` — execute independent plan tasks in the current session.
- `dispatching-parallel-agents` — for 2+ independent tasks with no shared state.
- `using-git-worktrees` — isolate feature work via a worktree.
- `requesting-code-review` — before merging/at major-feature completion.
- `receiving-code-review` — when acting on review feedback.
- `finishing-a-development-branch` — once implementation is complete and tests pass.
- `verification-before-completion` — run and confirm verification commands before claiming work is done.
- `writing-skills` — create/edit/verify skills.

## Notes for this repo

- Native iOS only (Swift/SwiftUI/iOS 17+). No React, Node, Python backend, or
  Android — see AGENTS.md's explicit exclusions.
- `docs/superpowers/` and `docs/Claude_Design/` (early planning spec/plan and
  HTML prototypes) were removed as stale/superseded once their described work
  landed in the app and in `FULL_DEVELOPMENT_PLAN.md`. `docs/IMPLEMENTATION.md`
  was removed for the same reason — its "Xcode is absent" starting state is no
  longer true and its phases duplicated `FULL_DEVELOPMENT_PLAN.md`.
- Repo history was intentionally reset to a single "Initial commit" — do not
  assume old commit SHAs or branches referenced in older docs still exist.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
