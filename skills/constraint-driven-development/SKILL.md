---
name: constraint-driven-development
description: Establishes a project's quality bar as a written contract and stops agents quietly lowering it. Interviews the user on which dimensions matter, supplies sane default thresholds when they have no number in mind, records everything in CONSTRAINTS.md, and watches the diff for a weakened bar — new `// ignore:` or `eslint-disable` suppressions, skipped or deleted tests, assertions stripped out, unimplemented stubs, thresholds edited down. Use when no quality bar is written down, when the user says "set up constraints" or "define our standards", when the user wants dimensions they care about — accessibility, app performance, coverage — set up as enforced constraints, when an agent keeps silencing checks or skipping tests to get to green, when you need a coverage or performance threshold and don't know what number to pick, or when an agent writes more code than anyone will read.
---

# Constraint-Driven Development

## Overview

Other skills in this pack describe what good looks like. `code-review-and-quality` gives you five axes. `test-driven-development` gives you a cycle. `security-and-hardening` gives you a threat list. All of that lives in prose the agent reads and may or may not follow, and none of it survives the end of the session.

This skill produces something different: a written record of **this project's** bar, with numbers, that outlives the conversation and can be checked mechanically.

The reason matters. When you wrote the code, reading it told you whether it was any good. An agent writes more in an afternoon than you will read that week, so the judgement moves out of your head and into checks that run around the loop. Those checks need to exist, they need numbers you actually chose, and they need to fire close enough to the work that the agent fixes its own output.

Spec-driven development says what to build. Test-driven development proves it works. Constraint-driven development defines what "good enough to ship" means, before anyone argues about it in a pull request.

## When to Use

Apply this skill when:

- Starting a project or a significant feature and no quality bar is written down
- The user asks to "set up constraints", "add quality gates", "define our standards", or "stop the agent shipping junk"
- An agent is producing volume nobody is reading line by line
- CI has checks but nobody can say which ones block a merge and which ones are decoration
- Coverage, performance, or accessibility numbers get argued about per-PR instead of decided once
- You're about to run `/build auto` or any autonomous loop, and the only thing standing between it and main is a test suite the agent also wrote

**When NOT to use:**

- The project already has a `CONSTRAINTS.md` and the user isn't changing it — read it and follow it instead
- One-off scripts, spikes, throwaway prototypes
- The user wants a code review right now (`code-review-and-quality`) or a CI pipeline built (`ci-cd-and-automation`)
- Pre-product-market-fit code with a two-week expected lifetime — the floor below is still worth it, the rest isn't

## Loading Constraints

The interview needs a live user. **Don't run it in non-interactive contexts** (CI, `/loop`, autonomous runs). If constraints are missing and you're in one of those, apply the Floor below, note that you did, and flag the rest for a human.

## The Process

### Step 1: Detect before you ask

Never ask what you can read. Before the first question, gather:

| What | Where to look |
|------|---------------|
| Language and stack | `pubspec.yaml` (Flutter or pure Dart, SDK constraints), `.fvmrc`; backend: `package.json`, `pyproject.toml`, `go.mod` |
| Test runner | `flutter_test` / `test` in dev dependencies, `test/` and `integration_test/`, `melos.yaml` |
| Existing linters | `analysis_options.yaml` (`flutter_lints`, `very_good_analysis`), `dart_code_linter` config |
| Coverage today | `coverage/lcov.info`, or run `flutter test --coverage` once |
| CI | `.github/workflows/`, `.gitlab-ci.yml` |
| Agent harness | `.claude/`, `.codex/`, `AGENTS.md` |

Report what you found in two lines, then ask only what's left.

### Step 2: Four questions, each with a default

Follow the one-question-at-a-time discipline from `interview-me`, with one change: every question here has a default, so "I don't know" is a complete answer that still produces a working config.

