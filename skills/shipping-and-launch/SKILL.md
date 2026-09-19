---
name: shipping-and-launch
description: Prepares production launches of Flutter mobile apps. Use when preparing a release for the App Store or Google Play, or when asking what needs to be in place before shipping. Use when you need a pre-launch and store-readiness checklist, when setting up crash and release monitoring, when planning a staged or phased rollout, or when you need a rollback and recovery strategy for an app that can't be recalled once installed.
---

# Shipping and Launch

## Overview

Ship with confidence. The goal is not just to release — it's to release safely, with monitoring in place, a recovery plan ready, and a clear understanding of what success looks like. Every launch should be recoverable, observable, and incremental.

**Mobile changes the rules.** You can't recall an installed app, releases pass through store review, and users update on their own schedule, so old versions keep running for weeks or months. Reversibility comes from staged rollouts, feature flags, a minimum-version gate, and a backend that stays compatible with old clients. Plan for all four before you ship.

## When to Use

- Releasing a new version or a first version to the App Store or Google Play
- Releasing a significant change to users
- Migrating data or backend infrastructure the app depends on
- Opening a beta, TestFlight, or closed-testing program
- Any release that carries risk (all of them)

## The Pre-Launch Checklist

### Code Quality

- [ ] All tests pass (unit, Cubit, widget, golden, integration)
- [ ] `flutter analyze` is clean and the release build has no warnings
- [ ] Code formatted, reviewed, and approved
- [ ] No TODO comments that should be resolved before launch
- [ ] No `print` / `debugPrint` debugging statements, debug banners, or dev menus in release code
- [ ] Error handling covers expected failure modes, including offline and slow networks
- [ ] Generated code (freezed, json) is current

### Security

- [ ] No secrets in code, version control, or the app binary
- [ ] Tokens are in secure storage; nothing sensitive in `SharedPreferences`, logs, or backups
- [ ] Dependencies reviewed: `pubspec.lock` committed, advisories triaged, no unvetted plugins or SDKs
- [ ] HTTPS only, and the pinning decision is recorded
- [ ] Release build is obfuscated (`--obfuscate --split-debug-info`) and the symbols are stored
- [ ] Merged Android manifest and `Info.plist` reviewed: permissions minimal, `debuggable` off
- [ ] Authorization enforced on the server; rate limiting on authentication endpoints

See `security-and-hardening` for the full mobile checklist.

### Performance

- [ ] Frame times within budget in profile mode on a real, mid-range device
- [ ] Cold start within the project budget
- [ ] No memory growth across repeated navigation
- [ ] App size within budget (`--analyze-size` compared with the last release)
- [ ] No N+1 queries or unbounded fetches on critical backend paths
- [ ] Images decoded at display size and cached

See `performance-optimization`, or run `/perf-mobile` for a structured audit.

### Accessibility

- [ ] Every interactive element is labeled and reachable with TalkBack and VoiceOver
- [ ] Touch targets are at least 48×48 dp
- [ ] Layout holds at 200% text scale, on small phones, and in landscape
- [ ] Color contrast meets WCAG 2.1 AA (4.5:1 for text) in light and dark themes
- [ ] Dynamic changes (errors, confirmations) are announced
- [ ] Error messages are descriptive and associated with their fields

### Store and Platform Readiness

**Both stores**
- [ ] Version name and a unique, increasing build number set (built by CI)
- [ ] Release notes and store listing content (screenshots for required device sizes, description) ready
- [ ] Privacy declarations match what the app and every bundled SDK actually collect (App Privacy labels and privacy manifest; Play Data safety form)
- [ ] In-app account deletion works end to end
- [ ] Permission requests are justified, requested in context, and their purpose strings are accurate
- [ ] Reviewer access provided if the app needs sign-in (a working demo account)
- [ ] Release set to **manual** or **managed** publishing, so you control when approved builds go live

**App Store**
- [ ] Compliance with the App Store Review Guidelines reviewed for this change (payments, sign-in, content, permissions)
- [ ] Export compliance (encryption) and age rating answered
- [ ] App Tracking Transparency prompt and usage description present if you track
- [ ] In-app purchases configured and tested in the sandbox
- [ ] Phased release selected

**Google Play**
- [ ] Target API level meets the current Play requirement, and the release is an app bundle
- [ ] Content rating and Data safety form complete
- [ ] Signed with the upload key, with Play App Signing enabled
- [ ] Staged rollout configured, and any closed-testing requirements for your developer account satisfied

