<?php
function mp_render_header(string $title, int $step = 1): void
{
    global $mpLang, $mpRtl, $mpAppName;
    $dir = $mpRtl ? 'rtl' : 'ltr';
    $themeBoot = <<<'JS'
(function(){try{var t=localStorage.getItem('mp_theme');document.documentElement.setAttribute('data-theme',t==='light'?'light':'dark');}catch(e){document.documentElement.setAttribute('data-theme','dark');}})();
JS;
    ?>
<!DOCTYPE html>
<html lang="<?php echo htmlspecialchars($mpLang); ?>" dir="<?php echo $dir; ?>" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover, interactive-widget=resizes-content">
  <title><?php echo htmlspecialchars($title . ' — ' . $mpAppName); ?></title>
  <script><?php echo $themeBoot; ?></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css" crossorigin="anonymous" referrerpolicy="no-referrer">
  <link rel="icon" type="image/png" sizes="32x32" href="assets/images/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="assets/images/favicon-16x16.png">
  <link rel="apple-touch-icon" sizes="180x180" href="assets/images/apple-touch-icon.png">
  <link rel="shortcut icon" href="favicon.ico">
  <link rel="stylesheet" href="assets/css/app.css?v=stv-remain-1">
</head>
<body>
  <div class="bg-glow" aria-hidden="true"></div>
  <header class="topbar">
    <div class="brand">
      <img src="assets/images/skypro_logo.png" alt="SkyPro" style="width:36px;height:36px;object-fit:contain;border-radius:8px;box-shadow:0 0 12px rgba(0,123,255,0.45);">
      <div class="brand-text">
        <strong><?php echo htmlspecialchars($mpAppName); ?></strong>
        <span><?php echo htmlspecialchars(mp_t('brand_sub')); ?></span>
      </div>
    </div>
    <div class="top-controls">
      <div class="theme-bar">
        <div class="theme-bar-label">
          <strong class="theme-mode-title"><?php echo htmlspecialchars(mp_t('theme_dark')); ?></strong>
          <span class="theme-mode-hint"><?php echo htmlspecialchars(mp_t('theme_hint_dark')); ?></span>
        </div>
        <button type="button" class="theme-toggle" id="themeToggle" aria-label="<?php echo htmlspecialchars(mp_t('theme_toggle')); ?>">
          <span class="theme-icons" aria-hidden="true">
            <i class="fa-solid fa-moon icon-moon"></i>
            <i class="fa-solid fa-sun icon-sun"></i>
          </span>
          <span class="theme-thumb" aria-hidden="true"></span>
        </button>
      </div>
      <div class="lang-toggle" role="group" aria-label="Language">
        <a class="lang-btn<?php echo $mpLang === 'en' ? ' is-active' : ''; ?>" href="?lang=en">EN</a>
        <a class="lang-btn<?php echo $mpLang === 'ar' ? ' is-active' : ''; ?>" href="?lang=ar">AR</a>
      </div>
    </div>
  </header>

  <nav class="steps" aria-label="Progress">
    <div class="step<?php echo $step >= 1 ? ' is-active' : ''; ?><?php echo $step > 1 ? ' is-done' : ''; ?>">
      <span class="step-ico"><i class="fa-solid fa-mobile-screen"></i></span>
      <span><?php echo htmlspecialchars(mp_t('step_device')); ?></span>
    </div>
    <div class="step-line" aria-hidden="true"></div>
    <div class="step<?php echo $step >= 2 ? ' is-active' : ''; ?>">
      <span class="step-ico"><i class="fa-solid fa-list-ul"></i></span>
      <span><?php echo htmlspecialchars(mp_t('step_playlists')); ?></span>
    </div>
  </nav>

  <main class="shell">
<?php
}

function mp_render_footer(): void
{
    ?>
  </main>
  <footer class="site-footer">
    <i class="fa-solid fa-circle-info"></i>
    <span><?php echo htmlspecialchars(mp_t('footer_note')); ?></span>
  </footer>
  <script src="assets/js/app.js?v=stv-remain-1"></script>
</body>
</html>
<?php
}

