import 'package:get_storage/get_storage.dart';

import '../../helpers/helpers.dart';
import '../models/category.dart';

/// ترتيب فئات البث المباشر حسب الحساب — يبقى بعد إغلاق التطبيق.
class LiveCategoryOrderStore {
  LiveCategoryOrderStore._();

  static GetStorage get _box => GetStorage();

  static String _key(String accountId) =>
      '$kStorageLiveCategoryOrderPrefix$accountId';

  static List<String> load(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) return const [];
    final raw = _box.read(_key(id));
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && !isIptvPinnedLiveCategory(e))
        .toList();
  }

  static void save(String accountId, List<String> ids) {
    final id = accountId.trim();
    if (id.isEmpty) return;
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !isIptvPinnedLiveCategory(e))
        .toList();
    _box.write(_key(id), clean);
  }

  /// يحافظ على الترتيب المحفوظ، ثم يضيف الفئات الجديدة في النهاية.
  static List<CategoryModel> apply(
    List<CategoryModel> raw,
    List<String> savedIds,
  ) {
    if (raw.isEmpty) return raw;
    final byId = <String, CategoryModel>{};
    for (final c in raw) {
      final id = (c.categoryId ?? '').trim();
      if (id.isEmpty || isIptvPinnedLiveCategory(id)) continue;
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
      if (id.isEmpty || isIptvPinnedLiveCategory(id)) continue;
      if (seen.add(id)) out.add(c);
    }
    return out;
  }
}
