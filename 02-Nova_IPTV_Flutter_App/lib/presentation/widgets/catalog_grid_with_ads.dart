import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mehdi_iptv/presentation/widgets/app_banner_ad.dart';
import 'package:mehdi_iptv/services/ads_service.dart';

/// Poster grid with AdMob banners in **separate sections** after full row groups.
///
/// First banner after [firstRowsPerBanner] rows, then each next gap grows by
/// [rowsStep] (e.g. 5 → 6 → 7 → …).
///
/// Preloads compact banners on open so the first ad is ready before scroll.
class CatalogGridWithAds extends StatefulWidget {
  const CatalogGridWithAds({
    super.key,
    required this.itemCount,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.itemBuilder,
    this.controller,
    this.cacheExtent,
    this.padding = EdgeInsets.zero,
    this.crossAxisSpacing = 10,
    this.mainAxisSpacing = 10,
    this.firstRowsPerBanner = 5,
    this.rowsStep = 1,
  });

  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final double? cacheExtent;
  final EdgeInsetsGeometry padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final int firstRowsPerBanner;
  final int rowsStep;

  @override
  State<CatalogGridWithAds> createState() => _CatalogGridWithAdsState();
}

class _CatalogGridWithAdsState extends State<CatalogGridWithAds> {
  @override
  void initState() {
    super.initState();
    if (AdsService.shouldShowBanner(AppBannerPlacement.catalog)) {
      unawaited(AdsService.preloadCompactBanners());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.crossAxisCount < 1 ? 1 : widget.crossAxisCount;
    final showAds =
        AdsService.shouldShowBanner(AppBannerPlacement.catalog) &&
        widget.itemCount > 0 &&
        widget.firstRowsPerBanner > 0;

    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      crossAxisSpacing: widget.crossAxisSpacing,
      mainAxisSpacing: widget.mainAxisSpacing,
      childAspectRatio: widget.childAspectRatio,
    );

    if (!showAds) {
      return GridView.builder(
        controller: widget.controller,
        padding: widget.padding,
        cacheExtent: widget.cacheExtent,
        addAutomaticKeepAlives: false,
        addSemanticIndexes: false,
        itemCount: widget.itemCount,
        gridDelegate: gridDelegate,
        itemBuilder: widget.itemBuilder,
      );
    }

    final totalRows = (widget.itemCount + cols - 1) ~/ cols;
    final entries = _buildEntries(totalRows);
    // ما نوسّعوش الكاش لـ 2400: كيبني صفوف بعيدة وكيطيّح الإطار على TV/الأجهزة الضعيفة.
    final cacheExtent = widget.cacheExtent ?? 160;

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = widget.padding.resolve(Directionality.of(context));
        final gridWidth = (constraints.maxWidth - pad.left - pad.right)
            .clamp(1.0, double.infinity);
        final cellWidth =
            (gridWidth - widget.crossAxisSpacing * (cols - 1)) / cols;
        final cellHeight = cellWidth / widget.childAspectRatio;

        return ListView.builder(
          controller: widget.controller,
          padding: widget.padding,
          cacheExtent: cacheExtent,
          addAutomaticKeepAlives: false,
          addSemanticIndexes: false,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            if (e.isBanner) {
              return const _CatalogBannerSection();
            }

            final row = e.rowIndex;
            final start = row * cols;
            final children = <Widget>[];
            for (var c = 0; c < cols; c++) {
              final itemIndex = start + c;
              if (c > 0) {
                children.add(SizedBox(width: widget.crossAxisSpacing));
              }
              if (itemIndex < widget.itemCount) {
                children.add(
                  SizedBox(
                    width: cellWidth,
                    height: cellHeight,
                    child: KeyedSubtree(
                      key: ValueKey('cat-item-$itemIndex'),
                      child: widget.itemBuilder(context, itemIndex),
                    ),
                  ),
                );
              } else {
                children.add(SizedBox(width: cellWidth, height: cellHeight));
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: row < totalRows - 1 ? widget.mainAxisSpacing : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            );
          },
        );
      },
    );
  }

  List<_CatalogEntry> _buildEntries(int totalRows) {
    final out = <_CatalogEntry>[];
    var row = 0;
    var bannerIndex = 0;
    while (row < totalRows) {
      final gap = widget.firstRowsPerBanner + (bannerIndex * widget.rowsStep);
      final rows = gap < 1 ? 1 : gap;
      final end = (row + rows) > totalRows ? totalRows : (row + rows);
      for (var r = row; r < end; r++) {
        out.add(_CatalogEntry.row(r));
      }
      row = end;
      if (row < totalRows) {
        out.add(const _CatalogEntry.banner());
        bannerIndex++;
      }
    }
    return out;
  }
}

class _CatalogEntry {
  const _CatalogEntry.row(this.rowIndex) : isBanner = false;
  const _CatalogEntry.banner()
      : rowIndex = -1,
        isBanner = true;

  final int rowIndex;
  final bool isBanner;
}

class _CatalogBannerSection extends StatelessWidget {
  const _CatalogBannerSection();

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(height: 14),
              const Center(
                child: AppBannerAd(
                  placement: AppBannerPlacement.catalog,
                  compact: true,
                  showOnTv: true,
                  excludeFocus: true,
                  reserveHeight: true,
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
