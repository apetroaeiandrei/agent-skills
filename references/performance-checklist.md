# Performance Checklist

Quick reference checklist for Flutter app performance and the backend it calls. Use alongside the `performance-optimization` skill, and the `mobile-performance-auditor` for a structured audit (`/perf-mobile`).

## Table of Contents

- [Mobile Performance Targets](#mobile-performance-targets)
- [Startup Diagnosis](#startup-diagnosis)
- [Flutter App Checklist](#flutter-app-checklist)
- [Backend Checklist](#backend-checklist)
- [Caching Strategies](#caching-strategies)
- [Measurement Commands](#measurement-commands)
- [Common Anti-Patterns](#common-anti-patterns)

## Mobile Performance Targets

Defaults. A project's own budget overrides them. **Measure in profile mode on a real, mid-range device**, never in debug mode or on an emulator.

| Metric | Target | Notes |
|--------|--------|-------|
| Frame build time (UI thread) | ≤ 16.6ms at 60Hz, ≤ 8.3ms at 120Hz | p90 and p99, not the average |
| Frame raster time (raster thread) | Same budget | Painting, clips, shaders, `saveLayer` |
| Frozen frames | None (a frame over 700ms) | Reported by Android vitals |
| Cold start (time to first frame) | Project budget | Android vitals flags 5s or more as slow |
| Memory | No sustained growth across repeated navigation | Growth means a leak |
| App size | Project budget, tracked per release | Download and install size |
| Crash / ANR rate | Below platform bad-behavior thresholds | Play vitals, Xcode Organizer |
| API response time | < 200ms (p95) | Server side |

## Startup Diagnosis

When cold start is slow, split it into its components (`flutter run --profile --trace-startup` writes `build/start_up_info.json`):

- [ ] **Before the framework is up** (process start, engine init) slow → check native splash, plugin registration, and heavy native initializers
- [ ] **Framework init to first frame** slow → profile your code in `main()` and the first screen's `build()`
- [ ] **Work before `runApp`** → parallelize with `Future.wait`, defer what the first screen doesn't need
- [ ] **First screen blocked on network** → render a useful state first, then load
- [ ] **Large assets or JSON** loaded synchronously at startup → load lazily or off the UI isolate
- [ ] **SDK initialization** (analytics, crash reporting, remote config, DI) awaited serially → parallelize or defer
- [ ] **Cubits/Blocs created eagerly** at launch → create lazily where the feature is opened

## Flutter App Checklist

### Frame Rendering (UI Thread)
- [ ] Frames build within budget in profile mode on a mid-range device
- [ ] `setState` scope is narrow; frequently changing state lives in small widgets
- [ ] `BlocBuilder` / `BlocConsumer` are narrow; `buildWhen` or `BlocSelector` used for large states
- [ ] States have value equality (freezed), so emitting an equal state doesn't rebuild
- [ ] `const` constructors and instances wherever possible
- [ ] No heavy work in `build()`, and no futures, controllers, or streams created in `build()`
- [ ] `MediaQuery.sizeOf` / `viewInsetsOf` / `textScalerOf` instead of `MediaQuery.of`
- [ ] No `IntrinsicHeight` / `IntrinsicWidth` inside lists or deep trees
- [ ] `AnimatedBuilder` / `TweenAnimationBuilder` given a `child` for the static subtree
- [ ] Subtrees extracted into widget classes (not `_buildX()` methods) to limit rebuild scope

### Lists and Scrolling
- [ ] Long lists use lazy builders (`ListView.builder`, `SliverList.builder`, `GridView.builder`)
- [ ] `itemExtent` or `prototypeItem` set for uniform lists
- [ ] No `shrinkWrap: true` on large or nested scrollables; no `Column` of many children in a `SingleChildScrollView`
- [ ] Items keyed (`ValueKey`) when they reorder or update
- [ ] Data paginated, without rebuilding the whole list per page
- [ ] Item builds are cheap: no oversize image decodes or heavy work per item

### Raster Thread and Shaders
- [ ] No `Opacity`, `ClipRRect`, `ClipPath`, `ShaderMask`, `BackdropFilter`, or `saveLayer` triggers in scrolling or animated content without need; `FadeTransition` / `AnimatedOpacity` used instead of `Opacity`
- [ ] `RepaintBoundary` placed deliberately around genuinely expensive, independently repainting subtrees
- [ ] The renderer (Impeller vs Skia) is confirmed per target platform before doing shader-warmup work
- [ ] Custom painters repaint only when needed (`shouldRepaint`)
- [ ] Off-screen animations paused (`TickerMode`); large animations (Lottie, Rive, GIF) sized appropriately

### Images and Assets
- [ ] Images decoded near display size (`cacheWidth` / `cacheHeight`, in physical pixels), not at full resolution
- [ ] Remote images cached (for example `cached_network_image`)
- [ ] Assets in efficient formats (WebP/AVIF where supported) and sensible dimensions, with resolution-aware variants
- [ ] `precacheImage` used only for what the first frame needs
- [ ] SVGs limited in count and complexity
- [ ] Fonts limited to 2–3 families and few weights; fonts fetched at runtime (`google_fonts`) are bundled instead when startup matters
- [ ] Icon fonts tree-shaken (the release default); no unused icon sets or fonts bundled

### Isolates and UI-Isolate Work
- [ ] Large JSON parsing, encryption, compression, image processing, and big sorts run off the UI isolate (`Isolate.run`), *after* measuring
- [ ] No synchronous file or database I/O on the UI isolate (`readAsStringSync` and similar)
- [ ] Isolates not used for trivial work (message-passing cost outweighs the gain)
- [ ] Platform channel calls are batched, and large payloads across channels avoided (copy cost)

### Startup
- [ ] Minimal work before `runApp`; independent initialization runs in parallel (`Future.wait`)
- [ ] Non-critical initialization (remote config, analytics warm-up) deferred until after the first frame
- [ ] First screen renders without waiting on the network
- [ ] `BlocProvider` creation lazy for features not needed at launch
- [ ] Rarely used features candidates for deferred loading (`deferred as`, deferred components on Android)
- [ ] Native splash hands off cleanly, with no blank frame or long white screen
- [ ] Startup measured with `--trace-startup`, and tracked per release

### Memory and Lifecycle
- [ ] `AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`, and subscriptions disposed or cancelled
- [ ] Cubits/Blocs cancel subscriptions and timers in `close()`
- [ ] Listeners added in `initState` removed in `dispose`
- [ ] No `BuildContext`, large objects, or images held in singletons, statics, or long-lived streams
- [ ] Image cache size appropriate for the app's memory profile
- [ ] Memory snapshots before and after repeated navigation show no sustained growth
- [ ] No `setState` or `emit` after `dispose` / `close` (mounted / `isClosed` checks across async gaps)

### Network (Client)
- [ ] API responses paginated, and payloads no larger than the screen needs
- [ ] Independent requests run in parallel (`Future.wait`); duplicate in-flight requests deduplicated
- [ ] Responses cached with sensible invalidation (`ETag` / conditional requests, HTTP cache, local database)
- [ ] One HTTP client instance reused (connection reuse), with timeouts set
- [ ] Retries bounded with exponential backoff; graceful offline and flaky-network behavior
- [ ] No requests issued from `build()` or widgets that rebuild often
- [ ] Response compression enabled; chatty endpoints replaced by batch or aggregate endpoints
- [ ] Polling replaced by push or streaming where possible

### App Size
- [ ] `--analyze-size` run on a release build, largest packages and assets reviewed
- [ ] Unused packages, assets, fonts, and icon sets removed
- [ ] App bundles (Android) or split-per-ABI used; debug symbols split out (`--split-debug-info`, paired with `--obfuscate`)
- [ ] Images compressed; large assets downloaded on demand instead of bundled
- [ ] Deferred components considered for rarely used features on Android
- [ ] Size tracked per release with a budget

### Battery and Background
- [ ] Timers, polling, and animations stop when the screen is off-screen or the app is backgrounded (`TickerMode`, lifecycle callbacks)
- [ ] Location requested at the lowest accuracy and frequency the feature needs, and stopped when not needed
- [ ] Wakelocks, background fetch, and long-running background tasks held no longer than necessary
- [ ] Sensors, camera, and streams released when leaving their screens
- [ ] Network work batched to avoid waking the radio repeatedly

## Backend Checklist

### Database
- [ ] No N+1 query patterns (use eager loading / joins)
- [ ] Queries have appropriate indexes
- [ ] List endpoints paginated (never `SELECT * FROM table`)
- [ ] Connection pooling configured
- [ ] Slow query logging enabled

#### Query plans
- [ ] `EXPLAIN ANALYZE` captured **before** the fix, not just after — it is the baseline
- [ ] `Seq Scan` on a large table understood: index missing, unusable, or genuinely not worth it
- [ ] Estimated vs actual `rows=` within an order of magnitude (if not, refresh statistics before touching indexes)
- [ ] No `Sort` node that a composite index could absorb
- [ ] Plan re-checked after the change — an index that did not change the plan gets reverted

#### Index strategy
- [ ] Composite index column order is equality first, then range/sort
- [ ] Index covers the query shape (filter + sort), not just one column in isolation
- [ ] Covering index considered for hot read paths (index-only scan avoids the heap fetch)
- [ ] Not indexing low-selectivity columns *for the dominant value*; a partial index still serves the rare-value query (`WHERE status = 'failed'`)
- [ ] Expression index used where the query applies a function (`lower(email)`)
- [ ] Full-text or trigram index used for leading-wildcard search, not a B-tree
- [ ] Write cost measured on write-heavy tables (every index taxes every `INSERT`/`UPDATE`)
- [ ] Unused and duplicate indexes dropped (they cost writes and buy nothing)

#### Connection pooling
- [ ] One pool per process, not per request or per module
- [ ] `instances × pool max` stays under the database's `max_connections`
- [ ] `connectionTimeoutMillis` set so exhaustion fails fast instead of queueing forever
- [ ] Exhaustion diagnosed before resizing: find what holds connections (long transactions, missing `await`, leaked clients)
- [ ] Serverless / autoscaling fronted by a multiplexing proxy (pgbouncer, RDS Proxy) rather than a larger pool

### API
- [ ] Response times < 200ms (p95)
- [ ] No synchronous heavy computation in request handlers
- [ ] Bulk operations instead of loops of individual calls
- [ ] Response compression (gzip/brotli)
- [ ] Appropriate caching (in-memory, Redis, CDN)

### Infrastructure
- [ ] CDN for static assets
- [ ] Server located close to users (or edge deployment)
- [ ] Horizontal scaling configured (if needed)
- [ ] Health check endpoint for load balancer

## Caching Strategies

The decision material (which layer, which invalidation strategy, what never to cache) lives in the `performance-optimization` skill. This section covers the read/write patterns and the checklist.

### Read and write patterns

| Pattern | How it works | Use when | Watch out for |
|---|---|---|---|
| **Cache-aside** (lazy) | App checks cache, on miss reads origin and populates | Default choice; read-heavy, tolerant of a cold first hit | Every miss hits the origin, so it needs stampede protection |
| **Read-through** | Cache layer itself loads on miss | You want the load path in one place, not at every call site | Hides origin latency; a slow origin looks like a slow cache |
| **Write-through** | Write goes to cache and origin together, synchronously | Reads must never see a stale value after a write | Adds cache latency to every write |
| **Write-behind** (write-back) | Write hits cache, origin updated asynchronously | Write-heavy, and the origin is the bottleneck | Data loss window if the cache dies before the flush. Needs durability you can defend |

### Negative caching

Cache the *absence* of a result too. A key that misses on every lookup (a nonexistent user ID probed in a loop, a 404 asset) sends every request to the origin, which is a cache that only protects the happy path.

- Store an explicit "not found" sentinel with a **shorter** TTL than positive entries
- Keep the negative TTL short enough that a newly created record appears promptly
- Never let an origin *error* become a negative cache entry, or one failing minute becomes many

### Request coalescing (stampede protection)

One recompute, N waiters. Prevents a hot key's expiry from delivering the full concurrent load to the origin:

```typescript
const inFlight = new Map<string, Promise<unknown>>();

function loadOnce<T>(key: string, fetcher: () => Promise<T>): Promise<T> {
  const existing = inFlight.get(key) as Promise<T> | undefined;
  if (existing) return existing;
  const p = fetcher().finally(() => inFlight.delete(key));
  inFlight.set(key, p);
  return p;
}
```

For a shared cache, the same idea needs a distributed lock, or `stale-while-revalidate` so waiters serve the stale value instead of blocking.

### Cache checklist
- [ ] The cached call was measured as expensive first (caching a fast call adds a hop and buys nothing)
- [ ] Read/write ratio justifies the cache (re-read far more often than written)
- [ ] Cache key includes every input the response varies on: tenant, viewer, locale, permissions, feature flags
- [ ] No per-user data cached under a key that does not identify the user
- [ ] One invalidation strategy chosen (TTL, event/tag, or versioned keys), not an accidental mix
- [ ] Acceptable staleness window written down, not implied by whatever TTL was typed
- [ ] Stampede protection on hot keys (coalescing, lock, or `stale-while-revalidate`)
- [ ] Negative results cached with a shorter TTL; origin errors never cached
- [ ] Eviction policy and memory ceiling set (an unbounded cache is a memory leak)
- [ ] Hit rate monitored — a cache nobody measures is an assumption, and a low hit rate is pure overhead
- [ ] Nothing cached whose staleness is a correctness bug (balances, permissions, inventory at checkout)

## Measurement Commands

### Workflow

1. **Field data first.** Check Play Console vitals, Xcode Organizer, Firebase Performance, or Crashlytics for real-user startup, jank, ANR, and crash data by app version and device before optimizing.
2. **Reproduce in profile mode on a real device.** Debug mode and emulators are not representative. Record a DevTools Performance capture while doing the slow interaction; check the UI vs raster thread, jank frames, and rebuild counts.
3. **Test on a mid-range or low-end Android device.** Many issues only show on slower hardware; a flagship phone hides them.

```bash
# Profile mode on a connected device
flutter run --profile

# Startup: writes build/start_up_info.json (time to first frame, framework init)
flutter run --profile --trace-startup

# App size: writes a code-size-analysis JSON; open it in DevTools' app size tool
flutter build apk --analyze-size        # also: appbundle, ios

# Repeatable frame timing in a test (integration_test + traceAction / TimelineSummary)
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart

# DevTools: Performance, CPU Profiler, Memory, Network, Inspector (widget rebuild counts)
dart devtools

# Android native stats
adb shell dumpsys gfxinfo <package> framestats     # frame timing
adb shell dumpsys meminfo <package>                # memory
adb shell am start -W -n <package>/<activity>      # cold start timing (TotalTime)

# iOS: Xcode Instruments (Time Profiler, Allocations, Animation Hitches, Energy) and Organizer
```

```dart
// Custom spans appear in the DevTools timeline
import 'dart:developer';
final tasks = Timeline.timeSync('parse-tasks', () => parseTasks(body));

// Overlay frame timings while running in profile mode
MaterialApp(showPerformanceOverlay: true, /* ... */)
```

Neither mobile-mcp nor the Dart MCP server produces a frame timeline or memory profile. Get those from DevTools, and see `flutter-devtools-and-device-testing` for what the agent tools can do (repeatable cold starts, screen recording, crash lists).

## Common Anti-Patterns

| Anti-Pattern | Impact | Fix |
|---|---|---|
| N+1 queries | Linear DB load growth | Use joins, includes, or batch loading |
| Unbounded queries | Memory exhaustion, timeouts | Always paginate, add LIMIT |
| Missing indexes | Slow reads as data grows | Add indexes for filtered/sorted columns |
| Indexing without reading the plan | Write cost paid, read gain unproven | `EXPLAIN ANALYZE` before and after; revert if the plan is unchanged |
| Redundant / unused indexes | Every write pays for them | Audit usage stats, drop what nothing reads |
| Connection pool per request | Exhausts `max_connections` under load | One pool per process; proxy for serverless |
| Cache key missing the viewer | One user's data served to another | Key on tenant, viewer, locale, permissions |
| Unbounded cache | Memory leak wearing an optimization's clothing | Set eviction policy and a memory ceiling |
| Cache stampede on a hot key | Origin takes full concurrent load at expiry | Coalesce misses, or `stale-while-revalidate` |
| Measuring in debug mode or on an emulator | Numbers off by an order of magnitude | Profile mode on a real, mid-range device |
| Whole-screen `BlocBuilder` / root `setState` | Large subtrees rebuild for a small change | `BlocSelector`, `buildWhen`, smaller widgets, `const` |
| `ListView(children: [...])` for long lists | Builds every item up front | `ListView.builder` with `itemExtent` |
| Full-resolution image for a small view | Memory and decode cost, raster jank | `cacheWidth` / `cacheHeight`, cached network images |
| Heavy parsing or sync I/O on the UI isolate | Dropped frames, frozen taps | `Isolate.run`, async I/O |
| Serial SDK init before `runApp` | Slow cold start | `Future.wait`, defer non-critical work |
| `Opacity` / clips / blurs in scrolling content | Raster-thread jank | `FadeTransition`, cheaper clipping, pre-rendered assets |
| Futures or controllers created in `build()` | Refetch and leaks on every rebuild | Create in `initState` or a Cubit; dispose |
| Undisposed controllers and subscriptions | Growing memory, eventual OOM kill | `dispose()` / `close()` everything you own |
| Polling and timers running in the background | Battery drain | Stop on pause; use push |
| Unreviewed packages and assets | Growing app size | `--analyze-size` per release, remove unused |
