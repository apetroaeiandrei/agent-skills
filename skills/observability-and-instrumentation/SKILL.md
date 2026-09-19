---
name: observability-and-instrumentation
description: Instruments Flutter apps and their backends so production behavior is visible and diagnosable. Use when adding logging, crash and ANR reporting, analytics, metrics, tracing, or alerting. Use when shipping any feature that runs on users' devices and you need evidence it works. Use when production issues are reported but you can't tell what happened from the available data.
---

# Observability and Instrumentation

## Overview

Code you can't observe is code you can't operate. Observability is the ability to answer "what is the system doing and why?" from the outside, using the telemetry the code emits. Instrumentation is not a post-launch add-on — it's written alongside the feature, the same way tests are. If a feature ships without telemetry, the first user-reported bug becomes archaeology instead of a query.

**Mobile telemetry comes from devices you can't reach.** It arrives late or not at all (offline, backgrounded, killed), from many app versions at once, under user consent and privacy rules, and it costs the user's battery and data. You can't attach a debugger to a customer's phone or SSH in. Whatever isn't captured when the failure happens is gone, so decide up front what each release must report, and tag every signal with the app version.

## When to Use

- Building any feature that will run in production
- Adding a new service, endpoint, background job, or external integration
- A production incident took too long to diagnose ("we couldn't tell what happened")
- Setting up or reviewing alerting rules
- Reviewing a PR that adds I/O, retries, queues, or cross-service calls
- Adding a screen, flow, or SDK to an app and needing to know it works on users' devices
- A crash, ANR, or one-star-review spike where you can't tell which version or device is affected

**NOT for:**
- Diagnosing a failure happening right now — use the `debugging-and-error-recovery` skill (observability is what makes that skill fast next time)
- Profiling and optimizing measured slowness — use the `performance-optimization` skill
- Launch-day monitoring checklists and rollback triggers — see the `shipping-and-launch` skill; this skill covers the instrumentation that feeds them

## Process

### 1. Define "working" before instrumenting

Telemetry without a question is noise. Before adding any instrumentation, write down 2–4 questions an on-call engineer will ask about this feature:

```
FEATURE: checkout payment retry
QUESTIONS ON-CALL WILL ASK:
1. What fraction of payments succeed on first attempt vs after retry?
2. When a payment fails permanently, why? (provider error? timeout? validation?)
3. Is the payment provider slower than usual?
4. Which app versions and devices are affected, and did the newest release make it worse?
→ Every signal below must help answer one of these.
```

If you can't name the questions, you're not ready to instrument — you'll log everything and learn nothing.

### 2. Pick the right signal for each question

| Signal | Answers | Cost profile | Example |
|---|---|---|---|
| **Structured log / breadcrumb** | "What happened in this specific case?" | Per-event; grows with traffic (on a device: also battery and data) | `payment_failed` with provider error code; the last 50 navigation and state breadcrumbs before a crash |
| **Crash / non-fatal report** | "What broke, on which version and device, with what stack?" | Per-failure; vendor-grouped | A `StateError` in `TasksCubit` on app 3.2.0, Android 14 |
| **Metric** | "How often / how fast, in aggregate?" | Fixed per series; cheap to query | Crash-free sessions, cold-start p90, backend p99 |
| **Analytics event** | "What are users doing, where do they drop off?" | Per-event; consent required | `checkout_started`, `checkout_completed` |
| **Trace** | "Where did time go from tap to database?" | Per-request; usually sampled | One slow checkout, broken down by client and server hops |

Rule of thumb: metrics tell you **that** something is wrong, traces tell you **where**, logs and crash reports tell you **why**. Analytics tells you whether anyone noticed.

### 3. Structured logging

#### In the app (Dart)

Put telemetry behind **one small interface** that the rest of the app depends on. It keeps the vendor swappable, gives you one place to enforce consent and PII rules, and lets tests use a fake:

```dart
abstract interface class Telemetry {
  void event(String name, {Map<String, Object?> fields = const {}});
  void breadcrumb(String message, {Map<String, Object?> data = const {}});
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    Map<String, Object?> context = const {},
  });
}
```

