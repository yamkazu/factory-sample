# factory-sample

A minimal **software factory on GitHub Actions**, modeled on
[Mastra's software factory](https://mastra.ai/blog/software-factory) /
[Mastra Factory](https://factory.mastra.ai/what-is-factory).
Issues flow through agent stages (Triage → Planning → Building → Review ⇄ Fix → Done),
each stage is a separate agent run with its own instructions, and humans keep the gates
that matter: accepting work, approving the plan, and merging.

```
 issue + label `factory`            (human: accept the task)
        │
        ▼
 ┌─────────────┐  needs-info ──► reporter comments ──┐
 │   Triage    │◄────────────────────────────────────┘
 └─────┬───────┘
       │ ready
       ▼
 ┌─────────────┐
 │  Planning   │ ──► plan comment, label factory:plan-ready
 └─────────────┘
        │  human adds `factory:plan-approved`   (human: approve the plan)
        ▼
 ┌─────────────┐
 │  Building   │ ──► branch factory/issue-N, PR "Closes #N" + evidence
 └─────┬───────┘
       ▼
 ┌─────────────┐ changes-requested ┌─────────┐
 │   Review    │──────────────────►│   Fix   │  (max FACTORY_MAX_FIX_ROUNDS, then needs-human)
 │ (fresh agent)◄──────────────────┤         │
 └─────┬───────┘                   └─────────┘
       │ approved
       ▼
  human merges  ──► issue closed + factory:done   (human: merge)
```

## How it maps to Mastra's design

| Mastra Factory | This repo |
| --- | --- |
| Stages: Intake / Triage / Planning / Building / Review / Done | Labels `factory:*` act as the board; each stage is a workflow job |
| One agent per function | One instruction file per agent in [`.github/factory/agents/`](.github/factory/agents) |
| Isolated sandbox per session | Each stage runs in a fresh GitHub-hosted runner |
| Review session separate from the authoring session | `factory-review.yml` runs a new agent that only reads the diff |
| Feedback returns to the author | `factory-fix.yml` + `@claude` mentions (`factory-assist.yml`) |
| Human gates: accept task, approve plan, merge | `factory` label, `factory:plan-approved` label, normal PR merge |
| "Approve the agent instructions, not every PR" | Agent prompts live in the repo and change via PR review |
| Typed handoffs, fail at the boundary | Each stage must leave a marker comment + label; a missing verdict escalates to `factory:needs-human` |

## Workflows

| File | Trigger | Agent |
| --- | --- | --- |
| `factory-triage-plan.yml` | label `factory`, reporter reply on `needs-info`, label `factory:ready` | Triage → Planning |
| `factory-build.yml` | label `factory:plan-approved` (by a human) | Build, opens PR |
| `factory-review.yml` | dispatched by build/fix, or a non-draft PR opened in this repo | Review, routes the loop |
| `factory-fix.yml` | dispatched by review | Fix |
| `factory-done.yml` | factory PR merged | marks issue `factory:done` |
| `factory-assist.yml` | `@claude` in a comment | general assistant |
| `factory-setup.yml` | manual | creates the labels |

Agents run with [`anthropics/claude-code-action@v1`](https://github.com/anthropics/claude-code-action).

## Setup

1. Add **one** repository secret: `ANTHROPIC_API_KEY`, or `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`).
2. Settings → Actions → General → Workflow permissions: **Read and write**, and tick
   **Allow GitHub Actions to create and approve pull requests**.
3. Run **Actions → "Factory: setup labels" → Run workflow** once.
4. For `@claude` mentions, install the [Claude GitHub App](https://github.com/apps/claude).
5. Fill in the **Checks** section of [`CLAUDE.md`](CLAUDE.md) and add your toolchain
   setup step to `factory-build.yml` / `factory-fix.yml`.

Optional repository variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `FACTORY_MODEL` | per stage below | model for every stage |
| `FACTORY_MODEL_TRIAGE` | `claude-sonnet-5-5` | triage model |
| `FACTORY_MODEL_PLAN` / `_BUILD` / `_REVIEW` | `claude-opus-5-5` | per-stage model routing |
| `FACTORY_MAX_FIX_ROUNDS` | `2` | review ⇄ fix rounds before escalating |
| `FACTORY_BUILD_TOOLS` | see workflow | tools the build/fix agents may use |

## Using it

1. Open an issue, then add the `factory` label.
2. Answer the triage questions if it asks (`factory:needs-info`).
3. Read the plan; add `factory:plan-approved` to build it, or comment and re-add `factory:ready` to re-plan.
4. Wait for `factory:approved` on the PR, review, and merge.

## Known limits

- Pushes and PRs made with `GITHUB_TOKEN` do **not** trigger your other workflows (e.g. CI).
  The factory chains its own stages with `workflow_dispatch`, but if you need regular CI or
  required status checks on factory PRs, switch the token to a GitHub App token
  (`actions/create-github-app-token`).
- Issue and PR text is untrusted input to the agents. Only people with triage/write access
  can add the labels that start a stage, and each stage has a restricted tool list; keep it
  that way when you edit `FACTORY_BUILD_TOOLS`.
- No visual checks for frontend changes (Mastra calls this out as a gap of test-only validation).
