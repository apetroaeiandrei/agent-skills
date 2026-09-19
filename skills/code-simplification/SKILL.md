---
name: code-simplification
description: Simplifies code for clarity. Use when refactoring code for clarity without changing behavior. Use when code works but is harder to read, maintain, or extend than it should be. Use when reviewing code that has accumulated unnecessary complexity.
---

# Code Simplification

> Inspired by the [Claude Code Simplifier plugin](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-simplifier/agents/code-simplifier.md). Adapted here as a model-agnostic, process-driven skill for any AI coding agent.

## Overview

Simplify code by reducing complexity while preserving exact behavior. The goal is not fewer lines — it's code that is easier to read, understand, modify, and debug. Every simplification must pass a simple test: "Would a new team member understand this faster than the original?"

## When to Use

- After a feature is working and tests pass, but the implementation feels heavier than it needs to be
- During code review when readability or complexity issues are flagged
- When you encounter deeply nested logic, long functions, or unclear names
- When refactoring code written under time pressure
- When consolidating related logic scattered across files
- After merging changes that introduced duplication or inconsistency

**When NOT to use:**

- Code is already clean and readable — don't simplify for the sake of it
- You don't understand what the code does yet — comprehend before you simplify
- The code is performance-critical and the "simpler" version would be measurably slower
- You're about to rewrite the module entirely — simplifying throwaway code wastes effort

## The Five Principles

### 1. Preserve Behavior Exactly

Don't change what the code does — only how it expresses it. All inputs, outputs, side effects, error behavior, and edge cases must remain identical. If you're not sure a simplification preserves behavior, don't make it.

```
ASK BEFORE EVERY CHANGE:
→ Does this produce the same output for every input?
→ Does this maintain the same error behavior?
→ Does this preserve the same side effects and ordering?
→ Do all existing tests still pass without modification?
```

In a Flutter app, "behavior" includes more than inputs and outputs. A simplification must also preserve:

- **Rebuild behavior and state preservation:** removing a `Key`, changing a widget's position in the tree, or dropping `const` can change what rebuilds and whether state survives
- **Accessibility:** removing a `Semantics`, `MergeSemantics`, or `tooltip` changes what screen readers announce
- **Lifecycle:** `dispose`, `mounted` checks, and subscription cancellation are behavior, not clutter
- **Platform behavior:** branches on `Platform.isIOS` or `kIsWeb`, and adaptive widgets, exist for a reason
- **Visual output:** a golden test that changes means you changed the UI

### 2. Follow Project Conventions

Simplification means making code more consistent with the codebase, not imposing external preferences. Before simplifying:

```
1. Read CLAUDE.md / project conventions
2. Study how neighboring code handles similar patterns
3. Match the project's style for:
   - Import ordering and module system
   - Function declaration style
   - Naming conventions
   - Error handling patterns
   - Type annotation depth
   - Flutter idioms: state management (Cubit), freezed models, widget classes, theme tokens
   - The lints in analysis_options.yaml
```

Simplification that breaks project consistency is not simplification — it's churn.

### 3. Prefer Clarity Over Cleverness

Explicit code is better than compact code when the compact version requires a mental pause to parse.

```dart
// UNCLEAR: Dense ternary chain
final label = isNew ? 'New' : isUpdated ? 'Updated' : isArchived ? 'Archived' : 'Active';

// CLEAR: Readable mapping
String statusLabel(Item item) {
  if (item.isNew) return 'New';
  if (item.isUpdated) return 'Updated';
  if (item.isArchived) return 'Archived';
  return 'Active';
}
```

```dart
// UNCLEAR: Chained folds with inline logic
final countById = items.fold<Map<String, int>>(
  {},
  (acc, item) => {...acc, item.id: (acc[item.id] ?? 0) + 1},
);

// CLEAR: Named intermediate step
final countById = <String, int>{};
for (final item in items) {
  countById[item.id] = (countById[item.id] ?? 0) + 1;
}
```

### 4. Maintain Balance

Simplification has a failure mode: over-simplification. Watch for these traps:

