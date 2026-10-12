import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

import '../../helpers/helpers.dart';
import '../../services/tmdb_rating_service.dart';

/// Fetches TMDB rating when IPTV metadata rating is missing or zero.
class TmdbResolvedRatingCard extends StatefulWidget {
  const TmdbResolvedRatingCard({
    super.key,
    required this.image,
    required this.iptvRating,
    this.serverUrl,
    this.tmdbId,
    this.isSeries = false,
    this.contentKey,
    this.title,
    this.year,
    required this.ratingCardBuilder,
  });

  final String image;
  final String? iptvRating;
  final String? serverUrl;
  final String? tmdbId;
  final bool isSeries;
  final String? contentKey;
  final String? title;
  final int? year;
  final Widget Function(String rate) ratingCardBuilder;

  @override
  State<TmdbResolvedRatingCard> createState() => _TmdbResolvedRatingCardState();
}

class _TmdbResolvedRatingCardState extends State<TmdbResolvedRatingCard> {
  late Future<String> _rateFuture;

  @override
  void initState() {
    super.initState();
    _rateFuture = TmdbRatingService.instance.resolveStarRating5(
      iptvRating: widget.iptvRating,
      tmdbId: widget.tmdbId,
      isSeries: widget.isSeries,
      contentKey: widget.contentKey,
      title: widget.title,
      year: widget.year,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _rateFuture,
      builder: (context, snapshot) {
        final rate = snapshot.data ?? widget.iptvRating ?? '0';
        return widget.ratingCardBuilder(rate);
      },
    );
  }
}

/// TMDB fallback badge for poster cards (lists, favourites, home).
class TmdbPosterRatingBadge extends StatefulWidget {
  const TmdbPosterRatingBadge({
    super.key,
    this.rating,
    this.rating5based,
    this.contentKey,
    this.title,
    this.year,
    this.tmdbId,
    this.isSeries = false,
  });

  final String? rating;
  final String? rating5based;
  final String? contentKey;
  final String? title;
  final int? year;
  final String? tmdbId;
  final bool isSeries;

  @override
  State<TmdbPosterRatingBadge> createState() => _TmdbPosterRatingBadgeState();
}

class _TmdbPosterRatingBadgeState extends State<TmdbPosterRatingBadge> {
  late Future<String?> _ratingFuture;

  @override
  void initState() {
    super.initState();
    _ratingFuture = _loadRating();
  }

  @override
  void didUpdateWidget(covariant TmdbPosterRatingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rating != widget.rating ||
        oldWidget.rating5based != widget.rating5based ||
        oldWidget.contentKey != widget.contentKey ||
        oldWidget.title != widget.title ||
        oldWidget.year != widget.year ||
        oldWidget.tmdbId != widget.tmdbId ||
        oldWidget.isSeries != widget.isSeries) {
      _ratingFuture = _loadRating();
    }
  }

  Future<String?> _loadRating() {
    if (TmdbRatingService.needsTmdbFallback(widget.rating, widget.rating5based)) {
      final hasContentKey =
          widget.contentKey != null && widget.contentKey!.trim().isNotEmpty;
      final hasTmdbId =
          widget.tmdbId != null && widget.tmdbId!.trim().isNotEmpty;
      if (!hasContentKey && !hasTmdbId) {
        return Future.value(null);
      }
    }

    return TmdbRatingService.instance.resolveDisplayRating10(
      rating: widget.rating,
      rating5based: widget.rating5based,
      tmdbId: widget.tmdbId,
      isSeries: widget.isSeries,
      contentKey: widget.contentKey,
      title: widget.title,
      year: widget.year ?? extractReleaseYear(widget.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iptv = formatContentRating(widget.rating, widget.rating5based);
    if (iptv != null) {
      return _badge(iptv);
    }

    return FutureBuilder<String?>(
      future: _ratingFuture,
      builder: (context, snapshot) {
        final text = snapshot.data;
        if (text == null || text.isEmpty) return _badge('-.-');
        return _badge(text);
      },
    );
  }

  Widget _badge(String text) {
    return Positioned(
      top: 0,
      left: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: const BoxDecoration(
          color: Color(0xFF3B9EFF),
          borderRadius: BorderRadius.only(bottomRight: Radius.circular(8)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11.sp,
            height: 1,
          ),
        ),
      ),
    );
  }
}
