---
name: test-driven-development
description: Drives development with tests using the red-green-refactor loop, in Flutter and Dart projects (unit, Cubit, widget, golden, and integration tests). Use when implementing any logic, fixing any bug, or changing any behavior. Use when you need to prove that code works, when a bug report arrives, or when you're about to modify existing functionality.
---

# Test-Driven Development

## Overview

Write a failing test before writing the code that makes it pass. For bug fixes, reproduce the bug with a test before attempting a fix. Tests are proof — "seems right" is not done. A codebase with good tests is an AI agent's superpower; a codebase without tests is a liability.

## When to Use

- Implementing any new logic or behavior
- Fixing any bug (the Prove-It Pattern)
- Modifying existing functionality
- Adding edge case handling
- Any change that could break existing behavior

**When NOT to use:** Pure configuration changes, documentation updates, or static content changes that have no behavioral impact.

**Related:** For UI changes, combine TDD with runtime verification on a device using Flutter DevTools, the Dart MCP server, and mobile-mcp — see Device and Runtime Verification below.

## Discover the Stack First

The TDD cycle is universal; the commands are not. Before writing the first test, discover how *this* repository tests, and use its commands for every RED, GREEN, and verification step:

- **Flutter or pure Dart?** `pubspec.yaml` with a `flutter:` SDK dependency means `flutter test`; a pure Dart package or CLI means `dart test`. Monorepos may use `melos`, and a version manager (`.fvmrc`) means `fvm flutter test`.
- **Checked-in wrappers** — prefer a repo script, `make test`, or the melos scripts over globally installed tools
- **Code generation** — freezed, `json_serializable`, and mock generators need `dart run build_runner build -d` before tests compile against them
- **Test framework and configuration** — `dart_test.yaml` tags, `analysis_options.yaml`, and how a single focused test differs from the full suite
- **Existing conventions** — where tests live (`test/` mirrors `lib/`), how files are named (`*_test.dart`), what patterns neighboring tests follow
- **Documented commands** — README, CONTRIBUTING, and CI workflows show the commands that actually gate merges

The usual Flutter commands:

```bash
flutter test                                              # full suite (unit, Cubit, widget, golden)
flutter test test/features/tasks/cubit/tasks_cubit_test.dart   # one file
flutter test --plain-name 'sets completedAt'              # one test by name
flutter test --coverage                                   # writes coverage/lcov.info
flutter test --update-goldens                             # regenerate golden images (review the diff!)
flutter test integration_test                             # integration tests; needs a device or emulator
dart run build_runner build -d                            # regenerate freezed / json code first when models changed
```

Run the repository's focused-test command during the loop and its full-suite command before completion. Never assume a default like `npm test` — a Gradle, Cargo, or pytest project has its own equivalent, and a Flutter project has its own.

The examples below use Dart and Flutter; the workflow is identical in any language once you've discovered the project's own tooling.

## The TDD Cycle

```
    RED                GREEN              REFACTOR
 Write a test    Write minimal code    Clean up the
 that fails  ──→  to make it pass  ──→  implementation  ──→  (repeat)
      │                  │                    │
      ▼                  ▼                    ▼
   Test FAILS        Test PASSES         Tests still PASS
```

### Step 1: RED — Write a Failing Test

Write the test first. It must fail. A test that passes immediately proves nothing.

```dart
// RED: This test fails because createTask doesn't exist yet
void main() {
  group('TaskService', () {
    test('creates a task with title and default status', () async {
      final service = TaskService(repository: InMemoryTaskRepository());

      final task = await service.createTask(title: 'Buy groceries');

      expect(task.id, isNotEmpty);
      expect(task.title, 'Buy groceries');
      expect(task.status, TaskStatus.pending);
      expect(task.createdAt, isA<DateTime>());
    });
  });
}
```

**It must fail for the right reason.** A compile error from stale generated code (a freezed class you changed but did not regenerate) is a false RED. Run `dart run build_runner build -d` first, so the failure you see is the missing behavior, not missing generation.

### Step 2: GREEN — Make It Pass

Write the minimum code to make the test pass. Don't over-engineer:

```dart
// GREEN: Minimal implementation
Future<Task> createTask({required String title}) async {
  final task = Task(
    id: _generateId(),
    title: title,
    status: TaskStatus.pending,
    createdAt: _now(),
  );
  await _repository.save(task);
  return task;
}
```

### Step 3: REFACTOR — Clean Up

With tests green, improve the code without changing behavior:

- Extract shared logic
- Improve naming
- Remove duplication
- Optimize if necessary

Run tests after every refactor step to confirm nothing broke.

## The Prove-It Pattern (Bug Fixes)

