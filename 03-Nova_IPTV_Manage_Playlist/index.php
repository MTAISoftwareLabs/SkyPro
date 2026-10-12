<?php
require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/includes/layout.php';

if (isset($_GET['lang'])) {
    setcookie('mp_lang', $mpLang, time() + 31536000, '/');
    // حافظ على device_id عند تبديل اللغة حتى لا تفرّغ الخانة
    $qs = $_GET;
    unset($qs['lang']);
    $target = 'index.php';
    if (!empty($qs)) {
        $target .= '?' . http_build_query($qs);
    }
    header('Location: ' . $target);
    exit;
}

// معرف الجهاز من رابط التطبيق (?device_id=...) — لملء الخانة تلقائياً
$incomingDeviceId = mp_normalize_device_id(
    (string)($_GET['device_id'] ?? $_GET['deviceId'] ?? $_GET['id'] ?? '')
);

// قادم من التطبيق بمعرّف جهاز: مفعّل → القوائم مباشرة، منتهٍ/محظور → رسالة خطأ
if ($incomingDeviceId !== '' && $_SERVER['REQUEST_METHOD'] !== 'POST' && empty($_GET['switch'])) {
    $incomingDev = mp_find_active_device($conn, $incomingDeviceId);
    if ($incomingDev) {
        $incomingStatus = strtolower(trim((string)($incomingDev['status'] ?? '')));
        if ($incomingStatus === 'blocked') {
            mp_flash_set('err', mp_t('err_device_blocked'));
        } elseif (!mp_device_is_usable($incomingDev)) {
            mp_flash_set('err', mp_t('err_device_expired'));
        } else {
            $_SESSION['mp_device_id'] = trim((string)($incomingDev['device_id'] ?? $incomingDeviceId));
            mp_open_active_session($incomingDev);
            header('Location: dashboard.php');
            exit;
        }
    }
}

// جلسة مفتوحة مسبقاً والجهاز ما زال مفعّلاً → لوحة القوائم
if (mp_session_unlocked()) {
    $sid = mp_session_device_id();
    $dev = $sid !== '' ? mp_find_active_device($conn, $sid) : null;

    if ($incomingDeviceId !== '') {
        if ($sid !== '' && strcasecmp($incomingDeviceId, $sid) !== 0) {
            unset(
                $_SESSION['mp_unlocked'],
                $_SESSION['mp_unlocked_at'],
                $_SESSION['mp_bound_code'],
                $_SESSION['mp_device_id']
            );
        } elseif (!$dev || !mp_device_is_usable($dev)) {
            unset($_SESSION['mp_unlocked'], $_SESSION['mp_unlocked_at'], $_SESSION['mp_bound_code']);
        }
    } elseif ($dev && mp_device_is_usable($dev) && empty($_GET['switch'])) {
        header('Location: dashboard.php');
        exit;
    } elseif (!$dev || !mp_device_is_usable($dev)) {
        unset($_SESSION['mp_unlocked'], $_SESSION['mp_unlocked_at'], $_SESSION['mp_bound_code']);
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!mp_csrf_ok($_POST['_csrf'] ?? null)) {
        mp_flash_set('err', mp_t('err_csrf'));
        header('Location: index.php');
        exit;
    }
    $deviceId = mp_normalize_device_id((string)($_POST['device_id'] ?? ''));
    if ($deviceId === '') {
        mp_flash_set('err', mp_t('err_device_required'));
        header('Location: index.php');
        exit;
    }
    $device = mp_find_active_device($conn, $deviceId);
    if (!$device) {
        mp_flash_set('err', mp_t('err_device_not_found'));
        header('Location: index.php');
        exit;
    }
    $status = strtolower(trim((string)($device['status'] ?? '')));
    if ($status === 'blocked') {
        mp_flash_set('err', mp_t('err_device_blocked'));
        header('Location: index.php');
        exit;
    }

    $storedId = trim((string)($device['device_id'] ?? $deviceId));
    $_SESSION['mp_device_id'] = $storedId;

    if (!mp_device_is_usable($device)) {
        if ($status === 'blocked') {
            mp_flash_set('err', mp_t('err_device_blocked'));
        } else {
            mp_flash_set('err', mp_t('err_device_expired'));
        }
        header('Location: index.php');
        exit;
    }

    mp_open_active_session($device);
    $_SESSION['mp_show_welcome_back'] = 1;
    header('Location: dashboard.php');
    exit;
}

$flash = mp_flash_take();
$prefill = $incomingDeviceId !== '' ? $incomingDeviceId : mp_session_device_id();

$supportDeviceId = '';
$supportRemain = null;
$supportCheckId = $prefill !== '' ? $prefill : $incomingDeviceId;
if ($supportCheckId !== '') {
    $supportDev = mp_find_active_device($conn, $supportCheckId);
    if ($supportDev) {
        $supportRemain = mp_remaining_activation($supportDev);
        if (mp_activation_needs_support_contact($supportRemain)) {
            $supportDeviceId = trim((string)($supportDev['device_id'] ?? $supportCheckId));
        } else {
            $supportRemain = null;
        }
    }
}

