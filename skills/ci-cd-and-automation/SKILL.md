---
name: ci-cd-and-automation
description: Automates CI/CD pipeline setup for Flutter apps. Use when setting up or modifying build, signing, and release pipelines. Use when you need to automate quality gates (format, analyze, test, build), configure emulator or device tests in CI, handle code signing and build numbers, distribute to TestFlight or Play tracks, or establish staged rollouts and rollback plans.
---

# CI/CD and Automation

## Overview

Automate quality gates so that no change reaches users without passing format, analysis, tests, and build. CI/CD is the enforcement mechanism for every other skill — it catches what humans and agents miss, and it does so consistently on every single change.

**Shift Left:** Catch problems as early in the pipeline as possible. A bug caught by the analyzer costs minutes; the same bug caught in a store review, or by users, costs days. Move checks upstream — static analysis before tests, tests before device builds, device builds before store tracks.

**Faster is Safer:** Smaller batches and more frequent releases reduce risk, not increase it. A release with 3 changes is easier to debug than one with 30. Frequent releases build confidence in the release process itself.

**Mobile raises the stakes on release automation.** You cannot roll back an installed app, every release passes through store review, and each upload needs valid signing and a unique, increasing build number. Manual signing and uploading is where mobile releases go wrong. Automate them.

## When to Use

- Setting up a new Flutter project's CI pipeline
- Adding or modifying automated checks
- Configuring release, signing, and store-distribution pipelines
- When a change should trigger automated verification
- Debugging CI failures

## The Quality Gate Pipeline

Every change goes through these gates before merge:

```
Pull Request Opened
    │
    ▼
┌────────────────────┐
│   DEPENDENCIES      │  flutter pub get --enforce-lockfile
│   ↓ pass            │
│   CODE GENERATION   │  dart run build_runner build -d (freezed, json)
│   ↓ pass            │
│   FORMAT CHECK      │  dart format --set-exit-if-changed
│   ↓ pass            │
│   ANALYZE           │  flutter analyze
│   ↓ pass            │
│   UNIT + WIDGET     │  flutter test --coverage (incl. goldens)
│   ↓ pass            │
│   BUILD             │  flutter build apk / ios --no-codesign
│   ↓ pass            │
│   INTEGRATION       │  integration_test on emulator/simulator
│   ↓ pass            │
│   DEPENDENCY CHECK  │  pubspec.lock committed, advisories triaged
│   ↓ pass            │
│   APP SIZE          │  --analyze-size vs. baseline
└────────────────────┘
    │
    ▼
  Ready for review
```

**No gate can be skipped.** If analysis fails, fix the code — don't disable the lint rule. If a test fails, fix the code — don't skip the test.

Two Flutter-specific rules:

