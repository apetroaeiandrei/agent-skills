Map<String, Map<String, Object>> parseConfig(List<String?> lines) {
  final result = <String, Map<String, Object>>{};
  var section = 'default';
  result[section] = {};
  for (var i = 0; i < lines.length; i++) {
    final original = lines[i];
    if (original != null) {
      final line = original.trim();
      if (line.isNotEmpty) {
        if (line[0] != '#' && line[0] != ';') {
          if (line[0] == '[' && line[line.length - 1] == ']') {
            final candidate = line.substring(1, line.length - 1).trim();
            if (candidate.isNotEmpty) {
              section = candidate;
              if (result[section] == null) result[section] = {};
            }
          } else {
            final separator = line.indexOf('=');
            if (separator >= 0) {
              final key = line.substring(0, separator).trim();
              final raw = line.substring(separator + 1).trim();
              if (key.isNotEmpty) {
                Object value;
                if (raw == 'true') {
                  value = true;
                } else if (raw == 'false') {
                  value = false;
                } else if (raw != '' && num.tryParse(raw) != null) {
                  value = num.parse(raw);
                } else if (raw.length >= 2 &&
                    ((raw[0] == '"' && raw[raw.length - 1] == '"') ||
                        (raw[0] == "'" && raw[raw.length - 1] == "'"))) {
                  value = raw.substring(1, raw.length - 1);
                } else {
                  value = raw;
                }
                result[section]![key] = value;
              }
            }
          }
        }
      }
    }
  }
  return result;
}