```
Q1: Beyond the floor, which of these do you want enforced?
    (a) Test coverage on new code
    (b) Security scanning
    (c) Performance budgets (frame times, startup, app size)
    (d) Accessibility (semantics, touch targets, contrast in widget tests)
    (e) Architecture boundaries
GUESS: (a) and (b) — you have a test runner already and you're handling user input.
DEFAULT if unsure: (a) and (b).
Say what each pick costs: (c) needs a device or device farm for frame and startup numbers, (d) needs accessibility guideline tests written, (e) needs a rules file written.
```

```
Q2: When a check fails while the agent is mid-task, should it block or warn?
GUESS: Block. You're running agents unattended and a warning nobody reads is a warning.
DEFAULT if unsure: Block on the floor, warn on everything else for the first two weeks.
```

```
Q3: Do you have target numbers in mind, or should I measure where you are today and hold that line?
GUESS: Measure. Most teams don't have a number, and an invented one gets ignored.
DEFAULT if unsure: Measure and hold. See "Ratchets" below.
```

```
Q4: What's the slowest check you'll tolerate before the agent hands work back?
GUESS: About 90 seconds. Longer and you'll stop running it.
DEFAULT if unsure: 90 seconds at task end, unlimited in CI.
```

Stop at four. A twelve-question intake produces a config nobody understands and a user who regrets starting.

### Step 3: Write CONSTRAINTS.md

One file at the repo root. Any agent on any harness can read it, and a change to it shows up in review where it belongs.

```markdown
# Constraints

Last reviewed: 2026-08-08 by @addy

## Floor (always enforced, no setup required)

- No new suppression comments: `// ignore:`, `// ignore_for_file:`, `// coverage:ignore-*` (backend: `@ts-ignore`, `eslint-disable`, `# noqa`)
- No unimplemented stubs: `throw UnimplementedError()`, empty `catch (_) {}`
- No skipped or deleted tests (`skip:`, `@Skip`) without a reason in the commit message
- No secrets in source
- This file does not get weakened to make a change pass

## Enforced with numbers

| Dimension | Rule | Checked by | Runs at |
|-----------|------|-----------|---------|
| Analysis | Zero analyzer issues (errors, warnings, lints) | `flutter analyze` | every edit |
| Format | Formatted | `dart format --output=none --set-exit-if-changed .` | every edit |
| Secrets | No secrets in source | `gitleaks detect --redact` | every edit |
| Coverage | Changed lines ≥ 80% covered | `flutter test --coverage` + git diff | task end, CI |
| Security: code | No high findings | analyzer lints (app), `semgrep scan --config p/default` (backend) | CI |
| Security: deps | Nothing at high or above | `osv-scanner scan source -r .` | CI |
| Accessibility | Zero guideline failures (tap target, label, contrast) | `flutter test test/accessibility/` | task end, CI |
| Performance: frames | p99 frame build and raster ≤ 16.6ms | `flutter drive --profile` timeline on a device | release candidate |
| Performance: startup | Cold start within budget | `flutter run --profile --trace-startup` | release candidate |

Every row names the command that produces the verdict. A dimension with a
number and no command in this column is an aspiration, not a constraint.

## Measured, not yet enforced

