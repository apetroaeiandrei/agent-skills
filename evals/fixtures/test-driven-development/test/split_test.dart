import 'package:split_payment/split.dart';
import 'package:test/test.dart';

void main() {
  test('splits an evenly divisible total into equal shares', () {
    expect(splitCents(10000, 4), [2500, 2500, 2500, 2500]);
  });

  test('a single participant receives the whole total', () {
    expect(splitCents(500, 1), [500]);
  });
}
