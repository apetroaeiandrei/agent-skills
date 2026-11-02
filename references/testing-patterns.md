# Testing Patterns Reference (Flutter/Dart)

Quick reference of Dart and Flutter testing patterns — `package:test`, `flutter_test`, `mocktail`, `bloc_test`, golden tests, and `integration_test` — illustrating the universal principles from the `test-driven-development` skill. The principles (Arrange-Act-Assert, naming, mock discipline, anti-patterns) apply in any ecosystem; the syntax and tooling shown here are Dart/Flutter-specific. In another stack, follow the same principles with the repository's own test framework and commands.

## Table of Contents

- [Test Structure (Arrange-Act-Assert)](#test-structure-arrange-act-assert)
- [Test Naming Conventions](#test-naming-conventions)
- [Common Matchers](#common-matchers)
- [Mocking Patterns](#mocking-patterns)
- [Cubit and Bloc Testing](#cubit-and-bloc-testing)
- [Widget Testing](#widget-testing)
- [Golden Testing](#golden-testing)
- [Repository / HTTP Testing](#repository--http-testing)
- [Integration Testing](#integration-testing)
- [Running Tests](#running-tests)
- [Test Anti-Patterns](#test-anti-patterns)

## Test Structure (Arrange-Act-Assert)

```dart
test('describes expected behavior', () {
  // Arrange: Set up test data and preconditions
  const input = (title: 'Test Task', priority: Priority.high);

  // Act: Perform the action being tested
  final result = createTask(title: input.title, priority: input.priority);

  // Assert: Verify the outcome
  expect(result.title, 'Test Task');
  expect(result.priority, Priority.high);
  expect(result.status, TaskStatus.pending);
});
```

Use `setUp` / `tearDown` for per-test state, never shared mutable globals.

## Test Naming Conventions

```dart
// Pattern: [unit] [expected behavior] [condition]
group('TaskService.createTask', () {
  test('creates a task with default pending status', () {});
  test('throws ValidationError when title is empty', () {});
  test('trims whitespace from title', () {});
  test('generates a unique ID for each task', () {});
});
```

Test files live in `test/`, mirror the `lib/` structure, and end in `_test.dart`.

## Common Matchers

```dart
// Equality
expect(result, expected);                    // equals() by default; deep for lists/maps/freezed
expect(result, same(instance));              // Identity
expect(result, isNot(expected));

// Nullness and booleans
expect(result, isNull);
expect(result, isNotNull);
expect(result, isTrue);
expect(result, isFalse);

// Numbers
expect(result, greaterThan(5));
expect(result, lessThanOrEqualTo(10));
expect(result, closeTo(0.3, 1e-9));          // Floating point

// Strings
expect(result, matches(RegExp(r'^task-\d+$')));
expect(result, contains('substring'));
expect(result, startsWith('Task'));

// Collections
expect(list, contains(item));
expect(list, hasLength(3));
expect(list, isEmpty);
expect(list, containsAll([a, b]));
expect(list, orderedEquals([a, b, c]));
expect(map, containsPair('key', 'value'));

// Types and properties
expect(result, isA<Task>());
expect(error, isA<ValidationError>().having((e) => e.message, 'message', 'Title is required'));

// Errors
expect(() => fn(), throwsA(isA<ValidationError>()));
expect(() => fn(), throwsA(predicate((e) => e is StateError && e.message == 'nope')));

// Async
await expectLater(asyncFn(), completion(equals(value)));
await expectLater(asyncFn(), throwsA(isA<Exception>()));
await expectLater(stream, emitsInOrder([1, 2, emitsDone]));
```

## Mocking Patterns

### Fakes First

A fake is a small working implementation. Prefer it to a mock when the logic is non-trivial:

```dart
class InMemoryTaskRepository implements TaskRepository {
  final _tasks = <String, Task>{};

  @override
  Future<void> save(Task task) async => _tasks[task.id] = task;

  @override
  Future<Task> get(String id) async =>
      _tasks[id] ?? (throw NotFoundException(id));

  @override
  Future<List<Task>> fetchTasks() async => _tasks.values.toList();
}
```

### Mocks and Stubs (mocktail)

```dart
class MockTaskRepository extends Mock implements TaskRepository {}

final repository = MockTaskRepository();

// Stubbing
when(() => repository.fetchTasks()).thenAnswer((_) async => [task]);
when(() => repository.get(any())).thenThrow(NotFoundException('missing'));

// Custom argument types need a fallback registered once
setUpAll(() => registerFallbackValue(FakeTask()));   // class FakeTask extends Fake implements Task {}
when(() => repository.save(any())).thenAnswer((_) async {});

// Interaction checks: use sparingly
verify(() => repository.save(any())).called(1);
verifyNever(() => repository.delete(any()));
```

### Mock at Boundaries Only

```
Mock or fake these:            Don't mock these:
├── HTTP requests              ├── Internal utility functions
├── Databases and file system  ├── Business logic
├── Platform plugins           ├── Data transformations
│   (location, camera, push)   ├── Validation functions
├── Secure storage             └── Pure functions
└── Time (inject the clock)
```

Wrap plugins in your own small interface (`LocationService`, `TokenStore`) so tests fake your interface and never touch a platform channel.

### Time

```dart
// Inject the clock rather than calling DateTime.now() in logic
class TaskService {
  TaskService({required this.repository, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final TaskRepository repository;
  final DateTime Function() _now;
}

// fakeAsync for timers, debounce, and retry logic
test('debounces search input', () {
  fakeAsync((async) {
    final cubit = SearchCubit(repository);
    cubit.onQueryChanged('fl');
    cubit.onQueryChanged('flu');
    async.elapse(const Duration(milliseconds: 300));
    verify(() => repository.search('flu')).called(1);
  });
});
```

## Cubit and Bloc Testing

```dart
blocTest<TasksCubit, TasksState>(
  'emits loading then loaded when the repository returns tasks',
  setUp: () => when(() => repository.fetchTasks()).thenAnswer((_) async => [task]),
  build: () => TasksCubit(repository),
  act: (cubit) => cubit.load(),
  expect: () => [
    const TasksState.loading(),
    TasksState.loaded(tasks: [task]),     // freezed value equality makes this exact
  ],
  verify: (_) => verify(() => repository.fetchTasks()).called(1),
);

blocTest<TasksCubit, TasksState>(
  'rolls back an optimistic toggle when the request fails',
  seed: () => TasksState.loaded(tasks: [task]),
  setUp: () => when(() => repository.toggle(task.id)).thenThrow(Exception('offline')),
  build: () => TasksCubit(repository),
  act: (cubit) => cubit.toggle(task.id),
  expect: () => [
    TasksState.loaded(tasks: [task.copyWith(done: true)]),   // optimistic
    TasksState.loaded(tasks: [task]),                        // rolled back
  ],
);
```

- Assert on the **emitted states**, not on internal calls.
- Use `seed` to start from a given state, `skip` to ignore earlier emissions, and `wait` for debounced or delayed emissions.
- Freezed states and models get equality for free. Don't test `==` or `copyWith`; test how your Cubit uses them.
- If a test suddenly fails to compile after changing a freezed class, run `dart run build_runner build -d`.

## Widget Testing

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

  testWidgets('shows the loaded tasks', (tester) async {
    when(() => cubit.state).thenReturn(TasksState.loaded(tasks: [task]));

    await pumpView(tester);

    expect(find.text(task.title), findsOneWidget);
  });

  testWidgets('shows an error with a retry action', (tester) async {
    when(() => cubit.state).thenReturn(const TasksState.failure('offline'));
    when(() => cubit.load()).thenAnswer((_) async {});

    await pumpView(tester);
    await tester.tap(find.text('Retry'));

    verify(() => cubit.load()).called(1);
  });

  testWidgets('meets tap target and label guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    when(() => cubit.state).thenReturn(TasksState.loaded(tasks: [task]));

    await pumpView(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### Finding Widgets

```dart
find.text('Create task');                       // By visible text
find.bySemanticsLabel('Delete Buy groceries');  // By accessibility label (preferred for icon buttons)
find.byType(TaskItem);                          // By type (when text/semantics are unavailable)
find.byKey(const ValueKey('task-list'));        // By key: last resort
find.descendant(of: find.byType(TaskItem), matching: find.byIcon(Icons.delete_outline));
```

### Interacting and Pumping

```dart
await tester.tap(finder);
await tester.enterText(find.byType(TextField), 'Buy groceries');
await tester.drag(find.byType(ListView), const Offset(0, -300));
await tester.pump();                                    // One frame
await tester.pump(const Duration(milliseconds: 300));   // Advance time (use with infinite animations)
await tester.pumpAndSettle();                           // Until animations finish; times out on infinite ones
```

### Adaptive Layout and Text Scale

```dart
testWidgets('lays out without overflow at 200% text on a small phone', (tester) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
      child: child!,
    ),
    home: const TasksView(),
  ));

  expect(tester.takeException(), isNull);   // Overflow errors surface here
});
```

## Golden Testing

```dart
testWidgets('TaskItem golden', (tester) async {
  await tester.pumpWidget(MaterialApp(theme: lightTheme, home: Scaffold(body: TaskItem(task: task))));

  await expectLater(find.byType(TaskItem), matchesGoldenFile('goldens/task_item_light.png'));
});
```

```bash
flutter test --update-goldens test/widgets/task_item_test.dart   # Generate or refresh; then REVIEW the images
```

- Fonts and rendering differ between operating systems. Generate and verify goldens on one platform in CI, or use a tool built for stable output (for example `alchemist`).
- Cover the states that matter: light and dark, large text, and error or empty variants. Tag goldens (`@Tags(['golden'])`) to run them separately.

## Repository / HTTP Testing

Test repositories against a fake HTTP client, not the network:

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

test('parses tasks from the API response', () async {
  final client = MockClient((request) async {
    expect(request.url.path, '/api/tasks');
    expect(request.headers['Authorization'], 'Bearer test-token');
    return http.Response('[{"id":"1","title":"Test Task","done":false}]', 200);
  });
  final repository = HttpTaskRepository(client: client, token: 'test-token');

  final tasks = await repository.fetchTasks();

  expect(tasks, [const Task(id: '1', title: 'Test Task')]);
});

test('maps a 401 to an UnauthorizedException', () async {
  final client = MockClient((_) async => http.Response('', 401));
  final repository = HttpTaskRepository(client: client, token: 'expired');

  await expectLater(repository.fetchTasks(), throwsA(isA<UnauthorizedException>()));
});

test('surfaces malformed payloads as a parsing error, not a crash', () async {
  final client = MockClient((_) async => http.Response('{"unexpected": true}', 200));
  final repository = HttpTaskRepository(client: client, token: 't');

  await expectLater(repository.fetchTasks(), throwsA(isA<ParsingException>()));
});
```

For the backend an app talks to, follow that backend's own framework and the same principles.

## Integration Testing

```dart
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can create and complete a task', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Authenticate
    await tester.enterText(find.bySemanticsLabel('Email'), 'test@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'testpass123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    // Create a task
    await tester.tap(find.bySemanticsLabel('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Title'), 'Buy groceries');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Buy groceries'), findsOneWidget);

    // Complete the task
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });
}
```

```bash
flutter test integration_test                      # Runs on the connected device or emulator
flutter test integration_test -d <device-id>       # Pick a device explicitly
```

- Use a fake or local backend for determinism. Reset app state between tests.
- Native dialogs and system UI (permissions, notifications, settings) are outside the widget tree: use a tool that can drive native UI, such as `patrol`, for those flows.
- For frame timelines, record with the same binding (`traceAction` / `watchPerformance`) and run in profile mode. See `performance-optimization`.

## Running Tests

```bash
dart run build_runner build -d          # Regenerate freezed / json code first if models changed
flutter analyze                         # Static analysis
flutter test                            # Everything except integration_test/
flutter test path/to/file_test.dart     # One file
flutter test --plain-name 'name'        # One test
flutter test --coverage                 # coverage/lcov.info
flutter test --tags golden              # Only tagged tests (see dart_test.yaml)
dart test                               # Pure Dart packages
```

## Test Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|---|---|---|
| Testing implementation details | Breaks on refactor | Test inputs/outputs and emitted states |
| Golden everything | No one reviews image diffs | A few meaningful goldens, reviewed |
| Shared mutable state | Tests pollute each other | `setUp`/`tearDown` per test |
| Testing third-party or generated code | Wastes time, not your bug | Fake the boundary; skip freezed's `==`/`copyWith` |
| `pumpAndSettle` on infinite animations | Hangs until timeout | Pump explicit durations |
| `Future.delayed` waits | Slow and flaky | Wait on finders, streams, or fake time |
| Finding by index or type only | Breaks on layout change, hides a11y gaps | Text or semantics label; key as a last resort |
| Real network or platform channels in unit/widget tests | Slow and non-deterministic | Fake your own interface |
| Skipping tests to pass CI | Hides real bugs | Fix or delete the test |
| Using `skip:` permanently | Dead code | Remove or fix it |
| Overly broad assertions | Doesn't catch regressions | Be specific |
| Unawaited async in tests | Swallowed errors, false passes | Always `await` (and `expectLater` for async matchers) |
