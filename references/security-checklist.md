# Security Checklist

Quick reference for Flutter mobile app security and the backend it talks to. Use alongside the `security-and-hardening` skill.

## Table of Contents

- [Threat Modeling (Start Here)](#threat-modeling-start-here)
- [Pre-Commit Checks](#pre-commit-checks)
- [Authentication and Sessions](#authentication-and-sessions)
- [Authorization](#authorization)
- [Secure Storage](#secure-storage)
- [Secure Communication](#secure-communication)
- [Input Validation](#input-validation)
- [Platform Configuration and Permissions](#platform-configuration-and-permissions)
- [Secrets and Binary Protections](#secrets-and-binary-protections)
- [Data Protection and Privacy](#data-protection-and-privacy)
- [Dependency Security](#dependency-security)
- [AI / LLM Security](#ai--llm-security)
- [Error Handling](#error-handling)
- [OWASP Mobile Top 10 Quick Reference](#owasp-mobile-top-10-quick-reference)
- [OWASP Top 10 Quick Reference (Backend/API)](#owasp-top-10-quick-reference-backendapi)
- [OWASP Top 10 for LLMs Quick Reference](#owasp-top-10-for-llms-quick-reference)

## Threat Modeling (Start Here)

Before reaching for controls, spend five minutes thinking like an attacker. On mobile, **assume the client is in the attacker's hands**: they can decompile your app, intercept its traffic, and read its storage on a lost or rooted device.

- [ ] Trust boundaries mapped (API requests and responses, deep links and app links, push payloads, platform channel messages, WebView content, the clipboard, uploads, webhooks, third-party APIs and SDKs, LLM output, and local values written by processes you don't control)
- [ ] Attacker capabilities assumed: physical access to a device, a rooted or jailbroken device, a decompiled or instrumented app, a proxy on the network path, other apps competing for your URL schemes
- [ ] Assets named (credentials, tokens, PII, payment data, admin actions, money movement)
- [ ] STRIDE run per boundary (Spoofing, Tampering, Repudiation, Info disclosure, DoS, Elevation)
- [ ] Abuse cases written next to use cases ("how would I misuse this?")

## Pre-Commit Checks

- [ ] No secrets in code (`git diff --cached | grep -i "password\|secret\|api_key\|token\|BEGIN .* PRIVATE KEY"`)
- [ ] `.gitignore` covers: `.env`, `.env.local`, `*.pem`, `*.key`, `*.jks`, `*.keystore`, `key.properties`, `*.p8`, and any `--dart-define-from-file` config holding non-public values
- [ ] `.env.example` and committed config use placeholder or public values only
- [ ] Generated files and `pubspec.lock` follow the project convention, and changes to `pubspec.lock` were reviewed

## Authentication and Sessions

- [ ] Passwords hashed **on the server** with bcrypt (≥12 rounds), scrypt, or argon2; the user's password is never stored on the device
- [ ] Access tokens short-lived; refresh tokens rotate and can be revoked server-side
- [ ] Tokens stored in platform secure storage (Keychain/Keystore), never `SharedPreferences` or plain files
- [ ] Token refresh handled in one place (an interceptor), so concurrent 401s cause one refresh
- [ ] OAuth/OIDC uses the authorization-code flow with PKCE in the system browser, no embedded WebView, no client secret in the app
- [ ] Biometrics (`local_auth`) treated as a convenience gate, not proof of identity; sensitive actions verified server-side
- [ ] Root/jailbreak detection and attestation (Play Integrity, App Attest) treated as server-evaluated signals, not client gates
- [ ] Logout wipes secure storage, caches, and local databases
- [ ] Rate limiting on the login endpoint (≤10 attempts per 15 minutes), enforced on the server
- [ ] Password reset tokens: time-limited (≤1 hour), single-use
- [ ] Account lockout after repeated failures (optional, with notification)
- [ ] MFA supported for sensitive operations (optional but recommended)

## Authorization

- [ ] **Authorization is enforced on the server.** Hidden buttons and client route guards are UX, not security
- [ ] Every protected endpoint checks authentication
- [ ] Every resource access checks ownership/role (prevents IDOR)
- [ ] Admin endpoints require admin role verification
- [ ] API keys scoped to minimum necessary permissions; keys shipped in the app restricted by bundle ID / package name / signing certificate in the provider's console
- [ ] JWT tokens validated on the server (signature, expiration, issuer)

## Secure Storage

- [ ] Tokens and secrets use `flutter_secure_storage` (Keychain/Keystore-backed); Keychain accessibility level chosen deliberately, with `*_this_device` variants for device-bound secrets
- [ ] Sensitive local databases encrypted; all local queries use bound parameters
- [ ] Android backups disabled or excluded for sensitive data (`android:allowBackup="false"` or backup rules); sensitive iOS files excluded from backup
- [ ] Sensitive screens hidden in the app switcher; screenshots blocked where the data warrants it
- [ ] Nothing sensitive in logs, the clipboard, notifications, or analytics
- [ ] Only the data you need is persisted; access tokens kept in memory where possible

## Secure Communication

- [ ] HTTPS only: Android `usesCleartextTraffic="false"` / network security config with `cleartextTrafficPermitted="false"`; iOS never sets `NSAllowsArbitraryLoads`
- [ ] No `badCertificateCallback` that accepts every certificate, and no permissive `HttpOverrides`, in any build that ships
- [ ] Debug-only trust anchors live in `<debug-overrides>` (Android) and never in release
- [ ] Certificate pinning decision recorded; if pinned: public key or intermediate CA pinned (not only the leaf), a backup pin shipped, a rotation plan and a way to update pins exist
- [ ] Verified with an intercepting proxy on a test device: pinned traffic fails, and unpinned traffic shows nothing beyond the API contract

## Input Validation

- [ ] All external input validated at system boundaries: API responses and routes, deep links, push payloads, platform channel messages, WebView messages
- [ ] Deep-link parameters validated in the router before any screen or Cubit sees them; sensitive actions never executed directly from a link
- [ ] Verified app links (Android) and universal links (iOS) preferred over custom URL schemes
- [ ] API responses parsed into typed models; malformed data handled without crashing; unknown enum values fall back safely
- [ ] Validation uses allowlists (not denylists)
- [ ] String lengths constrained (min/max) and numeric ranges validated
- [ ] Email, URL, and date formats validated with proper libraries
- [ ] File uploads: type restricted, size limited, content verified (enforced on the server)
- [ ] SQL queries parameterized, on the server and in the on-device database
- [ ] WebViews: JavaScript disabled unless required, navigation allowlisted, no untrusted URLs, no sensitive JavaScript channels, no tokens injected into web content
- [ ] URLs validated before redirect (prevent open redirect, including `?next=` parameters)
- [ ] Server-side URL fetches allowlisted; private/reserved IPs blocked (prevent SSRF)
- [ ] Destructive path operations (delete/move/overwrite), on the server or on the device: symlinks resolved, allowlisted root, minimum depth, ownership evidence read before the call

### Destructive Path Operations

Containment for a target named by data. Resolve first, then decide — and treat the
result as a candidate, not as authorization:

```typescript
import { realpath, readFile } from 'node:fs/promises';
import { resolve, relative, isAbsolute, join, sep } from 'node:path';

const ALLOWED_ROOTS = ['/var/lib/myapp/sessions']; // an allowlist, not a pattern
const MIN_DEPTH = 1;                               // so a root is never the target

async function resolveDeletable(candidate: string, expectedOwner: string) {
  const target = await realpath(resolve(candidate)); // symlinks resolved BEFORE the check
  const inRoot = ALLOWED_ROOTS.some((root) => {
    const rel = relative(root, target);
    // `rel === '..'` / `'../'` only — a plain `startsWith('..')` would also
    // reject a legitimate child named `..cache`.
    if (rel === '' || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)) return false;
    return rel.split(sep).length >= MIN_DEPTH;
  });
  if (!inRoot) throw new Error(`refusing: outside allowed roots (${target})`);

  const owner = await readFile(join(target, '.owner'), 'utf8').catch(() => null);
  if (owner?.trim() !== expectedOwner) throw new Error(`refusing: unproven owner (${target})`);
  return target;
}
```

What this does not do, and must be said where the snippet is copied from:

- **The marker is self-attestation.** Anything that can write inside the root can write
  `.owner`. `expectedOwner` has to come from authenticated state, and the marker needs
  integrity protection (restrictive ownership, or a MAC) before it is authorization
  rather than a consistency check against a misderived target.
- **Returning a path leaves a check/use race.** Where an untrusted process can swap an
  ancestor between the check and the call, operate on a descriptor with no-follow,
  beneath-the-root semantics, or guarantee the hierarchy is immutable for the duration.

The same containment applies to on-device file operations, such as cache cleanup and
export or import of user files. In Dart, resolve symlinks first and compare against
resolved roots. On iOS, for example, `/var` is a symlink to `/private/var`, so an
unresolved root will never match a resolved target:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

Future<Directory> resolveDeletable(String candidate, Set<String> allowedRoots) async {
  final target = await Directory(candidate).resolveSymbolicLinks();   // BEFORE the check
  final roots = [for (final r in allowedRoots) await Directory(r).resolveSymbolicLinks()];
  // isWithin is false when the target equals the root, so a root is never the target
  if (!roots.any((root) => p.isWithin(root, target))) {
    throw StateError('refusing: outside allowed roots ($target)');
  }
  return Directory(target);
}
```

The same limits apply: an in-tree marker is self-attestation, and resolving a path then
operating on the *name* is a check/use race wherever an untrusted process can swap an
ancestor.

## Platform Configuration and Permissions

- [ ] Merged Android manifest of the **release** build reviewed (plugins add permissions and components): not `android:debuggable`, `android:allowBackup` deliberate, every component has an explicit `android:exported`, permissions minimal
- [ ] `Info.plist` contains only the usage-description keys in use, with accurate purpose strings; privacy manifest (`PrivacyInfo.xcprivacy`) matches SDK behavior
- [ ] Permissions requested at the moment of use with a rationale; denial and "don't ask again" handled gracefully; unused permissions removed
- [ ] New URL schemes, intent filters, and app links reviewed for hijacking and exposure
- [ ] No `flutter_driver` extension, dev menus, debug banners, or verbose logging reachable in release builds
- [ ] Backend-as-a-service rules (Firestore, Storage, and so on) locked down by default and tested

## Secrets and Binary Protections

- [ ] No real secrets in the app: assume every string in the binary is readable, including `--dart-define` values
- [ ] Only public, low-privilege identifiers ship in the app; privileged keys (payments, LLMs, admin) live on the server behind authentication and rate limits
- [ ] Keys that must ship are restricted in the provider's console (bundle ID, package name, signing certificate)
- [ ] Release builds obfuscated: `--obfuscate --split-debug-info=build/symbols`; symbols kept out of the artifact and stored for de-obfuscation
- [ ] Obfuscation treated as a speed bump, not a control: sensitive logic and checks enforced server-side
- [ ] Signing keys, keystores, `key.properties`, and `.p8` keys held in the CI secret store, never in the repository
- [ ] Cryptography uses vetted libraries and authenticated encryption; no hard-coded keys, salts, or IVs; `Random.secure()` for randomness

## Data Protection and Privacy

- [ ] Sensitive fields excluded from API responses (`passwordHash`, `resetToken`, etc.)
- [ ] Sensitive data not logged (passwords, tokens, full CC numbers), including `print` / `debugPrint` in release code
- [ ] PII encrypted at rest (if required by regulation), on the device and on the server
- [ ] HTTPS for all external communication
- [ ] Database backups encrypted
- [ ] Personal data classified, collected against a stated purpose, minimized, with a retention limit
- [ ] Analytics and third-party SDK data sharing gated on consent; store privacy declarations (App Privacy labels, Play Data safety) match actual collection
- [ ] In-app account deletion works end to end (server data, backups, analytics copies)

## Dependency Security

### Dart and Flutter (the app)

- [ ] `pubspec.lock` committed for the app, and CI installs from it (`flutter pub get --enforce-lockfile`; confirm your SDK supports the flag)
- [ ] Advisories triaged by reachability (pub.dev advisories, your SDK's audit command if it has one); deferrals have a reason and a review date
- [ ] New dependencies vetted: publisher (prefer verified), maintenance, release age, popularity and pub points, license, transitive graph, lookalike names
- [ ] Plugins' native code reviewed: Gradle and CocoaPods build files, requested permissions, bundled binaries, and manifest changes merged into yours
- [ ] `git:` and `path:` dependencies pinned to a commit and justified
- [ ] Third-party SDKs (analytics, ads, payments, crash reporting) approved as a security *and* privacy decision
- [ ] `dev_dependencies` kept out of the runtime graph; unused packages removed
- [ ] Flutter SDK version pinned and upgraded deliberately

### Backend and Tooling Repositories (JavaScript)

The matrices below apply to the backend or any Node tooling repository, and are kept here for that use.

First locate the **installation boundary**. If the package is matched by a parent `workspaces` declaration, use that workspace root; otherwise use the nearest project root that owns both its manifest and dependency graph. At that boundary, corroborate `packageManager` (when present), the lockfile, and CI commands. Stop if they disagree or competing manager lockfiles exist there. A nested project is independent only when it is outside the parent workspace; independent subprojects may legitimately use different managers.

| Manager/version signal | Frozen/immutable CI install | Known-advisory audit |
|---|---|---|
| npm (`package-lock.json` or `npm-shrinkwrap.json`) | `npm ci` | `npm audit` |
| pnpm | `pnpm install --frozen-lockfile` | `pnpm audit` |
| Yarn 2+ | `yarn install --immutable` | `yarn npm audit -A -R` |
| Yarn 1 | `yarn install --frozen-lockfile` | `yarn audit` |

For an unlisted manager or version, consult its official documentation; do not substitute another manager's commands or newer defaults.

### Install-Script Gate

Never discover dependency lifecycle scripts by first executing an ordinary install on a client whose defaults have not been verified.

1. Bootstrap with dependency scripts disabled, or with a documented default-deny policy plus fail-closed enforcement.
2. Inspect the exact script source and package version before approval.
3. Record the narrowest native allow/deny policy at the installation boundary and commit it.
4. Run a clean frozen/immutable install with that policy and verify the required packages still build.

**Point-in-time snapshot:** Package-manager defaults and command names change quickly. Verify this matrix against the pinned client's current official documentation before relying on it.

| Manager version | Native policy |
|---|---|
| npm without verified granular approvals | Bootstrap with `npm ci --ignore-scripts`, or persist `ignore-scripts=true` when project-wide blocking is intended. Keep scripts disabled or deliberately upgrade before allowing any reviewed dependency script. |
| npm 11.18.x (verified on 11.18.0) | Unreviewed dependency scripts run with a warning by default. Enforce `strict-allow-scripts=true` before a normal install, then use the workspace-unaware `npm install-scripts ls` from the installation boundary; keep approvals version-pinned and denials name-wide. |
| npm 12.x (verified on 12.0.1) | Unreviewed dependency scripts are skipped by default; `strict-allow-scripts=true` makes their presence fail the install before execution. Use the same `npm install-scripts` review and approval flow. |
| pnpm 11+ | Use `pnpm approve-builds` and commit `allowBuilds` decisions; `strictDepBuilds` defaults to `true`, so unreviewed builds fail. |
| pnpm 10.26–10.x | Configure `allowBuilds` explicitly, or use `pnpm approve-builds` with the legacy `onlyBuiltDependencies` / `ignoredBuiltDependencies` lists. Set `strictDepBuilds: true`; its v10 default is `false`. |
| pnpm 10.1–10.25 | `pnpm approve-builds` records the legacy lists; enable `strictDepBuilds` where supported (10.3+). |
| Older or unknown pnpm | Bootstrap with `pnpm install --frozen-lockfile --ignore-scripts`. Keep scripts disabled unless the pinned version documents an enforceable policy. |
| Yarn 4.14+ | Dependency postinstalls are disabled by default. Grant only required exceptions with top-level `dependenciesMeta.<package>.built: true`. |
| Yarn 2–4.13 | Set `enableScripts: false` in `.yarnrc.yml`, then grant only required exceptions with top-level `dependenciesMeta.<package>.built: true`; do not enable scripts globally. |
| Yarn 1 | Bootstrap with `yarn install --ignore-scripts`; keep scripts disabled unless each required exception is reviewed under the pinned client's documented workflow. |

Authoritative checks: [npm install-scripts](https://docs.npmjs.com/cli/v11/commands/npm-install-scripts/), [install policy](https://docs.npmjs.com/cli/v11/commands/npm-install/), and [CLI releases](https://github.com/npm/cli/releases); [pnpm approve-builds](https://pnpm.io/cli/approve-builds) and [build settings](https://pnpm.io/settings#allowbuilds); [Yarn security](https://yarnpkg.com/features/security) and [manifest](https://yarnpkg.com/configuration/manifest#dependenciesMeta).

**Supply-chain hygiene** (advisory audits do not catch newly malicious packages):
- [ ] Exactly one authoritative lockfile per project/workspace root is committed and CI never rewrites it
- [ ] Critical/high findings are triaged for reachability; deferrals have a reason and review date
- [ ] Forced audit remediation (`npm audit fix --force` or equivalent) is never automatic; remediation diffs and changelogs are reviewed
- [ ] Registry signatures/provenance are verified where the manager supports it
- [ ] Dependency lifecycle scripts are blocked before first execution and approved only through the pinned manager's native policy
- [ ] New dependencies are reviewed for ownership, maintenance, release age, provenance, transitive graph, and typosquatting

## AI / LLM Security

For any feature that calls an LLM (chatbots, summarizers, agents, RAG):

- [ ] Model output treated as untrusted — never into `eval`/SQL/shell/WebView HTML/file paths
- [ ] **No LLM API key in the app**: calls go through your backend, which holds the key, authenticates the user, and rate-limits
- [ ] Prompt injection assumed; permissions enforced in code, not in the system prompt
- [ ] Secrets, cross-tenant data, and full system prompts kept out of the context window
- [ ] Tool/agent permissions scoped; destructive or irreversible actions require confirmation
- [ ] Token, rate, and recursion/loop limits set (bound consumption)

## Error Handling

```typescript
// Server, production: generic error, no internals
res.status(500).json({
  error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' }
});

// NEVER in production:
res.status(500).json({
  error: err.message,
  stack: err.stack,         // Exposes internals
  query: err.sql,           // Exposes database details
});
```

```dart
// App: show a friendly message, report the detail, never show stack traces to users
ErrorWidget.builder = (details) => const ErrorFallback();          // Release builds
FlutterError.onError = (details) => telemetry.recordError(         // Report without PII
  details.exception,
  details.stack ?? StackTrace.current,
  fatal: true,
);
```

- [ ] Users never see stack traces or raw server errors
- [ ] Error reports carry no tokens, PII, or full request/response bodies

## OWASP Mobile Top 10 Quick Reference

The 2024 list. Use the [OWASP MASVS](https://mas.owasp.org/MASVS/) as the verification standard.

| # | Risk | Prevention |
|---|---|---|
| M1 | Improper Credential Usage | No secrets in the app or repo; secure storage; short-lived, revocable tokens |
| M2 | Inadequate Supply Chain Security | Committed `pubspec.lock`, vetted packages and SDKs, review native plugin code |
| M3 | Insecure Authentication/Authorization | Server-side enforcement; PKCE OAuth; biometrics as a gate only |
| M4 | Insufficient Input/Output Validation | Validate deep links, push, channels, WebView, and API responses; typed models |
| M5 | Insecure Communication | HTTPS only, no cert-validation bypass, considered pinning |
| M6 | Inadequate Privacy Controls | Minimize data, consent, accurate store declarations, account deletion |
| M7 | Insufficient Binary Protections | Obfuscation, no client-side-only checks, server-side attestation signals |
| M8 | Security Misconfiguration | Reviewed manifests and plists, explicit `exported`, no debug surface in release |
| M9 | Insecure Data Storage | Keychain/Keystore, encrypted DBs, backups excluded, no sensitive logs |
| M10 | Insufficient Cryptography | Vetted libraries, authenticated encryption, `Random.secure()`, no hard-coded keys |

## OWASP Top 10 Quick Reference (Backend/API)

| # | Vulnerability | Prevention |
|---|---|---|
| 1 | Broken Access Control | Auth checks on every endpoint, ownership verification |
| 2 | Cryptographic Failures | HTTPS, strong hashing, no secrets in code |
| 3 | Injection | Parameterized queries, input validation |
| 4 | Insecure Design | Threat modeling, spec-driven development |
| 5 | Security Misconfiguration | Security headers, minimal permissions, audit deps |
| 6 | Vulnerable Components | Dependency audits for the app (pub advisories) and the backend (`npm audit`, `pip-audit`, ...), keep deps updated, minimal deps |
| 7 | Auth Failures | Strong passwords, rate limiting, session management |
| 8 | Data Integrity Failures | Verify updates/dependencies, signed artifacts |
| 9 | Logging Failures | Log security events, don't log secrets |
| 10 | SSRF | Validate/allowlist URLs, restrict outbound requests |

## OWASP Top 10 for LLMs Quick Reference

For apps with LLM features. See the [OWASP GenAI Security Project](https://genai.owasp.org/llm-top-10/).

| ID | Risk | Prevention |
|---|---|---|
| LLM01 | Prompt Injection | Don't trust the system prompt as a boundary; enforce permissions in code |
| LLM02 | Sensitive Information Disclosure | Keep secrets/PII out of prompts; filter outputs |
| LLM03 | Supply Chain | Vet models, datasets, and plugins like any dependency |
| LLM04 | Data and Model Poisoning | Use trusted model sources, verify integrity; vet fine-tuning and RAG data |
| LLM05 | Improper Output Handling | Treat model output as untrusted; validate, parameterize, encode |
| LLM06 | Excessive Agency | Scope tool permissions; confirm destructive actions |
| LLM07 | System Prompt Leakage | Assume the system prompt can leak; put no secrets in it |
| LLM08 | Vector and Embedding Weaknesses | Partition RAG embeddings per tenant; validate documents before indexing |
| LLM09 | Misinformation | Ground answers with citations; validate critical claims; keep a human in the loop |
| LLM10 | Unbounded Consumption | Cap tokens, request rate, and loop/recursion depth |