Store policies and requirements change often; check the current guidelines for both stores rather than trusting a static list.

### Backend and Infrastructure

- [ ] The backend is compatible with **every app version still in use**, not just the new one
- [ ] API and schema changes follow expand-then-contract; nothing old clients depend on is removed
- [ ] Environment configuration set in production, and remote config and feature flag defaults are safe
- [ ] Database migrations applied (or ready to apply) and compatible with old clients
- [ ] Logging, crash reporting, and dashboards configured for the new version
- [ ] Health check endpoint exists and responds
- [ ] Capacity is sized for the rollout, including push notification and update spikes

### Documentation

- [ ] README updated with any new setup requirements
- [ ] API documentation current
- [ ] ADRs written for any architectural decisions
- [ ] Changelog and user-facing release notes updated
- [ ] Support and on-call have the release runbook and know the halt procedure

## Feature Flag Strategy

Ship behind feature flags to decouple release from deployment. On mobile this is your fastest recovery tool, because a flag changes behavior on devices that already have the code, with no store review.

```dart
// Flags come from remote config, with safe defaults when it's unreachable or not yet fetched
if (flags.isEnabled('task-sharing')) {
  return TaskSharingPanel(task: task);   // New feature
}
return const SizedBox.shrink();          // Default: existing behavior
```

**Feature flag lifecycle:**

```
1. RELEASE with flag OFF    → Code is in the store build but inactive
2. ENABLE for team/beta     → Internal testing on production builds
3. GRADUAL ROLLOUT          → 5% → 25% → 50% → 100% of users
4. MONITOR at each stage    → Watch crashes, performance, funnels, feedback
5. CLEAN UP                 → Remove flag and dead code path after full rollout
```

**Rules:**
- Every feature flag has an owner and an expiration date
- Clean up flags within 2 weeks of full rollout
- Don't nest feature flags (creates exponential combinations)
- Test both flag states (on and off) in CI
- **Target by app version and platform**, so a flag never enables code an old build doesn't contain
- **Remember config latency:** clients fetch and cache remote config, so a flag change takes effect on the next fetch, not instantly. Set the fetch interval with that in mind, and keep a **kill switch** for every risky feature
- Keep a **minimum supported version** setting so you can force or prompt updates off a broken release

For flag mechanics in the pipeline, see `ci-cd-and-automation`.

## Staged Rollout

### The Rollout Sequence

```
1. BUILD and verify in CI
   └── Full test suite, release build, integration tests on emulator/device farm
   └── Manual smoke test of critical flows on real devices (see flutter-devtools-and-device-testing)

2. INTERNAL testing (Play internal track / TestFlight internal)
   └── The exact binary you plan to ship, installed the way users install it
   └── Check for crashes, that symbols upload, and that flags and config load

3. BETA (Play closed/open track / TestFlight external)
   └── Real users on real devices and OS versions
   └── Crash-free rate and vitals within threshold before proceeding

4. SUBMIT for review, with manual release
   └── Submit early; review time varies and can slip
   └── Release only after approval, when someone can watch the rollout

5. PRODUCTION, staged (Play staged rollout / App Store phased release)
   └── Start small (for example 5%), with feature flags OFF for risky features
   └── Advance only when all thresholds pass at enough volume (see table below)

6. GRADUAL increase (20% → 50% → 100%), flags enabled progressively
   └── Same monitoring at each step
   └── Halt at any point

7. FULL rollout
   └── Monitor for 1 week, including old versions still in the wild
   └── Clean up feature flags
```

**Store mechanics (verify current behavior):**
- **Google Play** staged rollout lets you choose the percentage, increase it, or halt it. Halting stops new users from receiving the release; it does not remove it from those who have it. You can't roll back to an earlier version code, so the fix is a new build with a higher one.
- **App Store** phased release ramps automatic updates over about seven days, and you can pause it. Users who update manually can still get the new version at any time. Recovery again means a new build.
- Adoption is gradual, so **wait for enough sessions on the new version** to judge it. Time alone is not the gate.

### Rollout Decision Thresholds

Compare the new version against the previous version at each stage. These are defaults; tune them to your app's baseline:

| Metric | Advance (green) | Hold and investigate (yellow) | Halt (red) |
|--------|-----------------|-------------------------------|------------|
| Crash rate (crashed sessions) | Within 10% of baseline | 10-100% above baseline | >2x baseline |
| ANR rate (Android) | Within 10% of baseline | 10-100% above baseline, or approaching Play's bad-behavior threshold | >2x baseline, or over the threshold |
| New crash signatures | None | New crashes at <0.1% of sessions | New crashes at >0.1% of sessions, or any on launch, login, or checkout |
| Cold start (p90) | Within 20% of baseline | 20-50% above baseline | >50% above baseline |
| API error rate from clients | Within 10% of baseline | 10-100% above baseline | >2x baseline |
| Business metrics (funnels, conversion) | Neutral or positive | Decline <5% (may be noise) | Decline >5% |
| Store rating and reviews | Neutral | Emerging complaints about the change | Review spike or rating drop tied to the release |

### When to Halt

Halt the rollout and switch to recovery if:
- Crash rate or ANR rate exceeds 2x baseline
- A new crash appears on a critical flow (launch, login, purchase)
- Cold start regresses by more than 50%
- User-reported issues spike
- Data integrity or data-loss issues are detected
- A security vulnerability is discovered

## Monitoring and Observability

### What to Monitor

```
App metrics (per app version and platform):
├── Crash-free users and sessions
├── ANR rate (Android) and hangs (iOS)
├── Cold start and screen load times
├── Frame jank / slow and frozen frames
├── Network error rates from the client's perspective
├── Adoption: share of users on each version
└── Key business metrics (conversion, engagement, funnels)

Store signals:
├── Play Console Android vitals
├── Xcode Organizer metrics (launches, hangs, memory, battery)
└── Ratings and review sentiment

Backend metrics:
├── Error rate (total and by endpoint), split by client version
├── Response time (p50, p95, p99)
├── Request volume
├── CPU, memory, database connections, queue depth
└── Traffic from old app versions
```

### Error Reporting

Capture Flutter framework errors, uncaught async errors, and platform errors, and report them with the app version and the build's symbols:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Errors caught by the Flutter framework (build, layout, paint)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reportError(details.exception, details.stack, fatal: true);
  };

  // Uncaught async and platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack, fatal: true);
    return true;
  };

  // Show a friendly fallback instead of the red error screen in release builds
  ErrorWidget.builder = (details) => const ErrorFallback();

  runApp(const App());
}
```

Never put tokens or PII in error reports (see `security-and-hardening` and `observability-and-instrumentation`). Upload the obfuscation symbols for each release so stack traces are readable.

```typescript
// Server-side error reporting
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  reportError(err, {
    method: req.method,
    url: req.url,
    userId: req.user?.id,
    appVersion: req.header('X-App-Version'),
  });

  // Don't expose internals to users
  res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
  });
});
```

### Post-Launch Verification

In the first hour after the release goes live:

```
1. Install the production build from the store on a real device (not a sideload) and confirm
   the version and build number
2. Run the critical user flows on it (mobile-mcp can drive them; see flutter-devtools-and-device-testing)
3. Check the crash dashboard for the new version: no new crash signatures, symbols resolve
4. Check cold start and error-rate dashboards against the previous version
5. Confirm feature flags and remote config load, and defaults are safe
6. Check the backend for errors from both new and old client versions
7. Verify the halt procedure is ready: who can pause the rollout, and how
```

## Error Budget Release Gate

Your service's error budget — the fraction of requests or time your SLO allows to fail — determines whether it's safe to ship. Use it as an objective gate — not a negotiation. For an app, crash-free sessions and ANR rate are natural client-side SLIs:

```
Budget remaining > 20%  →  Ship normally; monitor closely
Budget remaining 0–20%  →  Slow rollouts only; no high-risk changes
Budget exhausted        →  Freeze feature work; focus entirely on reliability
Budget resets           →  Resume normal pace; bake in the fix that recovered it
```

A high burn rate during a staged rollout (consuming budget faster than the baseline pace) is a **hold** signal in the rollout thresholds table above — treat it the same as an elevated crash rate.

## Rollback and Recovery Strategy

An installed app can't be recalled, so "rollback" means containing the damage and moving users forward. Every release needs this plan before it ships:

| Lever | Speed | What it does |
|---|---|---|
| Disable a feature flag | Minutes (after clients fetch config) | Turns off the broken feature on devices that already have it |
| Halt the staged rollout | Minutes | Stops new users receiving the release |
| Backend rollback or hotfix | Minutes to hours | Fixes server-side causes; must stay compatible with old clients |
| Ship a fixed build | Hours to days (store review) | Only real fix for a client bug; use a higher build number and request expedited review for severe issues |
| Raise the minimum supported version | After the fixed build is out | Forces or prompts users off the broken release |

```markdown
## Recovery Plan for [Feature/Release]

