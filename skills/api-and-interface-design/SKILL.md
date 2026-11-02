---
name: api-and-interface-design
description: Guides stable API and interface design. Use when designing APIs, module boundaries, or any public interface. Use when creating REST or GraphQL endpoints, defining the contract between a Flutter app and its backend, defining Dart interfaces between layers, or keeping old app versions working as an API evolves.
---

# API and Interface Design

## Overview

Design stable, well-documented interfaces that are hard to misuse. Good interfaces make the right thing easy and the wrong thing hard. This applies to REST APIs, GraphQL schemas, module boundaries, widget constructors, repository interfaces, and any surface where one piece of code talks to another.

For a mobile app, the app-to-backend contract is the hardest one to change: you cannot force users to update, so every app version ever released keeps calling your API until it ages out. Design as if the oldest supported client is calling today.

## When to Use

- Designing new API endpoints
- Defining module boundaries or contracts between teams
- Creating widget constructor APIs, repository interfaces, or package boundaries
- Defining the contract between a mobile app and its backend
- Establishing database schema that informs API shape
- Changing existing public interfaces

## Core Principles

### Hyrum's Law

> With a sufficient number of users of an API, all observable behaviors of your system will be depended on by somebody, regardless of what you promise in the contract.

This means: every public behavior — including undocumented quirks, error message text, timing, and ordering — becomes a de facto contract once users depend on it. Design implications:

- **Be intentional about what you expose.** Every observable behavior is a potential commitment.
- **Don't leak implementation details.** If users can observe it, they will depend on it.
- **Plan for deprecation at design time.** See `deprecation-and-migration` for how to safely remove things users depend on.
- **Tests are not enough.** Even with perfect contract tests, Hyrum's Law means "safe" changes can break real users who depend on undocumented behavior.

### The One-Version Rule

Avoid forcing consumers to choose between multiple versions of the same dependency or API. Diamond dependency problems arise when different consumers need different versions of the same thing. Design for a world where only one version exists at a time — extend rather than fork.

### 1. Contract First

Define the interface before implementing it. The contract is the spec — implementation follows.

```typescript
// Define the contract first
interface TaskAPI {
  // Creates a task and returns the created task with server-generated fields
  createTask(input: CreateTaskInput): Promise<Task>;

  // Returns paginated tasks matching filters
  listTasks(params: ListTasksParams): Promise<PaginatedResult<Task>>;

  // Returns a single task or throws NotFoundError
  getTask(id: string): Promise<Task>;

  // Partial update — only provided fields change
  updateTask(id: string, input: UpdateTaskInput): Promise<Task>;

  // Idempotent delete — succeeds even if already deleted
  deleteTask(id: string): Promise<void>;
}
```

On the client, the same principle applies to the layer boundary. Define the repository contract in Dart before implementing it, so Cubits depend on an abstraction and tests can fake it:

```dart
abstract interface class TaskRepository {
  /// Creates a task and returns it with server-generated fields.
  Future<Task> createTask(CreateTaskInput input);

  /// Returns one page of tasks. Throws [NetworkException] on connectivity failure.
  Future<Page<Task>> listTasks({String? cursor, int limit = 20});

  /// Returns a single task or throws [NotFoundException].
  Future<Task> getTask(TaskId id);

  /// Idempotent delete: succeeds even if already deleted.
  Future<void> deleteTask(TaskId id);
}
```

### 2. Consistent Error Semantics

Pick one error strategy and use it everywhere:

```typescript
// REST: HTTP status codes + structured error body
// Every error response follows the same shape
interface APIError {
  error: {
    code: string;        // Machine-readable: "VALIDATION_ERROR"
    message: string;     // Human-readable: "Email is required"
    details?: unknown;   // Additional context when helpful
  };
}

// Status code mapping
// 400 → Client sent invalid data
// 401 → Not authenticated
// 403 → Authenticated but not authorized
// 404 → Resource not found
// 409 → Conflict (duplicate, version mismatch)
// 422 → Validation failed (semantically invalid)
// 500 → Server error (never expose internal details)
```

**Don't mix patterns.** If some endpoints throw, others return null, and others return `{ error }` — the consumer can't predict behavior.