```dart
// BAD: print, string interpolation. Unqueryable, reaches device logs, and may leak data
print('payment $id failed for ${user.email} after $attempt retries');

// GOOD: stable event name + structured fields, safe identifiers only
telemetry.event('payment_failed', fields: {
  'paymentId': id,
  'provider': 'stripe',
  'errorCode': error.code,
  'attempt': attempt,
});
```

**Tag everything with the app version.** Set global context once at startup so every event, breadcrumb, and crash carries it, or you can never tell whether a fix worked:

```dart
final info = await PackageInfo.fromPlatform();
telemetry.setGlobalContext({
  'appVersion': info.version,
  'buildNumber': info.buildNumber,
  'flavor': config.flavor,               // dev / staging / prod
  'platform': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'sessionId': sessionId,                // Per app launch
  'flags': activeFlagNames,              // Which experiments were on
});
```

- **Levels in production:** only `warn` and above, plus breadcrumbs, leave the device. Don't ship `debug` output, and don't leave `print` / `debugPrint` in release code (it reaches device logs).
- **Stable names, not `runtimeType`.** `--obfuscate` mangles class names in release builds, so a `runtimeType` string you send is unstable and unqueryable. Use explicit strings for event names, screens, and Cubits.
- **Correlate with the backend.** Send a request ID (and the app version) on every API call (`X-Request-Id`, `X-App-Version`) and record the same ID client-side, so a crash report or support ticket can be joined to server logs.
- **Never log secrets, tokens, passwords, or PII:** no auth headers, no user-entered text, no email addresses, no full response bodies, no raw state objects. Screen names and event names are fine; field contents usually aren't. Use a pseudonymous user ID, never an email or phone number. This is a hard rule from `security-and-hardening`.
- **Keep it non-blocking and fail-safe.** Telemetry must never throw into feature code, block the UI isolate, or block startup.

#### On the backend (services the app calls)

Log events, not prose. Every log line is a JSON object with a stable event name and machine-readable fields:

```typescript
// BAD: string interpolation — unqueryable, inconsistent
logger.info(`Payment ${id} failed for user ${userId} after ${n} retries`);

// GOOD: stable event name + structured fields
logger.warn({
  event: 'payment_failed',
  paymentId: id,
  provider: 'stripe',
  errorCode: err.code,
  attempt: n,
}, 'payment failed');
```

**Log levels — use them consistently:**

| Level | Meaning | On-call action |
|---|---|---|
| `error` | Invariant broken; someone may need to act | Investigate |
| `warn` | Degraded but handled (retry succeeded, fallback used) | Watch for trends |
| `info` | Significant business event (order placed, job finished) | None |
| `debug` | Diagnostic detail | Off in production by default |

**Correlation IDs are mandatory.** Generate (or accept) a request ID at the system boundary and attach it to every log line, span, and outbound call. Without it, you cannot reconstruct a single request from interleaved logs:

```typescript
// Express: child logger per request, ID propagated downstream
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] ?? crypto.randomUUID();
  req.log = logger.child({ requestId: req.id });
  res.setHeader('x-request-id', req.id);
  next();
});
```

**When several entry points write to one log, name the entry point.** A correlation ID identifies a run; it does not say which code path started it. The same job reached by a scheduler, by a replay endpoint, and by a manual CLI run produces interchangeable lines in one sink, so attributing a line falls back to elimination — cross-reading the scheduler's history, the process table, a deploy log — and that argument holds only as long as those external records happen to still exist. Stamp the entry point where the run starts, next to the correlation ID, and propagate both the same way:

```typescript
// One helper for every entry point: the run's own logger carries both fields.
// `entryPoint`, not `source` — ECS reserves `source.*` for network fields.
export const runLog = (entryPoint: 'scheduler' | 'replay_endpoint' | 'cli', runId: string) =>
  logger.child({ entryPoint, requestId: runId });

// scheduler tick        -> runLog('scheduler', crypto.randomUUID())
// POST /jobs/:id/replay -> runLog('replay_endpoint', req.id)
// CLI invocation        -> runLog('cli', process.env.RUN_ID ?? crypto.randomUUID())
```