When a bug is reported, **do not start by trying to fix it.** Start by writing a test that reproduces it.

```
Bug report arrives
       │
       ▼
  Write a test that demonstrates the bug
       │
       ▼
  Test FAILS (confirming the bug exists)
       │
       ▼
  Implement the fix
       │
       ▼
  Test PASSES (proving the fix works)
       │
       ▼
  Run full test suite (no regressions)
```

**Example:**

```dart
// Bug: "Completing a task doesn't update the completedAt timestamp"

// Step 1: Write the reproduction test (it should FAIL)
test('sets completedAt when task is completed', () async {
  final service = TaskService(repository: InMemoryTaskRepository());
  final task = await service.createTask(title: 'Test');

  final completed = await service.completeTask(task.id);

  expect(completed.status, TaskStatus.completed);
  expect(completed.completedAt, isNotNull);   // This fails → bug confirmed
});

// Step 2: Fix the bug
Future<Task> completeTask(String id) async {
  final task = await _repository.get(id);
  final completed = task.copyWith(
    status: TaskStatus.completed,
    completedAt: _now(),   // This was missing
  );
  await _repository.save(completed);
  return completed;
}

// Step 3: Test passes → bug fixed, regression guarded
```

For UI bugs, reproduce the bug in a **widget test** first (see Widget Tests below); only fall back to a device when the bug depends on real rendering, platform behavior, or performance.

## The Test Pyramid

Invest testing effort according to the pyramid — most tests should be small and fast, with progressively fewer tests at higher levels:

```
          ╱╲
         ╱  ╲         Integration / E2E Tests (~5-10%)
        ╱    ╲        Full flows on a real device or emulator
       ╱──────╲
      ╱        ╲      Widget + Golden Tests (~25-30%)
     ╱          ╲     Screens and widgets in the headless test environment
    ╱────────────╲
   ╱              ╲   Unit + Cubit Tests (~60-70%)
  ╱                ╲  Pure logic, repositories, Cubits: milliseconds each
 ╱──────────────────╲
```

The percentages are a rough guide, not a quota. **Widget tests are the workhorse of Flutter UI testing:** they run without a device, in the same Dart VM as unit tests, and are far faster and less flaky than integration tests.

**The Beyonce Rule:** If you liked it, you should have put a test on it. Infrastructure changes, refactoring, and migrations are not responsible for catching your bugs — your tests are. If a change breaks your code and you didn't have a test for it, that's on you.

### Test Sizes (Resource Model)

Beyond the pyramid levels, classify tests by what resources they consume:

| Size | Constraints | Speed | Example |
|------|------------|-------|---------|
| **Small** | Single process, no device, no real network or platform channels | Milliseconds to seconds | Unit tests, `bloc_test` Cubit tests, widget tests |
| **Medium** | Golden files, local fakes, a local test server | Seconds | Golden tests, repository tests against a fake HTTP client or in-memory database |
| **Large** | Real device or emulator, real plugins, possibly external services | Minutes | `integration_test` flows, native permission and notification flows, performance timelines |

Small tests should make up the vast majority of your suite. They're fast, reliable, and easy to debug when they fail.

### Decision Guide

```
Is it pure logic with no side effects?
  → Unit test (small)

Is it a Cubit or Bloc reacting to inputs?
  → bloc_test: assert on the emitted states (small)

Does a screen or widget render the right thing for each state, and respond to taps?
  → Widget test (small)

Does it need to look exactly right (theme, dark mode, large text)?
  → Golden test (medium), used sparingly

Does it cross a boundary (HTTP, database, file system)?
  → Repository/integration test against a fake or local dependency (medium)

Is it a critical user flow that must work end-to-end, or does it touch real plugins and native UI?
  → integration_test on a device (large); limit these to critical paths
```

## Writing Good Tests

### Test State, Not Interactions

Assert on the *outcome* of an operation, not on which methods were called internally. Tests that verify method call sequences break when you refactor, even if the behavior is unchanged. For Cubits, that means asserting on the **emitted states**, not on `verify(() => repository.fetchTasks())`.

```dart
// Good: Tests what the function does (state-based)
test('returns tasks sorted by creation date, newest first', () async {
  final tasks = await service.listTasks(sortBy: SortBy.createdAt, descending: true);

  expect(tasks.first.createdAt.isAfter(tasks.last.createdAt), isTrue);
});

// Bad: Tests how the function works internally (interaction-based)
test('calls repository.query with ORDER BY created_at DESC', () async {
  await service.listTasks(sortBy: SortBy.createdAt, descending: true);

  verify(() => repository.query(orderBy: 'created_at DESC')).called(1);
});
```

