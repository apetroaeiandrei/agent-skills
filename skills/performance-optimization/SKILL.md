---
name: performance-optimization
description: Optimizes application performance across Flutter apps, backend, queries, and databases. Use when performance requirements exist, when you suspect performance regressions, when jank, slow startup, memory growth, or app size need improvement, when N+1 query patterns need fixing, or when profiling reveals bottlenecks.
---

# Performance Optimization

## Overview

Measure before optimizing. Performance work without measurement is guessing — and guessing leads to premature optimization that adds complexity without improving what matters. Profile first, identify the actual bottleneck, fix it, measure again. Optimize only what measurements prove matters.

## When to Use

- Performance requirements exist in the spec (frame budgets, startup time, app size, response time SLAs)
- Users or monitoring report jank, slow startup, crashes, ANRs, or battery drain
- Frame times, cold start, or app size are past their budget
- You suspect a change introduced a regression
- Building features that handle large datasets, long lists, or high traffic

**When NOT to use:** Don't optimize before you have evidence of a problem. Premature optimization adds complexity that costs more than the performance it gains.

## Mobile Performance Targets

Treat these as defaults. A project's own budget (see `constraint-driven-development`) overrides them.

| Metric | Target | Notes |
|--------|--------|-------|
| **Frame build time** (UI thread) | ≤ 16.6ms at 60Hz, ≤ 8.3ms at 120Hz | Build + layout must fit the frame budget on the slowest device you support |
| **Frame raster time** (raster thread) | Same budget | Painting, clipping, shaders, `saveLayer` |
| **Frozen frames** | None (a frame over 700ms) | Android vitals reports these as frozen frames |
| **Cold start** (time to first frame) | Project budget | Android vitals flags cold start of 5s or more as slow |
| **Memory** | No sustained growth across repeated navigation | Growth means a leak; a high steady state risks out-of-memory kills |
| **App size** | Project budget | Download and install size, tracked per release |
| **Crash / ANR rate** | Below the platform's bad-behavior thresholds | Play Console vitals, Xcode Organizer |

**Always measure in profile mode on a real device.** Debug mode is misleading by an order of magnitude, and emulators and simulators do not reflect real GPUs, thermals, or memory pressure.

## The Optimization Workflow

```
1. MEASURE  → Establish baseline with real data
2. IDENTIFY → Find the actual bottleneck (not assumed)
3. FIX      → Address the specific bottleneck
4. VERIFY   → Measure again; keep or revert
5. GUARD    → Add monitoring or tests to prevent regression
```

### Step 1: Measure

Two complementary approaches — use both:

- **Lab (profile mode on a real device):** Controlled conditions, reproducible. Best for CI regression detection and isolating specific issues. Flutter DevTools, `integration_test` timeline summaries, and `--trace-startup`.
- **Field (Play Console vitals, Xcode Organizer, Firebase Performance, Crashlytics):** Real users on real devices. Required to validate that a fix actually improved user experience, especially on the low-end devices you don't own.

**Flutter app:**
```bash
# Lab: profile mode on a connected physical device
flutter run --profile
# DevTools → Performance tab → record; check UI vs raster thread, jank frames, rebuild counts
# DevTools → Memory tab → snapshots before and after repeated navigation

# Startup: writes build/start_up_info.json (time to first frame)
flutter run --profile --trace-startup

# App size: writes a code-size-analysis JSON; open it in DevTools' app size tool.
# Android needs a single ABI: without --target-platform the build fails with
# "Cannot perform code size analysis when building for multiple ABIs".
flutter build appbundle --analyze-size --target-platform android-arm64
flutter build ios --analyze-size

# Repeatable frame timing in a test: integration_test + traceAction / TimelineSummary,
# run with `flutter drive --profile` (see test-driven-development for the setup)
```

```dart
// Custom spans show up in the DevTools timeline
import 'dart:developer';

final result = Timeline.timeSync('parse-tasks', () => parseTasks(body));
```

Agent-driven checks: `mobile-mcp` can repeat a cold start and record the screen, but neither it nor the Dart MCP server produces a frame timeline. Get that from DevTools. See `flutter-devtools-and-device-testing`, or run `/perf-mobile` for a structured audit.

