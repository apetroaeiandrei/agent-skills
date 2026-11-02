import 'package:config_parser_fixture/config_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses sections, values, comments, and defaults', () {
    expect(
      parseConfig([
        'owner = "Ada"',
        '# ignored',
        '[server]',
        'port = 8080',
        'enabled = true',
        'note = hello',
      ]),
      {
        'default': {'owner': 'Ada'},
        'server': {'port': 8080, 'enabled': true, 'note': 'hello'},
      },
    );
  });
}
