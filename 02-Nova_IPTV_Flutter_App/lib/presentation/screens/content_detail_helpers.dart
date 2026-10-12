import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Valid Xtream stream/series id for detail fetch and playback.
String? validIptvContentId(String? raw) {
  final id = (raw ?? '').trim();
  if (id.isEmpty || id.toLowerCase() == 'null') return null;
  return id;
}

bool isBlankMeta(String? value) {
  final t = (value ?? '').trim();
  return t.isEmpty || t.toLowerCase() == 'null' || t == '-';
}

String? pickMeta(String? primary, [String? fallback]) {
  if (!isBlankMeta(primary)) return primary!.trim();
  if (!isBlankMeta(fallback)) return fallback!.trim();
  return null;
}

/// Backdrop carousel sources: API backdrops → single backdrop → poster → list icon.
List<String> detailBackdropImages({
  List<String>? backdropPath,
  String? backdrop,
  String? poster,
  String? listFallback,
}) {
  final out = <String>[];
  void add(String? raw) {
    if (isBlankMeta(raw)) return;
    final t = raw!.trim();
    if (!out.contains(t)) out.add(t);
  }

  for (final s in backdropPath ?? const <String>[]) {
    add(s);
  }
  add(backdrop);
  add(poster);
  add(listFallback);
  return out;
}

Widget buildContentDetailLoadFailed({required VoidCallback onRetry}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'not_available'.tr,
            textAlign: TextAlign.center,
            style: Get.textTheme.titleMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: Text('license_invalid_retry'.tr),
          ),
        ],
      ),
    ),
  );
}