**Backend:**
```bash
# Response time logging
# Application Performance Monitoring (APM)
# Database query logging with timing

# Simple timing
console.time('db-query');
const result = await db.query(...);
console.timeEnd('db-query');
```

### Where to Start Measuring

Use the symptom to decide what to measure first:

```
What is slow?
├── App startup
│   ├── Long time to first frame? --> Measure with --trace-startup; look for work before runApp
│   ├── Serial SDK initialization? --> Parallelize with Future.wait, defer what the first screen doesn't need
│   └── Blank or white screen before the UI? --> Check native splash handoff and first-screen data loading
├── Scrolling or animation janks
│   ├── UI thread over budget? --> Profile build/layout: rebuild counts, heavy build(), non-lazy lists
│   ├── Raster thread over budget? --> Look for saveLayer, Opacity, clips, blurs, oversized images, shaders
│   └── Only the first run of an animation? --> Shader compilation; confirm which renderer the target uses
├── Interaction feels sluggish
│   ├── UI freezes on tap? --> Long synchronous work on the UI isolate (parsing, sorting, crypto)
│   ├── Input lag in forms? --> Rebuild scope; is the whole screen rebuilding per keystroke?
│   └── Keyboard opens slowly? --> MediaQuery.of rebuilding large trees; heavy layout below the field
├── After navigation
│   ├── Data loading? --> Measure API response times, check for sequential request waterfalls
│   └── Screen build slow? --> Profile widget build time, check for N+1 fetches from the client
├── Memory grows or the app is killed
│   └── Snapshot before/after repeated navigation --> undisposed controllers/subscriptions, retained contexts, oversized images
├── App is too large
│   └── Run --analyze-size --> largest packages, assets, ABIs
├── Battery drain
│   └── Timers, polling, location, wakelocks, animations running off-screen
└── Backend / API
    ├── Single endpoint slow? --> Profile database queries, check indexes
    ├── All endpoints slow? --> Check connection pool, memory, CPU
    └── Intermittent slowness? --> Check for lock contention, GC pauses, external deps
```

### Step 2: Identify the Bottleneck

Common bottlenecks by category:

**Flutter app:**

| Symptom | Likely Cause | Investigation |
|---------|-------------|---------------|
| Slow cold start | Serial SDK init before `runApp`, first screen blocked on network, eager Cubit creation | `--trace-startup`, read `main()` |
| Jank while scrolling | Non-lazy lists, expensive item builds, full-size image decoding | DevTools frame chart, rebuild counts |
| Raster-thread jank | `Opacity`, clips, blurs, `saveLayer`, oversized images, shader compilation | DevTools raster timeline |
| UI freezes on tap | Large JSON parsing, sorting, or crypto on the UI isolate | Long frames in the UI-thread timeline |
| Excess rebuilds | `setState` high in the tree, whole-screen `BlocBuilder`, missing `const`, missing state equality | Rebuild counts in DevTools |
| Memory growth | Undisposed controllers and subscriptions, retained `BuildContext`, unbounded image cache | Memory snapshots across navigation |
| Large app size | Unused packages and assets, all ABIs bundled, uncompressed images | `--analyze-size` |

**Backend:**

| Symptom | Likely Cause | Investigation |
|---------|-------------|---------------|
| Slow API responses | N+1 queries, missing indexes, unoptimized queries | Check database query log |
| Memory growth | Leaked references, unbounded caches, large payloads | Heap snapshot analysis |
| CPU spikes | Synchronous heavy computation, regex backtracking | CPU profiling |
| High latency | Missing caching, redundant computation, network hops | Trace requests through the stack |

### Step 3: Fix Common Anti-Patterns

#### N+1 Queries (Backend)

```typescript
// BAD: N+1 — one query per task for the owner
const tasks = await db.tasks.findMany();
for (const task of tasks) {
  task.owner = await db.users.findUnique({ where: { id: task.ownerId } });
}

// GOOD: Single query with join/include
const tasks = await db.tasks.findMany({
  include: { owner: true },
});
```

#### Unbounded Data Fetching

```typescript
// BAD: Fetching all records
const allTasks = await db.tasks.findMany();

// GOOD: Paginated with limits
const tasks = await db.tasks.findMany({
  take: 20,
  skip: (page - 1) * 20,
  orderBy: { createdAt: 'desc' },
});
```

#### Queries That Ignore Their Index

"Add an index" is the guess. The query plan is the measurement:

