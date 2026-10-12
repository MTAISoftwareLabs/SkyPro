import 'dart:math' as math;

import 'package:get_storage/get_storage.dart';

import '../helpers/helpers.dart';
import '../logic/cubits/prefetch/prefetch_cubit.dart';
import '../presentation/screens/content_detail_helpers.dart';
import '../repository/models/category.dart';
import '../repository/models/channel_movie.dart';
import '../repository/models/channel_serie.dart';
import '../repository/models/movie_detail.dart';
import '../repository/models/serie_details.dart';
import '../services/iptv_image_cache.dart';
import '../services/parental_control_service.dart';
import '../services/tmdb_rating_service.dart';

/// أقصى شرائح للهيرو (TV Home) — افتراضي عند غياب إعداد اللوحة.
const int kHomeHeroMaxSlides = 5;

/// مصدر محتوى الهيرو من لوحة التحكم: تلقائي / أفلام / مسلسلات.
enum HomeHeroContentMode { auto, movies, series }

/// إعدادات هيرو الرئيسية القادمة من الـ admin panel.
class HomeHeroPanel {
  HomeHeroPanel._();

  static const String _kEnabled = 'hero_promo_enabled';
  static const String _kImage = 'hero_promo_image_url';
  static const String _kTitle = 'hero_promo_title';
  static const String _kText = 'hero_promo_text';
  static const String _kLink = 'hero_promo_link_url';
  static const String _kCount = 'hero_banner_count';
  static const String _kMode = 'hero_content_mode';