### DAMP Over DRY in Tests

In production code, DRY (Don't Repeat Yourself) is usually right. In tests, **DAMP (Descriptive And Meaningful Phrases)** is better. A test should read like a specification — each test should tell a complete story without requiring the reader to trace through shared helpers.

```dart
// DAMP: Each test is self-contained and readable
test('rejects tasks with empty titles', () {
  expect(
    () => createTask(title: '', assignee: 'user-1'),
    throwsA(isA<ValidationError>().having((e) => e.message, 'message', 'Title is required')),
  );
});

test('trims whitespace from titles', () {
  final task = createTask(title: '  Buy groceries  ', assignee: 'user-1');

  expect(task.title, 'Buy groceries');
});

// Over-DRY: Shared setup obscures what each test actually verifies
// (Don't do this just to avoid repeating the input shape)
```

Duplication in tests is acceptable when it makes each test independently understandable.

### Prefer Real Implementations Over Mocks

Use the simplest test double that gets the job done. The more your tests use real code, the more confidence they provide.

```
Preference order (most to least preferred):
1. Real implementation  → Highest confidence, catches real bugs
2. Fake                 → In-memory version of a dependency (e.g., InMemoryTaskRepository)
3. Stub                 → Returns canned data, no behavior (mocktail `when(...).thenReturn`)
4. Mock (interaction)   → Verifies method calls — use sparingly
```

**Use mocks only when:** the real implementation is too slow, non-deterministic, or has side effects you can't control (HTTP APIs, platform plugins such as location or camera, push notifications, the clock). Over-mocking creates tests that pass while production breaks.

Hide plugins and platform APIs behind your own small interface, so unit and widget tests can fake them without touching platform channels.

### Use the Arrange-Act-Assert Pattern

```dart
test('marks overdue tasks when deadline has passed', () {
  // Arrange: Set up the test scenario
  final task = Task(title: 'Test', deadline: DateTime(2025, 1, 1));

  // Act: Perform the action being tested
  final result = checkOverdue(task, now: DateTime(2025, 1, 2));

  // Assert: Verify the outcome
  expect(result.isOverdue, isTrue);
});
```

### One Assertion Per Concept

```dart
// Good: Each test verifies one behavior
test('rejects empty titles', () { /* ... */ });
test('trims whitespace from titles', () { /* ... */ });
test('enforces maximum title length', () { /* ... */ });

// Bad: Everything in one test
test('validates titles correctly', () {
  expect(() => createTask(title: ''), throwsA(isA<ValidationError>()));
  expect(createTask(title: '  hello  ').title, 'hello');
  expect(() => createTask(title: 'a' * 256), throwsA(isA<ValidationError>()));
});
```

### Name Tests Descriptively

```dart
// Good: Reads like a specification
group('TaskService.completeTask', () {
  test('sets status to completed and records timestamp', () { /* ... */ });
  test('throws NotFoundException for non-existent task', () { /* ... */ });
  test('is idempotent: completing an already-completed task is a no-op', () { /* ... */ });
  test('notifies the task assignee', () { /* ... */ });
});

// Bad: Vague names
group('TaskService', () {
  test('works', () { /* ... */ });
  test('handles errors', () { /* ... */ });
  test('test 3', () { /* ... */ });
});
```

## Flutter Testing Toolkit

### Cubit and Bloc Tests

Use `bloc_test` and assert on the sequence of emitted states. With freezed states, equality works out of the box, so `expect` can list the exact states.

```dart
blocTest<TasksCubit, TasksState>(
  'emits loading then loaded when the repository returns tasks',
  setUp: () => when(() => repository.fetchTasks()).thenAnswer((_) async => [task]),
  build: () => TasksCubit(repository),
  act: (cubit) => cubit.load(),
  expect: () => [
    const TasksState.loading(),
    TasksState.loaded(tasks: [task]),
  ],
);

blocTest<TasksCubit, TasksState>(
  'emits failure when the repository throws',
  setUp: () => when(() => repository.fetchTasks()).thenThrow(Exception('offline')),
  build: () => TasksCubit(repository),
  act: (cubit) => cubit.load(),
  expect: () => [const TasksState.loading(), isA<TasksFailure>()],
);
```

Prefer a fake repository over mocks where the logic is non-trivial. Test the rollback path of optimistic updates, and event transformers (debounce, droppable) with `fakeAsync` or `wait:`.

### Widget Tests

A widget test builds a widget in a headless environment and lets you interact with it. Provide the ancestors it needs (`MaterialApp`, theme, localization, a provided Cubit) and find things the way a user or screen reader would: by text, by semantics label, then by key as a last resort.

```dart
class MockTasksCubit extends MockCubit<TasksState> implements TasksCubit {}

void main() {
  late MockTasksCubit cubit;

  setUp(() => cubit = MockTasksCubit());

  Future<void> pumpView(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TasksCubit>.value(value: cubit, child: const TasksView()),
        ),
      );

  testWidgets('shows the empty state when there are no tasks', (tester) async {
    when(() => cubit.state).thenReturn(const TasksState.loaded(tasks: []));

    await pumpView(tester);

    expect(find.text('No tasks yet'), findsOneWidget);
  });

  testWidgets('tapping the checkbox toggles the task', (tester) async {
    when(() => cubit.state).thenReturn(TasksState.loaded(tasks: [task]));
    when(() => cubit.toggle(task.id)).thenAnswer((_) async {});

    await pumpView(tester);
    await tester.tap(find.byType(Checkbox));

    verify(() => cubit.toggle(task.id)).called(1);   // The tap is the behavior under test
  });
}
```

- Cover **every state** a screen can render: loading, failure, empty, loaded.
- `pump()` advances one frame; `pumpAndSettle()` waits for animations to finish and **times out on infinite animations** (spinners, shimmer). Pump specific durations for those.
- Assert accessibility where it matters: `expect(tester, meetsGuideline(androidTapTargetGuideline))`, `labeledTapTargetGuideline`, `textContrastGuideline`, after `final handle = tester.ensureSemantics();`.
- Test with a large text scale and a small surface (`tester.view.physicalSize`) for adaptive layouts.
- Don't test framework widgets themselves (that a `Checkbox` toggles); test your screen's behavior.

### Golden Tests

Golden tests compare a rendered widget against a reference image. Use them to lock in visual design, not as a substitute for behavior tests.

```dart
testWidgets('TaskItem matches the golden in light and dark', (tester) async {
  await tester.pumpWidget(themedApp(const TaskItem(/* ... */)));
  await expectLater(find.byType(TaskItem), matchesGoldenFile('goldens/task_item_light.png'));
});
```

- Generate with `flutter test --update-goldens`, then **review the image diff** before committing. Blindly updating goldens to turn the suite green defeats the test.
- Golden rendering differs by operating system and font. Run goldens on one CI platform, or use a tool built for stable output (for example `alchemist`), and load real fonts.
- Keep goldens few and meaningful: key states, both themes, large text. Tag them (`@Tags(['golden'])`) so they can be run or skipped separately.

### Integration Tests

`integration_test` runs the whole app on a device or emulator. Keep these to critical paths (sign in, core create/complete flow, checkout).

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can create and complete a task', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Title'), 'Buy groceries');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Buy groceries'), findsOneWidget);
  });
}
```

- Run against a fake or local backend so results are deterministic, never a shared staging service.
- Native UI (permission dialogs, notifications, system settings) is outside Flutter's widget tree. Use a tool that can drive native UI, such as `patrol`, for those flows.
- Never use fixed `Future.delayed` waits; wait on finders.
- The same binding records performance timelines: see `performance-optimization` for frame-time budgets.

### Time, Async, and Determinism

- Inject the clock (`DateTime Function() now`, or `package:clock`) instead of calling `DateTime.now()` inside logic you want to test.
- Use `fakeAsync` for timers, debounce, and retries; never sleep in a test.
- Assert on streams with `expectLater(stream, emitsInOrder([...]))`.
- Give each test its own state; don't share mutable objects across tests.

### What Not to Test

Don't test what code generation and the framework already guarantee: freezed's `==`, `copyWith`, `toString`, and generated `fromJson`/`toJson` plumbing. Test the behavior *you* wrote: custom getters and methods on freezed classes, JSON edge cases your `fromJson` handles through converters, and how a Cubit uses the states.

## Test Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Testing implementation details | Tests break when refactoring even if behavior is unchanged | Test inputs and outputs, not internal structure |
| Flaky tests (timing, order-dependent) | Erode trust in the test suite | Use deterministic assertions, fake time, isolate test state |
| Testing framework or generated code | Wastes time testing third-party behavior | Only test YOUR code |
| Golden abuse | Large image sets nobody reviews, blindly updated | Few, meaningful goldens; review every diff |
| `pumpAndSettle` with infinite animations | Hangs until timeout | Pump specific durations, or stub the animation |
| Fixed `Future.delayed` in tests | Slow and still flaky | Wait on finders, streams, or fake time |
| Finding widgets only by type or index | Breaks on layout changes, ignores accessibility | Find by text or semantics label; key as a last resort |
| No test isolation | Tests pass individually but fail together | Each test sets up and tears down its own state |
| Real network or plugins in unit/widget tests | Slow, flaky, environment-dependent | Fake the boundary behind your own interface |
| Mocking everything | Tests pass but production breaks | Prefer real implementations > fakes > stubs > mocks. Mock only at boundaries where real deps are slow or non-deterministic |
| Leaving `skip:` on tests | Dead tests hide real bugs | Fix or delete the test |

## Device and Runtime Verification

Widget tests run in a headless environment. They don't prove real rendering, platform behavior, permissions, or performance. For UI changes, finish the TDD loop by verifying on a device:

```
1. Tests first: reproduce the bug or specify the behavior in a unit, Cubit, or widget test
2. GREEN and REFACTOR as usual
3. VERIFY on a simulator/emulator (and a real device where performance or plugins matter):
   launch, drive the flow, check runtime errors and logs, compare screenshots, hot reload
