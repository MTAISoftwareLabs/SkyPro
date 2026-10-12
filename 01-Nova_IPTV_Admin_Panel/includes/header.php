<?php
// الهيدر الموحد للوحة التحكم - تصميم عصري وأنيق مع دعم تعدد اللغات
// استخدم $current_page = 'index' | 'add_device' | 'settings' | 'edit' | 'manage' قبل تضمين الهيدر
if (!isset($current_page)) {
    $current_page = '';
}

require_once __DIR__ . '/lang.php';
require_once __DIR__ . '/admin_auth.php';

if (isset($conn) && function_exists('adminIsLoggedIn') && adminIsLoggedIn() && !empty($_SESSION['admin_user_id'])) {
    adminRefreshSessionFromDb($conn);
}

// Refuse normal panel use until buyer sets App API secret + credential encryption key.
$adminSecurityKeysMissing = false;
if (isset($conn) && function_exists('adminIsLoggedIn') && adminIsLoggedIn()) {
    require_once __DIR__ . '/api_auth.php';
    require_once __DIR__ . '/credential_crypto.php';
    $apiSec = function_exists('app_api_get_secret') ? app_api_get_secret($conn) : '';
    $credOk = function_exists('credential_is_configured') && credential_is_configured($conn);
    $adminSecurityKeysMissing = ($apiSec === '' || !$credOk);
    // التحويل الرئيسي يتم مبكراً من adminBootstrapLogin قبل HTML.
    // هنا احتياط فقط إن وُجدت صفحة لم تستدعِه.
    if ($adminSecurityKeysMissing && ($current_page ?? '') !== 'settings') {
        if (function_exists('adminRedirectIfSecurityKeysMissing')) {
            adminRedirectIfSecurityKeysMissing($conn);
        } elseif (!headers_sent()) {
            header('Location: settings.php?security_setup=1');
            exit;
        } else {
            $target = 'settings.php?security_setup=1';
            echo '<script>location.replace(' . json_encode($target) . ');</script>';
            echo '<noscript><meta http-equiv="refresh" content="0;url=' . htmlspecialchars($target, ENT_QUOTES, 'UTF-8') . '"></noscript>';
            exit;
        }
    }
}

$unreadFeedbackCount = 0;
if (isset($conn) && function_exists('getUnreadFeedbackCount')) {
    try {
        $unreadFeedbackCount = getUnreadFeedbackCount($conn);
    } catch (Throwable $e) {
        $unreadFeedbackCount = 0;
    }
}