| Metric | Today | Direction |
|--------|-------|-----------|
| Project coverage | 62.4% | must not fall |
| App size (Android app bundle) | 18.4 MB | must not grow |

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|----|------|------|--------|-------|---------|
| W1 | `avoid_dynamic_calls` | `lib/legacy/**` | Rewrite tracked in ENG-441 | @addy | 2026-11-01 |
```

Then add one line to `AGENTS.md` and `CLAUDE.md`: `Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass.`

### Step 4: Install what each dimension needs

Picking a dimension means installing something. Don't leave the user with a number and no mechanism, and don't invent your own checker when a de facto one exists — these tools are listed because their rule formats and thresholds are what everything else in the ecosystem targets, so the team's existing config keeps working.

| Dimension | Tool | Install | Run | Gate on |
|-----------|------|---------|-----|---------|
| Analysis and lint | the Dart analyzer + your `analysis_options.yaml` | already there | `flutter analyze` | any issue |
| Format | `dart format` | already there | `dart format --output=none --set-exit-if-changed .` | any change needed |
| Coverage (Dart) | your test runner | already there | `flutter test --coverage` (writes `coverage/lcov.info`) | coverage of changed lines |
| Accessibility | `flutter_test` guidelines | already there | `flutter test` (tests using `meetsGuideline(...)`) | zero failures |
| Performance: frames | `integration_test` + `TimelineSummary` | already there | `flutter drive --profile --driver=... --target=...` on a device | p90/p99 frame build and raster budget |
| Performance: startup | Flutter tooling | already there | `flutter run --profile --trace-startup` | time to first frame budget |
| Performance: app size | Flutter tooling | already there | `flutter build appbundle --analyze-size` | size budget vs. baseline |
| Architecture | `import_lint` (or a `custom_lint` rule) | `dart pub add --dev import_lint` | see the package's README | any violation |
| Assertion quality | a Dart mutation-testing package (optional; tooling is less mature than in JS) | per package | scope to changed files | mutation score |
| Security: secrets | gitleaks | `brew install gitleaks` | `gitleaks detect --redact --no-banner` | any finding |
| Security: dependencies | osv-scanner | `brew install osv-scanner` | `osv-scanner scan source -r .` (reads `pubspec.lock`) | high or above |
| Security: code (backend) | Semgrep | `pipx install semgrep` | `semgrep scan --config p/default --config p/owasp-top-ten` | any high finding |
| Types, lint, coverage (backend) | your stack's own tools | already there | `tsc --noEmit`, `eslint .`, `vitest run --coverage`, `mypy .`, `ruff check` | any error / changed-line coverage |

Five things that will bite you if you skip them:

1. **`--redact` on gitleaks is not optional.** Without it the matched secret lands in the agent's transcript, which is how a leaked key ends up in a log, a summary, or a commit message. Report the rule and the location, never the value.
2. **Frame, startup, and integration checks need a device.** They only work against a running app in profile mode, on a real device or a device farm (an emulator is fine for correctness, not for timing). They belong in a runtime stage such as a release-candidate or nightly job, not the edit loop. If the project has no UI or no device to run on — a package, a CLI — say so and drop the dimension rather than inventing a check that can't run.
3. **Scope the expensive ones to the diff.** Mutation testing on the whole repo takes hours and gets turned off; on the files a change touched it takes under a minute. Same for Semgrep, which takes a path list, and for `flutter test`, which accepts the test files related to what changed.
4. **Coverage needs no second test run.** Read the lcov your suite already writes and intersect it with `git diff`. Running the suite twice to get a number is the fastest way to make people hate this.
5. **Semgrep's registry rules are free to run; check the licence before redistributing them.** `opengrep` is a drop-in fork with the same rule format and JSON output if that matters to your legal team.

Add each one to the project's own script so it's reproducible without an agent:

```makefile
# Makefile (or melos scripts): the same three tiers for a Flutter project
check-fast:
	dart format --output=none --set-exit-if-changed . && flutter analyze && gitleaks detect --redact --no-banner

check-task: check-fast
	flutter test --coverage

check-full: check-task
	osv-scanner scan source -r .
