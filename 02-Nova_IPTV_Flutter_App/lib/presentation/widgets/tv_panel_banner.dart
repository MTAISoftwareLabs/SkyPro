import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Panel-driven TV banner (image or HTML). Used when AdMob is unavailable on TV.
class TvPanelBanner extends StatefulWidget {
  const TvPanelBanner({
    super.key,
    required this.imageUrl,
    required this.clickUrl,
    required this.htmlUrl,
    this.padding = EdgeInsets.zero,
    this.excludeFocus = false,
    this.height = 50,
    this.maxWidth = 320,
  });

  final String? imageUrl;
  final String? clickUrl;
  final String? htmlUrl;
  final EdgeInsetsGeometry padding;
  final bool excludeFocus;
  final double height;
  final double maxWidth;

  @override
  State<TvPanelBanner> createState() => _TvPanelBannerState();
}

class _TvPanelBannerState extends State<TvPanelBanner> {
  WebViewController? _web;
  bool _webReady = false;
  bool _imageFailed = false;

  String get _image => (widget.imageUrl ?? '').trim();
  String get _html => (widget.htmlUrl ?? '').trim();
  String get _click => (widget.clickUrl ?? '').trim();

  bool get _useImage => _image.isNotEmpty && !_imageFailed;
  bool get _useHtml => !_useImage && _html.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_useHtml) _initWeb();
  }

  @override
  void didUpdateWidget(covariant TvPanelBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.htmlUrl != widget.htmlUrl) {
      _imageFailed = false;
      _web = null;
      _webReady = false;
      if (_useHtml) _initWeb();
    }
  }

  void _initWeb() {
    final url = _html;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (kDebugMode) debugPrint('[Ads] TV HTML banner invalid url=$url');
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _webReady = true);
          },
          onWebResourceError: (err) {
            if (kDebugMode) {
              debugPrint('[Ads] TV HTML banner error: ${err.description}');
            }
          },
          onNavigationRequest: (req) {
            // Keep first load inside the WebView; open later navigations externally.
            if (req.isMainFrame &&
                req.url != url &&
                !req.url.startsWith(url)) {
              final u = Uri.tryParse(req.url);
              if (u != null) {
                unawaited(_launch(u));
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(uri);
    _web = c;
  }

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[Ads] TV banner launch failed: $e');
    }
  }

  Future<void> _onTap() async {
    if (_click.isEmpty) return;
    final uri = Uri.tryParse(_click);
    if (uri == null) return;
    await _launch(uri);
  }

  void _onImageError() {
    if (!mounted || _imageFailed) return;
    setState(() {
      _imageFailed = true;
      if (_html.isNotEmpty && _web == null) _initWeb();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_useImage && !_useHtml) return const SizedBox.shrink();

    final w = widget.maxWidth;
    final h = widget.height;

    Widget child;
    if (_useImage) {
      child = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _click.isEmpty ? null : _onTap,
          child: Image.network(
            _image,
            width: w,
            height: h,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _onImageError());
              return SizedBox(width: w, height: h);
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(width: w, height: h);
            },
          ),
        ),
      );
    } else {
      final web = _web;
      child = SizedBox(
        width: w,
        height: h,
        child: web == null
            ? const SizedBox.shrink()
            : Opacity(
                opacity: _webReady ? 1 : 0,
                child: WebViewWidget(controller: web),
              ),
      );
    }

    child = Center(
      child: SizedBox(width: w, height: h, child: child),
    );

    if (widget.excludeFocus) {
      child = ExcludeFocus(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          child: child,
        ),
      );
    }

    return Padding(padding: widget.padding, child: child);
  }
}