Both fields have to cross the same boundaries as the correlation ID — queue metadata, HTTP headers — or a worker re-derives the entry point and guesses. A field that merely correlates with an entry point is a hint, not an attribution: anything that can invoke the job can reproduce it.

**Never log secrets, tokens, passwords, or full PII.** This is a hard rule from the `security-and-hardening` skill — telemetry pipelines are a classic data-leak path. Allowlist fields; don't log whole request bodies.

### 4. Metrics

#### Client metrics

Most client metrics come from a crash and performance SDK rather than code you write. Make sure each one exists, is split by **app version, platform, and OS version**, and has an owner:

```
Stability:   crash-free users, crash-free sessions, ANR rate (Android), hangs (iOS)
Speed:       cold start, screen render time, slow and frozen frames
Network:     request success rate, latency, by endpoint, as the client sees it
Adoption:    share of users per app version (to know when an old version can be retired)
Funnels:     step-to-step conversion for critical flows (from analytics events)
```

- Custom timings (a checkout submit, an initial data load) go through the same `Telemetry` interface as a named trace, with attribute values from **small, fixed sets** (screen name, flavor), never user IDs or raw URLs.
- The store dashboards (Play Console vitals, Xcode Organizer) are field data for stability, startup, and rendering. Watch them per release; see `shipping-and-launch`.
- Measuring frame times and startup for optimization work belongs to `performance-optimization`, and needs profile-mode captures. Field vitals tell you *that* something regressed.

#### Backend metrics (RED / USE)

For request-driven services, instrument **RED** on every endpoint and every external dependency: **R**ate (requests/sec), **E**rrors (failure rate), **D**uration (latency histogram, not average). For resources (queues, pools, hosts), use **USE**: **U**tilization, **S**aturation, **E**rrors.

As with tracing, the vendor-neutral path is the OpenTelemetry metrics API (same SDK and context as step 7). The example below uses Prometheus' `prom-client` — one common backend choice, not the only one; the RED/USE and cardinality rules are identical either way.

```typescript
import { Histogram } from 'prom-client';

const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'status_class'],  // '2xx', not '200'
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});
```

**Cardinality is the failure mode.** Every unique label combination is a separate time series. Labels must come from small, fixed sets (route template, status class, provider name). Never use user IDs, raw URLs, error messages, or other unbounded values as labels — that belongs in logs and traces.

```
OK as label:    route="/api/tasks/:id"   status_class="5xx"   provider="stripe"
NEVER a label:  user_id, email, request_id, full URL, error message text
```

Track averages never, percentiles always: an average hides the 1% of users having a terrible time. Use histograms and read p50/p95/p99.

### 5. Crash, ANR, and error reporting

Crashes are the most valuable signal a mobile app produces, and the one you can only capture at the moment of failure.

**Capture every failure path.** The Flutter framework, Dart async code, isolates, and the native layers each report separately:

| Source | How it's captured |
|---|---|
| Flutter framework errors (build, layout, paint) | `FlutterError.onError` |
| Uncaught async and platform errors | `PlatformDispatcher.instance.onError` |
| Errors in other isolates | An error listener on each isolate you spawn |
| Errors inside Cubits and Blocs | A `BlocObserver.onError` that forwards to `Telemetry` |
| Native crashes (Android JVM/NDK, iOS signals) | The crash SDK's native integration |
| ANRs (Android) and hangs (iOS) | The crash SDK where supported, plus Play vitals and Xcode Organizer |
| Caught but unexpected errors (parse failures, exhausted retries) | `recordError(..., fatal: false)`: non-fatal reports |

The global hook setup for `FlutterError.onError` and `PlatformDispatcher` is in `shipping-and-launch`. Route those hooks and the Bloc observer through the `Telemetry` interface:

```dart
class TelemetryBlocObserver extends BlocObserver {
  TelemetryBlocObserver(this._telemetry);
  final Telemetry _telemetry;

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    _telemetry.recordError(error, stackTrace, context: {'source': 'bloc'});
    super.onError(bloc, error, stackTrace);
  }
}

// main(): Bloc.observer = TelemetryBlocObserver(telemetry);
```