- **Pin the Flutter version** (declare `environment: flutter:` in `pubspec.yaml`, or use FVM's `.fvmrc`) so local machines and CI build with the same SDK. Bump it deliberately in its own PR.
- **Run code generation in CI.** If generated files (`*.freezed.dart`, `*.g.dart`) are gitignored, CI must generate them before analyzing and testing. If they are committed, add a check that regenerating produces no diff (`git diff --exit-code`).

## GitHub Actions Configuration

### Basic CI Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: pubspec.yaml   # Same pinned SDK as local
          cache: true

      - name: Install dependencies
        run: flutter pub get --enforce-lockfile

      - name: Generate code
        run: dart run build_runner build -d

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed .

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test --coverage

      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
```

### Build Jobs

Analysis and tests don't prove the app compiles for each platform. Add build jobs, depending on the quality job:

```yaml
  build-android:
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'          # Match the JDK your Android Gradle Plugin requires
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d
      - name: Build (compile check; release signing happens in the release workflow)
        run: flutter build apk --debug

  build-ios:
    needs: quality
    runs-on: macos-latest             # macOS minutes cost more; see CI Optimization
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d
      - name: Build (no code signing)
        run: flutter build ios --debug --no-codesign
```

### Integration and E2E Tests

`integration_test` needs a running device. On CI that is an emulator or simulator (or a device farm for real hardware).

```yaml
  integration-android:
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d
      # Enable hardware acceleration (KVM) as described in the emulator-runner action's README
      - name: Integration tests on an emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: x86_64
          script: flutter test integration_test
```

- Run against a fake or local backend so results are deterministic, never a shared staging service.
- **Emulators are for correctness, not performance.** For frame-time and startup budgets, use a real device or a device farm (Firebase Test Lab, AWS Device Farm, BrowserStack). See `performance-optimization`.
- Native flows (permission dialogs, notifications) need a tool that can drive native UI, such as `patrol`. See `test-driven-development`.
- iOS integration tests run on a macOS runner with a booted simulator, or on a device farm.

## Feeding CI Failures Back to Agents

The power of CI with AI agents is the feedback loop. When CI fails:

```
CI fails
    │
    ▼
Copy the failure output
    │
    ▼
Feed it to the agent:
"The CI pipeline failed with this error:
[paste specific error]
Fix the issue and verify locally before pushing again."
    │
    ▼
Agent fixes → pushes → CI runs again
```

**Key patterns:**

```
Format failure   → Agent runs `dart format .` and commits
Analyze failure  → Agent runs `dart fix --apply` for safe fixes, then fixes the rest by hand
Codegen diff     → Agent runs `dart run build_runner build -d` and commits the regenerated files
Test failure     → Agent follows the debugging-and-error-recovery skill
Golden mismatch  → Agent checks whether the diff is a real visual change or a platform font
                   difference before touching the golden; never blindly `--update-goldens`
Gradle/Pods error→ Agent checks SDK, JDK, and dependency versions, and the lockfiles
Signing/upload   → Agent checks secrets, build number uniqueness, and store API errors
```

## Release Automation

Releases are built and uploaded by CI from a tag or a protected branch, never from a developer's laptop.

### Versioning

`pubspec.yaml`'s `version: 1.4.0+27` is `build-name+build-number`. The **build number must be unique and increasing for every upload** to each store. Derive it from CI (for example the run number) instead of editing it by hand, and keep the human-readable version in `pubspec.yaml` or the tag:

```bash
flutter build appbundle --release --build-name=1.4.0 --build-number=$GITHUB_RUN_NUMBER
```

A re-run of the same workflow reuses the run number: treat a duplicate build number as a release failure to fix, not to bypass.

### Code Signing

Signing keys are the most sensitive secrets in the pipeline.

- **Android:** keep the upload keystore out of the repository. Store it base64-encoded in the CI secret store, restore it at build time, and generate `key.properties` from secrets. Use Play App Signing so Google holds the app signing key and a lost upload key is recoverable.
- **iOS:** prefer managed signing (Fastlane `match`, Codemagic's managed signing) over manually exporting certificates. Authenticate to App Store Connect with an **API key**, not a personal Apple ID password.
- Signing secrets belong only in the release workflow, scoped to a protected environment. PR builds never receive them.

### Release Workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags: ['v*']

jobs:
  android:
    runs-on: ubuntu-latest
    environment: production          # Protected environment: required reviewers, scoped secrets
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d

      - name: Restore upload keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          STORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks
          printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=upload-keystore.jks\n' \
            "$STORE_PASSWORD" "$KEY_PASSWORD" "$KEY_ALIAS" > android/key.properties

      - name: Build app bundle
        run: >
          flutter build appbundle --release
          --obfuscate --split-debug-info=build/symbols
          --build-number=${{ github.run_number }}

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
          working-directory: android

      - name: Upload to the Play internal track
        working-directory: android
        env:
          SUPPLY_JSON_KEY_DATA: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}   # Check the env var name in Fastlane's docs
        run: bundle exec fastlane internal

      - uses: actions/upload-artifact@v4       # Keep the symbols for de-obfuscating crash reports
        with:
          name: debug-symbols
          path: build/symbols
```

The iOS job follows the same shape on a `macos-latest` runner: `flutter build ipa --release --obfuscate --split-debug-info=build/symbols --build-number=...`, signing via `match` or managed signing, and `upload_to_testflight` authenticated with an App Store Connect API key from secrets.

Upload the split debug symbols to your crash reporter (see `observability-and-instrumentation`), or the obfuscated stack traces are unreadable.

### Fastlane Lanes

Fastlane keeps store uploads scriptable and reviewable. Check its docs for the options in your version:

```ruby
# android/fastlane/Fastfile
default_platform(:android)

platform :android do
  desc 'Upload the release bundle to the internal track'
  lane :internal do
    upload_to_play_store(
      track: 'internal',
      aab: '../build/app/outputs/bundle/release/app-release.aab'
    )
  end

  desc 'Promote internal to production at a staged rollout fraction'
  lane :promote do |options|
    upload_to_play_store(
      track: 'internal',
      track_promote_to: 'production',
      rollout: options[:rollout] || '0.05',
      skip_upload_aab: true
    )
  end
end
```

Codemagic is a Flutter-focused CI/CD service that bundles signing and store publishing, and is a reasonable alternative to assembling this on GitHub Actions.

## Deployment Strategies

### Preview Builds

Every PR that needs manual testing gets an installable build, the mobile equivalent of a preview deployment:

- Distribute a build to testers with Firebase App Distribution, TestFlight internal groups, or a Codemagic/CI artifact.
- Trigger on a label (for example `preview`) so macOS and signing minutes are spent only when needed.
- Preview builds use a separate flavor and bundle ID (see Environment Management), so they install next to the production app.

### Feature Flags

**On mobile, feature flags are your rollback tool.** An installed app can't be reverted, and a hotfix takes store review and user updates. Flags decouple release from deployment: ship code dark, then enable it remotely.

- **Ship code without enabling it.** Merge to main early, enable when ready.
- **Turn off a broken feature without a new release.** Disable the flag instead of waiting for a hotfix to propagate.
- **Canary new features.** Enable for 1% of users, then 10%, then 100%.
- **Run A/B tests.** Compare behavior with and without the feature.

```dart
// Simple feature flag pattern (flags come from remote config, with safe defaults)
Widget build(BuildContext context) {
  final flags = context.read<FeatureFlags>();
  return flags.isEnabled('new-checkout-flow')
      ? const NewCheckoutPage()
      : const LegacyCheckoutPage();
}
```

- Default every flag to its **safe** value when remote config is unreachable or not yet fetched.
- Keep a **kill switch** for risky features, and a **minimum supported version** setting so you can force-update users off a broken release.
- **Flag lifecycle:** Create → Enable for testing → Canary → Full rollout → Remove the flag and dead code. Flags that live forever become technical debt: set a cleanup date when you create them.

### Staged Rollouts

Both stores support staged releases. Use them.

```
Tag pushed → CI builds, signs, uploads
    │
    ▼
Internal testing (Play internal track / TestFlight internal)
    │ Smoke test on real devices
    ▼
Beta (Play closed/open track / TestFlight external)
    │ Crash-free rate and vitals within threshold
    ▼
Production, staged (Play staged rollout %, App Store phased release)
    │ 5% → 20% → 50% → 100%, watching crash rate, ANRs, and key flows at each step
    │
    ├── Regression detected → Halt the rollout, disable the flag, ship a fix
    └── Clean → Continue to 100%
```

See `shipping-and-launch` for go/no-go criteria and monitoring.

### Rollback Plan

You cannot recall an installed app. Plan for that:

| Situation | Response |
|---|---|
| Regression in a flagged feature | Turn the flag off remotely |
| Regression in a staged rollout | Halt the rollout in the store console; users who haven't updated stay on the old version |
| Regression in a shipped release | Ship a fixed build (expedited review if severe) and use the minimum-version setting to move users forward |
| Bad backend change | Roll back the backend, and keep API changes backward compatible with old app versions |

Every release should have a defined answer to "how do we stop this, and how do we fix it?" before it goes to production.

## Environment Management

```
Flavors:
  dev       → bundle ID com.example.app.dev,  dev backend,     dev Firebase project
  staging   → bundle ID com.example.app.stg,  staging backend, staging Firebase project
  prod      → bundle ID com.example.app,      production

config/dev.json, config/staging.json   → Committed, non-secret configuration
.env / real secrets                    → NOT committed
CI secrets                             → Stored in GitHub Secrets / vault
Signing + store credentials            → Release environment only (protected)
```

```bash
flutter run --flavor staging --dart-define-from-file=config/staging.json
flutter build appbundle --flavor prod --dart-define-from-file=config/prod.json
```

- **Separate bundle IDs per flavor** so development, staging, and production builds install side by side and can't share data or push tokens.
- `--dart-define` values end up in the binary. Use them for environment selection and public identifiers, never for real secrets (see `security-and-hardening`).
- CI should never have production secrets outside the release workflow. Use separate credentials for CI testing.

## Automation Beyond CI

### Dependabot / Renovate

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: pub
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
  - package-ecosystem: bundler          # Fastlane
    directory: /android
    schedule:
      interval: weekly
```

Review dependency PRs as you would any new dependency: read the changelog, check for new native code and permissions, and let CI (including the build jobs) prove they compile on both platforms. Bump the Flutter SDK deliberately in its own PR.

### Build Cop Role

Designate someone responsible for keeping CI green. When the build breaks, the Build Cop's job is to fix or revert — not the person whose change caused the break. This prevents broken builds from accumulating while everyone assumes someone else will fix it.

### PR Checks

- **Required reviews:** At least 1 approval before merge
- **Required status checks:** CI must pass before merge
- **Branch protection:** No force-pushes to main
- **Auto-merge:** If all checks pass and approved, merge automatically

## CI Optimization

When the pipeline exceeds 10 minutes, apply these strategies in order of impact:

```
Slow CI pipeline?
├── Cache dependencies
│   ├── flutter-action `cache: true` caches the SDK and pub cache
│   ├── Cache Gradle (setup-gradle) for Android builds
│   └── Cache CocoaPods (keyed on Podfile.lock) for iOS builds
├── Run jobs in parallel
│   └── Split format/analyze, tests, Android build, and iOS build into separate parallel jobs
├── Only run what changed
│   └── Use path filters to skip unrelated jobs (docs-only PRs; iOS build only when ios/ or pubspec changes)
├── Shard the test suite
│   └── `flutter test --total-shards N --shard-index i` across runners
├── Move slow work off the critical path
│   └── Run emulator integration tests and full device-farm runs on merge or nightly, not on every PR
├── Watch macOS runner cost
│   └── macOS minutes cost several times more than Linux: run iOS builds only where they add signal
└── Use larger runners
    └── GitHub-hosted larger runners or self-hosted for CPU-heavy builds
```

**Example: parallelism and sharding**
```yaml
jobs:
  static:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1, 2, 3]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version-file: pubspec.yaml, cache: true }
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build -d
      - run: flutter test --total-shards 3 --shard-index ${{ matrix.shard }} --coverage
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "CI is too slow" | Optimize the pipeline (see CI Optimization), don't skip it. A 5-minute pipeline prevents hours of debugging. |
| "This change is trivial, skip CI" | Trivial changes break builds. CI is fast for trivial changes anyway. |
| "The test is flaky, just re-run" | Flaky tests mask real bugs and waste everyone's time. Fix the flakiness. |
| "We'll add CI later" | Projects without CI accumulate broken states. Set it up on day one. |
| "Manual testing is enough" | Manual testing doesn't scale and isn't repeatable. Automate what you can. |
| "macOS runners are expensive, skip the iOS build" | An Android-only green build hides iOS breakage until release day. Run it where it adds signal (main, and PRs that touch `ios/` or dependencies). |
| "I'll sign and upload from my laptop, it's faster" | It is a single point of failure, unaudited, and holds keys on a personal machine. Automate it. |
| "I'll bump the build number by hand" | Collisions and skipped numbers fail store uploads at the worst time. Derive it from CI. |
| "We can hotfix quickly if it breaks" | A hotfix needs store review and user updates. Use staged rollouts and feature flags. |
| "The emulator passed, so it's fine on devices" | Emulators miss real GPUs, OEM quirks, and thermals. Use device farms for what matters. |