```sql
EXPLAIN ANALYZE
SELECT id, title FROM tasks
WHERE owner_id = 42 ORDER BY created_at DESC LIMIT 20;
```

Three things in the output decide the fix:

| What you see | What it means |
|---|---|
| `Seq Scan` on a large table where you expected an index | No usable index for this predicate |
| Estimated `rows=` off from actual by an order of magnitude | Stale statistics; the planner is choosing on bad information |
| A `Sort` node above the scan | The index covers the filter but not the `ORDER BY` |

Index for the **shape of the query**, not the column in isolation. In a composite index, equality columns come first, then the range or sort column:

```sql
CREATE INDEX idx_tasks_owner_created ON tasks (owner_id, created_at DESC);
```

**When an index will not help:**

| Situation | Why |
|---|---|
| Low selectivity, querying the dominant value (a `status` column that is 95% `active`, filtered on `active`) | A sequential scan is genuinely cheaper; the planner will ignore the index. Filtering on the rare value is the opposite case, and a partial index serves it well |
| Leading wildcard (`LIKE '%term'`) | A B-tree cannot seek without a prefix; needs trigram or full-text |
| Function on the column (`WHERE lower(email) = ?`) | The plain column index is unusable; index the expression instead |
| Write-heavy table | Every index is a tax on every `INSERT`/`UPDATE`; measure the write cost, not just the read gain |

Re-run `EXPLAIN ANALYZE` after. An index that did not change the plan is a revert (Step 4), and it is not free: it still costs on every write.

#### Connection Pool Exhaustion

The signature is distinctive: **every** endpoint slows at once, the slow time is spent waiting for a connection rather than executing, and the database reports mostly idle sessions.

```typescript
// BAD: a pool per request or per module — under serverless this multiplies
// by instance count and exhausts the database's connection limit
// GOOD: one pool per process, sized against the database's ceiling
const pool = new Pool({
  max: 10,                        // instances × max must stay under max_connections
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000, // fail fast instead of queueing forever
});
```

**Bigger is not faster.** A pool larger than what the database can execute concurrently just relocates the queue from your app to the database, where it is harder to see. When instance count is unbounded (serverless, autoscaling), a proxy that multiplexes connections (pgbouncer, RDS Proxy) is the fix, not a higher `max`.

#### Non-Lazy Lists (Flutter)

```dart
// BAD: builds every item up front, even the thousands off-screen
ListView(children: tasks.map((t) => TaskItem(task: t)).toList())

// GOOD: builds only what is visible; a fixed extent skips per-item measurement
ListView.builder(
  itemCount: tasks.length,
  itemExtent: 72,
  itemBuilder: (context, i) => TaskItem(task: tasks[i]),
)
```

Also avoid `shrinkWrap: true` on large scrollables and a `Column` of many children inside `SingleChildScrollView`.

#### Unnecessary Rebuilds (Flutter)

```dart
// BAD: the whole screen rebuilds whenever any part of the state changes
BlocBuilder<TasksCubit, TasksState>(
  builder: (context, state) => Scaffold(/* large tree */),
)

// GOOD: rebuild only the widget that reads the value
BlocSelector<TasksCubit, TasksState, int>(
  selector: (state) => switch (state) {
    TasksLoaded(:final tasks) => tasks.where((t) => t.done).length,
    _ => 0,
  },
  builder: (context, doneCount) => Text('$doneCount done'),
)

// GOOD: const subtrees are never rebuilt
const SizedBox(height: Spacing.md),
const _Header(),
```

- Freezed states give value equality, so emitting an equal state does not rebuild listeners. Hand-written state classes without `==` rebuild on every `emit`.
- Extract subtrees into small widget classes (not `_buildX()` methods) so `setState` and rebuilds affect less.
- Never create futures, controllers, or expensive objects inside `build()`.

#### Heavy Work on the UI Isolate

```dart
// BAD: parsing a large payload on the UI isolate drops frames
final tasks = (jsonDecode(body) as List)
    .map((e) => Task.fromJson(e as Map<String, Object?>))
    .toList();

// GOOD: run it on another isolate
final tasks = await Isolate.run(
  () => (jsonDecode(body) as List)
      .map((e) => Task.fromJson(e as Map<String, Object?>))
      .toList(),
);
```