**Give every report the context to act on it:**
- The global tags (app version, build number, flavor, platform, OS, session) and the active feature flags
- **Breadcrumbs:** a bounded trail of recent navigation, key user actions, connectivity changes, and state transitions. Record them from your code with **explicit names**, not `runtimeType`, and never include state contents, which may hold PII
- A pseudonymous user ID, so you can count affected users without knowing who they are

**Symbols make or break it.** Release builds are obfuscated and split (`--obfuscate --split-debug-info`). Without the symbols, stack traces are unreadable:
- Upload the Dart symbols, the Android R8/ProGuard mapping, and the iOS dSYMs **for every release**, from CI (see `ci-cd-and-automation`)
- Prove it: force a test crash in a release-like build on a device, and confirm the report arrives with a readable, de-obfuscated stack
- Route debug builds to a dev project or disable reporting there, so development noise never pollutes production stats

**Triage by version.** Watch crash-free rate for the newest version against the previous one, alert on **new** issue signatures, and mark regressions. That comparison is what the rollout thresholds in `shipping-and-launch` are built on.

### 6. Product analytics and offline-safe delivery

Analytics events answer "is anyone using this, and where do they drop off?" They are also personal-data processing, and they run on a phone that is often offline.

**Consent and privacy first:**
- Collect analytics only with the user's consent where the law or store policy requires it, honor opt-out immediately, and check that crash reporting and analytics are covered by your privacy notice. Confirm the details with whoever owns privacy for the product.
- Keep the store declarations (App Privacy labels, Play Data safety) in sync with every SDK you add (see `security-and-hardening`).
- Use pseudonymous IDs, no PII in event fields, and a retention period you can state.

**Design the events:**
- A small, stable taxonomy: `snake_case` names, a fixed schema per event, values from bounded sets. Version the schema when it changes.
- Track funnels for critical flows (`checkout_started` → `payment_submitted` → `checkout_completed`), not every tap.
- Include a client-generated **event ID**, the client timestamp, and the send timestamp. Device clocks are wrong more often than you'd expect, and the event ID lets the server deduplicate retries.

**Deliver it without hurting the device:**
- **Queue on disk and batch.** Buffer events locally, upload in batches, and flush when the app goes to the background (`AppLifecycleState.paused`), not per event. Frequent tiny uploads wake the radio and drain the battery.
- **Bound the queue.** Cap events and bytes, drop the oldest first, and never let telemetry fill storage.
- **Retry with backoff, and be idempotent.** A failed upload keeps the batch for the next flush; the event ID makes a repeat harmless.
- **Respect the network.** Defer large uploads on metered or poor connections, and never block the UI or startup on a flush.
- **Sample** high-volume events, and keep everything for errors and critical funnels.
- Prefer your analytics SDK's own queue. Build one only when you have to, and then test it in airplane mode.

```dart
class EventQueue {
  EventQueue(this._store, this._upload, {this.maxEvents = 500});
  final EventStore _store;
  final Future<void> Function(List<TelemetryEvent>) _upload;
  final int maxEvents;

  Future<void> add(TelemetryEvent event) async {
    final events = [...await _store.load(), event];
    if (events.length > maxEvents) events.removeRange(0, events.length - maxEvents);  // Drop oldest
    await _store.save(events);
  }

  Future<void> flush() async {
    final batch = await _store.load();
    if (batch.isEmpty) return;
    try {
      await _upload(batch);            // Server dedupes by event ID
      await _store.remove(batch);
    } on Exception {
      // Keep the batch for the next flush; back off before retrying
    }
  }
}
```

### 7. Distributed tracing

Use OpenTelemetry — it's the vendor-neutral standard, and auto-instrumentation covers HTTP, gRPC, and common DB clients with near-zero code:

```typescript
// tracing.ts — must be imported before anything else
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  serviceName: 'checkout-service',
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

Add manual spans only around meaningful internal units of work (e.g., `applyDiscounts`, `chargeProvider`) and attach the attributes on-call will filter by. Propagate context across every async boundary — HTTP headers, queue message metadata — or the trace dies at the gap. Sample head-based at a low rate by default; keep 100% of errors if your backend supports tail sampling.

**Extend the trace to the app.** Have the client generate or accept a trace context and send it on API calls (the W3C `traceparent` header, or at minimum a request ID), so one slow checkout can be followed from the tap through the server hops to the database. Sample on the client to limit battery, data, and cost, and never put PII in span attributes.

### 8. Alerting

Alert on **symptoms users feel**, not on causes:

```
SYMPTOM (page-worthy):                       CAUSE (dashboard, not a page):
crash-free sessions of the latest version    device memory at 85%
  drops below the agreed floor               one device model's slow start
new crash signature on launch/login/checkout an SDK's init time creeping up
ANR rate approaching the platform threshold  battery drain on one OS version
checkout completion rate drops               one pod restarted
error rate > 1% for 5 min                    CPU at 85%
p99 API latency > 2s
```

Cause-based alerts fire when nothing is wrong and miss failures you didn't predict. Symptom-based alerts fire exactly when users are hurt, regardless of the cause.

Rules for every alert you create:

1. **It must be actionable.** If the response is "ignore it, it self-heals", delete the alert.
2. **It links to a runbook** — even three lines: what it means, first query to run, escalation path.
3. **It has a threshold and duration** justified by the SLO or by historical data, not by a guess.
4. Use two severities only: **page** (user-facing, act now) and **ticket** (degradation, act this week). A third tier becomes noise that trains people to ignore everything.
5. **Scope client alerts by app version.** An alert on overall crash rate is diluted by old versions; an alert on the release you just shipped fires when it matters, and its runbook can point at halting the rollout.

#### Writing Runbooks

Rule 2 above requires every alert to link to a runbook. A runbook's job is to answer three questions without requiring the reader to think: what is happening, what to check first, and who to call if that doesn't resolve it. Store in `docs/runbooks/` named after the alert.

**Minimum viable runbook (a few lines), for an app alert:**

```markdown
# Runbook: Crash spike on the latest app version
**Means:** A regression in the newest release, or a bad remote-config change.
**First check:** Crash dashboard filtered to the latest version: what is the top new issue, and is it on a critical flow?
**Then:** If critical, turn off the feature flag and halt the staged rollout (see `shipping-and-launch`).
**Escalate to:** the mobile on-call rotation.
```

**And for a backend alert:**

```markdown
# Runbook: High Error Rate on /api/tasks
**Means:** DB connection pool likely exhausted, or a bad deploy.
**First check:** `SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';`
  — if count > pool limit, see Step 2. (Swap in the equivalent for your database.)
