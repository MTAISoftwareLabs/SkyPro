<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';
require_once __DIR__ . '/includes/onesignal_push.php';

$current_page = 'settings';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$success = $error = '';
$canEditSettings = adminCan('settings');
$isGuest = adminIsGuestRole();

require_once __DIR__ . '/includes/api_auth.php';
require_once __DIR__ . '/includes/credential_crypto.php';

// جلب الإعدادات الحالية
try {
    $settings = getSettings($conn);
} catch (PDOException $e) {
    $error = t('msg.db_error');
    $settings = [];
}

$isSettingsAjax = (
    (isset($_POST['settings_ajax']) && (string)$_POST['settings_ajax'] === '1')
    || (isset($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower((string)$_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest')
);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf($isSettingsAjax);
    if (!$canEditSettings) {
        if ($isSettingsAjax) {
            header('Content-Type: application/json; charset=utf-8');
            http_response_code(403);
            echo json_encode([
                'success' => false,
                'message' => t('msg.settings_no_permission'),
            ], JSON_UNESCAPED_UNICODE);
            exit;
        }
        header('Location: access_denied.php?perm=settings');
        exit;
    }

    $apiSecretAction = trim((string)($_POST['app_api_secret_action'] ?? ''));
    $credKeyAction = trim((string)($_POST['credential_enc_key_action'] ?? ''));
    if ($isGuest && ($apiSecretAction !== '' || $credKeyAction !== '')) {
        header('Location: access_denied.php?perm=settings');
        exit;
    }
    if ($apiSecretAction === 'regenerate') {
        $newSecret = app_api_regenerate_secret($conn);
        if ($newSecret !== '') {
            $success = t('msg.app_api_secret_regenerated');
            $settings = getSettings($conn);
        } else {
            $error = t('msg.db_error');
        }
    } elseif ($apiSecretAction === 'save_custom') {
        $custom = trim((string)($_POST['app_api_secret_custom'] ?? ''));
        if (strlen($custom) < 32 || strlen($custom) > 128) {
            $error = t('msg.app_api_secret_invalid');
        } else {
            try {
                app_api_ensure_secret_column($conn);
                $stmt = $conn->query("SELECT id FROM settings LIMIT 1");
                $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
                if ($row) {
                    $upd = $conn->prepare("UPDATE settings SET app_api_secret = ? WHERE id = ?");
                    $upd->execute([$custom, (int)$row['id']]);
                    $success = t('msg.app_api_secret_saved');
                    $settings = getSettings($conn);
                } else {
                    $error = t('msg.db_error');
                }
            } catch (PDOException $e) {
                $error = t('msg.db_error');
            }
        }
    } elseif ($credKeyAction === 'generate') {
        $newKey = credential_generate_and_save_key($conn);
        if ($newKey !== '') {
            $success = t('msg.credential_enc_key_generated');
            $settings = getSettings($conn);
            if (function_exists('credential_migrate_plaintext_passwords')) {
                credential_migrate_plaintext_passwords($conn);
            }
        } else {
            $error = t('msg.db_error');
        }
    } elseif (!empty($_POST['settings_partial']) && (string)$_POST['settings_partial'] === '1') {
        // AJAX quick-save: update only the named field(s), never the whole form.
        $fieldsRaw = $_POST['settings_fields'] ?? '[]';
        $fields = is_string($fieldsRaw) ? json_decode($fieldsRaw, true) : $fieldsRaw;
        if (!is_array($fields)) {
            $fields = [];
        }
        $checkboxFields = [
            'auto_block_expired', 'block_vpn_global', 'ads_enabled',
            'sync_activation_with_server', 'activation_enforced', 'block_screenshots', 'piracy_detection_enabled',
            'onesignal_enabled', 'hero_promo_enabled',
        ];
        $patch = [];
        foreach ($fields as $field) {
            if (!is_string($field) || $field === '') {
                continue;
            }
            if (in_array($field, $checkboxFields, true)) {
                $raw = $_POST[$field] ?? '0';
                $patch[$field] = ((string)$raw === '1' || $raw === 1 || $raw === true) ? 1 : 0;
            } elseif (array_key_exists($field, $_POST)) {
                $patch[$field] = $_POST[$field];
            }
        }
        if (isset($patch['onesignal_rest_api_key']) && trim((string)$patch['onesignal_rest_api_key']) === '') {
            unset($patch['onesignal_rest_api_key']);
        }
        try {
            if ($patch && updateSettingsPartial($conn, $patch)) {
                $success = t('msg.settings_saved');
                $settings = getSettings($conn);
            } else {
                $error = t('msg.settings_save_error');
            }
        } catch (PDOException $e) {
            $error = t('msg.db_error');
        }
    } elseif (!empty($_POST['save_login_servers']) && (string)$_POST['save_login_servers'] === '1') {
        $parsed = login_servers_from_post($_POST);
        if (empty($parsed['ok'])) {
            $error = (string) ($parsed['error'] ?? t('settings.login_server_url_invalid'));
        } else {
            $servers = $parsed['servers'] ?? [];
            try {
                save_login_servers($conn, $servers);
                $firstUrl = $servers[0]['url'] ?? '';
                updateSettingsPartial($conn, ['default_server_url' => $firstUrl]);
                $success = t('settings.login_servers_saved');
                $settings = getSettings($conn);
            } catch (PDOException $e) {
                $error = t('msg.db_error');
            }
        }
    } else {
    $app_name = $_POST['app_name'] ?? '';
    $default_expiry_days = $_POST['default_expiry_days'] ?? 30;
    $max_devices_per_user = $_POST['max_devices_per_user'] ?? 1;
    $auto_block_expired = isset($_POST['auto_block_expired']) ? 1 : 0;
    $block_vpn_global = isset($_POST['block_vpn_global']) ? 1 : 0;
    $default_server_url = $_POST['default_server_url'] ?? '';
    $ads_enabled = isset($_POST['ads_enabled']) ? 1 : 0;
    // Home banner removed — keep column at 0 for older app builds.
    $banner_home_only = 0;
    $banner_ad_unit_android = trim($_POST['banner_ad_unit_android'] ?? '');
    $banner_ad_unit_ios = trim($_POST['banner_ad_unit_ios'] ?? '');
    $interstitial_ad_unit_android = trim($_POST['interstitial_ad_unit_android'] ?? '');
    $interstitial_ad_unit_ios = trim($_POST['interstitial_ad_unit_ios'] ?? '');
    $admob_app_id_android = trim($_POST['admob_app_id_android'] ?? '');
    $admob_app_id_ios = trim($_POST['admob_app_id_ios'] ?? '');
    $tv_banner_image_url = trim($_POST['tv_banner_image_url'] ?? '');
    $tv_banner_click_url = trim($_POST['tv_banner_click_url'] ?? '');
    $tv_banner_html_url = trim($_POST['tv_banner_html_url'] ?? '');
    $hero_promo_enabled = isset($_POST['hero_promo_enabled']) ? 1 : 0;
    // أسماء بدون _url أولاً (جدران نارية) ثم الأسماء القديمة.
    $hero_promo_image_url = trim((string)($_POST['hero_promo_image'] ?? $_POST['hero_promo_image_url'] ?? ''));
    $hero_promo_title = trim((string)($_POST['hero_promo_title'] ?? ''));
    $hero_promo_text = trim((string)($_POST['hero_promo_text'] ?? ''));
    $hero_promo_link_url = trim((string)($_POST['hero_promo_link'] ?? $_POST['hero_promo_link_url'] ?? ''));
    $hero_banner_count = max(1, min(10, (int)($_POST['hero_banner_count'] ?? 5)));
    $hero_content_mode = hero_content_mode_normalize($_POST['hero_content_mode'] ?? 'auto');
    $sync_activation_with_server = isset($_POST['sync_activation_with_server']) ? 1 : 0;
    $app_version = trim($_POST['app_version'] ?? '1.0.0');
    $app_activation_url = trim($_POST['app_activation_url'] ?? '');
    $support_contact_url = trim($_POST['support_contact_url'] ?? '');
    $purchase_url = trim($_POST['purchase_url'] ?? '');
    $activation_enforced = isset($_POST['activation_enforced']) ? 1 : 0;
    $block_screenshots = isset($_POST['block_screenshots']) ? 1 : 0;
    $privacy_policy_url = trim($_POST['privacy_policy_url'] ?? '');
    $privacy_policy_html = (string)($_POST['privacy_policy_html'] ?? '');
    $privacy_policy_mode = (($_POST['privacy_policy_mode'] ?? 'url') === 'html') ? 'html' : 'url';
    $about_us_html = (string)($_POST['about_us_html'] ?? '');
    $tmdb_api_key = trim($_POST['tmdb_api_key'] ?? '');
    $opensubtitles_api_key = trim($_POST['opensubtitles_api_key'] ?? '');
    $opensubtitles_username = trim($_POST['opensubtitles_username'] ?? '');
    $opensubtitles_password = trim($_POST['opensubtitles_password'] ?? '');
    $piracy_detection_enabled = isset($_POST['piracy_detection_enabled']) ? 1 : 0;
    $piracy_packages = normalizePiracyPackagesText($_POST['piracy_packages'] ?? '');
    $piracy_message = trim((string)($_POST['piracy_message'] ?? ''));
    $onesignal_enabled = isset($_POST['onesignal_enabled']) ? 1 : 0;
    $onesignal_app_id = trim((string)($_POST['onesignal_app_id'] ?? ''));
    $onesignal_rest_api_key = trim((string)($_POST['onesignal_rest_api_key'] ?? ''));
    $loginParsed = login_servers_from_post($_POST);
    $loginServersOk = !empty($loginParsed['ok']);
    $loginServers = $loginServersOk ? ($loginParsed['servers'] ?? []) : [];
    if ($loginServersOk) {
        $default_server_url = $loginServers[0]['url'] ?? '';
    } else {
        $default_server_url = trim((string) ($settings['default_server_url'] ?? ''));
        // لا نوقف حفظ باقي الإعدادات (مثل الهيرو) بسبب خطأ سيرفرات الدخول.
        // نعرض التحذير فقط إن وُجدت صفوف سيرفر غير صالحة.
        $hasServerRows = false;
        $names = $_POST['login_server_name'] ?? [];
        $urls = $_POST['login_server_url'] ?? [];
        if (is_array($names) || is_array($urls)) {
            $n = max(is_array($names) ? count($names) : 0, is_array($urls) ? count($urls) : 0);
            for ($i = 0; $i < $n; $i++) {
                if (trim((string)($names[$i] ?? '')) !== '' || trim((string)($urls[$i] ?? '')) !== '') {
                    $hasServerRows = true;
                    break;
                }
            }
        }
        if ($hasServerRows) {
            $error = (string) ($loginParsed['error'] ?? t('settings.login_server_url_invalid'));
        }
    }
    
    try {
        ensureSettingsColumns($conn);
        if (updateSettings(
            $conn,
            $default_expiry_days,
            $max_devices_per_user,
            $auto_block_expired,
            $block_vpn_global,
            $default_server_url,
            $piracy_detection_enabled,
            $piracy_packages !== '' ? $piracy_packages : null,
            $piracy_message !== '' ? $piracy_message : null,
            $ads_enabled,
            $banner_home_only,
            $banner_ad_unit_android,
            $banner_ad_unit_ios,
            $interstitial_ad_unit_android,
            $interstitial_ad_unit_ios,
            1,
            1,
            $sync_activation_with_server,
            $app_version,
            $app_name,
            $app_activation_url,
            $support_contact_url,
            $purchase_url,
            $activation_enforced,
            $privacy_policy_url,
            $privacy_policy_html,
            $privacy_policy_mode,
            $about_us_html,
            $tmdb_api_key,
            $opensubtitles_api_key,
            $opensubtitles_username,
            $opensubtitles_password,
            $block_screenshots
        )) {
            // App IDs + TV HTML banner saved separately so older updateSettings() signatures stay compatible.
            updateSettingsPartial($conn, [
                'admob_app_id_android' => $admob_app_id_android,
                'admob_app_id_ios' => $admob_app_id_ios,
                'tv_banner_image_url' => $tv_banner_image_url,
                'tv_banner_click_url' => $tv_banner_click_url,
                'tv_banner_html_url' => $tv_banner_html_url,
            ]);
            // هيرو: حفظ منفصل عموداً بعمود (TEXT + bypass جدران نارية على *_url).
            saveHeroSettings($conn, [
                'hero_promo_enabled' => $hero_promo_enabled,
                'hero_promo_image_url' => $hero_promo_image_url,
                'hero_promo_title' => $hero_promo_title,
                'hero_promo_text' => $hero_promo_text,
                'hero_promo_link_url' => $hero_promo_link_url,
                'hero_banner_count' => $hero_banner_count,
                'hero_content_mode' => $hero_content_mode,
            ]);
            if ($loginServersOk) {
                save_login_servers($conn, $loginServers);
            }
            try {
                onesignal_save_settings_patch($conn, $onesignal_enabled, $onesignal_app_id, $onesignal_rest_api_key);
            } catch (PDOException $e) {
                // ignore — main settings already saved
            }
            // إعدادات الهيرو/الإعلانات تُحفظ حتى لو فشل تحقق سيرفرات الدخول.
            if ($error === '') {
                $success = t('msg.settings_saved');
            } else {
                // الحفظ الأساسي نجح — نُعلم المستخدم مع ذكر خطأ السيرفرات إن وُجد.
                $success = t('msg.settings_saved') . ' — ' . $error;
                $error = '';
            }
            $settings = getSettings($conn);
        } else {
            $error = $error !== '' ? $error : t('msg.settings_save_error');
        }
    } catch (PDOException $e) {
        $error = t('msg.db_error');
    }
    } // end else (normal settings save)

    if ($isSettingsAjax && $apiSecretAction === '') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode([
            'success' => $success !== '',
            'message' => $success !== '' ? $success : ($error !== '' ? $error : t('msg.settings_save_error')),
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

$appApiSecret = '';
$appApiSecretConfigured = false;
$credentialEncKeyConfigured = false;
try {
    $rawSecret = app_api_get_secret($conn);
    $appApiSecretConfigured = $rawSecret !== '';
    $appApiSecret = $isGuest ? '' : $rawSecret;
    $credentialEncKeyConfigured = credential_is_configured($conn);
    $settings = getSettings($conn);
    if ($isGuest && is_array($settings)) {
        unset($settings['app_api_secret'], $settings['credential_enc_key'], $settings['onesignal_rest_api_key']);
    }
} catch (Throwable $e) {
    // ignore
}

$privacy_mode_ui = 'url';
if (!empty($settings['privacy_policy_mode']) && $settings['privacy_policy_mode'] === 'html') {
    $privacy_mode_ui = 'html';
} else {
    $uInf = trim((string)($settings['privacy_policy_url'] ?? ''));
    $hInf = trim((string)($settings['privacy_policy_html'] ?? ''));
    if ($hInf !== '' && $uInf === '') {
        $privacy_mode_ui = 'html';
    }
}
$onesignalRestKeyConfigured = onesignal_rest_api_key_configured($settings);
$onesignalPushReady = onesignal_push_configured($settings);
$onesignalRestKeyValue = '';
if (!$isGuest && $onesignalRestKeyConfigured) {
    $onesignalRestKeyValue = trim((string)($settings['onesignal_rest_api_key'] ?? ''));
}
$loginServerRows = login_servers_for_settings($settings);
$loginServerCount = max(1, count($loginServerRows ?: [['name' => '', 'url' => '']]));
$settingsCssPath = __DIR__ . '/assets/css/settings.css';
$settingsCssVer = is_file($settingsCssPath) ? (string) filemtime($settingsCssPath) : '1';
?>

<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('nav.settings'); ?> - <?php echo t('app.title'); ?></title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700&display=swap" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link rel="stylesheet" href="assets/css/settings.css?v=<?php echo htmlspecialchars($settingsCssVer, ENT_QUOTES, 'UTF-8'); ?>">
</head>
<body class="admin-app">
    <?php require_once 'includes/header.php'; ?>

    <div class="container-fluid admin-main settings-layout mt-3 px-3 px-lg-4">
        <div class="settings-page">

            <div class="settings-page__header">
                <div class="settings-page__header-copy">
                    <span class="settings-page__eyebrow"><?php echo $lang === 'ar' ? 'لوحة التحكم' : 'Control center'; ?></span>
                    <h1><?php echo t('nav.settings'); ?></h1>
                    <p><?php echo $lang === 'ar'
                        ? 'ضبط التطبيق، الوصول، الحماية، والإعلانات من مكان واحد.'
                        : 'Configure the app, access, protection, and ads from one place.'; ?></p>
                </div>
            </div>

                        <?php if ($success): ?>
            <div class="settings-alert settings-alert--success"><i class="fas fa-circle-check"></i> <?php echo $success; ?></div>
                        <?php endif; ?>
                        <?php if ($error): ?>
            <div class="settings-alert settings-alert--error"><i class="fas fa-triangle-exclamation"></i> <?php echo $error; ?></div>
                        <?php endif; ?>
                        <?php if (!$canEditSettings): ?>
                        <?php require_once __DIR__ . '/includes/view_only_banner.php'; ?>
                        <?php endif; ?>

                        <form method="POST"
                              action=""
                              id="appApiSecretRegenForm"
                              data-admin-perm="settings"
                              data-admin-confirm
                              data-confirm-tone="warn"
                              data-confirm-icon="fas fa-key"
                              data-confirm-ok-icon="fas fa-sync-alt"
                              data-confirm-title="<?php echo htmlspecialchars(t('settings.app_api_secret_regen_title'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-message="<?php echo htmlspecialchars(t('settings.app_api_secret_regen_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-warning="<?php echo htmlspecialchars(t('settings.app_api_secret_regen_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-ok="<?php echo htmlspecialchars(t('settings.app_api_secret_regen_ok'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                              hidden>
                            <input type="hidden" name="app_api_secret_action" value="regenerate">
                        </form>
                        <form method="POST" action="" id="appApiSecretCustomForm" data-admin-perm="settings" hidden>
                            <input type="hidden" name="app_api_secret_action" value="save_custom">
                        </form>
                        <form method="POST"
                              action=""
                              id="credentialEncKeyGenForm"
                              data-admin-perm="settings"
                              data-admin-confirm
                              data-confirm-tone="warn"
                              data-confirm-icon="fas fa-lock"
                              data-confirm-ok-icon="fas fa-key"
                              data-confirm-title="<?php echo htmlspecialchars(t('settings.credential_enc_key_label'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-message="<?php echo htmlspecialchars(t('settings.credential_enc_key_help'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-ok="<?php echo htmlspecialchars(t('settings.credential_enc_key_generate'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                              hidden>
                            <input type="hidden" name="credential_enc_key_action" value="generate">
                        </form>

                        <?php if (!$isGuest && (!$appApiSecretConfigured || !$credentialEncKeyConfigured)): ?>
                            <div class="settings-alert settings-alert--warning"><i class="fas fa-shield-halved"></i> <?php echo t('settings.security_keys_required_banner'); ?></div>
                        <?php endif; ?>

                        <div class="card ns-setting-card">
                        <form method="POST" action="" id="settingsMainForm" data-admin-perm="settings" novalidate>
                            <fieldset <?php echo $canEditSettings ? '' : 'disabled'; ?> style="border:0;padding:0;margin:0;min-width:0;">

                            <div class="ns-setting">
                                <aside class="ns-setting__sidebar" aria-label="Settings tabs">
                                    <div class="ns-setting__sidebar-label"><?php echo $lang === 'ar' ? 'الأقسام' : 'Sections'; ?></div>
                                    <div class="ns-setting__nav" id="nsSettingsNav" role="tablist" aria-orientation="vertical">
                                        <button type="button" class="ns-setting__tab is-active" role="tab" data-pane="app" aria-selected="true">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-mobile-screen"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'التطبيق' : 'App'; ?></span>
                                                <span class="ns-setting__tab-sub"><?php echo $lang === 'ar' ? 'هوية وروابط' : 'Brand & links'; ?></span>
                                            </span>
                                        </button>
                                        <button type="button" class="ns-setting__tab" role="tab" data-pane="access" aria-selected="false">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-user-lock"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'الوصول' : 'Access'; ?></span>
                                                <span class="ns-setting__tab-sub"><?php echo $lang === 'ar' ? 'تفعيل وسيرفرات' : 'Activation & servers'; ?></span>
                                            </span>
                                        </button>
                                        <button type="button" class="ns-setting__tab" role="tab" data-pane="protection" aria-selected="false">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-shield-halved"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'الحماية' : 'Protection'; ?></span>
                                                <span class="ns-setting__tab-sub"><?php echo $lang === 'ar' ? 'VPN وقرصنة' : 'VPN & piracy'; ?></span>
                                            </span>
                                        </button>
                                        <button type="button" class="ns-setting__tab" role="tab" data-pane="ads" aria-selected="false">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-ad"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'الإعلانات' : 'Ads'; ?></span>
                                                <span class="ns-setting__tab-sub"><?php echo $lang === 'ar' ? 'AdMob وبانر' : 'AdMob & TV banner'; ?></span>
                                            </span>
                                        </button>
                                        <button type="button" class="ns-setting__tab" role="tab" data-pane="integrations" aria-selected="false">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-puzzle-piece"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'التكاملات' : 'Integrations'; ?></span>
                                                <span class="ns-setting__tab-sub">TMDB · OneSignal</span>
                                            </span>
                                        </button>
                                        <button type="button" class="ns-setting__tab" role="tab" data-pane="security" aria-selected="false">
                                            <span class="ns-setting__tab-ico"><i class="fas fa-key"></i></span>
                                            <span class="ns-setting__tab-txt">
                                                <span class="ns-setting__tab-title"><?php echo $lang === 'ar' ? 'الأمان' : 'Security'; ?></span>
                                                <span class="ns-setting__tab-sub"><?php echo $lang === 'ar' ? 'مفاتيح API' : 'API secrets'; ?></span>
                                            </span>
                                        </button>
                                    </div>
                                </aside>

                                <div class="ns-setting__content">

                            <!-- ========== APP ========== -->
                            <div class="ns-pane is-active" id="ns-pane-app" role="tabpanel" data-pane="app">
                                <h4 class="ns-pane__title"><i class="fas fa-mobile-screen"></i> <?php echo $lang === 'ar' ? 'التطبيق' : 'App'; ?></h4>
                                <p class="ns-pane__hint"><?php echo $lang === 'ar' ? 'الاسم، الروابط، الخصوصية، وعنوان الصفحة الرئيسية.' : 'Name, links, privacy, and home hero.'; ?></p>

                            <div class="settings-field">
                                <label for="app_name" class="form-label">
                                    <i class="fas fa-signature"></i>
                                    <?php echo t('settings.app_name_label'); ?>
                                </label>
                                <input type="text"
                                       class="form-control"
                                       id="app_name"
                                       name="app_name"
                                       value="<?php echo htmlspecialchars($settings['app_name'] ?? 'Nova IPTV Player'); ?>"
                                       placeholder="<?php echo $lang === 'ar' ? 'مثال: Nova IPTV Player' : 'e.g. Nova IPTV Player'; ?>">
                                <span class="settings-field__help"><?php echo t('settings.app_name_help'); ?></span>
                            </div>

                            <div class="settings-field">
                                <label for="app_version" class="form-label">
                                    <i class="fas fa-code-branch"></i>
                                    <?php echo t('settings.app_version_label'); ?>
                                </label>
                                <input type="text"
                                       class="form-control"
                                       id="app_version"
                                       name="app_version"
                                       value="<?php echo htmlspecialchars($settings['app_version'] ?? '1.0.0'); ?>"
                                       placeholder="1.0.0">
                                <span class="settings-field__help"><?php echo t('settings.app_version_help'); ?></span>
                            </div>

                            <div class="settings-grid-2">
                            <div class="settings-field">
                                <label for="support_contact_url" class="form-label"><i class="fas fa-headset"></i> <?php echo t('settings.support_contact_label'); ?></label>
                                <input type="text" class="form-control" id="support_contact_url" name="support_contact_url"
                                       value="<?php echo htmlspecialchars($settings['support_contact_url'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.support_contact_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.support_contact_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label for="purchase_url" class="form-label"><i class="fas fa-cart-shopping"></i> <?php echo t('settings.purchase_url_label'); ?></label>
                                <input type="text" class="form-control" id="purchase_url" name="purchase_url"
                                       value="<?php echo htmlspecialchars($settings['purchase_url'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.purchase_url_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.purchase_url_help'); ?></span>
                            </div>
                            </div>

                            <div class="settings-field">
                                <label for="privacy_policy_mode" class="form-label"><i class="fas fa-shield-halved"></i> <?php echo t('settings.privacy_mode_label'); ?></label>
                                <select class="form-select" id="privacy_policy_mode" name="privacy_policy_mode" onchange="window.togglePrivacyPolicyFields && window.togglePrivacyPolicyFields()">
                                    <option value="url" <?php echo $privacy_mode_ui === 'url' ? 'selected' : ''; ?>><?php echo t('settings.privacy_mode_url'); ?></option>
                                    <option value="html" <?php echo $privacy_mode_ui === 'html' ? 'selected' : ''; ?>><?php echo t('settings.privacy_mode_html'); ?></option>
                                </select>
                                <span class="settings-field__help"><?php echo t('settings.privacy_mode_help'); ?></span>
                            </div>

                            <div class="settings-field" id="block_privacy_url" style="<?php echo $privacy_mode_ui === 'html' ? 'display:none' : ''; ?>">
                                <label for="privacy_policy_url" class="form-label"><i class="fas fa-globe"></i> <?php echo t('settings.privacy_url_only_label'); ?></label>
                                <input type="text" class="form-control" id="privacy_policy_url" name="privacy_policy_url"
                                       value="<?php echo htmlspecialchars($settings['privacy_policy_url'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.privacy_url_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.privacy_url_only_help'); ?></span>
                            </div>

                            <div class="settings-field" id="block_privacy_html" style="<?php echo $privacy_mode_ui === 'url' ? 'display:none' : ''; ?>">
                                <label for="privacy_policy_html" class="form-label"><i class="fas fa-code"></i> <?php echo t('settings.privacy_html_only_label'); ?></label>
                                <textarea class="form-control" id="privacy_policy_html" name="privacy_policy_html" rows="8"
                                          placeholder="<?php echo t('settings.privacy_html_placeholder'); ?>"><?php echo htmlspecialchars($settings['privacy_policy_html'] ?? ''); ?></textarea>
                                <span class="settings-field__help"><?php echo t('settings.privacy_html_only_help'); ?></span>
                            </div>

                            <div class="settings-field">
                                <label for="about_us_html" class="form-label"><i class="fas fa-info-circle"></i> <?php echo t('settings.about_us_label'); ?></label>
                                <textarea class="form-control" id="about_us_html" name="about_us_html" rows="8"
                                          placeholder="<?php echo t('settings.about_us_placeholder'); ?>"><?php echo htmlspecialchars($settings['about_us_html'] ?? ''); ?></textarea>
                                <span class="settings-field__help"><?php echo t('settings.about_us_help'); ?></span>
                            </div>

                            <div class="ns-pane__subhead">
                                <strong><?php echo t('settings.hero_section_title'); ?></strong>
                                <p class="ns-pane__hint"><?php echo t('settings.hero_section_help'); ?></p>
                            </div>
                            <?php
                            $heroMode = hero_content_mode_normalize($settings['hero_content_mode'] ?? 'auto');
                            $heroCount = max(1, min(10, (int)($settings['hero_banner_count'] ?? 5)));
                            $heroPromoOn = !empty($settings['hero_promo_enabled']);
                            ?>
                            <div class="settings-grid-2">
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_banner_count_label'); ?></label>
                                <input type="number"
                                       class="form-control"
                                       name="hero_banner_count"
                                       min="1"
                                       max="10"
                                       value="<?php echo (int) $heroCount; ?>">
                                <span class="settings-field__help"><?php echo t('settings.hero_banner_count_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_content_mode_label'); ?></label>
                                <select class="form-control" name="hero_content_mode">
                                    <option value="auto" <?php echo $heroMode === 'auto' ? 'selected' : ''; ?>><?php echo t('settings.hero_content_mode_auto'); ?></option>
                                    <option value="movies" <?php echo $heroMode === 'movies' ? 'selected' : ''; ?>><?php echo t('settings.hero_content_mode_movies'); ?></option>
                                    <option value="series" <?php echo $heroMode === 'series' ? 'selected' : ''; ?>><?php echo t('settings.hero_content_mode_series'); ?></option>
                                </select>
                                <span class="settings-field__help"><?php echo t('settings.hero_content_mode_help'); ?></span>
                            </div>
                            <div class="settings-field" style="grid-column:1 / -1;">
                                <div class="feature-toggle" style="margin:0;">
                                    <div class="feature-left">
                                        <div>
                                            <div class="feature-title"><?php echo t('settings.hero_promo_enabled_label'); ?></div>
                                            <div class="feature-desc"><?php echo t('settings.hero_promo_enabled_help'); ?></div>
                                        </div>
                                    </div>
                                    <div class="toggle-wrapper">
                                        <span class="toggle-label off"><?php echo t('off'); ?></span>
                                        <label class="toggle-switch">
                                            <input type="checkbox" id="hero_promo_enabled" name="hero_promo_enabled" <?php echo $heroPromoOn ? 'checked' : ''; ?>>
                                            <span class="slider"></span>
                                        </label>
                                        <span class="toggle-label on"><?php echo t('on'); ?></span>
                                    </div>
                                </div>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_promo_image_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="hero_promo_image"
                                       inputmode="url"
                                       autocomplete="off"
                                       value="<?php echo htmlspecialchars($settings['hero_promo_image_url'] ?? ''); ?>"
                                       placeholder="https://example.com/hero-promo.jpg">
                                <span class="settings-field__help"><?php echo t('settings.hero_promo_image_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_promo_link_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="hero_promo_link"
                                       inputmode="url"
                                       autocomplete="off"
                                       value="<?php echo htmlspecialchars($settings['hero_promo_link_url'] ?? ''); ?>"
                                       placeholder="https://example.com/offer">
                                <span class="settings-field__help"><?php echo t('settings.hero_promo_link_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_promo_title_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="hero_promo_title"
                                       maxlength="255"
                                       value="<?php echo htmlspecialchars($settings['hero_promo_title'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.hero_promo_title_placeholder'); ?>">
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.hero_promo_text_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="hero_promo_text"
                                       maxlength="500"
                                       value="<?php echo htmlspecialchars($settings['hero_promo_text'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.hero_promo_text_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.hero_promo_text_help'); ?></span>
                            </div>
                            </div>
                            </div>

                            <!-- ========== ACCESS ========== -->
                            <div class="ns-pane" id="ns-pane-access" role="tabpanel" data-pane="access" hidden>
                                <h4 class="ns-pane__title"><i class="fas fa-user-lock"></i> <?php echo $lang === 'ar' ? 'الوصول' : 'Access'; ?></h4>
                                <p class="ns-pane__hint"><?php echo $lang === 'ar' ? 'التفعيل، الحدود، وسيرفرات الدخول.' : 'Activation, limits, and login servers.'; ?></p>

                            <div class="feature-toggle">
                                <div class="feature-toggle-left">
                                    <div class="feature-icon">
                                        <i class="fas fa-user-lock"></i>
                                    </div>
                                    <div>
                                        <div class="feature-title"><?php echo t('settings.activation_enforced_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.activation_enforced_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="activation_enforced" name="activation_enforced"
                                            <?php echo ($settings['activation_enforced'] ?? 1) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="settings-grid-2 settings-grid-2--equal">
                            <div class="settings-field">
                                <label for="default_expiry_days" class="form-label"><i class="fas fa-calendar-alt"></i> <?php echo t('settings.default_days_label'); ?></label>
                                <div class="settings-number-group">
                                    <button type="button" onclick="stepDown('default_expiry_days')">−</button>
                                    <input type="number" id="default_expiry_days" name="default_expiry_days" value="<?php echo $settings['default_expiry_days'] ?? 30; ?>" min="1" required>
                                    <button type="button" onclick="stepUp('default_expiry_days')">+</button>
                                    <div class="settings-number-suffix"><?php echo t('settings.default_days_suffix'); ?></div>
                                </div>
                                <span class="settings-field__help"><?php echo t('settings.default_days_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label for="max_devices_per_user" class="form-label"><i class="fas fa-mobile-alt"></i> <?php echo t('settings.max_devices_label'); ?></label>
                                <div class="settings-number-group">
                                    <button type="button" onclick="stepDown('max_devices_per_user')">−</button>
                                    <input type="number" id="max_devices_per_user" name="max_devices_per_user" value="<?php echo $settings['max_devices_per_user'] ?? 1; ?>" min="1" required>
                                    <button type="button" onclick="stepUp('max_devices_per_user')">+</button>
                                    <div class="settings-number-suffix"><?php echo t('settings.max_devices_suffix'); ?></div>
                                </div>
                                <span class="settings-field__help"><?php echo t('settings.max_devices_help'); ?></span>
                            </div>
                            </div>

                            <div class="feature-toggle">
                                <div class="feature-left">
                                    <div>
                                        <div class="feature-title"><i class="fas fa-ban feature-inline-icon"></i> <?php echo t('settings.auto_block_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.auto_block_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="auto_block_expired" name="auto_block_expired" <?php echo ($settings['auto_block_expired'] ?? 0) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="settings-field">
                                <label for="app_activation_url" class="form-label"><i class="fas fa-bolt"></i> <?php echo t('settings.app_activation_url_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       id="app_activation_url"
                                       name="app_activation_url"
                                       value="<?php echo htmlspecialchars($settings['app_activation_url'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.app_activation_url_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.app_activation_url_help'); ?></span>
                            </div>

                            <div class="ns-pane__subhead">
                                <strong><?php echo t('settings.server_section_title'); ?></strong>
                                <p class="ns-pane__hint"><?php echo t('settings.login_servers_help'); ?></p>
                            </div>

                            <div class="login-servers-stack" id="login-servers-list">
                                <?php
                                $loginServerRowHtml = function ($name = '', $url = '') {
                                    ?>
                                <div class="login-server-card">
                                    <div class="login-server-field">
                                        <label class="form-label"><?php echo t('settings.login_server_name'); ?></label>
                                        <input type="text" class="form-control" name="login_server_name[]"
                                               value="<?php echo htmlspecialchars($name); ?>"
                                               placeholder="<?php echo t('settings.login_server_name_placeholder'); ?>">
                                    </div>
                                    <div class="login-server-field login-server-field--url">
                                        <label class="form-label"><?php echo t('settings.login_server_url'); ?></label>
                                        <div class="login-server-controls">
                                        <div class="input-group">
                                            <input type="text" class="form-control login-server-url-input" name="login_server_url[]"
                                                   value="<?php echo htmlspecialchars($url); ?>"
                                                   placeholder="<?php echo t('settings.server_url_placeholder'); ?>"
                                                   autocomplete="off" spellcheck="false">
                                                <button type="button" class="login-server-save">
                                                    <i class="fas fa-save"></i> <?php echo t('settings.login_server_save'); ?>
                                            </button>
                                            </div>
                                        </div>
                                        <div class="login-server-url-error" aria-live="polite"></div>
                                    </div>
                                    <div class="login-server-field login-server-field--remove">
                                        <label class="form-label login-server-field-spacer" aria-hidden="true">&nbsp;</label>
                                        <button type="button" class="login-server-remove" title="<?php echo t('settings.login_server_remove'); ?>">
                                            <i class="fas fa-times"></i> <?php echo t('settings.login_server_remove'); ?>
                                        </button>
                                    </div>
                                </div>
                                    <?php
                                };
                                if (!$loginServerRows) {
                                    $loginServerRowHtml();
                                } else {
                                    foreach ($loginServerRows as $row) {
                                        $loginServerRowHtml((string) ($row['name'] ?? ''), (string) ($row['url'] ?? ''));
                                    }
                                }
                                ?>
                            </div>
                            <button type="button" class="settings-add-server" id="add-login-server">
                                <i class="fas fa-plus"></i> <?php echo t('settings.login_server_add'); ?>
                            </button>
                            <span class="settings-field__help d-block mb-3"><?php echo t('settings.login_servers_external_note'); ?></span>

                            <div class="feature-toggle mb-0">
                                <div class="feature-toggle-left">
                                    <div class="feature-icon">
                                        <i class="fas fa-arrows-rotate"></i>
                                    </div>
                                    <div>
                                        <div class="feature-title">
                                            <?php echo t('settings.sync_activation_panel_label'); ?>
                                        </div>
                                        <div class="feature-desc">
                                            <?php echo t('settings.sync_activation_panel_help'); ?>
                                        </div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="sync_activation_with_server" name="sync_activation_with_server"
                                            <?php echo ($settings['sync_activation_with_server'] ?? 0) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>
                            </div>

                            <!-- ========== PROTECTION ========== -->
                            <div class="ns-pane" id="ns-pane-protection" role="tabpanel" data-pane="protection" hidden>
                                <h4 class="ns-pane__title"><i class="fas fa-shield-halved"></i> <?php echo $lang === 'ar' ? 'الحماية' : 'Protection'; ?></h4>
                                <p class="ns-pane__hint"><?php echo t('settings.piracy_toggle_help'); ?></p>

                            <div class="feature-toggle">
                                <div class="feature-toggle-left">
                                    <div class="feature-icon">
                                        <i class="fas fa-mobile-alt"></i>
                                    </div>
                                    <div>
                                        <div class="feature-title"><?php echo t('settings.block_screenshots_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.block_screenshots_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="block_screenshots" name="block_screenshots"
                                            <?php echo ($settings['block_screenshots'] ?? 1) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="feature-toggle">
                                <div class="feature-toggle-left">
                                    <div class="feature-icon">
                                        <i class="fas fa-shield-alt"></i>
                                    </div>
                                    <div>
                                        <div class="feature-title"><?php echo t('settings.vpn_block_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.vpn_block_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox"
                                               id="block_vpn_global"
                                               name="block_vpn_global"
                                               <?php echo ($settings['block_vpn_global'] ?? 0) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="feature-toggle">
                                <div class="feature-toggle-left">
                                    <div class="feature-icon">
                                        <i class="fas fa-user-secret"></i>
                                    </div>
                                    <div>
                                        <div class="feature-title"><?php echo t('settings.piracy_toggle_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.piracy_toggle_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="piracy_detection_enabled" name="piracy_detection_enabled"
                                            <?php echo ($settings['piracy_detection_enabled'] ?? 0) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="settings-field">
                                <label for="piracy_packages" class="form-label"><i class="fas fa-ban"></i> <?php echo t('settings.piracy_packages_label'); ?></label>
                                <textarea class="form-control" id="piracy_packages" name="piracy_packages" rows="6"
                                          placeholder="com.screenrecorder.app&#10;com.videodownloader.app"><?php echo htmlspecialchars((string)($settings['piracy_packages'] ?? '')); ?></textarea>
                                <span class="settings-field__help"><?php echo t('settings.piracy_packages_help'); ?></span>
                            </div>

                            <div class="settings-field">
                                <label for="piracy_message" class="form-label"><i class="fas fa-comment-dots"></i> <?php echo t('settings.piracy_message_label'); ?></label>
                                <textarea class="form-control" id="piracy_message" name="piracy_message" rows="3"
                                          placeholder="<?php echo htmlspecialchars(t('settings.piracy_message_placeholder')); ?>"><?php echo htmlspecialchars((string)($settings['piracy_message'] ?? '')); ?></textarea>
                                <span class="settings-field__help"><?php echo t('settings.piracy_message_help'); ?></span>
                            </div>
                            </div>

                            <!-- ========== ADS ========== -->
                            <div class="ns-pane" id="ns-pane-ads" role="tabpanel" data-pane="ads" hidden>
                                <h4 class="ns-pane__title"><i class="fas fa-ad"></i> <?php echo t('settings.ads_section_title'); ?></h4>
                                <p class="ns-pane__hint"><?php echo t('settings.ads_enabled_help'); ?></p>

                            <div class="feature-toggle">
                                <div class="feature-left">
                                    <div>
                                        <div class="feature-title"><i class="fas fa-bullhorn feature-inline-icon"></i> <?php echo t('settings.ads_enabled_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.ads_enabled_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="ads_enabled" name="ads_enabled" <?php echo ($settings['ads_enabled'] ?? 1) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="settings-grid-2">
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.admob_app_id_android_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="admob_app_id_android"
                                       value="<?php echo htmlspecialchars($settings['admob_app_id_android'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.admob_app_id_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.admob_app_id_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.admob_app_id_ios_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="admob_app_id_ios"
                                       value="<?php echo htmlspecialchars($settings['admob_app_id_ios'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.admob_app_id_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.admob_app_id_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.banner_android_label'); ?></label>
                                <input type="text"
                                       class="form-control"
                                       name="banner_ad_unit_android"
                                       value="<?php echo htmlspecialchars($settings['banner_ad_unit_android'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.banner_android_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.banner_android_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.banner_ios_label'); ?></label>
                                <input type="text" class="form-control" name="banner_ad_unit_ios"
                                       value="<?php echo htmlspecialchars($settings['banner_ad_unit_ios'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.banner_android_placeholder'); ?>">
                                <span class="settings-field__help"><?php echo t('settings.banner_android_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.interstitial_android_label'); ?></label>
                                <input type="text" class="form-control" name="interstitial_ad_unit_android"
                                       value="<?php echo htmlspecialchars($settings['interstitial_ad_unit_android'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.interstitial_android_placeholder'); ?>">
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.interstitial_ios_label'); ?></label>
                                <input type="text" class="form-control" name="interstitial_ad_unit_ios"
                                       value="<?php echo htmlspecialchars($settings['interstitial_ad_unit_ios'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.interstitial_ios_placeholder'); ?>">
                            </div>
                            </div>

                            <div class="ns-pane__subhead">
                                <strong><?php echo t('settings.tv_banner_section_title'); ?></strong>
                                <p class="ns-pane__hint"><?php echo t('settings.tv_banner_section_help'); ?></p>
                            </div>
                            <div class="settings-grid-2">
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.tv_banner_image_label'); ?></label>
                                <input type="url"
                                       class="form-control"
                                       name="tv_banner_image_url"
                                       value="<?php echo htmlspecialchars($settings['tv_banner_image_url'] ?? ''); ?>"
                                       placeholder="https://example.com/banner-320x50.jpg">
                                <span class="settings-field__help"><?php echo t('settings.tv_banner_image_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label"><?php echo t('settings.tv_banner_click_label'); ?></label>
                                <input type="url"
                                       class="form-control"
                                       name="tv_banner_click_url"
                                       value="<?php echo htmlspecialchars($settings['tv_banner_click_url'] ?? ''); ?>"
                                       placeholder="https://example.com/offer">
                                <span class="settings-field__help"><?php echo t('settings.tv_banner_click_help'); ?></span>
                            </div>
                            <div class="settings-field" style="grid-column:1 / -1;">
                                <label class="form-label"><?php echo t('settings.tv_banner_html_label'); ?></label>
                                <input type="url"
                                       class="form-control"
                                       name="tv_banner_html_url"
                                       value="<?php echo htmlspecialchars($settings['tv_banner_html_url'] ?? ''); ?>"
                                       placeholder="https://example.com/tv-banner.html">
                                <span class="settings-field__help"><?php echo t('settings.tv_banner_html_help'); ?></span>
                            </div>
                            </div>
                            </div>

                            <!-- ========== INTEGRATIONS ========== -->
                            <div class="ns-pane" id="ns-pane-integrations" role="tabpanel" data-pane="integrations" hidden>
                                <h4 class="ns-pane__title"><i class="fas fa-puzzle-piece"></i> <?php echo $lang === 'ar' ? 'التكاملات' : 'Integrations'; ?></h4>
                                <p class="ns-pane__hint"><?php echo t('settings.api_keys_section_intro'); ?></p>

                            <div class="settings-grid-2">
                                <div class="settings-field">
                                    <label for="tmdb_api_key" class="form-label"><i class="fas fa-film"></i> <?php echo t('settings.tmdb_api_key_label'); ?></label>
                                    <input type="text" class="form-control field-mono" id="tmdb_api_key" name="tmdb_api_key"
                                           value="<?php echo htmlspecialchars($settings['tmdb_api_key'] ?? ''); ?>"
                                           placeholder="<?php echo t('settings.tmdb_api_key_placeholder'); ?>"
                                           autocomplete="off">
                                    <span class="settings-field__help"><?php echo t('settings.tmdb_api_key_help'); ?></span>
                                </div>
                                <div class="settings-field">
                                    <label for="opensubtitles_api_key" class="form-label"><i class="fas fa-closed-captioning"></i> <?php echo t('settings.opensubtitles_api_key_label'); ?></label>
                                    <input type="text" class="form-control field-mono" id="opensubtitles_api_key" name="opensubtitles_api_key"
                                           value="<?php echo htmlspecialchars($settings['opensubtitles_api_key'] ?? ''); ?>"
                                           placeholder="<?php echo t('settings.opensubtitles_api_key_placeholder'); ?>"
                                           autocomplete="off">
                                    <span class="settings-field__help"><?php echo t('settings.opensubtitles_api_key_help'); ?></span>
                                </div>
                                <div class="settings-field">
                                    <label for="opensubtitles_username" class="form-label"><i class="fas fa-user"></i> <?php echo t('settings.opensubtitles_username_label'); ?></label>
                                    <input type="text" class="form-control" id="opensubtitles_username" name="opensubtitles_username"
                                           value="<?php echo htmlspecialchars($settings['opensubtitles_username'] ?? ''); ?>"
                                           placeholder="<?php echo t('settings.opensubtitles_username_placeholder'); ?>"
                                           autocomplete="off">
                                    <span class="settings-field__help"><?php echo t('settings.opensubtitles_username_help'); ?></span>
                                </div>
                                <div class="settings-field">
                                    <label for="opensubtitles_password" class="form-label"><i class="fas fa-lock"></i> <?php echo t('settings.opensubtitles_password_label'); ?></label>
                                    <div class="input-group">
                                        <input type="password" class="form-control" id="opensubtitles_password" name="opensubtitles_password"
                                               value="<?php echo htmlspecialchars($settings['opensubtitles_password'] ?? ''); ?>"
                                               placeholder="<?php echo t('settings.opensubtitles_password_placeholder'); ?>"
                                               autocomplete="new-password">
                                        <button type="button" class="btn" id="opensubtitles_password_toggle"
                                                title="<?php echo $lang === 'ar' ? 'إظهار / إخفاء كلمة المرور' : 'Show / hide password'; ?>"
                                                aria-label="<?php echo $lang === 'ar' ? 'إظهار كلمة المرور' : 'Show password'; ?>">
                                            <i class="fas fa-eye" id="opensubtitles_password_icon"></i>
                                        </button>
                                    </div>
                                    <span class="settings-field__help"><?php echo t('settings.opensubtitles_password_help'); ?></span>
                                </div>
                            </div>

                            <div class="ns-pane__subhead">
                                <strong><?php echo t('settings.onesignal_section_title'); ?></strong>
                                <p class="ns-pane__hint"><?php echo t('settings.onesignal_section_intro'); ?></p>
                                <div class="ns-pane__chips">
                                    <?php if (adminCan('notifications_send')): ?>
                                    <a href="notifications.php" class="ns-chip"><i class="fas fa-paper-plane"></i> <?php echo t('settings.onesignal_page_link'); ?></a>
                                    <?php endif; ?>
                                    <?php if ($onesignalPushReady): ?>
                                    <span class="ns-chip ns-chip--ok"><i class="fas fa-check-circle"></i> <?php echo $lang === 'ar' ? 'جاهز للإرسال' : 'Ready to send'; ?></span>
                                    <?php else: ?>
                                    <span class="ns-chip ns-chip--warn"><i class="fas fa-triangle-exclamation"></i> <?php echo $lang === 'ar' ? 'أكمل الإعداد' : 'Setup incomplete'; ?></span>
                                    <?php endif; ?>
                                </div>
                            </div>

                            <div class="onesignal-settings-form" id="onesignalSettingsBlock">
                            <div class="feature-toggle">
                                <div class="feature-left">
                                    <div>
                                        <div class="feature-title"><i class="fas fa-bell feature-inline-icon"></i> <?php echo t('settings.onesignal_enabled_label'); ?></div>
                                        <div class="feature-desc"><?php echo t('settings.onesignal_enabled_help'); ?></div>
                                    </div>
                                </div>
                                <div class="toggle-wrapper">
                                    <span class="toggle-label off"><?php echo t('off'); ?></span>
                                    <label class="toggle-switch">
                                        <input type="checkbox" id="onesignal_enabled" name="onesignal_enabled" <?php echo !empty($settings['onesignal_enabled']) ? 'checked' : ''; ?>>
                                        <span class="slider"></span>
                                    </label>
                                    <span class="toggle-label on"><?php echo t('on'); ?></span>
                                </div>
                            </div>

                            <div class="settings-grid-2">
                            <div class="settings-field">
                                <label class="form-label" for="onesignal_app_id"><?php echo t('settings.onesignal_app_id_label'); ?></label>
                                <input type="text" class="form-control field-mono" id="onesignal_app_id" name="onesignal_app_id"
                                       value="<?php echo htmlspecialchars($settings['onesignal_app_id'] ?? ''); ?>"
                                       placeholder="<?php echo t('settings.onesignal_app_id_placeholder'); ?>"
                                       autocomplete="off"
                                       <?php echo $canEditSettings ? '' : 'disabled'; ?>>
                                <span class="settings-field__help"><?php echo t('settings.onesignal_app_id_help'); ?></span>
                            </div>
                            <div class="settings-field">
                                <label class="form-label" for="onesignal_rest_api_key"><?php echo t('settings.onesignal_rest_key_label'); ?></label>
                                <?php if ($onesignalRestKeyConfigured): ?>
                                    <div class="settings-alert settings-alert--success py-2 mb-2"><i class="fas fa-check-circle"></i> <?php echo t('settings.onesignal_rest_key_ready'); ?></div>
                                <?php else: ?>
                                    <div class="settings-alert settings-alert--warning py-2 mb-2"><i class="fas fa-triangle-exclamation"></i> <?php echo t('settings.onesignal_rest_key_missing'); ?></div>
                                <?php endif; ?>
                                <div class="input-group">
                                    <input type="password" class="form-control field-mono" id="onesignal_rest_api_key" name="onesignal_rest_api_key"
                                           value="<?php echo htmlspecialchars($isGuest ? ($onesignalRestKeyConfigured ? str_repeat('•', 48) : '') : $onesignalRestKeyValue, ENT_QUOTES, 'UTF-8'); ?>"
                                           placeholder="<?php echo t('settings.onesignal_rest_key_placeholder'); ?>"
                                           autocomplete="new-password"
                                           <?php echo ($canEditSettings && !$isGuest) ? '' : 'readonly disabled'; ?>>
                                    <button type="button" class="btn" id="onesignal_rest_api_key_toggle"
                                            title="<?php echo $lang === 'ar' ? 'إظهار / إخفاء المفتاح' : 'Show / hide key'; ?>"
                                            aria-label="<?php echo $lang === 'ar' ? 'إظهار المفتاح' : 'Show key'; ?>"
                                            <?php echo ($canEditSettings && !$isGuest) ? '' : 'disabled'; ?>>
                                        <i class="fas fa-eye" id="onesignal_rest_api_key_icon"></i>
                                    </button>
                                </div>
                                <span class="settings-field__help"><?php echo t('settings.onesignal_rest_key_help'); ?></span>
                            </div>
                            </div>
                            </div>
                            </div>

                            <!-- ========== SECURITY ========== -->
                            <div class="ns-pane" id="ns-pane-security" role="tabpanel" data-pane="security" hidden>
                                <h4 class="ns-pane__title"><i class="fas fa-key"></i> <?php echo $lang === 'ar' ? 'الأمان' : 'Security'; ?></h4>
                                <p class="ns-pane__hint"><?php echo t('settings.app_api_secret_help'); ?></p>

                            <div class="secret-box">
                                <label class="form-label mb-2"><i class="fas fa-shield-halved"></i> <?php echo t('settings.app_api_secret_label'); ?></label>
                                <div class="input-group mb-2">
                                    <input type="text"
                                           class="form-control font-monospace"
                                           id="app_api_secret_display"
                                           readonly
                                           value="<?php echo htmlspecialchars($isGuest ? ($appApiSecretConfigured ? str_repeat('•', 48) : '') : $appApiSecret); ?>"
                                           <?php echo $isGuest ? '' : 'onclick="this.select();"'; ?>>
                                    <button type="button"
                                            class="btn btn-outline-light"
                                            <?php if ($isGuest): ?>
                                            disabled
                                            title="<?php echo $lang === 'ar' ? 'النسخ غير متاح في وضع الضيف' : 'Copy is unavailable in Guest mode'; ?>"
                                            <?php else: ?>
                                            onclick="(function(){var i=document.getElementById('app_api_secret_display');i.select();try{navigator.clipboard.writeText(i.value);}catch(e){} })();"
                                            <?php endif; ?>>
                                        <i class="fas fa-copy"></i>
                                    </button>
                                </div>
                                <div class="d-flex flex-wrap gap-2 align-items-center mb-3">
                                    <button type="submit" form="appApiSecretRegenForm" class="btn-secret-regen"
                                            <?php echo $canEditSettings ? '' : 'disabled'; ?>>
                                        <i class="fas fa-sync-alt"></i> <?php echo t('settings.app_api_secret_regen'); ?>
                                    </button>
                                </div>
                                <label class="form-label" for="app_api_secret_custom"><i class="fas fa-pen"></i> <?php echo t('settings.app_api_secret_custom_label'); ?></label>
                                <div class="input-group">
                                    <input type="text" class="form-control field-mono" id="app_api_secret_custom"
                                           name="app_api_secret_custom" form="appApiSecretCustomForm"
                                           minlength="32" maxlength="128" placeholder="32–128 chars"
                                           <?php echo $canEditSettings ? '' : 'disabled'; ?>>
                                    <button type="submit" form="appApiSecretCustomForm" class="btn-secret-save"
                                            <?php echo $canEditSettings ? '' : 'disabled'; ?>>
                                        <?php echo t('button.save_changes'); ?>
                                    </button>
                                </div>
                            </div>

                            <div class="secret-box">
                                <label class="form-label mb-2"><i class="fas fa-lock"></i> <?php echo t('settings.credential_enc_key_label'); ?></label>
                                <p class="settings-field__help mb-2"><?php echo t('settings.credential_enc_key_help'); ?></p>
                                <?php if ($credentialEncKeyConfigured): ?>
                                    <div class="settings-alert settings-alert--success py-2 mb-2"><i class="fas fa-check-circle"></i> <?php echo t('settings.credential_enc_key_ready'); ?></div>
                                <?php else: ?>
                                    <div class="settings-alert settings-alert--error py-2 mb-2"><i class="fas fa-triangle-exclamation"></i> <?php echo t('settings.credential_enc_key_missing'); ?></div>
                                <?php endif; ?>
                                <button type="submit" form="credentialEncKeyGenForm" class="btn-secret-regen"
                                        <?php echo $canEditSettings ? '' : 'disabled'; ?>>
                                    <i class="fas fa-key"></i> <?php echo t('settings.credential_enc_key_generate'); ?>
                                </button>
                            </div>
                            </div>

                                </div><!-- /.ns-setting__content -->
                            </div><!-- /.ns-setting -->

                            <div class="text-center mt-3 mb-2 settings-bottom-save">
                                <button type="submit" class="btn-edit btn-edit-main" id="settingsBottomSave">
                                    <span class="btn-edit__ico"><i class="fas fa-floppy-disk"></i></span>
                                    <?php echo t('button.save_changes'); ?>
                                </button>
                            </div>
                            </fieldset>
                        </form>
                        </div><!-- /.ns-setting-card -->
                        </div><!-- /.settings-page -->
                    </div>

    <?php if ($canEditSettings): ?>
    <div class="settings-savebar" id="settingsSavebar" aria-live="polite">
        <div class="settings-savebar__text">
            <?php echo $lang === 'ar' ? 'تعديلات غير محفوظة' : 'Unsaved changes'; ?>
            <small id="settingsSavebarCount"><?php echo $lang === 'ar' ? 'راجع التعديلات ثم احفظ.' : 'Review your edits, then save.'; ?></small>
        </div>
        <button type="button" class="settings-savebar__btn" id="settingsSavebarBtn">
            <i class="fas fa-floppy-disk"></i> <?php echo t('button.save_changes'); ?>
        </button>
    </div>
    <?php endif; ?>

    <?php require_once 'includes/footer.php'; ?>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <?php require_once 'includes/admin_confirm_modal.php'; ?>
    
    <script>

(function(){
  var list = document.getElementById('login-servers-list');
  var addBtn = document.getElementById('add-login-server');
  if (!list || !addBtn) return;
  var msgInvalid = <?php echo json_encode(t('settings.login_server_url_invalid'), JSON_UNESCAPED_UNICODE); ?>;
  var msgSaved = <?php echo json_encode(t('settings.login_servers_saved'), JSON_UNESCAPED_UNICODE); ?>;
  var msgError = <?php echo json_encode(t('msg.settings_save_error'), JSON_UNESCAPED_UNICODE); ?>;

  function isValidLoginServerUrl(raw){
    var url = String(raw || '').trim();
    if (!url) return false;
    if (!/^https?:\/\//i.test(url)) url = 'http://' + url;
    var host = '';
    try {
      host = new URL(url).hostname || '';
    } catch (e) {
      return false;
    }
    if (!host) return false;
    if (host.toLowerCase() === 'localhost') return true;
    if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return true;
    return /^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i.test(host);
  }

  function clearRowError(row){
    var inp = row.querySelector('.login-server-url-input');
    var err = row.querySelector('.login-server-url-error');
    if (inp) inp.classList.remove('is-invalid');
    if (err) {
      err.classList.remove('is-visible');
      err.textContent = '';
    }
  }

  function showRowError(row, message){
    var inp = row.querySelector('.login-server-url-input');
    var err = row.querySelector('.login-server-url-error');
    if (inp) {
      inp.classList.add('is-invalid');
      inp.focus();
    }
    if (err) {
      err.classList.add('is-visible');
      err.textContent = message || msgInvalid;
    }
  }

  function toast(message, isError){
    var el = document.getElementById('settingsAjaxToast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'settingsAjaxToast';
      el.className = 'settings-ajax-toast';
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.classList.toggle('is-error', !!isError);
    el.classList.add('is-show');
    setTimeout(function(){ el.classList.remove('is-show'); }, 3200);
  }

  function bindRemove(btn){
    btn.addEventListener('click', function(){
      var rows = list.querySelectorAll('.login-server-card');
      var row = btn.closest('.login-server-card');
      if (!row) return;
      if (rows.length <= 1) {
        row.querySelectorAll('input').forEach(function(inp){ inp.value = ''; });
        clearRowError(row);
        if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
        return;
      }
      row.remove();
      if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
    });
  }

  function bindSave(btn){
    btn.addEventListener('click', function(){
      var rows = list.querySelectorAll('.login-server-card');
      var names = [];
      var urls = [];
      var invalidRow = null;
      rows.forEach(function(row){
        clearRowError(row);
        var nameInp = row.querySelector('[name="login_server_name[]"]');
        var urlInp = row.querySelector('[name="login_server_url[]"]');
        var name = ((nameInp && nameInp.value) || '').trim();
        var url = ((urlInp && urlInp.value) || '').trim();
        if (!name && !url) return;
        if (!isValidLoginServerUrl(url)) {
          if (!invalidRow) invalidRow = row;
          showRowError(row, msgInvalid);
          return;
        }
        names.push(name);
        urls.push(url);
      });
      if (invalidRow) {
        toast(msgInvalid, true);
        return;
      }
      var body = new URLSearchParams();
      body.set('save_login_servers', '1');
      body.set('settings_ajax', '1');
      if (window.ADMIN_CSRF_TOKEN) body.set('csrf_token', window.ADMIN_CSRF_TOKEN);
      names.forEach(function(n){ body.append('login_server_name[]', n); });
      urls.forEach(function(u){ body.append('login_server_url[]', u); });
      btn.disabled = true;
      fetch(window.location.href, {
        method: 'POST',
        headers: window.adminCsrfHeaders({
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest'
        }),
        body: body.toString(),
        credentials: 'same-origin'
      }).then(function(r){ return r.json(); }).then(function(data){
        if (data && data.success) {
          toast(data.message || msgSaved, false);
        } else {
          toast((data && data.message) || msgInvalid, true);
        }
      }).catch(function(){
        toast(msgError, true);
      }).finally(function(){
        btn.disabled = false;
      });
    });
  }

  list.querySelectorAll('.login-server-remove').forEach(bindRemove);
  list.querySelectorAll('.login-server-save').forEach(bindSave);
  addBtn.addEventListener('click', function(){
    var first = list.querySelector('.login-server-card');
    if (!first) return;
    var clone = first.cloneNode(true);
    clone.querySelectorAll('input').forEach(function(inp){
      inp.value = '';
      inp.classList.remove('is-invalid');
    });
    var err = clone.querySelector('.login-server-url-error');
    if (err) {
      err.classList.remove('is-visible');
      err.textContent = '';
    }
    var rm = clone.querySelector('.login-server-remove');
    if (rm) {
      var freshRm = rm.cloneNode(true);
      rm.parentNode.replaceChild(freshRm, rm);
      bindRemove(freshRm);
    }
    var sv = clone.querySelector('.login-server-save');
    if (sv) {
      var freshSv = sv.cloneNode(true);
      sv.parentNode.replaceChild(freshSv, sv);
      bindSave(freshSv);
    }
    list.appendChild(clone);
    if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
  });
})();

function stepUp(id){
  var el = document.getElementById(id);
  if (!el) return;
  el.stepUp();
  if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
}

function stepDown(id){
  var el = document.getElementById(id);
  if (!el) return;
  el.stepDown();
  if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
}

window.togglePrivacyPolicyFields = function () {
  var sel = document.getElementById('privacy_policy_mode');
  var v = sel ? sel.value : 'url';
  var bUrl = document.getElementById('block_privacy_url');
  var bHtml = document.getElementById('block_privacy_html');
  if (bUrl && bHtml) {
    if (v === 'html') {
      bUrl.style.display = 'none';
      bHtml.style.display = '';
    } else {
      bUrl.style.display = '';
      bHtml.style.display = 'none';
    }
  }
  if (window.settingsUpdateDirtyState) window.settingsUpdateDirtyState();
};

(function(){
  var btn = document.getElementById('opensubtitles_password_toggle');
  var inp = document.getElementById('opensubtitles_password');
  var icon = document.getElementById('opensubtitles_password_icon');
  if (!btn || !inp || !icon) return;
  var labelShow = <?php echo json_encode($lang === 'ar' ? 'إظهار كلمة المرور' : 'Show password', JSON_UNESCAPED_UNICODE); ?>;
  var labelHide = <?php echo json_encode($lang === 'ar' ? 'إخفاء كلمة المرور' : 'Hide password', JSON_UNESCAPED_UNICODE); ?>;
  btn.addEventListener('click', function(){
    var show = inp.type === 'password';
    inp.type = show ? 'text' : 'password';
    icon.className = show ? 'fas fa-eye-slash' : 'fas fa-eye';
    btn.setAttribute('aria-label', show ? labelHide : labelShow);
  });
})();

(function(){
  var btn = document.getElementById('onesignal_rest_api_key_toggle');
  var inp = document.getElementById('onesignal_rest_api_key');
  var icon = document.getElementById('onesignal_rest_api_key_icon');
  if (!btn || !inp || !icon) return;
  var labelShow = <?php echo json_encode($lang === 'ar' ? 'إظهار المفتاح' : 'Show key', JSON_UNESCAPED_UNICODE); ?>;
  var labelHide = <?php echo json_encode($lang === 'ar' ? 'إخفاء المفتاح' : 'Hide key', JSON_UNESCAPED_UNICODE); ?>;
  btn.addEventListener('click', function(){
    var show = inp.type === 'password';
    inp.type = show ? 'text' : 'password';
    icon.className = show ? 'fas fa-eye-slash' : 'fas fa-eye';
    btn.setAttribute('aria-label', show ? labelHide : labelShow);
  });
})();

(function(){
  var form = document.getElementById('settingsMainForm');
  var savebar = document.getElementById('settingsSavebar');
  var savebarBtn = document.getElementById('settingsSavebarBtn');
  var savebarCount = document.getElementById('settingsSavebarCount');
  if (!form) return;

  var initialSnapshot = '';
  var saving = false;
  var toastTimer = null;
  var isAr = <?php echo json_encode($lang === 'ar'); ?>;
  var lblChangesAr = <?php echo json_encode('تعديلات غير محفوظة', JSON_UNESCAPED_UNICODE); ?>;
  var lblChangesEn = <?php echo json_encode('unsaved changes', JSON_UNESCAPED_UNICODE); ?>;
  var lblReviewAr = <?php echo json_encode('راجع التعديلات ثم احفظ.', JSON_UNESCAPED_UNICODE); ?>;
  var lblReviewEn = <?php echo json_encode('Review your edits, then save.', JSON_UNESCAPED_UNICODE); ?>;
  var msgSaved = <?php echo json_encode(t('msg.settings_saved'), JSON_UNESCAPED_UNICODE); ?>;
  var msgError = <?php echo json_encode(t('msg.settings_save_error'), JSON_UNESCAPED_UNICODE); ?>;

  function captureSnapshot() {
    if (!form) return '';
    var parts = [];

    form.querySelectorAll('input, textarea, select').forEach(function (el) {
      if (!el || !el.name) return;
      if (el.type === 'submit' || el.type === 'button' || el.type === 'file') return;
      if (el.name === 'csrf_token') return;
      if (el.name === 'login_server_name[]' || el.name === 'login_server_url[]') return;
      var assoc = el.getAttribute('form');
      if (assoc && assoc !== form.id) return;
      if (el.closest && el.closest('fieldset[disabled]')) return;

      if (el.type === 'checkbox') {
        parts.push(el.name + '\x1e' + (el.checked ? '1' : '0'));
        return;
      }
      if (el.type === 'radio') {
        if (!el.checked) return;
        parts.push(el.name + '\x1e' + String(el.value));
        return;
      }
      if (el.type === 'hidden') return;
      parts.push(el.name + '\x1e' + String(el.value == null ? '' : el.value));
    });

    form.querySelectorAll('.login-server-card').forEach(function (card, idx) {
      var nameInp = card.querySelector('[name="login_server_name[]"]');
      var urlInp = card.querySelector('[name="login_server_url[]"]');
      var name = nameInp ? String(nameInp.value || '') : '';
      var url = urlInp ? String(urlInp.value || '') : '';
      parts.push('login_server_row:' + idx + '\x1e' + name + '\x0f' + url);
    });

    parts.sort();
    return parts.join('\x1f');
  }

  function parseSnapshot(snap) {
    var map = Object.create(null);
    if (!snap) return map;
    snap.split('\x1f').forEach(function (part) {
      var sep = part.indexOf('\x1e');
      if (sep === -1) return;
      map[part.slice(0, sep)] = part.slice(sep + 1);
    });
    return map;
  }

  function countSnapshotDiff(baseSnap, currentSnap) {
    var base = parseSnapshot(baseSnap);
    var current = parseSnapshot(currentSnap);
    var keys = Object.create(null);
    Object.keys(base).forEach(function (k) { keys[k] = true; });
    Object.keys(current).forEach(function (k) { keys[k] = true; });
    var count = 0;
    Object.keys(keys).forEach(function (k) {
      if (String(base[k] || '') !== String(current[k] || '')) count++;
    });
    return count;
  }

  function formatChangeCount(n) {
    return isAr ? (n + ' ' + lblChangesAr) : (n + ' ' + lblChangesEn);
  }

  function updateDirtyState() {
    if (!savebar) return;
    var current = captureSnapshot();
    var diff = initialSnapshot !== '' ? countSnapshotDiff(initialSnapshot, current) : 0;
    var isDirty = diff > 0;
    savebar.classList.toggle('is-visible', isDirty);
    if (savebarCount) {
      savebarCount.textContent = isDirty
        ? formatChangeCount(diff)
        : (isAr ? lblReviewAr : lblReviewEn);
    }
  }
  window.settingsUpdateDirtyState = updateDirtyState;

  function ensureToast(){
    var el = document.getElementById('settingsAjaxToast');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'settingsAjaxToast';
    el.className = 'settings-ajax-toast';
    el.setAttribute('role', 'status');
    el.setAttribute('aria-live', 'polite');
    document.body.appendChild(el);
    return el;
  }

  function showToast(message, isError){
    var el = ensureToast();
    el.textContent = message || (isError ? msgError : msgSaved);
    el.classList.toggle('is-error', !!isError);
    el.classList.add('is-show');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function(){
      el.classList.remove('is-show');
    }, 2600);
  }

  function saveFullFormAjax(){
    if (saving) return;
    saving = true;
    var fd = new FormData(form);
    fd.append('settings_ajax', '1');
    if (typeof window.adminAppendCsrf === 'function') fd = window.adminAppendCsrf(fd);
    fetch(window.location.href, {
      method: 'POST',
      body: fd,
      credentials: 'same-origin',
      headers: window.adminCsrfHeaders({
        'X-Requested-With': 'XMLHttpRequest'
      })
    }).then(function(res){
      return res.json().then(function(data){
        return { ok: res.ok, data: data };
      }).catch(function(){
        return { ok: false, data: null };
      });
    }).then(function(result){
      saving = false;
      var data = result.data || {};
      if (result.ok && data.success) {
        showToast(data.message || msgSaved, false);
        initialSnapshot = captureSnapshot();
        updateDirtyState();
        return;
      }
      showToast((data && data.message) || msgError, true);
    }).catch(function(){
      saving = false;
      showToast(msgError, true);
    });
  }

  function refreshSnapshot() {
    initialSnapshot = captureSnapshot();
    updateDirtyState();
  }

  refreshSnapshot();
  setTimeout(refreshSnapshot, 0);

  form.addEventListener('input', updateDirtyState);
  form.addEventListener('change', updateDirtyState);

  form.addEventListener('keydown', function(e){
    if (e.key !== 'Enter') return;
    var t = e.target;
    if (!t || t.tagName === 'TEXTAREA' || t.tagName === 'BUTTON') return;
    e.preventDefault();
  });

  form.addEventListener('submit', function(e){
    e.preventDefault();
    saveFullFormAjax();
  });

  if (savebarBtn) {
    savebarBtn.addEventListener('click', function () {
      saveFullFormAjax();
    });
  }
})();

(function () {
  var STORAGE_KEY = 'novaSettingsActiveTab';
  var tabs = document.querySelectorAll('#nsSettingsNav .ns-setting__tab');
  var panes = document.querySelectorAll('.ns-pane[data-pane]');
  if (!tabs.length || !panes.length) return;

  function activate(paneId) {
    var found = false;
    panes.forEach(function (pane) {
      var match = pane.getAttribute('data-pane') === paneId;
      pane.classList.toggle('is-active', match);
      if (match) {
        pane.removeAttribute('hidden');
        found = true;
      } else {
        pane.setAttribute('hidden', '');
      }
    });
    tabs.forEach(function (tab) {
      var match = tab.getAttribute('data-pane') === paneId;
      tab.classList.toggle('is-active', match);
      tab.setAttribute('aria-selected', match ? 'true' : 'false');
    });
    if (!found) activate('app');
    try { localStorage.setItem(STORAGE_KEY, paneId); } catch (e) {}
  }

  var saved = '';
  try { saved = localStorage.getItem(STORAGE_KEY) || ''; } catch (e) {}
  var initial = saved && document.getElementById('ns-pane-' + saved) ? saved : 'app';
  activate(initial);

  tabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      activate(tab.getAttribute('data-pane') || 'app');
    });
  });
})();

</script>
</body>
</html> 
</html> 
</html> 