---
description: Define and enforce this project's quality bar — interview, sane defaults, CONSTRAINTS.md
---

Invoke the agent-skills:constraint-driven-development skill.

$ARGUMENTS

Default behaviour with no arguments: set up constraints for this repository.

1. **Detect first.** Read pubspec.yaml (and package.json / pyproject.toml / go.mod for the backend), the test runner, existing lint configs, current coverage output, CI workflows, and the agent harness in use. Report what you found in two lines. Never ask for anything you can read.

2. **Interview, at most four questions.** One at a time, each with your best guess and a usable default so "I don't know" still produces a working config:
   - Which dimensions beyond the floor (coverage, security, performance, accessibility, architecture)
   - Block or warn when a check fails mid-task
   - Target numbers, or measure today's values and hold them
   - Slowest check tolerated before handing work back

3. **Write CONSTRAINTS.md** at the repo root with a Floor section, enforced numbers, measured-only metrics with today's values, and an exceptions table with owners and expiry dates. Every number needs a stated reason.

4. **Install what each picked dimension needs.** A dimension with a number and no tool behind it is an aspiration. Use the de facto tool so existing config keeps working: `flutter analyze` and `dart format` for analysis, `flutter test --coverage` for coverage, gitleaks (always `--redact`) for secrets, osv-scanner for dependencies, Semgrep for backend code scanning, `flutter_test` accessibility guidelines for accessibility, `integration_test` timelines and `--trace-startup` for performance, `--analyze-size` for app size, `import_lint` or `custom_lint` for boundaries. Record the exact command next to each rule in CONSTRAINTS.md. Frame and startup checks need a real device or device farm; if the project has none, say so and drop the dimension rather than inventing a check. Add the commands to a Makefile or melos scripts as check:fast / check:task / check:full.

5. **Place each check by cost.** Types, lint and secrets in the edit loop (seconds). Related tests and changed-line coverage at task end (under 90s). Everything else at review or in CI. Scope checks to the diff, not the whole repo.

6. **Point the agent at it.** Add a line to CLAUDE.md telling agents to read CONSTRAINTS.md and never weaken it to make a change pass.

7. **Verify.** Run the constraints against the current branch. If anything fails that the user disagrees with, fix the constraint now rather than leaving a gate people will learn to ignore.

Sub-commands:
- `/constraints check` — run the current constraints against this branch and report
- `/constraints guard` — inspect the diff for a weakened bar: lowered thresholds, skipped or deleted tests, new suppression comments, unfinished stubs, new exceptions
- `/constraints ratchet` — record today's measured values as the floor that must not fall
