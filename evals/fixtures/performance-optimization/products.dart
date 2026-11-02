/// Builds the rows shown on the products screen, each with its sales rank.
List<String> buildProductRows(List<Product> products) {
  final rows = <String>[];
  for (final product in products) {
    final rank = ([...products]..sort((a, b) => b.sales.compareTo(a.sales)))
            .indexWhere((candidate) => candidate.id == product.id) +
        1;
    rows.add('#$rank ${product.name}: ${product.sales}');
  }
  return rows;
}

class Product {
  const Product({required this.id, required this.name, required this.sales});

  final int id;
  final String name;
  final int sales;
}