mp_render_header(mp_t('home_title'), 1);
?>
  <section class="hero-card">
    <div class="kicker"><i class="fa-solid fa-satellite-dish"></i> Nova</div>
    <h1><?php echo htmlspecialchars(mp_t('home_title')); ?></h1>
    <p class="lead"><?php echo htmlspecialchars(mp_t('home_lead')); ?></p>
    <?php mp_render_flash($flash); ?>

    <form method="post" class="form-grid" autocomplete="off">
      <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
      <div class="field">
        <label for="device_id"><?php echo htmlspecialchars(mp_t('device_label')); ?></label>
        <div class="input-wrap">
          <span class="ico"><i class="fa-solid fa-mobile-screen"></i></span>
          <input
            type="text"
            id="device_id"
            name="device_id"
            required
            value="<?php echo htmlspecialchars($prefill); ?>"
            placeholder="<?php echo htmlspecialchars(mp_t('device_placeholder')); ?>"
            autocomplete="off"
            inputmode="text"
            spellcheck="false"
          >
        </div>
        <div class="hint"><?php echo htmlspecialchars(mp_t('device_help')); ?></div>
      </div>
      <div class="actions">
        <button type="submit" class="btn btn-primary">
          <i class="fa-solid fa-arrow-<?php echo $mpRtl ? 'left' : 'right'; ?>"></i>
          <?php echo htmlspecialchars(mp_t('btn_next')); ?>
        </button>
      </div>
    </form>
  </section>
<?php if ($supportRemain !== null && $supportDeviceId !== ''): ?>
  <section class="remain-card remain-card--home<?php echo empty($supportRemain['ok']) ? ' is-expired-support' : ' is-renew-support'; ?>" id="remainCard" aria-live="polite"
           data-device-id="<?php echo htmlspecialchars($supportDeviceId, ENT_QUOTES, 'UTF-8'); ?>"
           data-renew-within="<?php echo (int)mp_activation_renew_within_days(); ?>"
           data-support-configured="<?php echo trim((string)$mpSupportUrl) !== '' ? '1' : '0'; ?>">
    <div class="remain-top">
      <div class="remain-ico remain-ico--warn"><i class="fa-solid fa-hourglass-end"></i></div>
      <div class="remain-copy">
        <strong><?php echo htmlspecialchars(mp_t('remain_title')); ?></strong>
        <span>
          <?php echo htmlspecialchars(!empty($supportRemain['lifetime']) ? mp_t('remain_until_life') : mp_t('remain_until')); ?>:
          <b id="remainUntil"><?php echo !empty($supportRemain['lifetime']) ? '∞' : htmlspecialchars(date('Y-m-d H:i', (int)$supportRemain['expiry_ts'])); ?></b>
        </span>
      </div>
      <div class="remain-big" id="remainBig"
           data-expiry="<?php echo (int)$supportRemain['expiry_ts']; ?>"
           data-percent="<?php echo (int)$supportRemain['percent']; ?>"
           data-lifetime="<?php echo !empty($supportRemain['lifetime']) ? '1' : '0'; ?>"
           data-expired-label="<?php echo htmlspecialchars(mp_t('remain_expired'), ENT_QUOTES, 'UTF-8'); ?>">
        <?php if (empty($supportRemain['ok'])): ?>
          <em id="remainDays" class="is-expired"><?php echo htmlspecialchars(mp_t('remain_expired')); ?></em>
        <?php else: ?>
          <em id="remainDays"><?php echo (int)$supportRemain['days']; ?></em>
          <small id="remainDaysLabel"><?php echo htmlspecialchars(mp_t('remain_days')); ?></small>
        <?php endif; ?>
      </div>
    </div>
    <div class="remain-bar" aria-hidden="true">
      <span id="remainBarFill" style="width: <?php echo (int)$supportRemain['percent']; ?>%;"></span>
    </div>
    <?php mp_render_remain_support_cta($supportDeviceId, $supportRemain); ?>
  </section>
<?php endif; ?>
  <script>
  (function () {
    var el = document.getElementById('device_id');
    if (!el) return;

    function pickId() {
      try {
        var u = new URL(window.location.href);
        var id = u.searchParams.get('device_id')
          || u.searchParams.get('deviceId')
          || u.searchParams.get('id')
          || '';
        if (!id && u.hash) {
          var raw = u.hash.replace(/^#/, '');
          if (raw.indexOf('=') >= 0) {
            var hp = new URLSearchParams(raw);
            id = hp.get('device_id') || hp.get('deviceId') || hp.get('did') || '';
          } else if (raw) {
            id = decodeURIComponent(raw);
          }
        }
        return (id || '').replace(/\s+/g, '').trim();
      } catch (e) {
        return '';
      }
    }

    var id = pickId();
    if (id && !String(el.value || '').trim()) {
      el.value = id;
    }
  })();
  </script>
<?php
mp_render_footer();
