---
name: security-and-hardening
description: Hardens Flutter apps and the backends they talk to against vulnerabilities. Use when auditing an input handler, deep link, or platform channel for vulnerabilities, when handling user input, authentication, token or data storage, biometrics, certificate pinning, platform permissions, or external integrations, or when checking a login flow against the OWASP Mobile Top 10. Use when building any feature that accepts untrusted data, manages user sessions, or interacts with third-party SDKs. Use when preparing a release build for obfuscation and manifest hardening, auditing pub dependencies, or assessing supply-chain risk in a new package. Use when personal data or privacy compliance (GDPR, CCPA, store privacy requirements) is involved.
---

# Security and Hardening

## Overview

Security-first development practices for Flutter mobile apps and the backends they call. Treat every external input as hostile, every secret as sacred, and every authorization check as mandatory. Security isn't a phase — it's a constraint on every line of code that touches user data, authentication, or external systems.

**The mobile difference: the client is in the attacker's hands.** The app binary can be downloaded and decompiled, traffic can be intercepted with a proxy, and local storage can be read on a lost, rooted, or jailbroken device. Anything you ship inside the app is public, and any check that runs only on the device can be bypassed. Design so that a fully compromised client can do no more than its own user is allowed to do, and enforce every rule that matters on the server.

## When to Use

- Building anything that accepts user input, deep links, push payloads, or platform channel messages
- Implementing authentication, authorization, or biometrics
- Storing or transmitting sensitive data (tokens, PII, payment data)
- Integrating with external APIs, third-party SDKs, or WebViews
- Adding certificate pinning, permissions, or new URL schemes and intent filters
- Preparing a release build (obfuscation, manifest and plist review)
- Adding file uploads, webhooks, or callbacks on the backend

## Process: Threat Model First

Controls bolted on without a threat model are guesses. Before hardening, spend five minutes thinking like an attacker:

1. **Map the trust boundaries.** Where does untrusted data cross into your system? HTTP requests and responses, form fields, **deep links and app links**, **push notification payloads**, **platform channel messages**, **WebView content**, **the clipboard**, file uploads, webhooks, third-party APIs and SDKs, message queues, and **LLM output** — plus the local values that look internal because the OS handed them to you: another process's command line or environment, filenames on a shared volume, a path in a job payload. Trust follows who *wrote* a value, not which channel delivered it. Every boundary is attack surface.
2. **Name the assets.** What's worth stealing or breaking? Credentials, PII, payment data, admin actions, money movement.
3. **Run STRIDE over each boundary** — a quick lens, not a ceremony:

| Threat | Ask | Typical mitigation |
|---|---|---|
| **S**poofing | Can someone impersonate a user/service? | Authentication, signature verification |
| **T**ampering | Can data be altered in transit or at rest? | Integrity checks, parameterized queries, HTTPS |
| **R**epudiation | Can an action be denied later? | Audit logging of security events |
| **I**nformation disclosure | Can data leak? | Encryption, field allowlists, generic errors |
| **D**enial of service | Can it be overwhelmed? | Rate limiting, input size caps, timeouts |
| **E**levation of privilege | Can a user gain rights they shouldn't? | Authorization checks, least privilege |

4. **Write abuse cases next to use cases.** For each feature, ask "how would I misuse this?" — then make that your first test.

**Assume these attacker capabilities on mobile:** physical access to an unlocked or lost device; a rooted or jailbroken device; a decompiled or instrumented copy of your app; a proxy on the network path (public Wi-Fi, a malicious profile); other apps on the same device competing for your URL schemes and intents.

If you can't name the trust boundaries for a feature, you're not ready to secure it. This is OWASP **A04: Insecure Design** — most breaches begin in design, not code.

### Standards to Anchor On

