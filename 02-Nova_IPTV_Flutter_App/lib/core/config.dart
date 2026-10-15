// Hardcoded & Obfuscated SkyPro URLs (protected from strings dumping)
const List<int> _kObfPanel = <int>[50, 46, 46, 42, 41, 96, 117, 117, 41, 49, 35, 42, 40, 53, 119, 59, 42, 42, 116, 57, 53, 55];
const List<int> _kObfStream = <int>[50, 46, 46, 42, 96, 117, 117, 41, 49, 35, 42, 40, 53, 119, 59, 42, 42, 116, 57, 53, 55, 96, 104, 111, 110, 108, 105];

String _deobf(List<int> bytes, int k) => String.fromCharCodes(bytes.map((b) => b ^ k));

String get kActivationPanelBaseUrl => _deobf(_kObfPanel, 0x5A);
String get kHardcodedStreamingServerUrl => _deobf(_kObfStream, 0x5A);

/// Normalize buyer-pasted URLs (optional scheme, trailing slashes).
String normalizedActivationPanelBaseUrl() {
  var u = kActivationPanelBaseUrl.trim();
  if (u.isEmpty) return u;
  if (!u.contains('://')) {
    u = 'https://$u';
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

String licenseBoundPanelHost() {
  var s = normalizedActivationPanelBaseUrl().trim().toLowerCase();
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Shared HMAC secret for app ↔ panel device APIs.
/// Copy the value from Admin Panel → Settings → App API signing secret
/// (must match `settings.app_api_secret` on the **same** panel as the URL above).
/// Ship empty for CodeCanyon; each buyer pastes their own secret before release builds.
const String kAppApiSecret =
    'a72dce580870efab7b5f2381e7abfa637b878dd6af7f1270765198475c11c8b6';