- **Inlining too aggressively** — removing a helper that gave a concept a name makes the call site harder to read
- **Combining unrelated logic** — two simple functions merged into one complex function is not simpler
- **Removing "unnecessary" abstraction** — some abstractions exist for extensibility or testability, not complexity
- **Optimizing for line count** — fewer lines is not the goal; easier comprehension is

### 5. Scope to What Changed

Default to simplifying recently modified code. Avoid drive-by refactors of unrelated code unless explicitly asked to broaden scope. Unscoped simplification creates noise in diffs and risks unintended regressions.

## The Simplification Process

### Step 1: Understand Before Touching (Chesterton's Fence)

Before changing or removing anything, understand why it exists. This is Chesterton's Fence: if you see a fence across a road and don't understand why it's there, don't tear it down. First understand the reason, then decide if the reason still applies.

```
BEFORE SIMPLIFYING, ANSWER:
- What is this code's responsibility?
- What calls it? What does it call?
- What are the edge cases and error paths?
- Are there tests that define the expected behavior?
- Why might it have been written this way? (Performance? Platform constraint? Historical reason?)
- If it's Flutter code: is it a lifecycle guard (`mounted`, `dispose`), a `Key`, a `RepaintBoundary`, a platform branch, or a workaround for an SDK or plugin bug? These look redundant and often aren't
- Check git blame: what was the original context for this code?
```

If you can't answer these, you're not ready to simplify. Read more context first.

### Step 2: Identify Simplification Opportunities

Scan for these patterns — each one is a concrete signal, not a vague smell:

**Structural complexity:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Deep nesting (3+ levels) | Hard to follow control flow | Extract conditions into guard clauses or helper functions |
| Long functions (50+ lines) | Multiple responsibilities | Split into focused functions with descriptive names |
| Nested ternaries | Requires mental stack to parse | Replace with if/else chains, switch, or lookup objects |
| Boolean parameter flags | `doThing(true, false, true)` | Replace with options objects or separate functions |
| Repeated conditionals | Same `if` check in multiple places | Extract to a well-named predicate function |

**Naming and readability:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Generic names | `data`, `result`, `temp`, `val`, `item` | Rename to describe the content: `userProfile`, `validationErrors` |
| Abbreviated names | `usr`, `cfg`, `btn`, `evt` | Use full words unless the abbreviation is universal (`id`, `url`, `api`) |
| Misleading names | Function named `get` that also mutates state | Rename to reflect actual behavior |
| Comments explaining "what" | `// increment counter` above `count++` | Delete the comment — the code is clear enough |
| Comments explaining "why" | `// Retry because the API is flaky under load` | Keep these — they carry intent the code can't express |

