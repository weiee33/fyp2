/// Preferences use the existing category-name contract and retain tap order.
/// Duplicate catalogue labels form one tile; records in the database are intact.
class CustomerExplorePreferences {
  static String key(String name) => name.trim().toLowerCase();

  static List<String> unique(Iterable<String> names) {
    final seen = <String>{};
    return [
      for (final name in names)
        if (key(name).isNotEmpty && seen.add(key(name))) name.trim(),
    ];
  }

  static List<Map<String, dynamic>> categories(
    List<Map<String, dynamic>> catalogue,
    List<String> preferences, {
    bool includeOthers = false,
  }) {
    final byName = <String, Map<String, dynamic>>{};
    for (final category in catalogue) {
      final name = key(category['category_name'] as String);
      byName.putIfAbsent(name, () => category);
    }
    final selected = unique(
      preferences,
    ).map(key).where(byName.containsKey).toList();
    // Empty or retired preferences must not leave Explore empty.
    if (selected.isEmpty) return byName.values.toList();
    return [
      for (final name in selected) byName[name]!,
      if (includeOthers)
        for (final entry in byName.entries)
          if (!selected.contains(entry.key)) entry.value,
    ];
  }
}
