# Accessibility Checklist

Quick reference for accessible Flutter apps: WCAG 2.1 AA (2.2 where required) applied to mobile, plus the Android and iOS platform guidelines. Use alongside the `flutter-ui-engineering` skill.

## Table of Contents

- [Essential Checks](#essential-checks)
- [Common Flutter Patterns](#common-flutter-patterns)
- [Testing Tools](#testing-tools)
- [Quick Reference: Announcements and Live Regions](#quick-reference-announcements-and-live-regions)
- [Common Anti-Patterns](#common-anti-patterns)

## Essential Checks

### Screen Readers (TalkBack and VoiceOver)
- [ ] All meaningful images have a `semanticLabel`; decorative images use `excludeFromSemantics: true`
- [ ] All interactive elements have an accessible label (`tooltip` on `IconButton`, `labelText` on inputs, or `Semantics(label:)`)
- [ ] Custom tappable widgets expose a role and action (`Semantics(button: true, onTap: ...)`), or better, use `InkWell` / `IconButton` / `TextButton`
- [ ] Buttons and links have descriptive text (not "Click here" or "More")
- [ ] Screen and section titles are marked as headings (`Semantics(header: true)`)
- [ ] Related content that reads as one item is grouped (`MergeSemantics`), and purely decorative widgets are excluded (`ExcludeSemantics`)
- [ ] Dynamic changes are announced (`Semantics(liveRegion: true)`, SnackBars, or a programmatic announcement)
- [ ] Reading order matches visual order, and the screen has a meaningful title on navigation
- [ ] Every screen has been walked through with TalkBack **and** VoiceOver

### Focus, Keyboard, and Switch Access
- [ ] All interactive elements are reachable with an external keyboard, switch access, or D-pad (focusable, activate with Enter/Space)
- [ ] Focus order follows visual and logical order (`FocusTraversalGroup` where it doesn't)
- [ ] Focus is visible on focused elements
- [ ] No focus traps: the user can always move on or go back
- [ ] Dialogs and sheets use `showDialog` / `showModalBottomSheet`, which scope focus and screen-reader navigation
- [ ] Focus moves sensibly after content changes (error focus, new screen, closed dialog)
- [ ] The system back gesture and hardware back button work, and intercepting them (`PopScope`) is deliberate

### Touch Targets and Gestures
- [ ] Touch targets are at least 48×48 dp (Material) and 44×44 pt (Apple HIG)
- [ ] Targets are spaced so adjacent ones aren't hit by accident
- [ ] Every complex gesture (swipe, drag, pinch, long-press, multi-finger) has a single-tap alternative
- [ ] No action is available only through hover, long-press, or motion (shake, tilt)
- [ ] Swipe-to-dismiss and reorder have accessible actions (custom semantics actions or visible buttons)

### Visual
- [ ] Text contrast ≥ 4.5:1 (normal text) or ≥ 3:1 (large text, 18pt+ or 14pt+ bold), in **light and dark** themes
- [ ] UI component and icon contrast ≥ 3:1 against the background, including disabled and focused states
- [ ] Color is not the only way to convey information (icons, text, patterns too)
- [ ] Layout holds at the largest OS font size (200%) and with bold text, without clipping or overflow
- [ ] Text scaling is never clamped or disabled to make a layout fit
- [ ] Non-essential motion respects reduce-motion (`MediaQuery.disableAnimationsOf`)
- [ ] No content flashes more than 3 times per second
- [ ] Layout works in portrait and landscape; orientation is not locked without a reason
- [ ] Layout adapts to small phones, tablets, and split-screen

### Forms
- [ ] Every input has a persistent visible label (`labelText`), not just a placeholder or hint
- [ ] Required fields indicated (not by color alone)
- [ ] Error messages are specific, shown near the field, and reachable by screen readers
- [ ] Error state is visible by more than color (icon, text, border)
- [ ] Submission errors are summarized, and focus or announcement takes the user to the problem
- [ ] Appropriate `keyboardType`, `textInputAction`, and `autofillHints` for known fields
- [ ] Password fields allow paste and password managers

### Content
- [ ] The app is localized, and layouts support right-to-left languages (`Directionality`, directional padding)
- [ ] Time-limited actions can be extended or turned off
- [ ] Audio and video have captions and controls; nothing autoplays with sound
- [ ] Links and tappable text are distinguishable by more than color
- [ ] Meaningful empty states and error states (not blank screens)

## Common Flutter Patterns

### Buttons vs. Tap Handlers

```dart
// Use a real button widget: focusable, has a role, meets the touch target size
IconButton(
  tooltip: 'Delete task',              // Becomes the accessible label
  icon: const Icon(Icons.delete_outline),
  onPressed: onDelete,
)

// GestureDetector exposes nothing to screen readers: BAD
GestureDetector(onTap: onDelete, child: const Icon(Icons.delete_outline))

// If you must use a custom tap target, add semantics: acceptable
Semantics(
  label: 'Delete task',
  button: true,
  child: InkWell(onTap: onDelete, child: const Padding(
    padding: EdgeInsets.all(12),
    child: Icon(Icons.delete_outline),
  )),
)
```

### Form Labels and Errors

```dart
// Persistent label; hint is a supplement, never the only label
TextFormField(
  keyboardType: TextInputType.emailAddress,
  textInputAction: TextInputAction.next,
  autofillHints: const [AutofillHints.email],
  decoration: const InputDecoration(
    labelText: 'Email address',
    helperText: 'We only use this to sign you in',
  ),
  validator: (value) =>
      (value == null || !value.contains('@')) ? 'Enter a valid email address' : null,
)
```

### Semantics Toolkit

```dart
Semantics(header: true, child: Text('Tasks', style: theme.textTheme.titleLarge))   // Heading

MergeSemantics(                                                                       // One item, not three
  child: ListTile(title: Text(task.title), subtitle: Text(task.dueLabel)),
)

Semantics(                                                                            // Status change
  liveRegion: true,
  child: Text(saved ? 'Task saved' : ''),
)

Image.asset('assets/divider.png', excludeFromSemantics: true)                         // Decorative
Image.network(url, semanticLabel: 'Profile photo of ${user.name}')                    // Meaningful

ExcludeSemantics(child: const DecorativeBackground())                                 // Hide noise
```

### Modal Dialogs

```dart
// showDialog scopes focus and screen-reader navigation for you
final confirmed = await showAdaptiveDialog<bool>(
  context: context,
  builder: (context) => AlertDialog.adaptive(
    title: const Text('Delete task?'),
    content: const Text('This can\'t be undone.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
    ],
  ),
);
```

### Loading States

```dart
Semantics(
  label: 'Loading tasks',
  liveRegion: true,
  child: const CircularProgressIndicator(),
)
// Prefer skeletons for content, and keep an accessible label on whatever you show
```

### Accessible Lists

```dart
ListView.builder(
  itemCount: tasks.length,
  itemBuilder: (context, i) {
    final task = tasks[i];
    return CheckboxListTile(
      value: task.done,
      onChanged: (_) => onToggle(task.id),
      title: Text(task.title),
      // Screen reader hears the title with its checked state and role
    );
  },
)
```

### Text Scale and Reduced Motion

```dart
final scale = MediaQuery.textScalerOf(context);            // Respect it; don't clamp it away
final reduceMotion = MediaQuery.disableAnimationsOf(context);

AnimatedContainer(
  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
  // ...
)
```

## Testing Tools

```dart
// Automated guidelines in widget tests
final handle = tester.ensureSemantics();
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
await expectLater(tester, meetsGuideline(textContrastGuideline));
handle.dispose();

// Inspect the semantics tree
debugDumpSemanticsTree();                                    // Print it
MaterialApp(showSemanticsDebugger: true, /* ... */)          // Overlay it while running
```

```bash
# Automated: widget tests with accessibility guidelines
flutter test

# On a device or emulator
# Android: TalkBack (Settings > Accessibility), Accessibility Scanner app, Switch Access, Voice Access
# iOS: VoiceOver (Settings > Accessibility), Xcode Accessibility Inspector, Voice Control, Dynamic Type
# Both: largest font size and display size, bold text, reduce motion, dark mode, RTL locale
```

- **Agent-driven checks:** `mobile_list_elements_on_screen` (mobile-mcp) reads the native accessibility tree. Controls missing from it are invisible to screen readers. See `flutter-devtools-and-device-testing`.
- Automated checks catch a fraction of issues (roughly a third at best). Always walk the main flows with a screen reader.

## Quick Reference: Announcements and Live Regions

| Mechanism | Behavior | Use For |
|-----------|----------|---------|
| `Semantics(liveRegion: true)` | Changes to the region's label or value are announced | Status updates, saved confirmations, validation errors |
| `SnackBar` | Announced by screen readers when shown | Transient confirmations |
| Programmatic announcement via `SemanticsService` | Announced on demand (check the current API in your SDK version) | Time-sensitive alerts and results of actions with no visible change |
| `Semantics(label: ..., button: true)` on a new route | Reading focus lands on the new screen's content | Screen changes |

## Common Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `GestureDetector` as a button | Invisible to screen readers, no keyboard activation | Use `IconButton` / `InkWell` / `TextButton`, or add `Semantics` |
| `IconButton` with no `tooltip` | Announced as "button" with no description | Add `tooltip` |
| Missing `semanticLabel` on meaningful images | Images invisible to screen readers | Add a descriptive label, or exclude decorative images |
| Color-only states | Invisible to color-blind users | Add icons, text, or patterns |
| Touch targets under 48×48 dp | Hard to hit for many users | Pad the tap area (`InkResponse`, `Padding`, `kMinInteractiveDimension`) |
| Long-press or swipe as the only path | Unusable with assistive tech and for many users | Provide a visible button or custom semantics action |
| Clamping or ignoring text scale | Low-vision users can't read the app | Fix the layout: `Flexible`, `Wrap`, scrolling; no fixed-height text containers |
| Placeholder text as the label | Disappears on input, often unread | Use `labelText` |
| Repeating the visible text in a `Semantics` label | Screen reader reads the text twice | Use `MergeSemantics`, or `excludeSemantics: true` on the inner widget |
| `ExcludeSemantics` on interactive widgets | Control disappears from the accessibility tree | Exclude only decorative content |
| Custom dropdown or picker with no semantics | Unusable with a screen reader | Use platform-aware widgets or add proper semantics |
| Locking orientation without need | Excludes users who mount devices in one orientation | Support both unless the product requires otherwise |
| Autoplaying animation, video, or audio | Disorienting, can't be stopped | Add controls, respect reduce-motion, don't autoplay with sound |
| Verifying only in light mode, at default text size | Misses contrast and overflow failures | Check dark mode, 200% text, and small screens |