**Escalate to:** #db-oncall or engineering on-call rotation.
```

**When to expand beyond three lines:** add steps only when the first check alone isn't enough to decide. A five-step runbook that covers the three most common causes is better than a twenty-step document that covers every edge case and gets skimmed.

**Keep runbooks current.** Update the runbook as part of closing every incident it was used in — a stale runbook builds false confidence. If a step was wrong or missing, fix it before marking the incident resolved.

### 9. Verify the telemetry itself

Instrumentation is code; it can be wrong. Before calling the work done, trigger the paths and look at the actual output:

- Force a crash and a non-fatal error in a **release-like build on a device** → the report arrives, tagged with app version and flavor, with a readable de-obfuscated stack
- Go offline (airplane mode), use the feature, then reconnect → queued events flush once, with no duplicates and no loss beyond the cap
- Turn analytics consent off → confirm nothing is sent
- Inspect real payloads (logs, breadcrumbs, event fields) → no tokens, emails, or user-entered text
- Follow one request from the app to the server by its request ID

- Force an error in staging → find it in the logs by `requestId`, confirm fields are structured (not `[object Object]`)
- Send test traffic → confirm metric series appear with the expected labels and sane values
- Follow one request across services in the tracing UI → no broken spans
- Fire each new alert once (lower the threshold temporarily) → confirm it reaches the right channel and the runbook link works

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll add logging after it works" | "After" becomes "after the first incident", which is the most expensive moment to discover you're blind. Instrument as you build. |
| "More logs = more observability" | Unstructured noise makes incidents slower, not faster. Three queryable events beat three hundred prose lines. |
| "`print` / `console.log` is fine for now" | Unstructured output can't be filtered, correlated, or alerted on, and on a device it reaches the logs. The structured logger costs five extra minutes once. |
| "We'll see crashes in the store console" | It shows aggregates, delayed, without your breadcrumbs, flags, or user journey. Crash reporting with context is what lets you fix it. |
| "Debug builds report crashes fine, so release will too" | Release builds are obfuscated and use different symbols. Only a test crash in a release-like build proves the stack is readable. |
| "Send every event immediately, it's simpler" | Constant small uploads drain the battery and fail offline. Queue, batch, and flush on background. |
| "Analytics is anonymous, so consent doesn't matter" | Device and user identifiers are personal data in most jurisdictions. Gate collection on consent and keep declarations accurate. |
| "Log the whole state so we can debug it" | State and payloads hold PII and tokens. Log names and safe identifiers, and let breadcrumbs carry the trail. |
| "We can just look at the dashboards when something breaks" | Dashboards built without defined questions show you everything except the answer. Start from on-call questions. |
| "Alert on everything important, we'll tune later" | A noisy pager trains people to ignore it. The tuning never happens; the missed real page does. |
| "User ID as a metric label makes debugging easier" | It also makes your metrics backend fall over. High-cardinality lookups belong in logs and traces. |
| "Tracing is overkill for our two services" | Two services already means cross-service latency questions logs can't answer. Auto-instrumentation makes the cost trivial. |

## Red Flags

- A feature PR with retries, queues, or external calls and zero new telemetry
- Telemetry with no app version, build number, or flavor attached
- `print` / `debugPrint` used as logging in release code
- Crash reporting without symbols uploaded for the release, so stacks are unreadable
- Crash reporting verified only in debug builds
- Analytics sent before consent, or events with PII or tokens in fields
- Events uploaded one by one, or an unbounded on-disk queue
- Sending `runtimeType` names as event or screen names (mangled by obfuscation)
- Telemetry that can throw into feature code or block startup
- Client alerts on overall crash rate that old versions dilute
- Log lines built by string interpolation instead of structured fields
- No correlation/request ID — each log line is an orphan
- One log stream fed by a scheduler, a webhook, and manual runs, with no field naming which one produced the line
- Metrics labeled with user IDs, raw URLs, or error message text (cardinality bomb)
- Latency tracked as an average with no percentiles
- Alerts that fire daily and get acknowledged without action
- Alerts on causes (CPU, memory) paging humans while user-facing error rate is unmonitored
- Secrets, tokens, or full request bodies appearing in logs
- "It works on my machine" as the only evidence a production feature is healthy

## Verification

After instrumenting a feature, confirm:

- [ ] The on-call questions for this feature are written down, and each signal maps to one
- [ ] All log output is structured (JSON, or `Telemetry` events in the app), with stable event names and a correlation ID on every line
- [ ] Every app signal carries app version, build number, flavor, platform, and OS version
- [ ] Crashes, non-fatal errors, and ANRs are captured (Flutter, async, isolate, Bloc, native), with breadcrumbs and a pseudonymous user ID
- [ ] Symbols and mappings are uploaded for each release, and a test crash in a release-like build produced a readable stack
- [ ] Analytics respects consent, uses a bounded schema, and queues, batches, and dedupes offline-safely
- [ ] Client alerts are scoped to the latest app version and have a runbook (including how to halt the rollout)
- [ ] Every log sink written by more than one entry point carries an entry-point field, set where the run starts and propagated with the correlation ID rather than inferred downstream
- [ ] No secrets, tokens, or unredacted PII in any log line (spot-check actual output)
- [ ] RED metrics exist for every new endpoint and every external dependency, with bounded label sets
- [ ] Latency is a histogram; p95/p99 are queryable
- [ ] A single request can be followed end-to-end in the tracing UI without broken spans
- [ ] Every new alert is symptom-based, has a runbook link, and was test-fired once
- [ ] An induced failure in staging was located via telemetry alone, without reading the source

For the at-a-glance version of this list, including the pre-launch instrumentation gate, see `../../references/observability-checklist.md`.
