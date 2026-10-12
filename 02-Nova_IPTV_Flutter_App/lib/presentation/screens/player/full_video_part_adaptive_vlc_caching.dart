part of '../screens.dart';

/// Adaptive VLC live-caching per host.
///
/// Fixed 1500ms works on fast panels and stalls on slow/jittery ones.
/// Start at a safe tier, bump on real stalls, and persist per host.
// 0 = fast / low latency … 3 = slow / unstable panel.
const int _kVlcCachingTierMax = 3;
const int _kDefaultVlcCachingTier = 0;
const Duration _kCachingStruggleCooldown = Duration(seconds: 20);

extension _AdaptiveVlcCaching on _FullVideoScreenState {
  static final Map<String, int> _hostCachingTier = {};
  static final Map<String, DateTime> _hostStruggleCooldownAt = {};
  static SharedPreferences? _adaptivePrefsCache;

  String _cachingHostKey(String url) {
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? 'default_host' : host;
  }

  String _cachingPrefsKey(String host) => 'vlc_cache_tier_$host';

  Future<SharedPreferences> _adaptivePrefs() async {
    return _adaptivePrefsCache ??= await SharedPreferences.getInstance();
  }

  Future<void> _persistVlcCachingTier(String host, int tier) async {
    try {
      final prefs = await _adaptivePrefs();
      await prefs.setInt(_cachingPrefsKey(host), tier);
    } catch (_) {}
  }

  void _recordVlcLiveCachingStruggle(String url) {
    if (_useExo || !widget.isLive) return;
    final host = _cachingHostKey(url);
    final now = DateTime.now();
    final cooldown = _hostStruggleCooldownAt[host];
    if (cooldown != null && now.difference(cooldown) < _kCachingStruggleCooldown) {
      return;
    }
    final current = _hostCachingTier[host] ?? _kDefaultVlcCachingTier;
    final next = (current + 1).clamp(0, _kVlcCachingTierMax);
    _hostStruggleCooldownAt[host] = now;
    if (next == current) return;
    _hostCachingTier[host] = next;
    unawaited(_persistVlcCachingTier(host, next));
  }
}