Use the [OWASP Mobile Application Security Verification Standard (MASVS)](https://mas.owasp.org/MASVS/) as the verification bar and the OWASP Mobile Top 10 as the risk list. This skill's sections map to them:

| Mobile Top 10 (2024) | Covered in |
|---|---|
| M1 Improper Credential Usage | Secure Storage; Secrets in the App; Secrets Management |
| M2 Inadequate Supply Chain Security | Supply-Chain Hygiene |
| M3 Insecure Authentication/Authorization | Authentication and Sessions; Broken Access Control |
| M4 Insufficient Input/Output Validation | Deep Links, WebViews, and Platform Channels; Input Validation Patterns |
| M5 Insecure Communication | Secure Communication |
| M6 Inadequate Privacy Controls | Data Privacy & Compliance |
| M7 Insufficient Binary Protections | Binary Protections |
| M8 Security Misconfiguration | Release Build and Manifest Hardening |
| M9 Insecure Data Storage | Secure Storage |
| M10 Insufficient Cryptography | Cryptography |



## The Three-Tier Boundary System

### Always Do (No Exceptions)

- **Validate all external input** at the boundary: API responses, deep-link parameters, push payloads, platform channel messages, WebView messages, and (on the server) API routes
- **Parameterize all database queries**, on the server and in the on-device database (bound arguments, never string concatenation)
- **Use HTTPS only** for all communication: no cleartext exceptions in release builds (Android network security config, iOS App Transport Security)
- **Store tokens and secrets in platform secure storage** (`flutter_secure_storage`, backed by Keychain and Keystore), never in `SharedPreferences` or plain files
- **Enforce authorization on the server.** Client-side checks are UX, not security
- **Hash passwords** on the server with bcrypt/scrypt/argon2 (never store plaintext, and never store the user's password on the device)
- **Build releases with `--obfuscate --split-debug-info`** and keep the debug symbols out of the artifact
- **Audit dependencies** (pub packages and native plugin code) and commit `pubspec.lock` before every release

### Ask First (Requires Human Approval)

- Adding new authentication flows or changing auth logic
- Storing new categories of sensitive data (PII, payment info)
- Adding a third-party SDK (analytics, ads, crash reporting, payments): it runs with your app's permissions and data
- Adding a permission to the Android manifest or a usage-description key to `Info.plist`
- Adding a URL scheme, intent filter, or app link
- Enabling JavaScript in a WebView, or exposing a JavaScript channel
- Adding, changing, or relaxing certificate pinning or the network security configuration
- Adding file upload handlers, or changing rate limiting on the backend
- Granting elevated permissions or roles

### Never Do

- **Never commit secrets** to version control (API keys, passwords, tokens, keystores, signing keys)
- **Never embed real secrets in the app.** Anything in the binary, including `--dart-define` values, is extractable. Obfuscation is not encryption
- **Never log sensitive data** (passwords, tokens, full credit card numbers). `print` and `debugPrint` output reaches device logs
- **Never trust client-side validation or client-side checks as a security boundary:** form validators, root or jailbreak detection, license checks, and feature flags in the app are all bypassable
- **Never disable TLS validation** (`badCertificateCallback` returning `true`, permissive `HttpOverrides`), even "temporarily"
- **Never store tokens or PII unencrypted on the device** (`SharedPreferences`, plain files, an unencrypted local database)
- **Never load untrusted URLs in a WebView with JavaScript enabled**, or pass tokens into web content
- **Never ship a debug build, the `flutter_driver` extension, or dev menus** in a release
- **Never expose stack traces** or internal error details to users

## Mobile Security Patterns

### Secure Storage

Treat the device as a place where data can be read by someone else: a thief, a forensic tool, malware on a rooted device, or a cloud backup.

```dart
// BAD: plain, unencrypted, included in backups
final prefs = await SharedPreferences.getInstance();
await prefs.setString('refresh_token', token);

// GOOD: Keychain / Keystore-backed storage
const storage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);
await storage.write(key: 'refresh_token', value: token);
```

- Choose the Keychain accessibility level deliberately: `first_unlock_this_device` for tokens needed in the background, a stricter level for higher-sensitivity data. Use `*_this_device` variants so secrets do not migrate to other devices through backups. Check the package's current README for Android options, which have changed between major versions.
- Store only what you must. Keep access tokens short-lived and in memory when you can; persist only the refresh token.
- **Local databases:** use bound parameters for every query (`db.query('tasks', where: 'owner_id = ?', whereArgs: [ownerId])`), and encrypt databases holding sensitive data (for example SQLCipher-backed storage).
- **Backups:** on Android set `android:allowBackup="false"` or explicit backup exclusion rules, and exclude sensitive files from iOS backups.
- **Screens:** hide sensitive screens in the app switcher and block screenshots where the data warrants it (a maintained plugin can set `FLAG_SECURE` on Android and blur on iOS).
- **Clipboard and logs:** never copy secrets to the clipboard, and never log them. Strip verbose logging from release builds.
- **Logout means wipe:** clear secure storage, caches, and databases when the user signs out or the account is removed.

### Authentication and Sessions

```dart
// One place owns tokens: storage, refresh, and logout
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);
  Future<void> save(AuthTokens t) => _storage.write(key: _refreshKey, value: t.refreshToken);
  Future<void> clear() => _storage.deleteAll();   // logout wipes everything

  static const _refreshKey = 'refresh_token';
}
```

- Use short-lived access tokens and rotating refresh tokens, with server-side revocation. Handle refresh in one place (for example an HTTP interceptor) so concurrent 401s trigger a single refresh.
- **OAuth/OIDC:** use the authorization-code flow with **PKCE** in the system browser (for example `flutter_appauth`), never an embedded WebView, and never a client secret inside the app.
- **Biometrics (`local_auth`) are a convenience gate, not proof of identity.** The result is a boolean produced on a device the attacker may control. Protect sensitive server actions with server-verified credentials, or bind the secret to a biometric-protected key.
- **Root/jailbreak detection and platform attestation (Play Integrity, App Attest) are signals.** Evaluate them on the server and combine them with other risk signals; do not treat a client-side check as a gate.
- Never store the user's password on the device.

### Secure Communication

```dart
// BAD: accepts any certificate, so any proxy or attacker can read the traffic
client.badCertificateCallback = (cert, host, port) => true;

// GOOD: default validation. For pinning, trust only your own CA (or use a pinning package)
final context = SecurityContext(withTrustedRoots: false)
  ..setTrustedCertificatesBytes(pinnedCaPem);
final client = HttpClient(context: context);
```

- **HTTPS only.** Android: `android:usesCleartextTraffic="false"` or a network security config with `cleartextTrafficPermitted="false"`; use `<debug-overrides>` for development trust anchors only. iOS: never set `NSAllowsArbitraryLoads`.
- **Certificate pinning is defense in depth, not a default.** It defends against a hostile CA or a user-installed proxy certificate. It also bricks the app if you rotate the certificate without warning. If you pin: pin the public key or an intermediate CA (not only the leaf), ship a backup pin, plan rotation, and keep a way to update pins (remote configuration or a forced update). Record the decision either way.
- Verify on a test device with an intercepting proxy: with pinning on, traffic must fail; with it off, nothing sensitive should be readable beyond what the API contract requires.

### Deep Links, WebViews, and Platform Channels

Everything that reaches the app from outside is untrusted input.

```dart
// Validate deep-link parameters in the router, before any screen or Cubit sees them
GoRoute(
  path: '/tasks/:id',
  redirect: (context, state) {
    final id = state.pathParameters['id'];
    if (id == null || !_taskId.hasMatch(id)) return '/';
    return null;
  },
  builder: (context, state) => TaskPage(id: state.pathParameters['id']!),
);
```

- **Prefer verified app links (Android App Links) and universal links (iOS) over custom URL schemes.** Any app can register the same custom scheme and intercept it.
- **A deep link never performs a sensitive action by itself.** Opening `myapp://transfer?to=...` must land on a confirmation screen behind authentication, not execute. Pass IDs, not commands, and allowlist redirect targets (`?next=`) to prevent open redirects.
- **Push payloads and notification taps** carry attacker-influenced data: validate them exactly like deep-link parameters.
- **WebViews:** disable JavaScript unless required, restrict navigation with a `NavigationDelegate` allowlist, never load untrusted URLs, do not expose JavaScript channels with sensitive capabilities, and never inject tokens into web content.
- **Platform channels:** treat method-call arguments as untrusted on both sides of the channel and validate types and ranges.
- **API responses** are untrusted too. Deserialize into typed freezed models, handle unexpected shapes without crashing, and bound sizes.

### Broken Access Control

Hiding a button or guarding a route in the app is UX, not authorization. A modified client calls the API directly. The server must check on every request:

```typescript
// Server: always check authorization, not just authentication
app.patch('/api/tasks/:id', authenticate, async (req, res) => {
  const task = await taskService.findById(req.params.id);

  // Check that the authenticated user owns this resource
  if (task.ownerId !== req.user.id) {
    return res.status(403).json({
      error: { code: 'FORBIDDEN', message: 'Not authorized to modify this task' }
    });
  }

  // Proceed with update
  const updated = await taskService.update(req.params.id, req.body);
  return res.json(updated);
});
```

### Secrets in the App

Assume the binary will be unpacked and every string in it read.

```dart
// BAD: a privileged key shipped in the app
const stripeSecretKey = 'sk_live_...';
const openAiKey = String.fromEnvironment('OPENAI_API_KEY');   // --dart-define is still in the binary

// GOOD: the app holds only public, low-privilege identifiers.
// Real secrets live on your server, and the app calls your backend, which calls the vendor.
```

- Public identifiers (a publishable payment key, a maps key restricted by bundle ID, package name, and signing certificate) may ship in the app. Restrict every such key in its provider's console.
- Anything that can spend money, read other users' data, or call a paid API (LLM keys, payment secret keys, admin tokens) stays on the backend behind authentication and rate limits.
- Consider a backend attestation layer (Firebase App Check, Play Integrity, App Attest) so your API can prefer requests from genuine app builds. It raises the cost of abuse; it does not make a client secret safe.

### Cryptography

- Don't design your own scheme. Use a vetted library (for example `package:cryptography`) or the platform's secure storage.
- Never hard-code keys, salts, or IVs. Generate randomness with `Random.secure()`.
- No MD5 or SHA-1 for security purposes. Use authenticated encryption (AES-GCM or ChaCha20-Poly1305) and never reuse a nonce with the same key.
- Don't store a derived or wrapping key next to the data it protects. Use the Keychain/Keystore.

### Binary Protections

```bash
# Obfuscate Dart symbols and split debug info out of the artifact
flutter build appbundle --obfuscate --split-debug-info=build/symbols
flutter build ipa --obfuscate --split-debug-info=build/symbols
```

- Obfuscation raises the effort to read your code; it does not hide strings or logic. It is a complement to server-side enforcement, never a substitute.
- Keep `build/symbols` (needed to de-obfuscate crash reports) in your crash reporting system or a private store, not in the shipped artifact.
- Do not gate features on client-side tamper checks alone; verify on the server.

### Release Build and Manifest Hardening

Security misconfiguration on mobile lives in build files and manifests.

- **Android manifest:** release builds must not be `android:debuggable`; set `android:allowBackup` deliberately; give every component an explicit `android:exported`; keep the permission list minimal. Plugins add permissions through manifest merging, so **review the merged manifest** of the release build, not just yours.
- **iOS `Info.plist`:** only the usage-description keys you use, accurate purpose strings, no `NSAllowsArbitraryLoads`, and a privacy manifest (`PrivacyInfo.xcprivacy`) that matches SDK behavior.
- **No debug surface in release:** the `flutter_driver` extension (`enableFlutterDriverExtension()`) only in a test entrypoint, and no dev menus, debug banners, or verbose logging in release builds. Do not rely on `kDebugMode` alone to hide something dangerous.
- **Signing keys:** upload keys, keystores, `key.properties`, and `.p8` keys are secrets. Keep them out of the repository and in your CI's secret store.
- **Backend rules:** if you use a backend-as-a-service (Firestore or Storage rules, for example), lock rules down by default and test them. Client SDKs cannot enforce access.

### Sensitive Data Exposure (API side)

```typescript
// Never return sensitive fields in API responses
function sanitizeUser(user: UserRecord): PublicUser {
  const { passwordHash, resetToken, ...publicFields } = user;
  return publicFields;
}

// Use environment variables for server secrets
const API_KEY = process.env.STRIPE_API_KEY;
if (!API_KEY) throw new Error('STRIPE_API_KEY not configured');
```

## Backend Security Patterns

These apply to the API your app talks to. Web-browser concerns (XSS, CSP, CORS, cookie sessions) do not apply to a native client and are omitted.

### Injection (SQL, NoSQL, OS Command)

```typescript
// BAD: SQL injection via string concatenation
const query = `SELECT * FROM users WHERE id = '${userId}'`;

// GOOD: Parameterized query
const user = await db.query('SELECT * FROM users WHERE id = $1', [userId]);

// GOOD: ORM with parameterized input
const user = await prisma.user.findUnique({ where: { id: userId } });
```

### Password Hashing and Tokens

```typescript
// Password hashing
import { hash, compare } from 'bcrypt';

const SALT_ROUNDS = 12;
const hashedPassword = await hash(plaintext, SALT_ROUNDS);
const isValid = await compare(plaintext, hashedPassword);
```

Issue short-lived access tokens and rotating refresh tokens, sign them with keys from the environment (not code), and support revocation so a lost device can be cut off.

### Server-Side Request Forgery (SSRF)

Any time the server fetches a URL the user influenced — webhooks, "import from URL", image proxies, link previews — an attacker can aim it at internal services (cloud metadata, `localhost`, private IPs).

```typescript
// BAD: fetch whatever the user gives you
await fetch(req.body.webhookUrl);

// GOOD: allowlist scheme + host, reject if ANY resolved IP is private, forbid redirects
import { lookup } from 'node:dns/promises';
import ipaddr from 'ipaddr.js';

const ALLOWED_HOSTS = new Set(['hooks.example.com']);

async function assertSafeUrl(raw: string): Promise<URL> {
  const url = new URL(raw);
  if (url.protocol !== 'https:') throw new Error('https only');
  if (!ALLOWED_HOSTS.has(url.hostname)) throw new Error('host not allowed');
  // Resolve ALL records; a single private/reserved address fails the check.
  const addrs = await lookup(url.hostname, { all: true });
  if (addrs.some((a) => ipaddr.parse(a.address).range() !== 'unicast')) {
    throw new Error('private/reserved IP');
  }
  return url;
}

await fetch(await assertSafeUrl(req.body.webhookUrl), { redirect: 'error' });
```

The `range() !== 'unicast'` check covers loopback, link-local `169.254.169.254` (cloud metadata, the #1 SSRF target), private, and unique-local ranges across IPv4 and IPv6.

**Caveat — this still has a TOCTOU gap.** `fetch` resolves DNS again after the check, so an attacker using a short-TTL record can rebind to an internal IP between validation and connection. For high-risk surfaces, resolve once and connect to the pinned IP, or put a filtering agent in front (`request-filtering-agent` / `ssrf-req-filter`).

## Input Validation Patterns

### Schema Validation at Boundaries

**Client:** form validators improve UX and catch typos; they are not a security control. Parse API responses, deep-link parameters, and channel messages into typed freezed models, and reject or default anything malformed.

**Server:** validate every request, regardless of what the app sends. A modified client skips your validators.

```typescript
import { z } from 'zod';

const CreateTaskSchema = z.object({
  title: z.string().min(1).max(200).trim(),
  description: z.string().max(2000).optional(),
  priority: z.enum(['low', 'medium', 'high']).default('medium'),
  dueDate: z.string().datetime().optional(),
});

// Validate at the route handler
app.post('/api/tasks', async (req, res) => {
  const result = CreateTaskSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(422).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid input',
        details: result.error.flatten(),
      },
    });
  }
  // result.data is now typed and validated
  const task = await taskService.create(result.data);
  return res.status(201).json(task);
});
```

### File Upload Safety

The app may check size and type before uploading (a picker's result is untrusted too), but the **server must enforce** these limits.

```typescript
// Restrict file types and sizes
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_SIZE = 5 * 1024 * 1024; // 5MB

function validateUpload(file: UploadedFile) {
  if (!ALLOWED_TYPES.includes(file.mimetype)) {
    throw new ValidationError('File type not allowed');
  }
  if (file.size > MAX_SIZE) {
    throw new ValidationError('File too large (max 5MB)');
  }
  // Don't trust the file extension — check magic bytes if critical
}
```

### Destructive Operations on Derived Paths

A delete, move, or overwrite is only as safe as the value that names its target. Reading that value from the kernel, a job payload, or a sibling service proves where it *arrived from*, not who *wrote* it — another process's command line is as attacker-controlled as a form field. A shape check ("absolute path, at least one directory deep") proves well-formedness and gets mistaken for authorization; that is how a cleanup routine deletes the root instead of the leaf.

Before a destructive call, require all three: the resolved target sits under an **allowlisted root** (compare after resolving symlinks, never on the raw string); it is at least one level **below** that root, so a root is never itself the target; and it carries **evidence that it is yours**, read *before* the operation and before any teardown that removes it — otherwise "absent" and "not mine" are indistinguishable. On refusal, log the rejected target and stop: a cleanup that falls back to a broader default path is the failure this guards against. Worked example in `../../references/security-checklist.md`.

Two limits, because the check reads stronger than it is. A marker inside the tree is self-attestation — anything that can write there can write the marker — so the expected owner has to come from authenticated state, and the marker needs integrity protection (restrictive ownership, or a MAC) before it counts as authorization. And resolving a path and then operating on the *name* is a check/use race wherever an untrusted process can swap an ancestor: on a shared volume, hold the target by descriptor and use no-follow, beneath-the-root operations, or make sure the hierarchy cannot change for the duration.

## Triaging Dependency Audit Results

Audits report known advisories; they do not prove a package is trustworthy or that vulnerable code is reachable. For a Flutter app, check pub.dev's security advisories for your dependencies, run `dart pub outdated` to see what is behind, and run your SDK's audit command if it provides one. For the backend, run its package manager's native audit. Use this decision tree:

```
An audit or advisory reports a vulnerability
├── Severity: critical or high
│   ├── Is the vulnerable code reachable in runtime, build, test, or deployment paths?
│   │   ├── YES --> Fix immediately (update, patch, or replace the dependency)
│   │   └── NO (confirmed unused across those paths) --> Fix soon, but not a blocker
│   └── Is a fix available?
│       ├── YES --> Update to the patched version
│       └── NO --> Check for workarounds, consider replacing the dependency, or add to allowlist with a review date
├── Severity: moderate
│   ├── Reachable in production? --> Fix in the next release cycle
│   └── Dev-only? --> Fix when convenient, track in backlog
└── Severity: low
    └── Track and fix during regular dependency updates
```

**Key questions:**
- Is the vulnerable function actually called in your code path?
- Is the dependency a runtime dependency or dev-only (`dev_dependencies` never ship in the app)?
- Is the vulnerability exploitable given your deployment context (e.g., a server-side vulnerability in a client-only app, or an Android-only bug in an iOS build)?

When you defer a fix, document the reason and set a review date.

### Supply-Chain Hygiene

A pub package runs inside your app with the app's permissions and can bring native code and manifest entries with it. Apply this order:

1. **Commit `pubspec.lock` for apps** and install from it in CI (`flutter pub get --enforce-lockfile`; check that your SDK supports the flag). Review lockfile diffs like code.
2. **Vet each new dependency before adding it:** publisher (prefer verified publishers), maintenance activity, release age, popularity and pub points, open issues, license, and its transitive graph. Watch for typosquats and near-duplicate names.
3. **Read what a plugin adds.** Pub does not run install scripts, but a plugin's Gradle and CocoaPods build files execute at build time, and its manifest changes merge into yours. Review new native code, requested permissions, and bundled binaries. Be wary of `git:` and `path:` dependencies, and pin them to a commit.
4. **Third-party SDKs** (analytics, ads, payments, crash reporting) collect data and run with your permissions. Treat adding one as a security and privacy decision (see Ask First), and keep store privacy declarations in sync with what each SDK does.
5. **Backend and tooling repositories** follow their own package manager: use the matrix in `../../references/security-checklist.md`, keep one authoritative lockfile per installation boundary, and block dependency install scripts unless explicitly approved.

Audits only find known advisories; they do not catch a newly malicious or typosquatted package. Therefore:

- **Never apply forced upgrades blindly.** Preview the changes, read changelogs, and test each resulting upgrade; a major-version bump can change behavior and permissions.
- **Review new dependencies, lockfile diffs, and platform build-file changes together** — ownership, maintenance, release age, transitive graph, and lookalike names (OWASP **M2**, **A06**, **LLM03**).

## Rate Limiting

Enforce limits on the server. A client-side throttle only improves behavior for honest users; the app should also back off exponentially on `429` and `5xx` responses.

```typescript
import rateLimit from 'express-rate-limit';

// General API rate limit
app.use('/api/', rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,                   // 100 requests per window
  standardHeaders: true,
  legacyHeaders: false,
}));

// Stricter limit for auth endpoints
app.use('/api/auth/', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,  // 10 attempts per 15 minutes
}));
```

**Count in a shared store once there is more than one process.** `express-rate-limit` keeps its counters in process memory by default. Behind a load balancer each instance holds its own count, so the effective limit is `max × instances`; on serverless or edge runtimes a fresh invocation starts from zero, so the auth limit above may never fire. Pass a shared `store` (Redis via `rate-limit-redis`), or use an HTTP-based limiter that works where a long-lived TCP connection does not (for example `@upstash/ratelimit`):

```typescript
import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';

const authLimiter = new Ratelimit({
  redis: Redis.fromEnv(),                       // UPSTASH_REDIS_REST_URL + _TOKEN
  limiter: Ratelimit.slidingWindow(10, '15 m'), // 10 attempts per 15 minutes, across all instances
});
const { success } = await authLimiter.limit(`login:${req.ip}`);
if (!success) return res.status(429).end();
```

## Secrets Management

```
Backend:
  .env files:
    ├── .env.example  → Committed (template with placeholder values)
    ├── .env          → NOT committed (contains real secrets)
    └── .env.local    → NOT committed (local overrides)

Flutter app (.gitignore must include):
  .env
  .env.local
  .env.*.local
  *.pem
  *.key
  *.jks
  *.keystore
  key.properties
  *.p8
  # Build-time config files that hold non-public values, e.g. a --dart-define-from-file JSON
```

`google-services.json` and `GoogleService-Info.plist` hold identifiers rather than secrets, but restrict the underlying API keys in the provider's console. Anything passed with `--dart-define` or `--dart-define-from-file` ends up in the binary: use it for environment selection and public identifiers, never for real secrets.

**Always check before committing:**
```bash
# Check for accidentally staged secrets
git diff --cached | grep -i "password\|secret\|api_key\|token\|BEGIN .* PRIVATE KEY"
```

**If a secret is ever committed, rotate it.** Deleting the line or rewriting history is not enough — assume it's compromised the moment it reaches a remote. Revoke and reissue the key first, then purge it from history. If a key was shipped inside a released app, rotate it and treat every installed copy as exposed.

## Data Privacy & Compliance

Securing data is "can an attacker read it?" Privacy is "should *we* even hold it, and for how long?" — a separate question that hardening doesn't answer. The cheapest data to protect, breach, and comply over is the data you never collected. Treat personal data as a liability to minimize, not an asset to hoard.

**Know what you hold.** You can't protect or honor a deletion request for data you can't find. Classify fields as you add them:

| Class | Examples | Handling |
|---|---|---|
| **Non-personal** | Aggregates, anonymized counts | Normal handling |
| **Personal (PII)** | Name, email, IP, device/user IDs | Minimize, access-control, include in export/delete |
| **Sensitive** | Health, finance, location, biometrics, gov IDs, anything about minors | Extra basis to collect, stricter access, often encryption + audit logging |

**Operating rules:**
- **Minimize and set a purpose.** Collect a field only against a stated use. "It might be useful later" is not a purpose — it's latent breach scope. Don't log PII into telemetry (the `observability-and-instrumentation` skill makes the same point from the ops side).
- **Set retention up front, then actually delete.** Every personal-data store needs a TTL and a working deletion path — including backups, caches, search indexes, and analytics copies. Data with no expiry is a breach scheduled for later.
- **Support the data-subject rights your jurisdiction requires** (GDPR/CCPA and kin): export, correct, and delete on request. These are engineering features — design the schema so a user's data is *findable* and *erasable*, not smeared irreversibly across systems.
- **Get consent before collection or third-party sharing**, and make it auditable. Sending PII to an analytics/ad/LLM vendor is "sharing" — the user's choice gates it, and the vendor needs a data-processing agreement.
- **Localize defaults, don't hardcode one region's law.** Data-residency and rules differ by user location; make the policy a configurable boundary, not an assumption.

**Mobile specifics:**
- **Request permissions at the moment of use, with a rationale, and request the minimum.** Handle denial and "don't ask again" gracefully; the feature degrades, the app does not break. Remove permissions you no longer use, including ones a plugin adds.
- **Keep store declarations truthful.** The App Store privacy labels and privacy manifest, and the Play Data safety form, must match what your code and every bundled SDK actually collect. Review them whenever you add or update an SDK.
- **Tracking needs consent on iOS** (App Tracking Transparency) and applies to identifiers you share with third parties.
- **Both stores require an in-app path to delete an account** and its data. Design it end to end (server data, backups, analytics copies) rather than hiding a flag.
- **Device identifiers, location, contacts, photos, and health data** are sensitive: collect with a stated purpose, keep coarse where possible, and don't send them to analytics.

When data crosses a trust boundary, validate it as untrusted (see Input Validation above); when a privacy incident exposes personal data, the breach-notification clock is part of the postmortem — follow the `debugging-and-error-recovery` skill.

## Securing AI / LLM Features

If your app calls an LLM — chatbots, summarizers, agents, RAG — it inherits a new attack surface. Map it to the [OWASP Top 10 for LLM Applications (2025)](https://genai.owasp.org/llm-top-10/):

- **Treat all model output as untrusted input (LLM05: Improper Output Handling).** Never pass LLM output straight into `eval`, SQL, a shell, a WebView as HTML, or a file path. Validate and encode it exactly as you would raw user input.
- **Assume prompts can be hijacked (LLM01: Prompt Injection).** Untrusted text in the context window — a user message, a fetched web page, a PDF — can carry instructions. The system prompt is not a security boundary; enforce permissions in code, not in the prompt.
- **Never ship an LLM API key in the app.** Route model calls through your backend, which holds the key, authenticates the user, and rate-limits usage (LLM10). A key in the binary is a key on the internet.
- **Keep secrets and other users' data out of prompts (LLM02 / LLM07).** Anything in the context can be echoed back. Don't put API keys, cross-tenant data, or the full system prompt where the model can repeat it.
- **Constrain tool and agent permissions (LLM06: Excessive Agency).** Scope tools to the minimum, require confirmation for destructive or irreversible actions, and validate every tool argument.
- **Bound consumption (LLM10: Unbounded Consumption).** Cap tokens, request rate, and loop/recursion depth so a crafted input can't run up cost or hang the system.
- **Isolate retrieval data (LLM08: Vector and Embedding Weaknesses).** In RAG, treat the vector store as a trust boundary: partition embeddings per tenant so one user can't retrieve another's data, and validate documents before indexing so poisoned content can't steer answers.

```typescript
// BAD: trusting model output as a command or as markup
const sql = await llm.generate(`Write SQL for: ${userQuestion}`);
await db.query(sql);                                   // arbitrary query execution
webView.loadHtmlString(await llm.reply(userMessage));   // script injection, via the model

// GOOD: model output is data — parse defensively, then validate, then encode
let intent;
try {
  intent = CommandSchema.parse(JSON.parse(await llm.replyJson(userMessage)));
} catch {
  throw new ValidationError('unexpected model output'); // JSON.parse or schema failed
}
await runAllowlistedAction(intent.action, intent.params);
showText(await llm.reply(userMessage));               // render as plain text, not markup
```

## Security Review Checklist

```markdown
### Authentication
- [ ] Tokens are in platform secure storage; access tokens are short-lived, refresh tokens rotate and can be revoked
- [ ] OAuth uses the system browser with PKCE and no client secret in the app
- [ ] Biometrics are a convenience gate; sensitive actions are verified server-side
- [ ] Logout wipes secure storage, caches, and local databases
- [ ] Login has server-side rate limiting; password reset tokens expire
- [ ] Passwords are hashed server-side (bcrypt/scrypt/argon2) and never stored on the device

### Authorization
- [ ] Every endpoint checks user permissions on the server
- [ ] Users can only access their own resources
- [ ] Admin actions require admin role verification
- [ ] Client-side route guards and hidden buttons are treated as UX only

### Input
- [ ] Deep links, push payloads, platform channel messages, and WebView messages are validated
- [ ] Sensitive actions are never executed directly from a deep link
- [ ] API responses are parsed into typed models and malformed data is handled
- [ ] All server input validated at the boundary; SQL (server and local) is parameterized
- [ ] Server-side URL fetches are allowlisted (no SSRF to internal services)
- [ ] Delete/move/overwrite targets built from data are checked against an allowlisted root, a minimum depth, and ownership evidence read before the operation

### Data
- [ ] No secrets in code, version control, or the app binary
- [ ] Sensitive fields excluded from API responses
- [ ] No sensitive data in `SharedPreferences`, plain files, logs, or the clipboard
- [ ] Backups exclude sensitive data; sensitive screens are protected in the app switcher
- [ ] Personal data is classified, collected against a stated purpose, and minimized
- [ ] Personal data has a retention limit and a working deletion path (incl. backups/indexes); in-app account deletion works
- [ ] Sharing with third parties has consent; store privacy declarations match SDK behavior

### Communication
- [ ] HTTPS only; no cleartext exceptions or `NSAllowsArbitraryLoads` in release
- [ ] No `badCertificateCallback` that accepts everything
- [ ] Certificate pinning decision recorded; if pinned, backup pin and rotation plan exist

### Build and Release
- [ ] Release built with `--obfuscate --split-debug-info`; symbols kept out of the artifact
- [ ] Merged Android manifest reviewed: not debuggable, `allowBackup` deliberate, explicit `exported`, minimal permissions
- [ ] `Info.plist` and privacy manifest reviewed
- [ ] No `flutter_driver` extension, dev menus, or debug logging in release
- [ ] Signing keys and keystores are not in the repository

### Infrastructure
- [ ] Rate limiting on the server, backed by a shared store when more than one instance serves traffic
- [ ] Backend-as-a-service rules locked down by default
- [ ] Error messages don't expose internals

### Supply Chain
- [ ] `pubspec.lock` committed; CI installs from it
- [ ] Advisories triaged by reachability and fix risk
- [ ] New dependencies and SDKs reviewed (publisher, maintenance, transitive graph, native code, permissions)

### AI / LLM (if used)
- [ ] Model output treated as untrusted (no eval/SQL/HTML-in-WebView/shell)
- [ ] LLM API keys live on the backend, not in the app
- [ ] Secrets and other users' data kept out of prompts
- [ ] Tool/agent permissions scoped; destructive actions require confirmation
```
## See Also

For detailed security checklists and pre-commit verification steps, see `../../references/security-checklist.md`.

To inspect a running build, intercept traffic on a test device, and drive the app safely, see `flutter-devtools-and-device-testing`. To keep tokens and PII out of logs, see `observability-and-instrumentation`.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "This is an internal tool, security doesn't matter" | Internal tools get compromised. Attackers target the weakest link. |
| "We'll add security later" | Security retrofitting is 10x harder than building it in. Add it now. |
| "No one would try to exploit this" | Automated scanners will find it. Security by obscurity is not security. |
| "The framework handles security" | Frameworks provide tools, not guarantees. You still need to use them correctly. |
| "Nobody will decompile a mobile app" | Extracting an APK or IPA and reading its strings takes minutes. Assume attackers have your binary. |
| "Obfuscation hides the key" | Obfuscation renames symbols; strings and behavior remain. A secret in the app is a public secret. |
| "The app sandbox makes local storage safe" | The sandbox does not stop a thief with a rooted device, a forensic tool, or a cloud backup. Use secure storage. |
| "`SharedPreferences` is fine for a token" | It is plain text on disk and in backups. Use Keychain/Keystore-backed storage. |
| "Root detection stops attackers" | It runs on a device the attacker controls and can be bypassed. Use it as a server-evaluated signal only. |
| "The biometric check passed, so it's the user" | It returns a boolean on a device the attacker may control. Verify sensitive actions on the server. |
| "Deep links are just navigation" | Any app or web page can fire one. Validate parameters, and never act on a link without user confirmation. |
| "We'll turn off cert validation just for the proxy" | It ships. Use debug-only trust anchors, never a blanket bypass. |
| "Pinning solves network security" | It is defense in depth with real operational risk. Without a rotation plan it will lock users out. |
| "It's just a prototype" | Prototypes become production. Security habits from day one. |
| "Threat modeling is overkill here" | Five minutes of "how would I attack this?" prevents the design flaws no control can patch later. |
| "It's just LLM output, it's only text" | That "text" can be a SQL statement, a script tag, or a shell command. Treat it like any untrusted input. |
| "The audit passed, so the dependency is safe" | Audits match known advisories. They do not detect a newly malicious package or make unreviewed install scripts safe to execute. |
| "Collect it now, we might need it later" | Data you don't hold can't be breached, subpoenaed, or mis-deleted. "Might need it" is breach scope, not a purpose. |
| "We'll handle deletion requests manually" | Manual erasure misses backups, caches, and analytics copies. If the schema can't find a user's data, you can't honor the request — design for it. |
| "Compliance is legal's problem, not ours" | Export, deletion, retention, and consent are schema and code. Legal can't bolt them on after you've smeared PII across ten systems. |

## Red Flags

- User input passed directly to database queries, shell commands, or HTML rendering
- A delete, move, or overwrite whose target comes from a payload, a config value, or another process's command line, guarded only by a shape check on the path
- Secrets in source code or commit history
- API endpoints without authentication or authorization checks
- Tokens, PII, or secrets in `SharedPreferences`, plain files, logs, or the clipboard
- Real API keys or LLM keys in the app, in `--dart-define`, or in source
- `badCertificateCallback` returning `true`, cleartext traffic allowed in release, or `NSAllowsArbitraryLoads`
- Deep links or push payloads that trigger actions without validation and user confirmation
- WebViews with JavaScript enabled loading untrusted content
- Authorization decisions made only in the app (hidden buttons, route guards)
- Root detection or biometrics treated as the security boundary
- Release builds without obfuscation, or with debuggable, exported-by-default, or over-broad permission manifests
- The `flutter_driver` extension or dev menus reachable in a release build
- No rate limiting on authentication endpoints, or an in-memory limiter in front of more than one instance
- Stack traces or internal errors exposed to users
- Dependencies with known critical vulnerabilities, an uncommitted `pubspec.lock`, non-reproducible installs, or plugins and SDKs added without reviewing their native code and permissions
- Server fetches user-supplied URLs without an allowlist (SSRF)
- LLM/model output passed into a query, the DOM, a shell, or `eval`
- Secrets, PII, or the full system prompt placed inside an LLM context window
- Personal data collected with no stated purpose, retention limit, or deletion path
- PII sent to analytics/ad/LLM vendors with no consent or data-processing agreement
- "Delete my account" that only flips a flag while the personal data lingers in stores and backups
- Store privacy declarations that no longer match what the app and its SDKs collect

## Verification

After implementing security-relevant code:

- [ ] No unmitigated reachable critical/high advisories; `pubspec.lock` is committed and CI installs from it
- [ ] No secrets in source code, git history, or the release binary
- [ ] All external input (API responses, deep links, push payloads, channel messages) validated at system boundaries
- [ ] Destructive filesystem operations resolve symlinks, then verify allowlisted root, minimum depth, and ownership before running
- [ ] Authorization checked on the server for every protected endpoint
- [ ] Tokens live in secure storage; nothing sensitive is in `SharedPreferences`, logs, or backups
- [ ] Traffic is HTTPS only; verified with an intercepting proxy on a test device (pinning behaves as decided)
- [ ] The release build is obfuscated, and its merged manifest and `Info.plist` were reviewed
- [ ] Error responses don't expose internal details
- [ ] Rate limiting active on auth endpoints, backed by a shared store when more than one instance serves traffic
- [ ] Server-side URL fetches validated against an allowlist (no SSRF)
- [ ] LLM/model output validated and encoded before use, and no LLM key in the app (if AI features present)
- [ ] Personal data is classified, minimized to a stated purpose, and has a retention limit
- [ ] Deletion and export requests work end-to-end (including backups, caches, and analytics copies)