```

That mapping matters more than the tools. `check:fast` is what runs after an edit, `check:task` when the agent thinks it's done, `check:full` in CI.

The commands now live in two places — the `Checked by` column in `CONSTRAINTS.md` and these scripts. If freezed or other generated code is committed, `check-fast` should run `dart run build_runner build -d` first, or CI will analyze stale output. `CONSTRAINTS.md` is the canonical source: it carries the reason alongside each command and it shows up in review. The scripts are convenience wrappers that must mirror it, not a second source of truth; if they drift, the file wins.

### Step 5: Wire it to the lifecycle

The single biggest mistake is running everything everywhere. A check that stalls the agent gets switched off, and a gate people switched off is worse than no gate, because the bar still looks like it exists.

| Phase | Command | What runs | Budget |
|-------|---------|-----------|--------|
| BUILD | `/build` | Types, lint, secrets, the floor | under 5s, changed file only |
| VERIFY | `/test` | Related tests, coverage on changed lines | under 90s |
| REVIEW | `/review` | Everything, plus the guards below | minutes |
| SHIP | `/ship` | Direction checks, no regressions | CI |

Two rules that keep this tolerable:

1. **Scope to the diff.** Check the lines this change touched, not the whole repo. Coverage of changed lines is a number the agent can move; project coverage is one it inherited.
2. **Cost decides placement.** Anything over a few seconds moves out of the edit loop. Mutation testing on a whole repo takes hours; on the files a change touched it takes under a minute, which is the difference between a check people run and one they don't.

### Step 6: Guard the bar itself

Someone will point out that if the agent writes the code and the checks, the checks prove nothing. Half right, and worth engineering around.

Agents don't craft clever loopholes. They hit a red check and take the cheapest road to green. Watch for these five moves in the diff, at review time:

1. **The threshold moved.** A budget lowered, a severity dropped, a check removed from the fast stage. Compare `CONSTRAINTS.md` against its state at the branch point.
2. **A test got easier.** `skip:` or `@Skip` added, a test file deleted, a golden regenerated to make a failure go away, assertions pulled out of tests that stayed.
3. **A checker got silenced.** New `// ignore:` or `// ignore_for_file:` (or `@ts-ignore` / `eslint-disable` in the backend). Four suppressions deserve special attention because they switch off a check you're relying on: `// coverage:ignore-line` (and `-file` / `-start`) drops code from coverage instead of testing it, a mutation-testing disable hides a surviving mutant, `nosemgrep` and `gitleaks:allow` do it for security findings.
4. **Work is unfinished.** A `throw UnimplementedError()` stub, an empty `catch` turning a failure into silence, a `TODO` standing where the implementation should be.
5. **An exception appeared.** A new row in the Exceptions table nobody discussed.

None of this needs tooling beyond `git diff`. Tightening the bar should be silent; loosening it should be loud.

Unlike the numbered dimensions, the floor has no de facto tool of its own, so an agent asked to enforce it tends to write a checker from scratch, and two agents write two different ones. A reference implementation of these five checks ships with this skill in [references/floor-guard.md](references/floor-guard.md) (diff-scoped, exit `0`/`1`/`2`, patterns adaptable per ecosystem). Adapt that rather than reinventing it, for the same reason every dimension names a de facto tool: so the mechanism is the same across runs and stacks.

**Not all checks are equally circular.** Rank them by one question: can the agent make this pass by writing code that doesn't work?

- **External** — the analyzer and `flutter_test`'s accessibility guidelines encode platform and WCAG rules, `osv-scanner` reads a vulnerability database, a profile-mode frame timeline measures a real device. The agent can't argue with these.
- **Project** — your lint rules, your layer boundaries. A human owns the file.
- **Suite** — your own tests. Most useful, and the only genuinely circular one.

A bar made entirely of the third kind is worth less than one with an outside opinion in it. Check that at least one external constraint is present.

### Step 7: Ratchets, when you don't have a number

Set 80% coverage on a codebase at 62% and you get a red build forever, then a team that learns to ignore red builds.

The alternative asks for no decision: record where you are, then refuse to get worse. Put it in the "Measured, not yet enforced" table with today's number and a direction. Every check compares against the recorded value, not an aspiration. When a number improves, update it; when it drops, that's the finding.

This also answers a fair objection to training. Models are rewarded for passing tests, which you can evaluate in seconds. Architectural rot shows up over months and never reaches the weights. A ratchet is the missing penalty, written down where the build can see it.

## Sane Defaults

When the user has no opinion, use these. They're chosen to be met by most codebases on day one.

| Constraint | Default | Why this number |
|------------|---------|-----------------|
| Coverage of changed lines | ≥ 80% | High enough to force a test, low enough to allow a config line |
| Project coverage | today's value, must not fall | No argument needed to adopt |
| Mutation score (if used) | ≥ 60% to start | Typical for a suite never mutated before; 80% is mature |
| Dependency vulnerabilities | nothing at high or above | Below that is mostly noise |
| Frame build and raster time (p99, profile mode) | ≤ 16.6ms (8.3ms on 120Hz devices) | One frame at 60Hz; measured on a mid-range device |
| Cold start | project budget, ratchet from today's value | Android vitals flags 5s or more as slow |
| App size | today's value, must not grow | No argument needed to adopt |
| Accessibility | zero guideline failures (tap target, label, contrast) in widget tests | Automated checks catch the mechanical failures |
| Exception lifetime | 90 days | Long enough to plan the fix, short enough to remember |
| Ratchet tolerance | 0.5% | Absorbs drift when an unrelated file moves the number |