Measure first: spawning an isolate has a cost, and small payloads are not worth it. Also avoid synchronous file I/O (`readAsStringSync`) on the UI isolate.

#### Slow Startup

```dart
// BAD: serial initialization blocks the first frame
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCrashReporting();
  await openDatabase();
  await loadRemoteConfig();
  runApp(const App());
}

// GOOD: run independent work in parallel; defer what the first screen doesn't need
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([initCrashReporting(), openDatabase()]);
  runApp(const App());
  unawaited(loadRemoteConfig());
}
```

Create Cubits lazily (`BlocProvider` is lazy by default) and keep app-wide providers to what is genuinely needed at launch.

#### Oversized Images (Flutter)

```dart
// BAD: decodes a full-resolution photo to show a 56dp avatar
Image.network(url, width: 56, height: 56)

// GOOD: decode at display size (cacheWidth is in physical pixels) and cache remote images
Image.network(
  url,
  width: 56,
  height: 56,
  cacheWidth: (56 * MediaQuery.devicePixelRatioOf(context)).round(),
)
```

Use an image caching package (such as `cached_network_image`) for remote images, ship assets in efficient formats and reasonable dimensions, and `precacheImage` only what the first frame needs.

#### Memory Leaks

```dart
class _SearchState extends State<Search> {
  final _controller = TextEditingController();
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.results.listen(_onResult);
  }

  @override
  void dispose() {
    _sub.cancel();        // Missing cancels and disposes are the usual leak
    _controller.dispose();
    super.dispose();
  }
}
```

Do the same in a Cubit's `close()` for subscriptions and timers you own. Verify with memory snapshots before and after repeatedly opening and closing the screen.

#### App Size

```bash
flutter build appbundle --analyze-size --target-platform android-arm64   # largest contributors (one ABI at a time)
flutter build appbundle                           # Play splits per ABI and density from the bundle
flutter build apk --split-per-abi                 # if distributing APKs directly
flutter build appbundle --obfuscate --split-debug-info=build/symbols   # smaller, and keep the symbols
```

Remove unused packages, assets, fonts, and icon sets; compress images; download large assets on demand instead of bundling them. Consider deferred components for rarely used features on Android.

#### Missing Caching (Backend)

Cache what is expensive to produce and read far more often than it changes. Caching a query that was already fast adds a network hop, a staleness bug, and an eviction policy to maintain, in exchange for nothing.

**Pick the layer deliberately:**

| Layer | Visible to | Use when | Cost |
|---|---|---|---|
| In-process (`Map`, LRU) | One instance | Small, hot, per-instance staleness is acceptable | Each instance drifts independently; invalidation reaches only one |
| Shared (Redis, Memcached) | All instances | Instances must agree, or the value is expensive to recompute | A network hop, and another service to run and monitor |
| CDN / edge | Everyone, per URL | Responses are public and identical for a given key | Invalidation is the hard part; assume you cannot recall a bad response quickly |

```typescript
// Cache frequently-read, rarely-changed data
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes
let cachedConfig: AppConfig | null = null;
let cacheExpiry = 0;

async function getAppConfig(): Promise<AppConfig> {
  if (cachedConfig && Date.now() < cacheExpiry) {
    return cachedConfig;
  }
  cachedConfig = await db.config.findFirst();
  cacheExpiry = Date.now() + CACHE_TTL;
  return cachedConfig;
}

// HTTP caching headers for static assets
app.use('/static', express.static('public', {
  maxAge: '1y',           // Cache for 1 year
  immutable: true,        // Never revalidate (use content hashing in filenames)
}));

// Cache-Control for API responses
res.set('Cache-Control', 'public, max-age=300'); // 5 minutes
```

**Key design decides correctness.** Every input that changes the response belongs in the key: tenant, locale, permissions, feature flags. A key that omits the viewer is how one user's data gets served to another, and that ships as a performance win.

**Choose one invalidation strategy, not three:**

| Strategy | Trade-off |
|---|---|
| TTL | Simplest. You accept staleness up to the TTL, so state the acceptable window explicitly |
| Event or tag based | Fresh on write, but writers now have to know the cache topology |
| Versioned keys (`user:42:profile:v7`) | Never invalidate, just stop reading old keys. Costs memory until eviction |

