# Menu component conventions

- Framework: Flutter (Material 3) with Dart 3.
- Styling: read colors and text styles from `Theme.of(context)`; spacing comes from the `Spacing` constants. Do not add a styling dependency.
- Public widgets are `const`-constructible and accept a `key`.
- Widgets must support TalkBack and VoiceOver users, large text, and touch targets of at least 48x48 dp.
- Focus returns to the trigger when a menu closes.
- The Android back button closes the menu; hardware keyboards can move between enabled items with the arrow keys.
- State: ephemeral UI state stays in the widget; anything with logic uses a Cubit. States and models are freezed classes (never Equatable); run `dart run build_runner build -d` after changing them.

The new dropdown should expose a trigger label and a list of actions. Disabled
actions remain visible but cannot receive focus or execute.
