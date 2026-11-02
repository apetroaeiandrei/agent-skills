List<T> paginate<T>(List<T> items, int page, int pageSize) {
  final start = page * pageSize;
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start.clamp(0, items.length), end);
}
