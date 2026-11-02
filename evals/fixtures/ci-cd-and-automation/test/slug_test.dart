import 'package:ci_fixture/slug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slugifies a title', () {
    expect(slugify('Hello World'), 'hello-world');
  });
}
