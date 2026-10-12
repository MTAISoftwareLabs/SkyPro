/// Default IPTV / Xtream server URL is **not** set here — configure
/// Examples: `https://panel.yourdomain.com` or `https://yourdomain.com/admin`
const String kActivationPanelBaseUrl = 'Your_Admin_Panel_Url';

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
    'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