## Red Flags

- No CI pipeline in the project
- CI failures ignored or silenced
- Tests disabled in CI to make the pipeline pass, or `--update-goldens` used to turn a golden failure green
- No pinned Flutter version (local and CI SDKs drift)
- Generated code not produced or checked in CI
- Builds verified on only one platform
- Signing keys, keystores, or store credentials in the repository or in PR-accessible secrets
- Manual signing and store uploads, or hand-edited build numbers
- Dev, staging, and production sharing one bundle ID
- Production releases with no staged rollout, no feature flag, and no way to halt
- Debug symbols not kept for obfuscated release builds
- Long CI times with no optimization effort

## Verification

After setting up or modifying CI:

- [ ] All quality gates are present (dependencies from the lockfile, codegen, format, analyze, tests, build)
- [ ] The Flutter SDK version is pinned and shared between local and CI
- [ ] Pipeline runs on every PR and push to main
- [ ] Failures block merge (branch protection configured)
- [ ] Android and iOS both build in CI
- [ ] Integration tests run on an emulator, simulator, or device farm, against a fake or local backend
- [ ] CI results feed back into the development loop
- [ ] Secrets are stored in the secrets manager, and signing secrets are only available to the protected release environment
- [ ] Releases are built, signed, and uploaded by CI, with a build number that is unique and increasing
- [ ] Release builds are obfuscated, and their debug symbols are stored
- [ ] There is a staged rollout, a feature-flag kill switch, and a documented way to halt and fix
- [ ] Pipeline runs in under 10 minutes for the test suite
