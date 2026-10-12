import 'package:get_storage/get_storage.dart';

import '../../helpers/helpers.dart';
import '../models/category.dart';

enum CatalogOrderKind { movie, series }

/// ترتيب فئات الأفلام/المسلسلات حسب الحساب — مثل ترتيب Live TV.
class CatalogCategoryOrderStore {
  CatalogCategoryOrderStore._();

  static GetStorage get _box => GetStorage();

  static String _prefix(CatalogOrderKind kind) {
    switch (kind) {
      case CatalogOrderKind.movie:
        return kStorageMovieCategoryOrderPrefix;
      case CatalogOrderKind.series:
        return kStorageSeriesCategoryOrderPrefix;
    }
  }

  static String _key(CatalogOrderKind kind, String accountId) =>
      '${_prefix(kind)}$accountId';

  static List<String> load(CatalogOrderKind kind, String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final raw = _box.read(_key(kind, id));
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && !isCatalogPinnedCategory(e))
        .toList();
  }

  static void save(
    CatalogOrderKind kind,
    String accountId,
    List<String> ids,
  ) {
    final id = accountId.trim();
    if (id.isEmpty) return;
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !isCatalogPinnedCategory(e))
        .toList();
    _box.write(_key(kind, id), clean);
  }

  /// يحافظ على الترتيب المحفوظ للفئات القابلة للسحب فقط.
  static List<CategoryModel> apply(
    List<CategoryModel> raw,
    List<String> savedIds,
  ) {
    if (raw.isEmpty) return raw;
    final byId = <String, CategoryModel>{};
    for (final c in raw) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty || isCatalogPinnedCategory(id)) continue;
      byId.putIfAbsent(id, () => c);
    }
    if (byId.isEmpty) return raw;

    final out = <CategoryModel>[];
    final seen = <String>{};
    for (final id in savedIds) {
      final c = byId[id];
      if (c != null && seen.add(id)) out.add(c);
    }
    for (final c in raw) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty || isCatalogPinnedCategory(id)) continue;
      if (seen.add(id)) out.add(c);
    }
    return out;
  }
}