  static void persistFromPanel(Map<dynamic, dynamic> data) {
    final box = GetStorage();

    final enabled = data['hero_promo_enabled'];
    if (enabled is bool) {
      box.write(_kEnabled, enabled);
    } else if (enabled != null) {
      box.write(
        _kEnabled,
        enabled == 1 || enabled == '1' || enabled == true,
      );
    }

    void writeStr(String key) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) {
        box.write(key, v);
      } else {
        box.remove(key);
      }
    }

    writeStr(_kImage);
    writeStr(_kTitle);
    writeStr(_kText);
    writeStr(_kLink);

    final rawCount = data['hero_banner_count'];
    if (rawCount != null) {
      final n = int.tryParse(rawCount.toString().trim());
      if (n != null) {
        box.write(_kCount, n.clamp(1, 10));
      }
    }

    final mode = (data['hero_content_mode'] ?? '').toString().trim().toLowerCase();
    if (mode == 'movies' || mode == 'series' || mode == 'auto') {
      box.write(_kMode, mode);
    }
  }

  static bool get promoEnabled {
    final v = GetStorage().read(_kEnabled);
    if (v is bool) return v;
    if (v == null) return false;
    return v == 1 || v == '1';
  }

  static String? get promoImageUrl {
    final u = (GetStorage().read(_kImage) ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  static String get promoTitle {
    final t = (GetStorage().read(_kTitle) ?? '').toString().trim();
    return t;
  }

  static String get promoText {
    final t = (GetStorage().read(_kText) ?? '').toString().trim();
    return t;
  }

  static String? get promoLinkUrl {
    final u = (GetStorage().read(_kLink) ?? '').toString().trim();
    return u.isNotEmpty ? u : null;
  }

  /// يظهر الإعلان فقط عند التفعيل + صورة.
  static bool get hasPromoSlide =>
      promoEnabled && (promoImageUrl?.isNotEmpty ?? false);

  static int get bannerCount {
    final v = GetStorage().read(_kCount);
    final n = v is int ? v : int.tryParse('$v');
    if (n == null) return kHomeHeroMaxSlides;
    return n.clamp(1, 10);
  }

  static HomeHeroContentMode get contentMode {
    final m = (GetStorage().read(_kMode) ?? 'auto').toString().trim().toLowerCase();
    switch (m) {
      case 'movies':
        return HomeHeroContentMode.movies;
      case 'series':
        return HomeHeroContentMode.series;
      default:
        return HomeHeroContentMode.auto;
    }
  }

  /// بصمة لتحديث الكاش عند تغيّر إعدادات اللوحة.
  static String settingsFingerprint() {
    return [
      'en:${promoEnabled ? 1 : 0}',
      'img:${promoImageUrl ?? ''}',
      't:$promoTitle',
      'x:$promoText',
      'l:${promoLinkUrl ?? ''}',
      'n:$bannerCount',
      'm:${contentMode.name}',
    ].join('|');
  }

  static HomeHeroSlide? buildPromoSlide() {
    if (!hasPromoSlide) return null;
    final title = promoTitle.isNotEmpty ? promoTitle : 'Promo';
    return HomeHeroSlide(
      isSeries: false,
      isPromo: true,
      title: title,
      imageUrl: promoImageUrl!,
      contentKey: 'promo:${promoImageUrl.hashCode}',
      plot: promoText.isNotEmpty ? promoText : null,
      linkUrl: promoLinkUrl,
    );
  }
}

/// شريحة هيرو جاهزة للعرض (من bootstrap أو من الصفحة الرئيسية).
class HomeHeroSlide {
  const HomeHeroSlide({
    required this.isSeries,
    required this.title,
    required this.imageUrl,
    required this.contentKey,
    this.movie,
    this.serie,
    this.rating,
    this.rating5based,
    this.year,
    this.genres = const <String>[],
    this.plot,
    this.tagline,
    this.isPromo = false,
    this.linkUrl,
  });

  final bool isSeries;
  final ChannelMovie? movie;
  final ChannelSerie? serie;
  final String title;
  final String imageUrl;
  final String contentKey;
  final String? rating;
  final String? rating5based;
  final int? year;
  final List<String> genres;
  final String? plot;
  final String? tagline;
  final bool isPromo;
  final String? linkUrl;
}

/// كاش هيرو التلفزيون — يُجهَّز أثناء bootstrap باش Home يفتح والبانر واجد.
class HomeHeroCache {
  HomeHeroCache._();

  static List<HomeHeroSlide> _slides = const [];
  static String _fingerprint = '';
  static String? _serverUrl;

  static List<HomeHeroSlide> get slides => _slides;
  static bool get isReady => _slides.isNotEmpty;

  static List<String> get imageUrls => _slides
      .map((s) => s.imageUrl)
      .where((u) => u.isNotEmpty)
      .toList(growable: false);

  static void clear() {
    _slides = const [];
    _fingerprint = '';
    _serverUrl = null;
  }

  static int _contentSlotCount() {
    final total = HomeHeroPanel.bannerCount;
    if (HomeHeroPanel.hasPromoSlide) {
      return math.max(0, total - 1);
    }
    return total;
  }

  static List<HomeHeroSlide> _withPromo(List<HomeHeroSlide> content) {
    final promo = HomeHeroPanel.buildPromoSlide();
    if (promo == null) return content;
    return [promo, ...content];
  }

  static String fingerprintFor(
    List<ChannelMovie> movies,
    List<ChannelSerie> series, {
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) {
    final parental = ParentalControlService.instance;
    final keys = <String>[
      'pc:${parental.homeSurfaceFingerprint()}',
      'cfg:${HomeHeroPanel.settingsFingerprint()}',
    ];
    for (final s in pickCandidates(
      movies,
      series,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    )) {
      if (s.isSeries) {
        keys.add('s:${s.serie?.seriesId ?? ''}');
      } else {
        keys.add('m:${s.movie?.streamId ?? ''}');
      }
    }
    return keys.join('|');
  }

  /// يرجّع الشرائح إن كانت لنفس المحتوى، وإلا null.
  static List<HomeHeroSlide>? takeIfMatches({
    required List<ChannelMovie> movies,
    required List<ChannelSerie> series,
    String? serverUrl,
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) {
    if (_slides.isEmpty) return null;
    final fp = fingerprintFor(
      movies,
      series,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    );
    if (fp.isEmpty || fp != _fingerprint) return null;
    if ((serverUrl ?? '') != (_serverUrl ?? '')) return null;
    return List<HomeHeroSlide>.unmodifiable(_slides);
  }

  static List<({bool isSeries, ChannelMovie? movie, ChannelSerie? serie})>
      pickCandidates(
    List<ChannelMovie> movies,
    List<ChannelSerie> series, {
    int? max,
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) {
    final slotMax = max ?? _contentSlotCount();
    if (slotMax <= 0) return const [];

    final parental = ParentalControlService.instance;
    final safeMovies = parental.filterMoviesForHomeSurface(
      movies,
      categoryNameForId: (id) =>
          ParentalControlService.categoryNameFromId(id, movieCategories),
    );
    final safeSeries = parental.filterSeriesForHomeSurface(
      series,
      categoryNameForId: (id) =>
          ParentalControlService.categoryNameFromId(id, seriesCategories),
    );

    final mode = HomeHeroPanel.contentMode;
    final useMovies = mode != HomeHeroContentMode.series;
    final useSeries = mode != HomeHeroContentMode.movies;

    final out =
        <({bool isSeries, ChannelMovie? movie, ChannelSerie? serie})>[];
    final seen = <String>{};
    void addMovie(ChannelMovie m) {
      if (!useMovies) return;
      final id = (m.streamId ?? '').trim();
      if (id.isEmpty || !seen.add('m:$id')) return;
      out.add((isSeries: false, movie: m, serie: null));
    }

    void addSerie(ChannelSerie s) {
      if (!useSeries) return;
      final id = (s.seriesId ?? '').trim();
      if (id.isEmpty || !seen.add('s:$id')) return;
      out.add((isSeries: true, movie: null, serie: s));
    }

    if (mode == HomeHeroContentMode.movies) {
      for (var i = 0; i < safeMovies.length && out.length < slotMax; i++) {
        addMovie(safeMovies[i]);
      }
      return out;
    }
    if (mode == HomeHeroContentMode.series) {
      for (var i = 0; i < safeSeries.length && out.length < slotMax; i++) {
        addSerie(safeSeries[i]);
      }
      return out;
    }

    final mLen = safeMovies.length;
    final sLen = safeSeries.length;
    final n = math.max(mLen, sLen);
    for (var i = 0; i < n && out.length < slotMax; i++) {
      if (i < mLen) addMovie(safeMovies[i]);
      if (out.length >= slotMax) break;
      if (i < sLen) addSerie(safeSeries[i]);
    }
    return out;
  }

  static List<String> _parseGenres(String? raw) {
    if (isBlankMeta(raw)) return const [];
    return raw!
        .split(RegExp(r'[,|/•]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .take(3)
        .toList(growable: false);
  }

  /// بناء فوري من قائمة الرئيسية (بوستر) — بلا انتظار API.
  static List<HomeHeroSlide> buildInstant({
    required List<ChannelMovie> movies,
    required List<ChannelSerie> series,
    String? serverUrl,
    bool isDemo = false,
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) {
    final built = <HomeHeroSlide>[];
    for (final c in pickCandidates(
      movies,
      series,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    )) {
      if (c.isSeries) {
        final serie = c.serie!;
        built.add(
          HomeHeroSlide(
            isSeries: true,
            serie: serie,
            title: sanitizeDisplayTitle(serie.name ?? ''),
            imageUrl: isDemo
                ? ''
                : resolveImageUrl(serie.cover, serverUrl),
            contentKey: 'series:${serie.seriesId ?? ''}',
            rating: serie.rating,
            rating5based: serie.rating5based,
            year: extractReleaseYear(serie.name),
            genres: const [],
            plot: pickMeta(serie.plot),
          ),
        );
      } else {
        final movie = c.movie!;
        built.add(
          HomeHeroSlide(
            isSeries: false,
            movie: movie,
            title: sanitizeDisplayTitle(movie.name ?? ''),
            imageUrl: isDemo
                ? ''
                : resolveImageUrl(movie.streamIcon, serverUrl),
            contentKey: 'movie:${movie.streamId ?? ''}',
            rating: movie.rating,
            rating5based: movie.rating5based,
            year: extractReleaseYear(movie.name),
            genres: const [],
            plot: null,
          ),
        );
      }
    }
    return _withPromo(built);
  }

  static HomeHeroSlide _fromMovie({
    required ChannelMovie movie,
    MovieDetail? detail,
    String? serverUrl,
    bool isDemo = false,
  }) {
    final info = detail?.info;
    final imgs = detailBackdropImages(
      backdropPath: info?.backdropPath,
      backdrop: info?.backdrop,
      poster: info?.movieImage,
      listFallback: movie.streamIcon,
    );
    final rawImg = imgs.isNotEmpty ? imgs.first : (movie.streamIcon ?? '');
    return HomeHeroSlide(
      isSeries: false,
      movie: movie,
      title: sanitizeDisplayTitle(
        pickMeta(detail?.movieData?.name, movie.name) ?? '',
      ),
      imageUrl: isDemo ? '' : resolveImageUrl(rawImg, serverUrl),
      contentKey: 'movie:${movie.streamId ?? ''}',
      rating: pickMeta(info?.rating, movie.rating),
      rating5based: movie.rating5based,
      year: extractReleaseYear(info?.releasedate) ??
          extractReleaseYear(movie.name),
      genres: _parseGenres(info?.genre),
      plot: pickMeta(info?.plot),
    );
  }

  static HomeHeroSlide _fromSerie({
    required ChannelSerie serie,
    SerieDetails? detail,
    String? serverUrl,
    bool isDemo = false,
  }) {
    final info = detail?.info;
    final imgs = detailBackdropImages(
      backdropPath: info?.backdropPath,
      poster: info?.cover,
      listFallback: serie.cover,
    );
    final rawImg = imgs.isNotEmpty ? imgs.first : (serie.cover ?? '');
    return HomeHeroSlide(
      isSeries: true,
      serie: serie,
      title: sanitizeDisplayTitle(
        pickMeta(info?.name, serie.name) ?? '',
      ),
      imageUrl: isDemo ? '' : resolveImageUrl(rawImg, serverUrl),
      contentKey: 'series:${serie.seriesId ?? ''}',
      rating: pickMeta(info?.rating, serie.rating),
      rating5based: serie.rating5based,
      year: extractReleaseYear(info?.releaseDate) ??
          extractReleaseYear(serie.name),
      genres: _parseGenres(info?.genre),
      plot: pickMeta(info?.plot, serie.plot),
    );
  }

  /// يحمّل التفاصيل + ي خزّن الشرائح + يسخّن صور الـ backdrop على القرص.
  static Future<void> warm({
    required List<ChannelMovie> movies,
    required List<ChannelSerie> series,
    required PrefetchCubit prefetch,
    String? serverUrl,
    bool isDemo = false,
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) async {
    final candidates = pickCandidates(
      movies,
      series,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    );
    if (candidates.isEmpty && !HomeHeroPanel.hasPromoSlide) {
      clear();
      return;
    }

    final built = <HomeHeroSlide>[];
    for (final c in candidates) {
      if (c.isSeries) {
        final serie = c.serie!;
        final id = validIptvContentId(serie.seriesId);
        SerieDetails? detail;
        if (id != null && !isDemo) {
          try {
            detail = await prefetch.getSerieDetailCached(id);
          } catch (_) {}
        }
        built.add(
          _fromSerie(
            serie: serie,
            detail: detail,
            serverUrl: serverUrl,
            isDemo: isDemo,
          ),
        );
      } else {
        final movie = c.movie!;
        final id = validIptvContentId(movie.streamId);
        MovieDetail? detail;
        if (id != null && !isDemo) {
          try {
            detail = await prefetch.getMovieDetailCached(id);
          } catch (_) {}
        }
        built.add(
          _fromMovie(
            movie: movie,
            detail: detail,
            serverUrl: serverUrl,
            isDemo: isDemo,
          ),
        );
      }
    }

    final withPromo = _withPromo(built);
    _slides = List<HomeHeroSlide>.unmodifiable(withPromo);
    _fingerprint = fingerprintFor(
      movies,
      series,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    );
    _serverUrl = serverUrl;

    final urls = imageUrls;
    if (urls.isNotEmpty) {
      await warmIptvImagesToDisk(
        urls,
        limit: urls.length,
        concurrency: 3,
        maxDuration: const Duration(seconds: 10),
      );
    }
  }

  /// بناء كامل (للتحديث من واجهة Home إن لزم).
  static Future<List<HomeHeroSlide>> buildFull({
    required List<ChannelMovie> movies,
    required List<ChannelSerie> series,
    required PrefetchCubit prefetch,
    String? serverUrl,
    bool isDemo = false,
    List<CategoryModel> movieCategories = const [],
    List<CategoryModel> seriesCategories = const [],
  }) async {
    await warm(
      movies: movies,
      series: series,
      prefetch: prefetch,
      serverUrl: serverUrl,
      isDemo: isDemo,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    );
    return List<HomeHeroSlide>.unmodifiable(_slides);
  }
}
