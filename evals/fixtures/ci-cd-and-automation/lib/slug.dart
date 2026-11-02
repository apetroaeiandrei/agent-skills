String slugify(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