### Trigger Conditions
- Crash rate or ANR rate > 2x baseline
- Cold start p90 > [X]ms
- New crash on [critical flow]
- User reports of [specific issue]

### Recovery Steps
1. Disable the feature flag (if applicable): owner [name], time to effect [config fetch interval]
2. Halt the staged rollout in [Play Console / App Store Connect]: owner [name]
3. Fix forward: build with a higher build number, submit with expedited review if severe
4. Prompt or force affected versions to update via the minimum-version setting
5. Verify recovery: crash dashboard for the new version, key flows on a real device
6. Communicate: notify team, support, and (if needed) users

### Backend and Data Considerations
- Backend changes for this release are backward compatible with app versions [A–B]
- Migration [X] is expand-only; the contract step ships after the old versions have aged out
- Data written by the new feature: [preserved / cleaned up / migrated]

### Time to Contain
- Feature flag: < [config fetch interval]
- Halt rollout: < 5 minutes
- Fixed build reaching users: [store review time + user update lag]
```

## See Also

- For the project-wide Definition of Done that every change must clear before this checklist, see `../../references/definition-of-done.md`
- For security pre-launch checks, see `../../references/security-checklist.md` and `security-and-hardening`
- For performance pre-launch checks, see `../../references/performance-checklist.md` and `performance-optimization`
- For accessibility verification before launch, see `../../references/accessibility-checklist.md`
- For building, signing, and uploading releases, see `ci-cd-and-automation`
- For crash reporting, logging, and alerting rules tied to SLOs, see `observability-and-instrumentation`

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It works in TestFlight / the internal track, so it'll work in production" | Production has other devices, OS versions, networks, and data. Roll out in stages and monitor. |
| "We can hotfix if it breaks" | A hotfix needs a build, store review, and users updating. Days, not minutes. Use flags and staged rollouts. |
| "Users update automatically" | Many don't, for weeks or months. Your backend must serve old versions, and old bugs stay live. |
| "Store review will catch problems" | Review checks policy compliance, not your crash rate or your funnel. |
| "We don't need feature flags for this" | Every feature benefits from a kill switch. On mobile it is often the only fast recovery. |
| "It's a small change, skip the staged rollout" | Small changes crash launches too. A staged rollout costs nothing and limits the blast radius. |
| "Monitoring is overhead" | Not having monitoring means you discover problems from one-star reviews instead of dashboards. |
| "We'll add crash reporting later" | Add it before launch. You can't debug a crash you can't see, and obfuscated traces need symbols uploaded per release. |
| "Rolling back is admitting failure" | Halting a rollout is responsible engineering. Shipping a broken release to everyone is the failure. |
| "The error rate looks fine, let's keep shipping" | Check the burn rate, not just the current error rate. Consuming budget faster than baseline is a hold signal even when individual thresholds are green. |

## Red Flags

- Releasing without a recovery plan, a kill switch, or a way to halt the rollout
- No crash reporting or symbols for the release
- Big-bang releases (100% at once, no staging)
- Backend changes that break older app versions
- Feature flags with no expiration or owner, or no safe default when config is unreachable
- No one monitoring the rollout for the first hours
- Store privacy declarations that don't match the app's behavior
- Submitting for review at the last minute before a fixed launch date
- Release configuration done by memory, not code (manual signing, manual build numbers)
- "It's Friday afternoon, let's ship it"
- Error budget exhausted but feature work continues unchanged

## Verification

Before releasing:

- [ ] Pre-launch checklist completed (all sections green, including store readiness)
- [ ] Feature flags configured with safe defaults and a kill switch (if applicable)
- [ ] Recovery plan documented: flag, halt, fix-forward, minimum-version gate
- [ ] Backend verified compatible with old app versions
- [ ] Crash reporting, symbols, and monitoring dashboards set up for the new version
- [ ] Release set to manual or managed publishing, with a staged or phased rollout
- [ ] Team, support, and on-call notified, with the runbook

After releasing:

- [ ] Production build installed from the store and verified on a real device
- [ ] Crash rate and ANR rate are normal for the new version
- [ ] Cold start and API error rates are normal
- [ ] Critical user flow works
- [ ] Flags and remote config load, and symbols resolve stack traces
- [ ] Halt procedure tested or verified ready

For every shipped service:

- [ ] Error budget policy in place: know what action to take when budget drops below 20% and when it's exhausted
