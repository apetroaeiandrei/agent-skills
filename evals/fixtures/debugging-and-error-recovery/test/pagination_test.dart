import 'package:pagination_fixture/pagination.dart';
import 'package:test/test.dart';

void main() {
  test('returns the second page for a one-based page number', () {
    expect(paginate(['a', 'b', 'c', 'd', 'e'], 2, 2), ['c', 'd']);
  });
}
