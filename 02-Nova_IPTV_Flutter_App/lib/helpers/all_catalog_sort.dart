part of 'helpers.dart';

/// خيارات الفرز لفئة «الكل» فقط (أفلام / مسلسلات).
/// [all] = بدون ترتيب (ترتيب السيرفر) — الأسرع للعرض الأول.
enum AllCatalogSort {
  all,
  newest,
  oldest,
  nameAsc,
  nameDesc,
  ratingHigh,
  ratingLow,
}

extension AllCatalogSortX on AllCatalogSort {
  String get labelKey {
    switch (this) {
      case AllCatalogSort.all:
        return 'all_sort_all';
      case AllCatalogSort.newest:
        return 'all_sort_newest';
      case AllCatalogSort.oldest:
        return 'all_sort_oldest';
      case AllCatalogSort.nameAsc:
        return 'all_sort_name_asc';
      case AllCatalogSort.nameDesc:
        return 'all_sort_name_desc';
      case AllCatalogSort.ratingHigh:
        return 'all_sort_rating_high';
      case AllCatalogSort.ratingLow:
        return 'all_sort_rating_low';
    }
  }

  IconData get icon {
    switch (this) {
      case AllCatalogSort.all:
        return Icons.apps_rounded;
      case AllCatalogSort.newest:
        return Icons.schedule_rounded;
      case AllCatalogSort.oldest:
        return Icons.history_toggle_off_rounded;
      case AllCatalogSort.nameAsc:
        return Icons.sort_by_alpha_rounded;
      case AllCatalogSort.nameDesc:
        return Icons.sort_by_alpha_rounded;
      case AllCatalogSort.ratingHigh:
        return Icons.star_rounded;
      case AllCatalogSort.ratingLow:
        return Icons.star_outline_rounded;
    }
  }
}

double allCatalogParseRating(String? rating, String? rating5based) {
  final primary = double.tryParse((rating ?? '').trim()) ?? 0;
  if (primary > 0) return primary;
  return double.tryParse((rating5based ?? '').trim()) ?? 0;
}

/// ترتيب نسخة من القائمة في الذاكرة فقط — بدون طلب شبكة.
List<T> sortAllCatalogList<T>({
  required List<T> source,
  required AllCatalogSort sort,
  required String? Function(T item) nameOf,
  required int Function(T item) timestampOf,
  required double Function(T item) ratingOf,
}) {
  if (source.isEmpty) return source;
  if (sort == AllCatalogSort.all) return source;

  final list = List<T>.from(source);
  int byName(T a, T b) =>
      (nameOf(a) ?? '').toLowerCase().compareTo((nameOf(b) ?? '').toLowerCase());

  switch (sort) {
    case AllCatalogSort.all:
      break;
    case AllCatalogSort.newest:
      list.sort((a, b) {
        final c = timestampOf(b).compareTo(timestampOf(a));
        return c != 0 ? c : byName(a, b);
      });
    case AllCatalogSort.oldest:
      list.sort((a, b) {
        final c = timestampOf(a).compareTo(timestampOf(b));
        return c != 0 ? c : byName(a, b);
      });
    case AllCatalogSort.nameAsc:
      list.sort(byName);
    case AllCatalogSort.nameDesc:
      list.sort((a, b) => byName(b, a));
    case AllCatalogSort.ratingHigh:
      list.sort((a, b) {
        final c = ratingOf(b).compareTo(ratingOf(a));
        return c != 0 ? c : byName(a, b);
      });
    case AllCatalogSort.ratingLow:
      list.sort((a, b) {
        final c = ratingOf(a).compareTo(ratingOf(b));
        return c != 0 ? c : byName(a, b);
      });
  }
  return list;
}