**Redundancy:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Duplicated logic | Same 5+ lines in multiple places | Extract to a shared function |
| Dead code | Unreachable branches, unused variables, commented-out blocks | Remove (after confirming it's truly dead) |
| Unnecessary abstractions | Wrapper that adds no value | Inline the wrapper, call the underlying function directly |
| Over-engineered patterns | Factory-for-a-factory, strategy-with-one-strategy | Replace with the simple direct approach |
| Redundant type assertions | Casting to a type that's already inferred | Remove the assertion |

### Step 3: Apply Changes Incrementally

Make one simplification at a time. Run tests after each change (`flutter test`), and let `dart fix --apply` and the analyzer handle purely mechanical, lint-driven cleanups (`prefer_const_constructors`, `unnecessary_this`, `prefer_final_locals`) in their own commit. **Submit refactoring changes separately from feature or bug fix changes.** A PR that refactors and adds a feature is two PRs — split them.

```
FOR EACH SIMPLIFICATION:
1. Make the change
2. Run the test suite
3. If tests pass → commit (or continue to next simplification)
4. If tests fail → revert and reconsider
```

Avoid batching multiple simplifications into a single untested change. If something breaks, you need to know which simplification caused it.

**The Rule of 500:** If a refactoring would touch more than 500 lines, invest in automation (codemods, sed scripts, AST transforms) rather than making the changes by hand. Manual edits at that scale are error-prone and exhausting to review.

### Step 4: Verify the Result

After all simplifications, step back and evaluate the whole:

```
COMPARE BEFORE AND AFTER:
- Is the simplified version genuinely easier to understand?
- Did you introduce any new patterns inconsistent with the codebase?
- Is the diff clean and reviewable?
- Would a teammate approve this change?
```

If the "simplified" version is harder to understand or review, revert. Not every simplification attempt succeeds.

Never simplify generated files (`*.freezed.dart`, `*.g.dart`). Simplify the source classes and regenerate.

## Language-Specific Guidance

### Dart

```dart
// SIMPLIFY: Redundant async wrapper
// Before
Future<User> getUser(String id) async {
  return await userService.findById(id);
}
// After (only outside a try/catch: inside one, `return await` changes which errors you catch)
Future<User> getUser(String id) => userService.findById(id);

// SIMPLIFY: Verbose null fallback
// Before
String displayName;
if (user.nickname != null) {
  displayName = user.nickname!;
} else {
  displayName = user.fullName;
}
// After (note: `??` falls back only on null, so an empty-string nickname still wins,
// exactly as in the original. Don't "simplify" to a check that treats '' as missing.)
final displayName = user.nickname ?? user.fullName;

// SIMPLIFY: Manual list building
// Before
final activeUsers = <User>[];
for (final user in users) {
  if (user.isActive) {
    activeUsers.add(user);
  }
}
// After
final activeUsers = users.where((user) => user.isActive).toList();

// SIMPLIFY: Conditional list building (collection if / spread)
// Before
final children = <Widget>[header];
if (showBanner) {
  children.add(banner);
}
children.addAll(items);
// After
final children = [header, if (showBanner) banner, ...items];

// SIMPLIFY: If/else chain over a sealed type or enum (Dart 3 switch expression)
// Before
String label(TaskStatus status) {
  if (status is TaskPending) return 'Pending';
  if (status is TaskCompleted) return 'Done';
  return 'Cancelled';
}
// After (also gives you exhaustiveness checking)
String label(TaskStatus status) => switch (status) {
      TaskPending() => 'Pending',
      TaskCompleted() => 'Done',
      TaskCancelled() => 'Cancelled',
    };

// SIMPLIFY: Redundant boolean return
// Before
bool isValid(String input) {
  if (input.isNotEmpty && input.length < 100) {
    return true;
  }
  return false;
}
// After
bool isValid(String input) => input.isNotEmpty && input.length < 100;
```

### TypeScript / JavaScript (backend)

```typescript
// SIMPLIFY: Unnecessary async wrapper
// Before
async function getUser(id: string): Promise<User> {
  return await userService.findById(id);
}
// After
function getUser(id: string): Promise<User> {
  return userService.findById(id);
}

// SIMPLIFY: Verbose conditional assignment
// Before
let displayName: string;
if (user.nickname) {
  displayName = user.nickname;
} else {
  displayName = user.fullName;
}
// After
const displayName = user.nickname || user.fullName;

// SIMPLIFY: Manual array building
// Before
const activeUsers: User[] = [];
for (const user of users) {
  if (user.isActive) {
    activeUsers.push(user);
  }
}
// After
const activeUsers = users.filter((user) => user.isActive);

// SIMPLIFY: Redundant boolean return
// Before
function isValid(input: string): boolean {
  if (input.length > 0 && input.length < 100) {
    return true;
  }
  return false;
}
// After
function isValid(input: string): boolean {
  return input.length > 0 && input.length < 100;
}
```

### Python

```python
# SIMPLIFY: Verbose dictionary building
# Before
result = {}
for item in items:
    result[item.id] = item.name
# After
result = {item.id: item.name for item in items}

# SIMPLIFY: Nested conditionals with early return
# Before
def process(data):
    if data is not None:
        if data.is_valid():
            if data.has_permission():
                return do_work(data)
            else:
                raise PermissionError("No permission")
        else:
            raise ValueError("Invalid data")
    else:
        raise TypeError("Data is None")
# After
def process(data):
    if data is None:
        raise TypeError("Data is None")
    if not data.is_valid():
        raise ValueError("Invalid data")
    if not data.has_permission():
        raise PermissionError("No permission")
    return do_work(data)
```

### Flutter Widgets

```dart
// SIMPLIFY: Container used only for padding or size
// Before
Container(padding: const EdgeInsets.all(16), child: child)
Container(width: 8, height: 8)
// After
Padding(padding: const EdgeInsets.all(16), child: child)
const SizedBox(width: 8, height: 8)

// SIMPLIFY: _buildX() helper methods → widget classes
// Before
Widget _buildHeader() => Padding(padding: const EdgeInsets.all(16), child: Text(title));
// After (can be const, rebuilds independently, is testable on its own)
class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(title));
}

// SIMPLIFY: Verbose conditional rendering
// Before
Widget build(BuildContext context) {
  if (user.isAdmin) {
    return const Badge(label: Text('Admin'), color: Colors.red);
  } else {
    return const Badge(label: Text('User'), color: Colors.grey);
  }
}
// After
Widget build(BuildContext context) => Badge(
      label: Text(user.isAdmin ? 'Admin' : 'User'),
      color: user.isAdmin ? Colors.red : Colors.grey,
    );
```

**Judgment calls: flag them, don't auto-refactor.** Each of these changes structure, not just expression:

- **Prop drilling through intermediate widgets:** consider whether a `BlocProvider`, an inherited widget, or composition solves it better.
- **`StatefulWidget` + `setState` doing feature logic:** moving it into a Cubit is a redesign, not a simplification.
- **Removing a `Key`, `Semantics`, `RepaintBoundary`, or `const`:** it may look redundant and change behavior. Verify with tests and a device before removing.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's working, no need to touch it" | Working code that's hard to read will be hard to fix when it breaks. Simplifying now saves time on every future change. |
| "Fewer lines is always simpler" | A 1-line nested ternary is not simpler than a 5-line if/else. Simplicity is about comprehension speed, not line count. |
| "I'll just quickly simplify this unrelated code too" | Unscoped simplification creates noisy diffs and risks regressions in code you didn't intend to change. Stay focused. |
| "The types make it self-documenting" | Types document structure, not intent. A well-named function explains *why* better than a type signature explains *what*. |
| "This abstraction might be useful later" | Don't preserve speculative abstractions. If it's not used now, it's complexity without value. Remove it and re-add when needed. |
| "The original author must have had a reason" | Maybe. Check git blame — apply Chesterton's Fence. But accumulated complexity often has no reason; it's just the residue of iteration under pressure. |
| "Removing that `mounted` check / `Key` / `Semantics` makes it cleaner" | Those are behavior: lifecycle safety, state preservation, accessibility. Confirm what they guard (Chesterton's Fence) before removing them. |
| "I'll refactor while adding this feature" | Separate refactoring from feature work. Mixed changes are harder to review, revert, and understand in history. |

## Red Flags

- Simplification that requires modifying tests to pass (you likely changed behavior)
- "Simplified" code that is longer and harder to follow than the original
- Renaming things to match your preferences rather than project conventions
- Removing error handling because "it makes the code cleaner"
- Simplifying code you don't fully understand
- Batching many simplifications into one large, hard-to-review commit
- Refactoring code outside the scope of the current task without being asked
- Removing `mounted` checks, `dispose` calls, `Key`s, `Semantics`, or platform branches because they "look unnecessary"
- Hand-editing generated files (`*.freezed.dart`, `*.g.dart`) instead of the source classes
- Treating a state-management redesign as a "simplification"
- A golden test diff that was updated to make a "simplification" pass

## Verification

After completing a simplification pass:

- [ ] All existing tests pass without modification, and goldens are unchanged
- [ ] `flutter analyze` and `dart format` are clean
- [ ] Build succeeds with no new warnings
- [ ] Linter/formatter passes (no style regressions)
- [ ] Each simplification is a reviewable, incremental change
- [ ] The diff is clean — no unrelated changes mixed in
- [ ] Simplified code follows project conventions (checked against CLAUDE.md or equivalent)
- [ ] No error handling was removed or weakened
- [ ] No dead code was left behind (unused imports, unreachable branches)
- [ ] A teammate or review agent would approve the change as a net improvement