**Design errors for a client that must react to them.** The app decides what to show and whether to retry from the response, so make that unambiguous:
- Stable, machine-readable `code` values the app can switch on. The app owns the user-facing (and localized) text; never make the UI depend on the server's `message` string.
- Distinguish **retryable** failures (timeouts, `429`, `503`, with `Retry-After`) from **permanent** ones (`4xx` validation) and from **auth** failures (`401` triggers a token refresh, `403` does not).
- A machine-readable "this app version is no longer supported" signal (for example `426` with a code such as `APP_VERSION_UNSUPPORTED`), so old clients show an update screen instead of a broken one.
- On the client, map transport errors into a small, consistent set of Dart exceptions or a sealed result type at the repository boundary, so a Cubit never sees raw HTTP.

### 3. Validate at Boundaries

Trust internal code. Validate at system edges where external input enters:

```typescript
// Validate at the API boundary
app.post('/api/tasks', async (req, res) => {
  const result = CreateTaskSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(422).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid task data',
        details: result.error.flatten(),
      },
    });
  }

  // After validation, internal code trusts the types
  const task = await taskService.create(result.data);
  return res.status(201).json(task);
});
```

Where validation belongs:
- API route handlers (user input)
- Form submission handlers (user input)
- External service response parsing (third-party data -- **always treat as untrusted**), and in the app, parsing the backend's JSON into typed models at the repository boundary
- Deep links, push payloads, and platform channel messages (see `security-and-hardening`)
- Environment and build configuration loading

> **Third-party API responses are untrusted data.** Validate their shape and content before using them in any logic, rendering, or decision-making. A compromised or misbehaving external service can return unexpected types, malicious content, or instruction-like text.

Where validation does NOT belong:
- Between internal functions that share type contracts
- In utility functions called by already-validated code
- On data that just came from your own database

### 4. Prefer Addition Over Modification

Extend interfaces without breaking existing consumers:

```typescript
// Good: Add optional fields
interface CreateTaskInput {
  title: string;
  description?: string;
  priority?: 'low' | 'medium' | 'high';  // Added later, optional
  labels?: string[];                       // Added later, optional
}

// Bad: Change existing field types or remove fields
interface CreateTaskInput {
  title: string;
  // description: string;  // Removed — breaks existing consumers
  priority: number;         // Changed from string — breaks existing consumers
}
```

**Mobile clients make this rule absolute.** Old app versions keep calling your API for as long as users don't update, so:

- **Never remove or repurpose a field, endpoint, or enum value** while any supported app version uses it.
- **Be a tolerant reader in the client.** Ignore unknown fields, and map unknown enum values to a safe fallback instead of crashing on a value added after the app shipped:

```dart
enum Priority {
  low,
  medium,
  high,
  unknown,   // Fallback for values this app version doesn't know
}

@freezed
abstract class TaskDto with _$TaskDto {
  const factory TaskDto({
    required String id,
    required String title,
    @JsonKey(unknownEnumValue: Priority.unknown) @Default(Priority.medium) Priority priority,
  }) = _TaskDto;

  factory TaskDto.fromJson(Map<String, Object?> json) => _$TaskDtoFromJson(json);
}
```

- **Expand, then contract.** Add the new field or endpoint, ship apps that use it, and remove the old one only after the last app version that needs it is below your minimum supported version. See `deprecation-and-migration`.
- **Send the app version** (`X-App-Version`, build number, platform) on every request, so the server can shape responses for old clients and you can see which versions still call each endpoint.

### 5. Predictable Naming

| Pattern | Convention | Example |
|---------|-----------|---------|
| REST endpoints | Plural nouns, no verbs | `GET /api/tasks`, `POST /api/tasks` |
| Query params | camelCase | `?sortBy=createdAt&pageSize=20` |
| Response fields | camelCase | `{ createdAt, updatedAt, taskId }` |
| Boolean fields | is/has/can prefix | `isComplete`, `hasAttachments` |
| Enum values | UPPER_SNAKE | `"IN_PROGRESS"`, `"COMPLETED"` |

### 6. Honouring an Idempotency Key

Accepting an `Idempotency-Key` is the contract. Honouring it is the implementation, and it is where the money is lost — a key the server accepts but handles carelessly is worse than no key at all, because the client now believes retrying is safe.

**Derive the key from the intent, not the attempt.** The key must be stable across retries of one intent and different across distinct intents:

```typescript
crypto.randomUUID()                    // ✗ new key per attempt — every retry is a new charge
`${userId}:${amount}`                  // ✗ two legitimate $50 charges collapse into one
`${orderId}:${Date.now()}`             // ✗ a timestamp is randomUUID() wearing a hat

req.headers['idempotency-key']         // ✓ client generates once, reuses on retry
`charge:v1:${orderId}`                 // ✓ derived from an immutable identifier
```

The key comes from the client or the initiating event — never from the layer doing the retrying.

**On mobile, retries are the norm:** connections drop, requests time out, and the app can be killed mid-request. Generate the key once per user intent (when the user taps "Pay"), **persist it with the pending action**, and reuse it on every retry, including after an app restart. Generating a fresh key per attempt is how a flaky train tunnel becomes a double charge.

**Claim atomically. A check followed by an act is a race:**

```typescript
// ✗ TOCTOU: two concurrent retries both read "not seen", both charge
if (!(await db.exists(key))) {
  await chargeCard(amount);
  await db.insert(key);
}

// ✓ let the unique constraint pick the winner
try {
  await db.insert({ key, state: 'in_progress', requestHash });
} catch (e) {
  if (isUniqueViolation(e)) return replayOrReject(key);
  throw;
}
const result = await chargeCard(amount);
await db.update({ key, state: 'succeeded', response: result });
```

The unique constraint *is* the mechanism. A store that cannot enforce uniqueness in one operation cannot back this.

**Guard the payload.** Same key with a different body is a client bug, and must fail loudly rather than serving the first response to a second request:

```typescript
if (existing.requestHash !== hash(req.body)) {
  return res.status(422).json({ error: 'idempotency key reused with a different payload' });
}
```

**Decide what an in-flight duplicate gets.** The first request is still running when the second arrives — the common case under retry storms:

| Strategy | Response | Use when |
|---|---|---|
| Reject | `409 Conflict` | Client can retry later; simplest and safest |
| Wait | Block for the result, bounded | Caller needs it synchronously |
| Return pending | `202` + status URL | Long-running effects |

Never let the second caller through because the first "seems stuck". A stalled attempt whose fate is unknown is exactly when duplicating costs most.

**Every call has three outcomes, not two: success, failure, and _unknown_.** A timeout tells you nothing about whether the effect applied. Record the intent *before* calling out, so a crash between the call and the response leaves evidence something must resolve later — rather than a silently retried charge.

**Set retention from the longest retry chain**, not from disk cost. Keys must outlive every path that can re-deliver the same intent, including a dead-letter queue replayed a week later and any provider dispute window. A 24-hour key TTL behind a 7-day DLQ is a duplicate waiting to happen.

## REST API Patterns

### Resource Design

```
GET    /api/tasks              → List tasks (with query params for filtering)
POST   /api/tasks              → Create a task
GET    /api/tasks/:id          → Get a single task
PATCH  /api/tasks/:id          → Update a task (partial)
DELETE /api/tasks/:id          → Delete a task

GET    /api/tasks/:id/comments → List comments for a task (sub-resource)
POST   /api/tasks/:id/comments → Add a comment to a task
```

### Pagination

Paginate list endpoints:

```typescript
// Request
GET /api/tasks?page=1&pageSize=20&sortBy=createdAt&sortOrder=desc

// Response
{
  "data": [...],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "totalItems": 142,
    "totalPages": 8
  }
}
```

**Prefer cursor pagination for lists an app scrolls.** Offset pagination skips or repeats items when the list changes between requests, and infinite scroll on a flaky connection makes that common:

```
GET /api/tasks?limit=20&cursor=eyJpZCI6IjEyMyJ9

{
  "data": [...],
  "nextCursor": "eyJpZCI6IjE0MyJ9"   // null when there are no more pages
}
```

### Filtering

Use query parameters for filters:

```
GET /api/tasks?status=in_progress&assignee=user123&createdAfter=2025-01-01
```

### Partial Updates (PATCH)

Accept partial objects — only update what's provided:

```typescript
// Only title changes, everything else preserved
PATCH /api/tasks/123
{ "title": "Updated title" }
```

## Designing for Mobile Clients

Everything above applies. These are the additional pressures a phone puts on an API:

| Pressure | Design response |
|---|---|
| Users update on their own schedule | Additive-only changes, tolerant readers, a minimum supported version, `X-App-Version` on every request |
| Flaky, slow, metered connections | Cursor pagination, small payloads, compression, conditional requests (`ETag` / `If-None-Match` → `304`), field selection where it pays off |
| Chatty endpoints cost battery and latency | Batch or aggregate endpoints for screens that need several resources; avoid waterfalls of dependent calls |
| Retries and duplicate submissions | Idempotency keys generated once per intent and persisted; safe retry semantics documented per endpoint |
| Offline and sync | Server-assigned versions or timestamps for conflict detection; a defined conflict policy (last-write-wins, reject with `409`, or merge) |
| Background and push | Small, versioned push payloads carrying IDs, not full data; the app fetches details when opened |
| Auth on a lost device | Short-lived access tokens, rotating refresh tokens, server-side revocation |

Decide the conflict policy and the retry semantics **in the contract**, not in each client's error handling.

## Dart Interface Patterns

### Use Sealed Classes (Freezed Unions) for Variants

```dart
// Good: Each variant is explicit and the compiler checks exhaustiveness
@freezed
sealed class TaskStatus with _$TaskStatus {
  const factory TaskStatus.pending() = TaskPending;
  const factory TaskStatus.inProgress({required String assignee, required DateTime startedAt}) = TaskInProgress;
  const factory TaskStatus.completed({required DateTime completedAt, required String completedBy}) = TaskCompleted;
  const factory TaskStatus.cancelled({required String reason, required DateTime cancelledAt}) = TaskCancelled;
}

String statusLabel(TaskStatus status) => switch (status) {
      TaskPending() => 'Pending',
      TaskInProgress(:final assignee) => 'In progress ($assignee)',
      TaskCompleted(:final completedAt) => 'Done on $completedAt',
      TaskCancelled(:final reason) => 'Cancelled: $reason',
    };
```

Adding a variant later makes every non-exhaustive `switch` a compile error, which is exactly what you want inside the app. Across the network, remember the tolerant-reader rule: a status the app doesn't know about must not crash it.

### Separate Transport Models from Domain Models

Keep the shape the server sends (a DTO with `fromJson`) separate from the model the app uses. Map one to the other at the repository boundary, so a backend change touches one mapper instead of every widget:

```dart
// Repository: the only place that knows the wire format
Future<Task> getTask(TaskId id) async {
  final json = await _client.getJson('/api/tasks/${id.value}');
  return TaskDto.fromJson(json).toDomain();
}
```

### Use Extension Types for IDs

```dart
extension type const TaskId(String value) {}
extension type const UserId(String value) {}

// Prevents accidentally passing a UserId where a TaskId is expected, with no runtime cost
Future<Task> getTask(TaskId id);
```

### Input/Output Separation

```dart
// Input: what the caller provides
@freezed
abstract class CreateTaskInput with _$CreateTaskInput {
  const factory CreateTaskInput({required String title, String? description}) = _CreateTaskInput;
}

// Output: what the system returns (includes server-generated fields)
@freezed
abstract class Task with _$Task {
  const factory Task({
    required TaskId id,
    required String title,
    String? description,
    required DateTime createdAt,
    required DateTime updatedAt,
    required UserId createdBy,
  }) = _Task;
}
```

Use freezed for these, and run `dart run build_runner build -d` after changing them (see `flutter-ui-engineering`).

## TypeScript Interface Patterns (Server)

The same principles apply to a TypeScript backend:

### Use Discriminated Unions for Variants

```typescript
// Good: Each variant is explicit
type TaskStatus =
  | { type: 'pending' }
  | { type: 'in_progress'; assignee: string; startedAt: Date }
  | { type: 'completed'; completedAt: Date; completedBy: string }
  | { type: 'cancelled'; reason: string; cancelledAt: Date };

// Consumer gets type narrowing
function getStatusLabel(status: TaskStatus): string {
  switch (status.type) {
    case 'pending': return 'Pending';
    case 'in_progress': return `In progress (${status.assignee})`;
    case 'completed': return `Done on ${status.completedAt}`;
    case 'cancelled': return `Cancelled: ${status.reason}`;
  }
}
```

### Input/Output Separation