function mp_render_flash(?array $flash): void
{
    if (!$flash) {
        return;
    }
    $type = ($flash['type'] ?? '') === 'ok' ? 'ok' : 'err';
    $icon = $type === 'ok' ? 'fa-circle-check' : 'fa-triangle-exclamation';
    echo '<div class="alert alert-' . $type . '" role="alert">';
    echo '<i class="fa-solid ' . $icon . '"></i>';
    echo '<span>' . htmlspecialchars((string)($flash['message'] ?? '')) . '</span>';
    echo '</div>';
}

/**
 * زر تواصل مع الدعم داخل بطاقة مدة التفعيل.
 * يُرسم دائماً (مخفي إن لم يُحتج) حتى يقدر JS يُظهره عند اقتراب الانتهاء.
 * Renew: متبقي < 5 أيام | Activate: منتهي | مخفي: Lifetime أو ≥ 5 أيام.
 */
function mp_render_remain_support_cta(string $deviceId, array $remain, ?bool $forceHidden = null): void
{
    global $mpSupportUrl;
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return;
    }
    $needs = mp_activation_needs_support_contact($remain);
    $hidden = $forceHidden !== null ? (bool)$forceHidden : !$needs;
    $kind = mp_support_contact_kind($remain);
    $href = mp_build_support_contact_url($deviceId, $kind);
    $hintKey = $kind === 'expired' ? 'contact_support_expired_hint' : 'contact_support_renew_hint';
    $btnKey = $kind === 'expired' ? 'contact_support_btn_activate' : 'contact_support_btn_renew';
    $icon = $kind === 'expired' ? 'fa-key' : 'fa-rotate-right';
    $hrefRenew = mp_build_support_contact_url($deviceId, 'renew');
    $hrefExpired = mp_build_support_contact_url($deviceId, 'expired');
    ?>
    <div class="remain-support" id="remainSupport"
         data-kind="<?php echo htmlspecialchars($kind, ENT_QUOTES, 'UTF-8'); ?>"
         data-hint-renew="<?php echo htmlspecialchars(mp_t('contact_support_renew_hint'), ENT_QUOTES, 'UTF-8'); ?>"
         data-hint-expired="<?php echo htmlspecialchars(mp_t('contact_support_expired_hint'), ENT_QUOTES, 'UTF-8'); ?>"
         data-btn-renew="<?php echo htmlspecialchars(mp_t('contact_support_btn_renew'), ENT_QUOTES, 'UTF-8'); ?>"
         data-btn-expired="<?php echo htmlspecialchars(mp_t('contact_support_btn_activate'), ENT_QUOTES, 'UTF-8'); ?>"
         data-href-renew="<?php echo htmlspecialchars($hrefRenew, ENT_QUOTES, 'UTF-8'); ?>"
         data-href-expired="<?php echo htmlspecialchars($hrefExpired, ENT_QUOTES, 'UTF-8'); ?>"
         <?php if ($hidden): ?>hidden<?php endif; ?>>
      <div class="remain-support__copy">
        <span class="remain-support__ico" aria-hidden="true"><i class="fa-solid fa-headset"></i></span>
        <p id="remainSupportHint"><?php echo htmlspecialchars(mp_t($hintKey)); ?></p>
      </div>
      <?php if (trim((string)$mpSupportUrl) !== '' && ($href !== '' || $hrefRenew !== '' || $hrefExpired !== '')): ?>
        <a
          class="btn btn-contact remain-support__btn"
          id="remainSupportBtn"
          href="<?php echo htmlspecialchars($href !== '' ? $href : ($hrefExpired !== '' ? $hrefExpired : $hrefRenew), ENT_QUOTES, 'UTF-8'); ?>"
          target="_blank"
          rel="noopener noreferrer"
        >
          <i class="fa-solid <?php echo htmlspecialchars($icon, ENT_QUOTES, 'UTF-8'); ?>" id="remainSupportBtnIco"></i>
          <span id="remainSupportBtnLabel"><?php echo htmlspecialchars(mp_t($btnKey)); ?></span>
          <i class="fa-solid fa-arrow-up-right-from-square remain-support__ext" aria-hidden="true"></i>
        </a>
      <?php else: ?>
        <div class="remain-support__missing">
          <i class="fa-solid fa-circle-info"></i>
          <span><?php echo htmlspecialchars(mp_t('no_support')); ?></span>
        </div>
      <?php endif; ?>
    </div>
    <?php
}
