# Session implementation task

Implement a settings form screen for this Flutter app: a Cubit that holds the
form state as a freezed sealed union (editing, saving, saved, failure), and
back-button handling that asks the user to confirm when there are unsaved
changes. The dependency versions are in `pubspec.yaml`.

Follow the currently documented approach for the versions this project uses,
for freezed class declarations and pattern matching, `flutter_bloc` widgets, and
intercepting back navigation. Ground every framework claim in official Flutter,
Dart, or package documentation and cite the exact pages used. Do not rely on
remembered patterns from older major versions. Flag any assumption that cannot
be verified from the repository or the official documentation.
