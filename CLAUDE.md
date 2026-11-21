# Project guide for agents

This file is read by every factory agent (triage, planning, build, review, fix).
Keep it short and accurate: it is the main lever for the quality of the factory's output.

## Conventions
- Keep changes small and focused on the issue.
- Every behaviour change needs a test.

## Checks
List the exact commands the build / fix agents must run before opening or updating a PR.
<!-- Example:
- `npm ci`
- `npm run lint`
- `npm test`
-->
- (no code yet: there are no checks to run)
