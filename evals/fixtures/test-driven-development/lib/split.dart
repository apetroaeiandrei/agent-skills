List<int> splitCents(int totalCents, int n) {
  final share = totalCents ~/ n;
  return List.filled(n, share);
}
