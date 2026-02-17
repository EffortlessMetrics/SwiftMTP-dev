# SwiftMTP Sprint Playbook

*Last updated: 2026-02-16*

This playbook defines how implementation sprints are executed for the `2.x` train. Use it with `Docs/ROADMAP.md` to keep planning, delivery, and release prep aligned.

## Goals

- Keep sprint scope small enough to finish with full gates green.
- Require evidence for behavior changes, especially transport and device quirks.
- Minimize release-week surprises by running release checklist items throughout the sprint.

## Sprint Naming and Scope

Use IDs in the form `2.1-A`, `2.1-B`, `2.1-C`.

- `A` sprint: transport reliability and user-visible error clarity
- `B` sprint: submission and privacy workflow hardening
- `C` sprint: CI/test signal consolidation and local-to-CI parity

Every sprint issue and PR title should include the sprint ID prefix.

Example:

```text
[2.1-A] Fix Pixel 7 timeout fallback after OpenSession
```

## Definition of Ready (DoR)

A sprint item is ready only when all are true:

- Problem statement includes an observed failure signature and expected outcome.
- Acceptance criteria are measurable (command output, test assertion, or artifact path).
- Required device mode is stated (`mtp-unlocked`, `ptp`, `charge-only`, and so on).
- Validation commands are listed and can be run from repo root.
- Docs impact is identified (`README`, troubleshooting, roadmap, or device page).

## Definition of Done (DoD)

A sprint item is done only when all are true:

- Code and tests are merged and match acceptance criteria.
- Required local gates were run (`build`, targeted tests, smoke, and TSAN when applicable).
- Real-device artifact paths are attached for transport/quirk behavior changes.
- Operator-facing docs are updated in the same PR.
- Changelog entry is added or amended under `Unreleased`.

## Weekly Execution Rhythm

### Monday: Plan and Confirm

- Confirm in-scope sprint items and carry-over from prior sprint.
- Re-check dependency blockers and risk owners.
- Verify docs links and command examples still match current scripts/workflows.

### Midweek: Integration Checkpoint

- Run sprint checkpoint gates from `Docs/ROADMAP.release-checklist.md`.
- Triage failures immediately (test flake, behavior regression, docs drift).
- Re-estimate items that need extra hardware validation time.

### Friday: Sprint Close Prep

- Mark done/carry-over per DoD status, not implementation percentage.
- Update roadmap status checkboxes and risk table.
- Move unfinished changelog notes forward with clear next action.

## Required Evidence by Change Type

- Transport behavior: `probe`, `usb-dump`, `device-lab connected` artifacts.
- Quirks or submission flow: `collect --strict`, `validate-submission`, `validate-quirks` outputs.
- CLI contracts: `./scripts/smoke.sh` output and relevant JSON examples.
- Concurrency-sensitive changes: TSAN command output for required suites.

## Carry-Over Rules

When an item is not done at sprint close:

1. Keep the original issue/PR linked.
2. Split remaining work into a new scoped item with a new acceptance criterion.
3. Move only unfinished acceptance criteria, not already-completed work.
4. Update `Docs/ROADMAP.md` to reflect the carry-over explicitly.

## Sprint Kickoff Command Pack

Run from repository root:

```bash
swift build --package-path SwiftMTPKit
swift test --package-path SwiftMTPKit --filter CoreTests
./scripts/smoke.sh
```

For milestone merges and release prep:

```bash
./run-all-tests.sh
```

## Related Docs

- [Roadmap](ROADMAP.md)
- [Testing Guide](ROADMAP.testing.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Contribution Guide](ContributionGuide.md)
- [Troubleshooting](Troubleshooting.md)