**Guard against the stampede.** A hot key expires, every concurrent request misses together, and the origin takes the full load at once, which is how a cache turns into an outage instead of preventing one. Serve stale while a single request recomputes (`stale-while-revalidate`), or coalesce concurrent misses behind one in-flight promise so N waiters cause one recompute.

**Do not cache:** anything whose staleness is a correctness bug (balances, permissions, inventory at checkout), or per-user data under a key that does not identify the user. See `../../references/performance-checklist.md` for request coalescing, write strategies, negative caching, and the cache checklist.

### Step 4: Verify (Keep or Revert)

A fix is a hypothesis until you re-measure. This step decides whether it survives.

**Re-measure the way you measured the baseline:** same command, same conditions, same fixed budget (wall-clock, sample count, or request count). On a device that means the same physical device, build mode (profile), battery and power settings, and thermal state: a warm, throttled phone against a cool one measures the phone. A baseline taken on a cold cache against a result taken on a warm one measures the cache, not your change.

**Change one thing at a time.** Three optimizations landed together produce one number, and you cannot attribute it. If they must ship together, measure each in isolation first.

**Beat the noise, not just the mean.** Repeat the measurement and compare the delta against run-to-run variance. A 3% gain inside ±5% variance is not a gain; it is a different sample.

Then decide, strictly:

| Result vs. baseline | Action |
|---|---|
| Past the threshold, tests green | **Keep.** Commit with the before/after numbers in the message. |
| Within noise (no measurable change) | **Revert.** |
| Worse | **Revert.** |
| Improved, but a test went red | **Revert.** A regression wearing a win's clothing. |

**"Neutral" is a revert, not a keep.** This is the step teams skip: the change is already written, throwing it away feels wasteful, so it lands unmeasured, and the codebase accretes complexity that never bought anything. Code you keep, you maintain forever. Make it pay for itself.

**Correctness gates the metric.** The suite stays green *and* the number moves. An "optimization" that wins by dropping work the product needed (skipping a validation, caching something that must be fresh, removing an `await` that was load-bearing) is a regression, not a win.

#### Log every attempt, including the reverted ones

Reverted work leaves no trace in git history, which is exactly why the same dead idea gets tried again next quarter. Keep a short ledger so a discarded idea stays discarded:

| Idea | Baseline → Result | Verdict | Why |
|---|---|---|---|
| Wrap each row in `RepaintBoundary` | p99 frame 24ms → 23ms | reverted | Inside noise (±2ms). Painting wasn't the bottleneck. |
| Switch to `ListView.builder` with `itemExtent` | p99 frame 24ms → 9ms | kept | Jank frames gone from the timeline. |
| Move JSON parsing to `Isolate.run` | Cold start 2.1s → 2.1s | reverted | Payload is 4KB; isolate overhead cancelled the gain. |

A section in the PR description or a `PERF.md` in the repo both work. What matters is that the next person (or the next agent) reads it before proposing an experiment, and doesn't re-run one that already failed.

### Step 5: Guard Against Regression

Guard the metric the user actually feels, not every available number. Use the
same frame time, cold start, app size, p95 latency, or other primary metric that
justified the fix.

Use two complementary layers when the surface is user-facing:

- **Lab CI gate:** Catch reproducible regressions before merge with a
  performance budget: an `integration_test` timeline summary with frame-time
  thresholds, run in profile mode on a consistent physical device or device
  farm (emulator variance makes it a flaky gate), and an app size check against
  the last release's `--analyze-size` output. Repeat noisy measurements or
  compare a median/trend so normal run-to-run variance does not turn the gate
  into a flaky check.
- **Field monitoring:** Alert on meaningful movement in Play Console vitals,
  Firebase Performance, Crashlytics, or Xcode Organizer data. Use it to locate
  the cause by app version and device model; treat store dashboards' delay as
  confirmation rather than an immediate alert.

When either guard fires, return to Step 1 and establish a fresh baseline before
proposing another fix.

**Set budgets and enforce them:**

```
Frame build / raster time: ≤ 16.6ms at 60Hz (8.3ms at 120Hz), p99 on a mid-range device
Frozen frames: none on core flows
Cold start: within the project budget on a mid-range device
App download size: within the project budget, tracked per release
Memory: no growth across repeated navigation
Crash / ANR rate: below platform thresholds
API response time: < 200ms (p95)
```

