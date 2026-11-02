import 'dart:convert';

import 'products.dart';

void main() {
  final products = List.generate(
    1000,
    (id) => Product(id: id, name: 'Product $id', sales: (id * 7919) % 10000),
  );

  final stopwatch = Stopwatch()..start();
  final rows = buildProductRows(products);
  stopwatch.stop();

  print(jsonEncode({
    'products': products.length,
    'rows': rows.length,
    'elapsedMs': stopwatch.elapsedMicroseconds / 1000,
  }));
}