```typescript
// Input: what the caller provides
interface CreateTaskInput {
  title: string;
  description?: string;
}

// Output: what the system returns (includes server-generated fields)
interface Task {
  id: string;
  title: string;
  description: string | null;
  createdAt: Date;
  updatedAt: Date;
  createdBy: string;
}
```

### Use Branded Types for IDs

```typescript
type TaskId = string & { readonly __brand: 'TaskId' };
type UserId = string & { readonly __brand: 'UserId' };

// Prevents accidentally passing a UserId where a TaskId is expected
function getTask(id: TaskId): Promise<Task> { ... }
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "We'll document the API later" | The types ARE the documentation. Define them first. |
| "We don't need pagination for now" | You will the moment someone has 100+ items. Add it from the start. |
| "PATCH is complicated, let's just use PUT" | PUT requires the full object every time. PATCH is what clients actually want. |
| "We'll version the API when we need to" | Breaking changes without versioning break consumers. Design for extension from the start. |
| "Nobody uses that undocumented behavior" | Hyrum's Law: if it's observable, somebody depends on it. Treat every public behavior as a commitment. |
| "Users will just update the app" | Many won't, for weeks or months, and you can't force them. Every released version is a consumer of your API. |
| "We can just maintain two versions" | Multiple versions multiply maintenance cost and create diamond dependency problems. Prefer the One-Version Rule. |
| "Internal APIs don't need contracts" | Internal consumers are still consumers. Contracts prevent coupling and enable parallel work. |
| "Accepting the Idempotency-Key header is enough" | The header is the contract; storing the key against the result is the implementation. A key you accept but don't honour tells the client retrying is safe when it isn't. |
| "Our queue guarantees exactly-once delivery" | No queue does across a consumer crash — the broker's ack and your side effect are not in one transaction. Design for at-least-once with idempotent processing. |
| "Duplicate requests are rare" | They're *correlated*. Retries spike exactly when a dependency is degraded — the moment duplicates are most likely and most expensive. |

## Red Flags

- Endpoints that return different shapes depending on conditions
- Inconsistent error formats across endpoints
- Validation scattered throughout internal code instead of at boundaries
- Breaking changes to existing fields (type changes, removals)
- List endpoints without pagination
- Verbs in REST URLs (`/api/createTask`, `/api/getUsers`)
- Removing or repurposing a field, endpoint, or enum value that a supported app version still uses
- A client that crashes on an unknown enum value or extra field
- Offset pagination on a list an app scrolls, or chatty endpoints that force waterfalls of calls per screen
- Idempotency keys regenerated per retry attempt, or not persisted across an app restart
- No way to tell which app versions call which endpoints, or to signal an unsupported version
- Widgets or Cubits depending on raw JSON or HTTP details instead of a repository contract
- Third-party API responses used without validation or sanitization
- A `SELECT` for an idempotency key followed by an `INSERT` — that's a race, not a guard
- An idempotency key derived from a UUID, timestamp, or anything else regenerated per attempt
- The same key accepted with a different request body, silently returning the first response
- A key retention window shorter than the longest path that can re-deliver the request

## Verification

After designing an API:

- [ ] Every endpoint has typed input and output schemas
- [ ] Error responses follow a single consistent format
- [ ] Validation happens at system boundaries only
- [ ] List endpoints support pagination
- [ ] New fields are additive and optional (backward compatible), and no field, endpoint, or enum value a supported app version uses was removed
- [ ] The app parses responses as a tolerant reader: unknown fields are ignored and unknown enum values map to a fallback
- [ ] Errors carry stable machine-readable codes; retryable, permanent, and auth failures are distinguishable; an unsupported-version signal exists
- [ ] Lists an app scrolls use cursor pagination
- [ ] The app sends its version on every request, and the server can identify which versions still call each endpoint
- [ ] Naming follows consistent conventions across all endpoints
- [ ] API documentation or types are committed alongside the implementation
- [ ] State-changing endpoints either honour an idempotency key or are documented as unsafe to retry
- [ ] The key is claimed in one atomic operation, guarded by a unique constraint
- [ ] A reused key with a different payload fails loudly rather than replaying the wrong response
- [ ] The in-flight-duplicate response is a deliberate choice (409, wait, or 202) rather than whatever falls out
- [ ] Key retention outlives the longest retry path, including dead-letter replay
- [ ] The app generates the key once per intent and persists it across retries and restarts
