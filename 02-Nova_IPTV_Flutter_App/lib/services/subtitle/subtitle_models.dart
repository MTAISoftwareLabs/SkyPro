enum SubtitleSearchBy {
  imdbId,
  tmdbId,
}

class SubtitleContentContext {
  const SubtitleContentContext({
    required this.contentKey,
    required this.isSeries,
    required this.title,
    this.tmdbId,
    this.imdbId,
    this.year,
    this.season,
    this.episode,
    this.fileName,
  });

  final String contentKey;
  final bool isSeries;
  final String title;
  final String? tmdbId;
  final String? imdbId;
  final int? year;
  final int? season;
  final int? episode;
  final String? fileName;
}

class SubtitleSearchQuery {
  const SubtitleSearchQuery({
    required this.searchBy,
    required this.query,
    required this.languageCode,
    required this.isSeries,
    this.season,
    this.episode,
    this.tmdbId,
    this.imdbId,
    this.title,
    this.year,
    this.fileName,
  });

  final SubtitleSearchBy searchBy;
  final String query;
  final String languageCode;
  final bool isSeries;
  final int? season;
  final int? episode;
  final String? tmdbId;
  final String? imdbId;
  final String? title;
  final int? year;
  final String? fileName;

  String cacheKey() {
    return [
      'cascade_v2',
      languageCode.toLowerCase(),
      isSeries ? 'tv' : 'movie',
      if (season != null) 's$season',
      if (episode != null) 'e$episode',
      'imdb${imdbId ?? ''}',
      'tmdb${tmdbId ?? ''}',
      'q${query.trim().toLowerCase()}',
      'title${(title ?? '').trim().toLowerCase()}',
      if (year != null) 'y$year',
      'file${(fileName ?? '').trim().toLowerCase()}',
      searchBy.name,
    ].join('|');
  }
}

class SubtitleResultItem {
  const SubtitleResultItem({
    required this.releaseName,
    required this.language,
    required this.downloads,
    required this.fileId,
  });

  final String releaseName;
  final String language;
  final int downloads;
  final int fileId;
}