```

Use the Dart MCP server and mobile-mcp for step 3. Setup, the debugging workflows, and the security boundaries for untrusted app output live in `flutter-devtools-and-device-testing`. Don't duplicate them here.

## When to Use Subagents for Testing

For complex bug fixes, spawn a subagent to write the reproduction test:

```
Main agent: "Spawn a subagent to write a test that reproduces this bug:
[bug description]. The test should fail with the current code."

Subagent: Writes the reproduction test

Main agent: Verifies the test fails, then implements the fix,
then verifies the test passes.
```

This separation ensures the test is written without knowledge of the fix, making it more robust.

## See Also

For Dart and Flutter testing patterns illustrating these principles — `package:test`, `flutter_test`, `mocktail`, `bloc_test`, golden tests, and `integration_test` — see `../../references/testing-patterns.md`. The principles transfer to any ecosystem; the syntax and tools there are Dart/Flutter-specific.

For state and model conventions (Cubit, freezed, and running `build_runner`), see `flutter-ui-engineering`.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll write tests after the code works" | You won't. And tests written after the fact test implementation, not behavior. |
| "This is too simple to test" | Simple code gets complicated. The test documents the expected behavior. |
| "Tests slow me down" | Tests slow you down now. They speed you up every time you change the code later. |
| "I tested it manually" | Manual testing doesn't persist. Tomorrow's change might break it with no way to know. |
| "Widget tests are overkill, I'll check it on the emulator" | Emulator checks don't persist and are slow. A widget test runs in milliseconds and guards the behavior forever. |
| "The golden changed, I'll just update it" | A golden diff is a visual change. Review it. If you didn't intend it, you found a bug. |
| "It compiles and analyzes clean, so it works" | The analyzer checks types, not behavior. Only a test proves behavior. |
| "The code is self-explanatory" | Tests ARE the specification. They document what the code should do, not what it does. |
| "It's just a prototype" | Prototypes become production code. Tests from day one prevent the "test debt" crisis. |
| "Let me run the tests again just to be extra sure" | After a clean test run, repeating the same command adds nothing unless the code has changed since. Run again after subsequent edits, not as reassurance. |

## Red Flags

- Writing code without any corresponding tests
- Reaching for a default test command (`npm test`) without checking what this repository actually uses (`flutter test` vs `dart test`, `fvm`, `melos`)
- Running tests against stale generated code after changing a freezed class
- Tests that pass on the first run (they may not be testing what you think)
- "All tests pass" but no tests were actually run
- Bug fixes without reproduction tests
- Tests that test framework behavior instead of application behavior
- Test names that don't describe the expected behavior
- Skipping tests to make the suite pass, or blindly running `--update-goldens`
- Widget tests for screens with no test of their loading, failure, or empty states
- Running the same test command twice in a row without any intervening code change

## Verification

After completing any implementation:

- [ ] Every new behavior has a corresponding test
- [ ] The full suite passes, run with the repository's own test command (`flutter test`, `dart test`, `melos run test`, `./gradlew test`, `pytest`, ...)
- [ ] `dart run build_runner build -d` was run after any freezed or generated-code change, before the tests
- [ ] Bug fixes include a reproduction test that failed before the fix
- [ ] Test names describe the behavior being verified
- [ ] No tests were skipped or disabled
- [ ] Every screen state (loading, failure, empty, loaded) has a widget test
- [ ] Golden changes were reviewed, not blindly updated
- [ ] Coverage hasn't decreased (if tracked; `flutter test --coverage`)
- [ ] UI changes were also verified on a device (see `flutter-devtools-and-device-testing`)

**Note:** Run each test command after a change that could affect the result. After a clean run, don't repeat the same command unless the code has changed since — re-running on unchanged code adds no confidence.