State the number and the reason together. A threshold without a rationale gets deleted by the next person who hits it.

## Escalation Path

Constraints work at three levels of teeth. Start at the first.

1. **Written only.** `CONSTRAINTS.md` exists and agents read it. Costs nothing, catches the honest mistakes, relies on the agent complying.
2. **Scripted.** A `make check` (or melos script) that runs the fast checks, wired into your agent's post-edit hook and your CI. Deterministic, no new dependency.
3. **Tool-backed.** A dedicated runner that handles diff scoping, budgets, ratchets, and the guard checks. Use when the config outgrows a shell script. The floor-guard reference in [references/floor-guard.md](references/floor-guard.md) is the starting point for the guard-checks half of this.

Most projects should stop at 2. Move to 3 when you're maintaining more than about thirty lines of check-running shell.

**A first run can be floor-only.** The floor guard is diff-only and needs no installs, so you can enforce the floor on day one and add numbered dimensions as you install each tool, rather than standing up every checker before the first commit is protected. Security tools that install machine-wide (gitleaks, osv-scanner) can also run CI-only if you'd rather keep laptops clean; declare where each dimension runs in the `Runs at` column.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "We'll add constraints once the code settles" | Code settles around whatever was allowed while it was moving |
| "The tests are the constraints" | Tests you wrote prove you agree with yourself; they say nothing about coverage of new code, dependency risk, or bundle growth |
| "We can't hit 80% coverage" | Then don't set 80%. Set today's number and hold it |
| "This will slow the agent down" | Only if you put slow checks in the fast loop. That's a placement error, not an argument against constraints |
| "I'll remember what our standards are" | The agent won't, and it's writing most of the code |
| "Constraints will block us shipping" | An exception with an owner and a date unblocks you. Deleting the constraint unblocks everyone forever |

## Red Flags

Stop and reconsider if you notice:

- The interview ran past four questions, or produced a config the user can't explain
- A budget was set that the codebase fails today, with no plan to reach it
- A dimension was written into CONSTRAINTS.md with a number but no tool behind it
- A checker was hand-rolled when a de facto one exists, so the team's existing config is ignored
- Every constraint is checked by the project's own test suite, with no external opinion
- `CONSTRAINTS.md` changed in the same commit as the feature that was failing
- An exception has no owner, or an expiry more than a year out
- The agent proposed relaxing a threshold instead of fixing the code
- Slow checks landed in the edit loop and someone has started passing `--no-verify`
- Nobody has opened `CONSTRAINTS.md` since it was written

## Verification

The skill was applied correctly when:

- [ ] `CONSTRAINTS.md` exists, and every number in it has a stated reason
- [ ] The floor is enforced and passes on the current codebase without changes
- [ ] Every dimension the user picked has a tool installed and a command that runs today
- [ ] Each constraint says where it runs, and the fast stage stays under a few seconds
- [ ] At least one constraint is external (not judged by this project's own tests)
- [ ] Measured-only metrics record today's value and a direction
- [ ] Exceptions have an owner and an expiry date
- [ ] `AGENTS.md` or `CLAUDE.md` points at the file
- [ ] A trial run on the current branch produces no failures the user disagrees with

## See Also

- `interview-me` — the one-question-at-a-time discipline this skill's intake borrows
- `code-review-and-quality` — how to review; this skill decides what the review enforces
- `ci-cd-and-automation` — building the pipeline these constraints run in
- `test-driven-development` — the suite that coverage and mutation constraints measure
- `security-and-hardening` — what the security dimension should contain
- `performance-optimization` — where the performance numbers come from