$expiringDevicesCount = 0;
if (isset($conn) && function_exists('getExpiringSoonDevicesCount')) {
    try {
        $expiringDevicesCount = getExpiringSoonDevicesCount($conn, 7);
    } catch (Throwable $e) {
        $expiringDevicesCount = 0;
    }
}
?>
<link rel="stylesheet" href="assets/css/admin-responsive.css?v=20260816a">
<link rel="stylesheet" href="assets/css/admin-confirm.css">
<?php if (function_exists('adminIsLoggedIn') && adminIsLoggedIn() && function_exists('admin_csrf_meta_tag')): ?>
<?php echo admin_csrf_meta_tag(); ?>
<script>
window.ADMIN_CSRF_TOKEN = <?php echo json_encode(admin_csrf_token(), JSON_UNESCAPED_UNICODE); ?>;
(function () {
  function injectCsrf(root) {
    var token = window.ADMIN_CSRF_TOKEN || '';
    if (!token) return;
    (root || document).querySelectorAll('form').forEach(function (form) {
      var method = (form.getAttribute('method') || 'get').toLowerCase();
      if (method !== 'post') return;
      var existing = form.querySelector('input[name="csrf_token"]');
      if (existing) {
        existing.value = token;
        return;
      }
      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'csrf_token';
      input.value = token;
      form.appendChild(input);
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { injectCsrf(document); });
  } else {
    injectCsrf(document);
  }
  window.adminCsrfHeaders = function (extra) {
    var h = Object.assign({}, extra || {});
    if (window.ADMIN_CSRF_TOKEN) h['X-CSRF-Token'] = window.ADMIN_CSRF_TOKEN;
    return h;
  };
  window.adminAppendCsrf = function (body) {
    if (!window.ADMIN_CSRF_TOKEN) return body;
    if (body instanceof FormData) {
      if (!body.has('csrf_token')) body.append('csrf_token', window.ADMIN_CSRF_TOKEN);
      return body;
    }
    if (body && typeof body === 'object' && typeof body.set === 'function') {
      body.set('csrf_token', window.ADMIN_CSRF_TOKEN);
      return body;
    }
    return body;
  };
})();
</script>
<?php endif; ?>
<style>
html, body { margin: 0; padding: 0; }
body {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    font-family: 'Cairo', system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: radial-gradient(circle at top left, #1e3c72 0, #2a5298 20%, #0b1723 55%, #050811 100%);
    color: #ecf0f1;
}

/* هيكل الصفحة العام للوحة التحكم */
.admin-main {
    flex: 1 0 auto;
    padding-top: 32px;
    padding-bottom: 32px;
    width: 100%;
    max-width: 100%;
    box-sizing: border-box;
}
.admin-navbar .navbar-toggler {
    border-color: rgba(148,163,184,0.45);
    padding: 0.45rem 0.65rem;
    border-radius: 10px;
}
.admin-navbar .navbar-toggler:focus {
    box-shadow: 0 0 0 0.2rem rgba(56,189,248,0.35);
}

.admin-shell-card {
    border-radius: 18px;
    background: radial-gradient(circle at top left, rgba(255,255,255,0.12), rgba(10,14,27,0.96));
    box-shadow:
        0 20px 45px rgba(0,0,0,0.55),
        0 0 0 1px rgba(255,255,255,0.02);
    border: 1px solid rgba(255,255,255,0.08);
    backdrop-filter: blur(18px);
}

.page-header {
    margin-bottom: 1.75rem;
}
.page-header-title {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    font-weight: 700;
    font-size: 1.4rem;
    color: #f9fafb;
}
.page-header-subtitle {
    margin-top: .25rem;
    color: #9ca3af;
    font-size: 0.95rem;
}

/* شريط التنقل العلوي */
.admin-navbar {
    background: radial-gradient(circle at top left, #17253b 0%, #020617 55%, #000 100%) !important;
    box-shadow:
        0 18px 40px rgba(0,0,0,0.55),
        0 0 0 1px rgba(148,163,184,0.15);
    top: 0;
    margin: 0;
    backdrop-filter: blur(20px);
    border-bottom: 1px solid rgba(148,163,184,0.25);
}
/* صف داخلي: الشعار في عمود منفصل بحد فاصل — يحرّر مساحة لروابط الأقسام */
.admin-navbar-inner {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    width: 100%;
}
.admin-navbar .navbar-brand.navbar-brand-pillar {
    font-weight: 700;
    display: inline-flex;
    align-items: center;
    gap: .5rem;
    letter-spacing: .02em;
    flex-shrink: 0;
    margin: 0;
    padding-top: 0.35rem;
    padding-bottom: 0.35rem;
}
.admin-navbar .navbar-brand-pillar i {
    color: #38bdf8;
    text-shadow: 0 0 12px rgba(56,189,248,0.8);
}
@media (min-width: 992px) {
    .admin-navbar-inner {
        flex-wrap: nowrap;
        gap: 0;
    }
    .admin-navbar .navbar-brand-pillar {
        padding-inline-end: 1.1rem;
        margin-inline-end: 1.1rem;
        border-inline-end: 1px solid rgba(148, 163, 184, 0.4);
        white-space: nowrap;
    }
    .admin-navbar #navbarNav.admin-navbar-collapse-main {
        flex: 1 1 0;
        min-width: 0;
    }
    .admin-navbar .navbar-nav-main {
        flex-wrap: nowrap !important;
    }
    .admin-navbar .navbar-nav-tools {
        flex-wrap: nowrap !important;
    }
}
@media (max-width: 991.98px) {
    .admin-navbar .navbar-brand-pillar {
        border-inline-end: none;
        margin-inline-end: 0;
        padding-inline-end: 0;
    }
    .admin-navbar .navbar-toggler.navbar-toggler-end {
        margin-inline-start: auto;
    }
}
.admin-navbar .nav-link {
    border-radius: 999px;
    padding: 7px 14px !important;
    font-size: 0.95rem;
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    color: #e5e7eb !important;
    transition: background 0.18s ease, color 0.18s ease, transform 0.14s ease;
}
.admin-navbar .nav-link i {
    font-size: 0.9rem;
}
.admin-navbar .nav-link:hover {
    background: rgba(148,163,184,0.18);
    color: #ffffff !important;
    transform: translateY(-1px);
}
.admin-navbar .nav-link.active {
    background: linear-gradient(135deg, #38bdf8, #6366f1);
    color: #0b1120 !important;
    box-shadow: 0 8px 18px rgba(37,99,235,0.45);
    font-weight: 600;
}

/* مبدّل اللغة العصري في الهيدر */
.lang-toggle {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 6px;
    border-radius: 999px;
    background: radial-gradient(circle at top left, rgba(15,23,42,0.95), rgba(15,23,42,0.9));
    border: 1px solid rgba(148,163,184,0.6);
    box-shadow: 0 8px 18px rgba(15,23,42,0.9);
}
.lang-toggle-icon {
    width: 22px;
    height: 22px;
    border-radius: 999px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: radial-gradient(circle at top, rgba(56,189,248,0.9), rgba(37,99,235,0.95));
    color: #0b1120;
    font-size: 0.8rem;
    box-shadow: 0 0 12px rgba(56,189,248,0.9);
}
.lang-toggle-buttons {
    display: inline-flex;
    border-radius: 999px;
    overflow: hidden;
}
.lang-toggle-btn {
    padding: 5px 12px;
    font-size: 0.78rem;
    border: none;
    background: transparent;
    color: #e5e7eb;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 44px;
    max-width: 110px;
    white-space: nowrap;
    transition: background 0.16s ease, color 0.16s ease;
}
[dir="rtl"] .lang-toggle-btn {
    font-size: 0.8rem;
    max-width: none;
    padding-inline: 10px;
}
.lang-toggle-btn.active {
    background: linear-gradient(135deg, #38bdf8, #6366f1);
    color: #0b1120;
    font-weight: 600;
}
.lang-toggle-btn:not(.active):hover {
    background: rgba(148,163,184,0.22);
}

/* تخطيط الشريط: روابط الأقسام في المنتصف، الأدوات على الطرف */
.admin-navbar .navbar-collapse .navbar-nav-tools {
    flex-shrink: 0;
}
.admin-navbar .navbar-collapse-inner {
    width: 100%;
}
.admin-navbar-center-shell {
    flex: 1 1 auto;
    min-width: 0;
    display: flex;
    justify-content: center;
    align-items: center;
}
@media (min-width: 992px) {
    .admin-navbar .navbar-collapse-inner {
        flex-wrap: nowrap;
        align-items: center;
        justify-content: flex-start;
        gap: 0.5rem 0.75rem;
    }
    .admin-navbar .navbar-nav-main {
        justify-content: center;
        row-gap: 0.35rem;
    }
}
@media (max-width: 991.98px) {
    .admin-navbar-center-shell {
        justify-content: stretch;
        width: 100%;
        order: 2;
    }
    .admin-navbar .navbar-nav-tools {
        order: 3;
    }
    .admin-navbar .navbar-collapse-inner {
        flex-direction: column;
        align-items: stretch !important;
        gap: 0.75rem;
        padding-top: 0.5rem;
    }
    .admin-navbar .navbar-nav-main {
        justify-content: flex-start;
    }
    [dir="rtl"] .admin-navbar .navbar-nav-main {
        justify-content: flex-end;
    }
    .admin-navbar .navbar-nav-main .nav-item {
        width: 100%;
    }
    .admin-navbar .navbar-nav-main .nav-link {
        width: 100%;
        justify-content: flex-start;
    }
    [dir="rtl"] .admin-navbar .navbar-nav-main .nav-link {
        justify-content: flex-end;
        text-align: right;
    }
    .admin-navbar .navbar-nav-tools {
        flex-wrap: wrap;
        justify-content: center;
        border-top: 1px solid rgba(148,163,184,0.2);
        padding-top: 0.75rem;
        margin-top: 0.25rem;
    }
    [dir="rtl"] .admin-navbar .navbar-nav-tools {
        justify-content: center;
    }
}
/* أسماء عربية أطول: السماح بالتفاف مناسب */
.admin-navbar .navbar-nav .nav-link {
    max-width: 100%;
    white-space: normal;
    line-height: 1.35;
    text-align: start;
}
[dir="rtl"] .admin-navbar .navbar-nav .nav-link {
    text-align: right;
}

.notif-link {
    position: relative;
    width: 38px;
    height: 38px;
    border-radius: 999px !important;
    display: inline-flex !important;
    align-items: center;
    justify-content: center;
    background: rgba(15,23,42,0.88);
    border: 1px solid rgba(148,163,184,0.35);
}
.notif-link i {
    font-size: 0.95rem;
}
.notif-link--log {
    background: linear-gradient(145deg, rgba(14,165,233,0.18), rgba(99,102,241,0.16));
    border-color: rgba(56,189,248,0.42);
}
.notif-link--log i {
    background: linear-gradient(135deg, #38bdf8, #818cf8);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    -webkit-text-fill-color: transparent;
}
.notif-link--log.active,
.notif-link.active {
    border-color: rgba(56,189,248,0.75);
    box-shadow: 0 0 0 1px rgba(24, 24, 24, 0.9), 0 8px 18px rgba(2,6,23,0.45);
}
.notif-badge {
    position: absolute;
    top: -6px;
    right: -6px;
    min-width: 19px;
    height: 19px;
    border-radius: 999px;
    background: linear-gradient(135deg, #ef4444, #dc2626);
    color: #fff;
    font-size: 0.72rem;
    font-weight: 700;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0 5px;
    box-shadow: 0 0 12px rgba(239,68,68,0.7);
}
[dir="rtl"] .notif-badge {
    right: auto;
    left: -6px;
}

/* فوتر موحد بتصميم داكن أنيق */
.admin-footer {
    background: radial-gradient(circle at top, #020617, #020617 40%, #000000 100%);
    color: #9ca3af;
    padding: 14px 0;
    margin-top: 32px;
    border-top: 1px solid rgba(148,163,184,0.35);
    font-size: 0.88rem;
    flex-shrink: 0;
}
.admin-footer a {
    color: #eab308;
    text-decoration: none;
    font-weight: 600;
}
.admin-footer a:hover {
    text-decoration: underline;
    color: #facc15;
}
</style>
<nav class="navbar navbar-expand-lg navbar-dark admin-navbar sticky-top">
    <div class="container-fluid px-3 px-lg-4 admin-navbar-inner">
        <a class="navbar-brand navbar-brand-pillar d-inline-flex align-items-center gap-2" href="index.php">
            <i class="fas fa-shield-alt"></i><span class="navbar-brand-text"><?php echo t('app.title'); ?></span>
        </a>
        <button class="navbar-toggler navbar-toggler-end" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" aria-controls="navbarNav" aria-expanded="false" aria-label="القائمة">
            <span class="navbar-toggler-icon"></span>
        </button>
        <div class="collapse navbar-collapse admin-navbar-collapse-main" id="navbarNav">
            <div class="d-flex flex-column flex-lg-row navbar-collapse-inner align-items-lg-center">
            <div class="admin-navbar-center-shell">
            <ul class="navbar-nav navbar-nav-main flex-wrap">
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'index' ? 'active' : ''; ?>" href="index.php">
                        <i class="fas fa-home"></i><span><?php echo t('nav.home'); ?></span>
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'add_device' ? 'active' : ''; ?>" href="add_device.php">
                        <i class="fas fa-plus-circle"></i><span><?php echo t('nav.add_device'); ?></span>
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'admin_users' ? 'active' : ''; ?>" href="admin_users.php">
                        <i class="fas fa-user-shield"></i><span><?php echo t('nav.admin_users'); ?></span>
                    </a>
                </li>
                <?php if (file_exists(__DIR__ . '/../manage_activations.php')): ?>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'manage' ? 'active' : ''; ?>" href="manage_activations.php">
                        <i class="fas fa-list"></i><span><?php echo t('nav.manage'); ?></span>
                    </a>
                </li>
                <?php endif; ?>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'playlist_codes' ? 'active' : ''; ?>" href="playlist_codes.php">
                        <i class="fas fa-qrcode"></i><span><?php echo t('nav.playlist_codes'); ?></span>
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'settings' ? 'active' : ''; ?>" href="settings.php">
                        <i class="fas fa-cog"></i><span><?php echo t('nav.settings'); ?></span>
                    </a>
                </li>
                <?php if (adminCan('notifications_send')): ?>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo $current_page === 'notifications' ? 'active' : ''; ?>" href="notifications.php">
                        <i class="fas fa-bell"></i><span><?php echo t('nav.notifications'); ?></span>
                    </a>
                </li>
                <?php endif; ?>
            </ul>
            </div>
            <ul class="navbar-nav navbar-nav-tools align-items-center flex-row flex-wrap gap-2">
                <li class="nav-item d-flex align-items-center gap-2">
                    <a class="nav-link notif-link py-2 <?php echo $current_page === 'expiring' ? 'active' : ''; ?>"
                       href="expiring-devices.php"
                       title="<?php echo htmlspecialchars(t('nav.expiry_alerts')); ?>">
                        <i class="fas fa-hourglass-half"></i>
                        <?php if ($expiringDevicesCount > 0): ?>
                            <span class="notif-badge" style="background:linear-gradient(135deg,#f59e0b,#d97706);box-shadow:0 0 12px rgba(245,158,11,0.65);"><?php echo $expiringDevicesCount; ?></span>
                        <?php endif; ?>
                    </a>
                    <a class="nav-link notif-link py-2 <?php echo $current_page === 'feedbacks' ? 'active' : ''; ?>"
                       href="feedbacks.php"
                       title="<?php echo htmlspecialchars(t('nav.feedbacks')); ?>">
                        <i class="fas fa-bell"></i>
                        <?php if ($unreadFeedbackCount > 0): ?>
                            <span class="notif-badge"><?php echo $unreadFeedbackCount; ?></span>
                        <?php endif; ?>
                    </a>
                    <a class="nav-link notif-link notif-link--log py-2 <?php echo $current_page === 'activity_log' ? 'active' : ''; ?>"
                       href="activity_log.php"
                       title="<?php echo htmlspecialchars(t('nav.activity_log')); ?>">
                        <i class="fas fa-clock-rotate-left"></i>
                    </a>
                </li>
                <li class="nav-item d-flex align-items-center">
                    <div class="lang-toggle">
                        <span class="lang-toggle-icon">
                            <i class="fas fa-globe"></i>
                        </span>
                        <div class="lang-toggle-buttons">
                            <a href="<?php echo build_lang_url('ar'); ?>"
                               class="lang-toggle-btn <?php echo $lang === 'ar' ? 'active' : ''; ?>">
                                <?php echo t('lang.name_ar'); ?>
                            </a>
                            <a href="<?php echo build_lang_url('en'); ?>"
                               class="lang-toggle-btn <?php echo $lang === 'en' ? 'active' : ''; ?>">
                                <?php echo t('lang.name_en'); ?>
                            </a>
                        </div>
                    </div>
                </li>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2 <?php echo ($current_page ?? '') === 'profile' ? 'active' : ''; ?>" href="admin_profile.php">
                        <i class="fas fa-user-circle"></i><span><?php echo t('nav.profile'); ?></span>
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link d-inline-flex align-items-center gap-2" href="logout.php">
                        <i class="fas fa-sign-out-alt"></i><span><?php echo t('nav.logout'); ?></span>
                    </a>
                </li>
            </ul>
            </div>
        </div>
    </div>
</nav>
<?php if (!empty($adminSecurityKeysMissing)): ?>
<div class="container-fluid px-3 pt-3">
    <div class="alert alert-warning mb-0">
        <i class="fas fa-shield-halved me-2"></i><?php echo t('settings.security_keys_required_banner'); ?>
    </div>
</div>
<?php endif; ?>
<?php
if (function_exists('adminIsLoggedIn') && adminIsLoggedIn() && function_exists('adminClientPermissionKeys')) {
    $deniedJs = ['_generic' => t('denied.perm.generic')];
    foreach (adminClientPermissionKeys() as $pk) {
        $mk = 'denied.perm.' . $pk;
        $deniedJs[$pk] = t($mk);
        if ($deniedJs[$pk] === $mk) {
            $deniedJs[$pk] = $deniedJs['_generic'];
        }
    }
    echo '<script>window.ADMIN_PERMS=' . json_encode(adminClientPermissionMap(), JSON_UNESCAPED_UNICODE) . ';';
    echo 'window.ADMIN_DENIED_TITLE=' . json_encode(t('denied.modal_title'), JSON_UNESCAPED_UNICODE) . ';';
    echo 'window.ADMIN_DENIED_BTN=' . json_encode(t('denied.modal_btn'), JSON_UNESCAPED_UNICODE) . ';';
    echo 'window.ADMIN_DENIED_MESSAGES=' . json_encode($deniedJs, JSON_UNESCAPED_UNICODE) . ';</script>';
}
?>
