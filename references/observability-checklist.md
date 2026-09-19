# Observability Checklist

Quick reference for instrumenting production code, including Flutter apps running on users' devices and the backends they call. Use alongside the `observability-and-instrumentation` skill.

## Table of Contents

- [On-Call Questions (Start Here)](#on-call-questions-start-here)
- [Structured Logging](#structured-logging)
- [Mobile App Telemetry](#mobile-app-telemetry)
- [Metrics](#metrics)
- [Distributed Tracing](#distributed-tracing)
- [Alerting](#alerting)
- [Dashboards](#dashboards)
- [Verify the Telemetry](#verify-the-telemetry)
- [Pre-Launch Gate](#pre-launch-gate)

## On-Call Questions (Start Here)

Telemetry without a question is noise. Before instrumenting anything:

- [ ] 2–4 questions an on-call engineer will ask about this feature are written down
- [ ] Every signal below maps to one of those questions
- [ ] Each question is matched to the right signal type: metrics say **that** something is wrong, traces say **where**, logs say **why**

## Structured Logging

- [ ] Logs are structured (JSON) with stable event names — not free-form strings
- [ ] Every log line carries a correlation/request ID, generated or accepted at the system boundary
- [ ] Correlation ID is propagated on every outbound call and async boundary (HTTP headers, queue metadata)
- [ ] Any log stream written by more than one entry point (scheduler, replay endpoint, manual run) carries an entry-point field, set where the run starts and propagated alongside the correlation ID
- [ ] Log levels are consistent: `error` = invariant broken, someone may act; `warn` = degraded but handled; `info` = significant business event; `debug` = off in production
- [ ] No secrets, tokens, passwords, or unredacted PII in any log line (hard rule from `security-and-hardening`)
- [ ] Fields are allowlisted — no whole request/response bodies, no auth headers
- [ ] External service calls logged with metadata only: endpoint, status, latency, attempt count, sanitized identifiers
- [ ] Actual log output spot-checked: structured fields, not `[object Object]`

## Mobile App Telemetry

- [ ] Telemetry sits behind one interface (`Telemetry`), so the vendor is swappable, consent and PII rules are enforced in one place, and tests can fake it
- [ ] Every signal carries app version, build number, flavor, platform, and OS version, plus a session ID and active feature flags
- [ ] No `print` / `debugPrint` as logging in release code; only `warn`+ and breadcrumbs leave the device
- [ ] Event, screen, and Cubit names are explicit strings, not `runtimeType` (mangled by `--obfuscate`)
- [ ] Requests carry a request ID and app version headers, so client reports join to server logs
- [ ] Crashes captured from every path: `FlutterError.onError`, `PlatformDispatcher.onError`, isolates, `BlocObserver.onError`, native crashes, ANRs/hangs; non-fatal errors recorded with `fatal: false`
- [ ] Reports include breadcrumbs (explicit names, no state contents) and a pseudonymous user ID
- [ ] Symbols and mappings (Dart split-debug-info, R8/ProGuard, dSYMs) uploaded per release from CI; a test crash in a release-like build showed a readable stack
- [ ] Debug builds report to a dev project or not at all
- [ ] Analytics respects consent and opt-out; events use a bounded, versioned schema with an event ID and timestamps; no PII in fields
- [ ] Events are queued on disk (bounded), batched, retried with backoff, deduplicated by event ID, and flushed on background, never blocking UI or startup
- [ ] Telemetry never throws into feature code
- [ ] Client alerts are scoped to the latest app version; runbooks say how to disable the flag and halt the rollout

## Metrics

- [ ] **RED** instrumented for every endpoint and every external dependency: Rate, Errors, Duration
- [ ] **USE** instrumented for every resource (queues, pools, hosts): Utilization, Saturation, Errors
- [ ] Latency is a histogram; p50/p95/p99 queryable — never an average
- [ ] All labels come from small, fixed sets (route template, status class, provider name)
- [ ] No unbounded label values: no user IDs, tenant IDs, emails, raw URLs, request IDs, or error message text
- [ ] Status codes grouped by class (`5xx`, not `503`)
- [ ] Queue depth and processing duration tracked for every worker/queue

## Distributed Tracing

- [ ] OpenTelemetry (or equivalent) initialized at service startup, before other imports
- [ ] Auto-instrumentation enabled for HTTP, gRPC, and DB clients
- [ ] Trace context propagated on every outbound call (W3C `traceparent`/`tracestate`) and extracted from every inbound request
- [ ] Context survives async boundaries — queue messages carry trace metadata
- [ ] Manual spans only around meaningful internal units of work, with the attributes on-call will filter by
- [ ] No secrets or PII as span attributes
- [ ] Head-based sampling at a low default rate; 100% of errors kept if tail sampling is available

## Alerting

- [ ] Every alert is symptom-based (crash-free rate of the latest version, new crash on a critical flow, ANR rate, funnel drop, error rate, p99 latency, queue age) — causes (CPU, disk, restarts, one device model) go to dashboards, not pagers
- [ ] Every alert is actionable; "ignore it, it self-heals" alerts are deleted
- [ ] Every alert links to a runbook — minimum three lines: what it means, first query to run, escalation path
- [ ] Thresholds and durations justified by an SLO or historical data, not guesses
- [ ] Two severities only: **page** (user-facing, act now) and **ticket** (degradation, act this week)
- [ ] Each new alert test-fired once: it reached the right channel and the runbook link works
- [ ] No alerts that fire daily and get acknowledged without action

## Dashboards

- [ ] Service health dashboard exists: error rate, latency p99, traffic, saturation
- [ ] Dependency health panel shows per-service error rates and latency
- [ ] Dashboard answers the on-call questions from the top of this checklist — not "everything except the answer"
- [ ] Default time range is sensible (1h–6h, not 30d)

## Verify the Telemetry

Instrumentation is code; it can be wrong:

- [ ] Forced an error in staging → found it in the logs by correlation ID
- [ ] Forced a crash and a non-fatal error in a release-like build on a device → arrived tagged with app version, with a readable stack
- [ ] Went offline, used the feature, reconnected → events flushed once, no duplicates
- [ ] Turned analytics consent off → nothing was sent
- [ ] Sent test traffic → metric series appear with expected labels and sane values
- [ ] Followed one request end-to-end in the tracing UI → no broken spans
- [ ] An induced failure was diagnosed from telemetry alone, without reading the source

## Pre-Launch Gate

Before a feature ships to production, all of the following are true:

- [ ] Structured logs flowing to the log aggregator, and app crash and error reports arriving with symbols and version tags
- [ ] RED metrics visible in dashboards for every new endpoint and dependency
- [ ] At least one symptom-based alert configured, with runbook, test-fired
- [ ] A request can be traced across every service it touches
- [ ] On-call knows where the runbooks are

For launch-day monitoring sequence and rollback triggers, see the `shipping-and-launch` skill.