**Enforce in CI:**
```bash
# Frame timing (profile mode, real device or device farm)
flutter drive --profile \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/scroll_perf_test.dart

# App size: build with --analyze-size and compare against the stored baseline.
# Pin the same ABI every run, or the numbers aren't comparable.
flutter build appbundle --analyze-size --target-platform android-arm64
```

## See Also

For detailed performance checklists, optimization commands, and anti-pattern reference, see `../../references/performance-checklist.md`.


## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "We'll optimize later" | Performance debt compounds. Fix obvious anti-patterns now, defer micro-optimizations. |
| "It's fast on my machine" | Your machine isn't the user's. Profile on representative hardware and networks. |
| "It runs at 60fps on my flagship phone" | Users own mid-range and older devices. Profile on the slowest device you support. |
| "Debug mode feels slow, so it must be slow" | Debug mode is not representative in either direction. Measure in profile mode on a real device. |
| "Wrap it in `RepaintBoundary` and `const` everywhere" | Blanket application adds clutter and can add cost. Use them where the timeline shows they help. |
| "This optimization is obvious" | If you didn't measure, you don't know. Profile first. |
| "Users won't notice 100ms" | Research shows 100ms delays impact conversion rates. Users notice more than you think. |
| "The framework handles performance" | Frameworks prevent some issues but can't fix N+1 queries, oversized images, or heavy work on the UI isolate. |
| "The query is slow, add an index" | Read the plan first. The index may already exist and be unusable, and every index taxes writes forever. |
| "Just cache it" | Caching an already-cheap call buys nothing and adds a staleness bug. Cache what is expensive *and* re-read far more than written. |
| "Raise the pool size, we're running out of connections" | A pool bigger than the database can serve moves the queue somewhere less visible. Find what holds connections. |
| "It didn't help much, but it doesn't hurt" | Neutral changes are a revert. You pay maintenance on them forever and got nothing back. |
| "We already wrote it, may as well keep it" | Sunk cost. The measurement doesn't care how long the change took to write. |
| "The improvement is obvious, no need to re-measure" | Then re-measuring is cheap and proves it. Unmeasured wins are how neutral complexity lands. |

## Red Flags

- Optimization without profiling data to justify it
- N+1 query patterns in data fetching
- An index added without a query plan before and after to justify it
- A cache key that omits an input the response depends on (tenant, locale, viewer)
- A cache with no stated staleness window and no invalidation strategy
- Connection pool size raised in response to exhaustion, without finding what holds connections
- List endpoints without pagination
- Images decoded at full resolution for small display sizes, or remote images with no caching
- App size growing without review
- Performance measured in debug mode or on an emulator
- `ListView(children: [...])` or `shrinkWrap: true` on long lists
- Whole-screen `BlocBuilder`s, or states without value equality, forcing needless rebuilds
- Heavy parsing or synchronous I/O on the UI isolate
- Controllers, subscriptions, or timers that are never disposed or cancelled
- No performance monitoring in production
- `RepaintBoundary`, `const`, or isolates applied everywhere "just in case" (overusing is as bad as underusing)
- Optimizations kept without a re-measurement that justifies them
- Several optimizations bundled into one measurement, so no single change can be attributed
- A "win" that required a test to be changed, skipped, or deleted
- The same failed optimization attempted more than once because nobody recorded the first attempt

## Verification

After any performance-related change:

- [ ] Before and after measurements exist (specific numbers)
- [ ] The result was re-measured the same way as the baseline (same command, same conditions)
- [ ] The improvement exceeds run-to-run variance, not just the mean
- [ ] Changes that didn't beat the baseline were reverted, not kept as neutral
- [ ] Attempts are logged, kept and reverted alike, so a dead idea isn't re-run
- [ ] The specific bottleneck is identified and addressed
- [ ] Frame times are within budget in profile mode on a real, mid-range device
- [ ] Cold start and memory behavior are within budget (no growth across repeated navigation)
- [ ] App size hasn't increased significantly (`--analyze-size`)
- [ ] No N+1 queries in new data fetching code
- [ ] Any new index is justified by a query plan before and after, and its write cost was considered
- [ ] Any new cache states what it keys on and how it goes stale
- [ ] The measured user-facing metric has a synthetic budget or field monitor that can detect regression
- [ ] Existing tests still pass (optimization didn't break behavior)
