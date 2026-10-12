<?php
require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/includes/layout.php';

mp_require_unlocked();

if (isset($_GET['lang'])) {
    setcookie('mp_lang', $mpLang, time() + 31536000, '/');
    header('Location: dashboard.php');
    exit;
}

$deviceId = mp_session_device_id();
$device = mp_find_active_device($conn, $deviceId);
if (!$device || !mp_device_is_usable($device)) {
    unset($_SESSION['mp_device_id'], $_SESSION['mp_unlocked']);
    mp_flash_set('err', mp_t('err_device_not_found'));
    header('Location: index.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!mp_csrf_ok($_POST['_csrf'] ?? null)) {
        $isAjaxEarly = (
            (isset($_POST['ajax']) && (string)$_POST['ajax'] === '1')
            || (
                isset($_SERVER['HTTP_X_REQUESTED_WITH'])
                && strtolower((string)$_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest'
            )
        );
        if ($isAjaxEarly) {
            http_response_code(400);
            header('Content-Type: application/json; charset=utf-8');
            echo json_encode(['success' => false, 'message' => mp_t('err_csrf')], JSON_UNESCAPED_UNICODE);
            exit;
        }
        mp_flash_set('err', mp_t('err_csrf'));
        header('Location: dashboard.php');
        exit;
    }

    $action = (string)($_POST['action'] ?? '');
    $isAjax = (
        (isset($_POST['ajax']) && (string)$_POST['ajax'] === '1')
        || (
            isset($_SERVER['HTTP_X_REQUESTED_WITH'])
            && strtolower((string)$_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest'
        )
    );
    $jsonOut = static function (array $payload, int $code = 200) : void {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($payload, JSON_UNESCAPED_UNICODE);
        exit;
    };
    try {
        if ($action === 'add') {
            $name = trim((string)($_POST['name'] ?? ''));
            $url = trim((string)($_POST['m3u_url'] ?? ''));
            $pin = (string)($_POST['pin'] ?? '');
            $pin2 = (string)($_POST['pin_confirm'] ?? '');
            if ($name === '') {
                throw new RuntimeException(mp_t('err_name_required'));
            }
            if ($url === '' || !preg_match('#^https?://#i', $url)) {
                throw new RuntimeException(mp_t('err_url_required'));
            }
            if (strlen($pin) < 4) {
                throw new RuntimeException(mp_t('err_pin_short'));
            }
            if (!hash_equals($pin, $pin2)) {
                throw new RuntimeException(mp_t('err_pin_mismatch'));
            }
            $hash = password_hash($pin, PASSWORD_DEFAULT);
            $stmt = $conn->prepare(
                'INSERT INTO device_web_playlists (device_id, name, m3u_url, pin_hash) VALUES (?, ?, ?, ?)'
            );
            $stmt->execute([$deviceId, $name, $url, $hash]);
            mp_flash_set('ok', mp_t('ok_added'));
        } elseif ($action === 'edit') {
            $id = (int)($_POST['playlist_id'] ?? 0);
            $name = trim((string)($_POST['name'] ?? ''));
            $url = trim((string)($_POST['m3u_url'] ?? ''));
            $pin = (string)($_POST['pin'] ?? '');
            if ($id <= 0) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            if ($name === '') {
                throw new RuntimeException(mp_t('err_name_required'));
            }
            $stmt = $conn->prepare(
                'SELECT id, pin_hash, m3u_url FROM device_web_playlists WHERE id = ? AND device_id = ? LIMIT 1'
            );
            $stmt->execute([$id, $deviceId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            if ($pin === '' || !password_verify($pin, (string)$row['pin_hash'])) {
                throw new RuntimeException(mp_t('err_pin_wrong'));
            }
            if ($url === '') {
                $url = trim((string)($row['m3u_url'] ?? ''));
            }
            if ($url === '' || !preg_match('#^https?://#i', $url)) {
                throw new RuntimeException(mp_t('err_url_required'));
            }
            $upd = $conn->prepare(
                'UPDATE device_web_playlists SET name = ?, m3u_url = ?, updated_at = NOW() WHERE id = ? AND device_id = ?'
            );
            $upd->execute([$name, $url, $id, $deviceId]);
            mp_flash_set('ok', mp_t('ok_updated'));
        } elseif ($action === 'delete') {
            $id = (int)($_POST['playlist_id'] ?? 0);
            $pin = (string)($_POST['pin'] ?? '');
            if ($id <= 0) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            $stmt = $conn->prepare(
                'SELECT id, pin_hash FROM device_web_playlists WHERE id = ? AND device_id = ? LIMIT 1'
            );
            $stmt->execute([$id, $deviceId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            if ($pin === '' || !password_verify($pin, (string)$row['pin_hash'])) {
                throw new RuntimeException(mp_t('err_pin_wrong'));
            }
            $del = $conn->prepare('DELETE FROM device_web_playlists WHERE id = ? AND device_id = ?');
            $del->execute([$id, $deviceId]);
            mp_flash_set('ok', mp_t('ok_deleted'));
        } elseif ($action === 'reveal') {
            $id = (int)($_POST['playlist_id'] ?? 0);
            $pin = (string)($_POST['pin'] ?? '');
            if ($id <= 0) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            $stmt = $conn->prepare(
                'SELECT id, name, m3u_url, pin_hash FROM device_web_playlists WHERE id = ? AND device_id = ? LIMIT 1'
            );
            $stmt->execute([$id, $deviceId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            if ($pin === '' || !password_verify($pin, (string)$row['pin_hash'])) {
                throw new RuntimeException(mp_t('err_pin_wrong'));
            }
            $jsonOut([
                'success' => true,
                'url' => (string)($row['m3u_url'] ?? ''),
                'name' => (string)($row['name'] ?? ''),
            ]);
        } elseif ($action === 'logout') {
            mp_logout_full($conn);
            header('Location: index.php');
            exit;
        } elseif ($action === 'generate_app_code') {
            $name = trim((string)($_POST['app_code_name'] ?? ''));
            $url = trim((string)($_POST['app_code_url'] ?? ''));
            $codeMode = strtolower(trim((string)($_POST['app_code_mode'] ?? 'random')));
            $customCode = '';
            if ($codeMode === 'custom') {
                $customCode = (string)($_POST['app_code_custom'] ?? '');
            }
            if ($name === '') {
                throw new RuntimeException(mp_t('err_name_required'));
            }
            if ($url === '' || !preg_match('#^https?://#i', $url)) {
                throw new RuntimeException(mp_t('err_url_required'));
            }
            $created = mp_create_device_bound_playlist_code($conn, $deviceId, $name, $url, $customCode);
            if (empty($created['ok'])) {
                $err = (string)($created['error'] ?? '');
                if ($err === 'format') {
                    throw new RuntimeException(mp_t('err_app_code_format'));
                }
                if ($err === 'demo') {
                    throw new RuntimeException(mp_t('err_app_code_demo'));
                }
                if ($err === 'duplicate') {
                    throw new RuntimeException(mp_t('err_app_code_duplicate'));
                }
                if ($err === 'url') {
                    throw new RuntimeException(mp_t('err_url_required'));
                }
                throw new RuntimeException(mp_t('err_app_code_failed'));
            }
            mp_flash_set('ok', str_replace('@code', (string)($created['code'] ?? ''), mp_t('ok_app_code_created')));
        } elseif ($action === 'delete_app_code') {
            $codeId = (int)($_POST['app_code_id'] ?? 0);
            if ($codeId <= 0 || !mp_delete_device_bound_playlist_code($conn, $codeId, $deviceId)) {
                throw new RuntimeException(mp_t('err_generic'));
            }
            mp_flash_set('ok', mp_t('ok_app_code_deleted'));
        }
    } catch (PDOException $e) {
        $msg = $e->getMessage();
        $err = (stripos($msg, 'Duplicate') !== false || stripos($msg, 'uniq_device_m3u') !== false)
            ? mp_t('err_duplicate')
            : mp_t('err_generic');
        if ($isAjax) {
            $jsonOut(['success' => false, 'message' => $err], 400);
        }
        mp_flash_set('err', $err);
    } catch (RuntimeException $e) {
        if ($isAjax) {
            $jsonOut(['success' => false, 'message' => $e->getMessage()], 400);
        }
        mp_flash_set('err', $e->getMessage());
    }

    header('Location: dashboard.php');
    exit;
}

$flash = mp_flash_take();
$playlists = mp_list_playlists($conn, $deviceId);
$appCodes = mp_list_device_playlist_codes($conn, $deviceId);
$suggestedAppCode = mp_random_playlist_code_for_device($conn, $deviceId);
$remain = mp_remaining_activation($device);
$remainCardClass = 'remain-card';
if (mp_activation_needs_support_contact($remain)) {
    $remainCardClass .= empty($remain['ok']) ? ' is-expired-support' : ' is-renew-support';
}
$showWelcome = !empty($_SESSION['mp_show_welcome_back']);
unset($_SESSION['mp_show_welcome_back']);

mp_render_header(mp_t('dash_title'), 2);
?>
  <section class="<?php echo htmlspecialchars($remainCardClass); ?>" id="remainCard" aria-live="polite"
           data-device-id="<?php echo htmlspecialchars($deviceId, ENT_QUOTES, 'UTF-8'); ?>"
           data-renew-within="<?php echo (int)mp_activation_renew_within_days(); ?>"
           data-support-configured="<?php echo trim((string)$mpSupportUrl) !== '' ? '1' : '0'; ?>">
    <div class="remain-top">
      <div class="remain-ico" id="remainIco"><i class="fa-solid fa-hourglass-half"></i></div>
      <div class="remain-copy">
        <strong><?php echo htmlspecialchars(mp_t('remain_title')); ?></strong>
        <span>
          <?php echo htmlspecialchars(!empty($remain['lifetime']) ? mp_t('remain_until_life') : mp_t('remain_until')); ?>:
          <b id="remainUntil"><?php echo !empty($remain['lifetime']) ? '∞' : htmlspecialchars(date('Y-m-d H:i', (int)$remain['expiry_ts'])); ?></b>
        </span>
        <span class="remain-delta" id="remainDelta" hidden></span>
      </div>
      <div class="remain-big" id="remainBig"
           data-expiry="<?php echo (int)$remain['expiry_ts']; ?>"
           data-percent="<?php echo (int)$remain['percent']; ?>"
           data-lifetime="<?php echo !empty($remain['lifetime']) ? '1' : '0'; ?>"
           data-max-seconds="<?php echo (int)($remain['max_seconds'] ?? 0); ?>"
           data-days-label="<?php echo htmlspecialchars(mp_t('remain_days'), ENT_QUOTES, 'UTF-8'); ?>"
           data-hours-label="<?php echo htmlspecialchars(mp_t('remain_hours'), ENT_QUOTES, 'UTF-8'); ?>"
           data-mins-label="<?php echo htmlspecialchars(mp_t('remain_mins'), ENT_QUOTES, 'UTF-8'); ?>"
           data-expired-label="<?php echo htmlspecialchars(mp_t('remain_expired'), ENT_QUOTES, 'UTF-8'); ?>"
           data-lifetime-label="<?php echo htmlspecialchars(mp_t('remain_lifetime'), ENT_QUOTES, 'UTF-8'); ?>"
           data-until-life-label="<?php echo htmlspecialchars(mp_t('remain_until_life'), ENT_QUOTES, 'UTF-8'); ?>"
           data-until-label="<?php echo htmlspecialchars(mp_t('remain_until'), ENT_QUOTES, 'UTF-8'); ?>"
           data-extend-label="<?php echo htmlspecialchars(mp_t('remain_extended'), ENT_QUOTES, 'UTF-8'); ?>"
           data-shrink-label="<?php echo htmlspecialchars(mp_t('remain_shortened'), ENT_QUOTES, 'UTF-8'); ?>">
        <?php if (!empty($remain['lifetime'])): ?>
          <em id="remainDays">∞</em>
          <small id="remainDaysLabel"><?php echo htmlspecialchars(mp_t('remain_lifetime')); ?></small>
          <span class="remain-sub" id="remainSub" hidden></span>
        <?php elseif ($remain['ok']): ?>
          <em id="remainDays"><?php echo (int)$remain['days']; ?></em>
          <small id="remainDaysLabel"><?php echo htmlspecialchars(mp_t('remain_days')); ?></small>
          <span class="remain-sub" id="remainSub">
            <?php echo (int)$remain['hours']; ?> <?php echo htmlspecialchars(mp_t('remain_hours')); ?>
            ·
            <?php echo (int)$remain['mins']; ?> <?php echo htmlspecialchars(mp_t('remain_mins')); ?>
          </span>
        <?php else: ?>
          <em id="remainDays" class="is-expired"><?php echo htmlspecialchars(mp_t('remain_expired')); ?></em>
          <small id="remainDaysLabel" hidden></small>
          <span class="remain-sub" id="remainSub" hidden></span>
        <?php endif; ?>
      </div>
    </div>
    <div class="remain-bar" aria-hidden="true">
      <span id="remainBarFill" style="width: <?php echo (int)$remain['percent']; ?>%;"></span>
    </div>
    <?php mp_render_remain_support_cta($deviceId, $remain); ?>
  </section>

  <section class="panel-card" style="margin-bottom:1rem;">
    <div class="dash-head">
      <div class="dash-head__info">
        <div class="kicker"><i class="fa-solid fa-list-check"></i> Dashboard</div>
        <h1><?php echo htmlspecialchars(mp_t('dash_title')); ?></h1>
        <p class="lead"><?php echo htmlspecialchars(mp_t('dash_lead')); ?></p>
        <div class="device-chip">
          <i class="fa-solid fa-mobile-screen"></i>
          <?php echo htmlspecialchars($deviceId); ?>
        </div>
      </div>
      <form method="post" class="dash-head__logout">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="logout">
        <button type="submit" class="btn btn-secondary">
          <i class="fa-solid fa-right-from-bracket"></i>
          <?php echo htmlspecialchars(mp_t('btn_logout')); ?>
        </button>
      </form>
    </div>
    <?php if ($showWelcome): ?>
      <div class="alert alert-ok" style="margin-top:1rem;"><i class="fa-solid fa-circle-check"></i><span><?php echo htmlspecialchars(mp_t('welcome_back')); ?></span></div>
    <?php endif; ?>
    <?php mp_render_flash($flash); ?>
  </section>

  <div class="dash-grid">
    <section class="panel-card">
      <h2 style="font-size:1.2rem;margin:0 0 0.85rem;">
        <i class="fa-solid fa-rectangle-list" style="color:var(--accent);"></i>
        <?php echo htmlspecialchars(mp_t('dash_title')); ?>
      </h2>
      <?php if (!$playlists): ?>
        <div class="empty-state">
          <div><i class="fa-solid fa-folder-open"></i></div>
          <div><?php echo htmlspecialchars(mp_t('list_empty')); ?></div>
        </div>
      <?php else: ?>
        <div class="playlist-list">
          <?php foreach ($playlists as $p): ?>
            <article class="playlist-item">
              <div class="playlist-meta">
                <strong><?php echo htmlspecialchars((string)$p['name']); ?></strong>
                <span class="playlist-url-hidden">
                  <i class="fa-solid fa-eye-slash"></i>
                  <?php echo htmlspecialchars(mp_t('url_hidden')); ?>
                </span>
                <div class="badge"><i class="fa-solid fa-lock"></i> <?php echo htmlspecialchars(mp_t('list_protected')); ?></div>
              </div>
              <div class="playlist-actions">
                <button
                  type="button"
                  class="btn btn-secondary playlist-action-btn playlist-action-btn--show"
                  data-open-modal="revealModal"
                  data-id="<?php echo (int)$p['id']; ?>"
                  data-name="<?php echo htmlspecialchars((string)$p['name'], ENT_QUOTES, 'UTF-8'); ?>"
                >
                  <i class="fa-solid fa-eye"></i>
                  <span><?php echo htmlspecialchars(mp_t('action_show_url')); ?></span>
                </button>
                <button
                  type="button"
                  class="btn btn-secondary playlist-action-btn"
                  data-open-modal="editModal"
                  data-id="<?php echo (int)$p['id']; ?>"
                  data-name="<?php echo htmlspecialchars((string)$p['name'], ENT_QUOTES, 'UTF-8'); ?>"
                >
                  <i class="fa-solid fa-pen"></i>
                  <span><?php echo htmlspecialchars(mp_t('action_edit')); ?></span>
                </button>
                <button
                  type="button"
                  class="btn btn-danger-soft playlist-action-btn"
                  data-open-modal="deleteModal"
                  data-id="<?php echo (int)$p['id']; ?>"
                  data-name="<?php echo htmlspecialchars((string)$p['name'], ENT_QUOTES, 'UTF-8'); ?>"
                >
                  <i class="fa-solid fa-trash"></i>
                  <span><?php echo htmlspecialchars(mp_t('action_delete')); ?></span>
                </button>
              </div>
            </article>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </section>

    <div class="dash-side-stack">
    <section class="panel-card">
      <h2 class="panel-card__title">
        <i class="fa-solid fa-plus" style="color:var(--accent-2);"></i>
        <?php echo htmlspecialchars(mp_t('add_card_title')); ?>
      </h2>
      <form method="post" class="form-grid" autocomplete="off">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="add">
        <div class="field">
          <label for="name"><?php echo htmlspecialchars(mp_t('field_name')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-tag"></i></span>
            <input type="text" id="name" name="name" required maxlength="255">
          </div>
        </div>
        <div class="field">
          <label for="m3u_url"><?php echo htmlspecialchars(mp_t('field_url')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-link"></i></span>
            <input type="url" id="m3u_url" name="m3u_url" required placeholder="https://...">
          </div>
        </div>
        <div class="pin-pair">
          <div class="field">
            <label for="pin"><?php echo htmlspecialchars(mp_t('field_pin')); ?></label>
            <div class="input-wrap">
              <span class="ico"><i class="fa-solid fa-lock"></i></span>
              <input type="password" id="pin" name="pin" required minlength="4" maxlength="32">
            </div>
          </div>
          <div class="field">
            <label for="pin_confirm"><?php echo htmlspecialchars(mp_t('field_pin_confirm')); ?></label>
            <div class="input-wrap">
              <span class="ico"><i class="fa-solid fa-lock"></i></span>
              <input type="password" id="pin_confirm" name="pin_confirm" required minlength="4" maxlength="32">
            </div>
          </div>
        </div>
        <div class="actions actions--block">
          <button type="submit" class="btn btn-primary">
            <i class="fa-solid fa-plus"></i>
            <?php echo htmlspecialchars(mp_t('btn_add')); ?>
          </button>
        </div>
      </form>
    </section>

    <section class="panel-card panel-card--app-codes">
      <h2 class="panel-card__title">
        <i class="fa-solid fa-qrcode" style="color:var(--accent-2);"></i>
        <?php echo htmlspecialchars(mp_t('app_codes_title')); ?>
      </h2>
      <p class="panel-card__lead"><?php echo htmlspecialchars(mp_t('app_codes_lead_short')); ?></p>

      <?php if ($appCodes): ?>
        <div class="mp-app-codes-compact">
          <?php foreach ($appCodes as $ac): ?>
            <div class="mp-app-code-row">
              <div class="mp-app-code-row__main">
                <strong><?php echo htmlspecialchars((string)$ac['label']); ?></strong>
                <span class="mp-app-code-row__code"><?php echo htmlspecialchars((string)$ac['code']); ?></span>
                <span class="badge badge--sm">
                  <i class="fa-solid fa-<?php echo !empty($ac['redeemed']) ? 'circle-check' : 'hourglass-half'; ?>"></i>
                  <?php echo htmlspecialchars(!empty($ac['redeemed']) ? mp_t('app_code_used') : mp_t('app_code_pending')); ?>
                </span>
              </div>
              <form method="post" class="mp-app-code-row__del" onsubmit="return confirm(<?php echo json_encode(mp_t('app_code_delete_confirm'), JSON_UNESCAPED_UNICODE); ?>);">
                <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
                <input type="hidden" name="action" value="delete_app_code">
                <input type="hidden" name="app_code_id" value="<?php echo (int)$ac['id']; ?>">
                <button type="submit" class="btn btn-danger-soft btn-square" title="<?php echo htmlspecialchars(mp_t('action_delete'), ENT_QUOTES, 'UTF-8'); ?>">
                  <i class="fa-solid fa-trash"></i>
                </button>
              </form>
            </div>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>

      <form method="post" class="mp-app-code-form" id="appCodeForm" autocomplete="off">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="generate_app_code">
        <div class="mp-app-code-form-stack">
          <div class="field">
            <label for="app_code_name"><?php echo htmlspecialchars(mp_t('app_code_name_label')); ?></label>
            <div class="input-wrap">
              <span class="ico"><i class="fa-solid fa-tag"></i></span>
              <input type="text" id="app_code_name" name="app_code_name" required maxlength="255" placeholder="<?php echo htmlspecialchars(mp_t('app_code_name_ph')); ?>">
            </div>
          </div>

          <div class="field">
            <label for="app_code_url"><?php echo htmlspecialchars(mp_t('field_url')); ?></label>
            <div class="input-wrap">
              <span class="ico"><i class="fa-solid fa-link"></i></span>
              <input type="url" id="app_code_url" name="app_code_url" required placeholder="https://...">
            </div>
          </div>

          <div class="field">
            <span class="field-label"><?php echo htmlspecialchars(mp_t('app_code_mode_label')); ?></span>
            <div class="mp-pc-segment" role="radiogroup" aria-label="<?php echo htmlspecialchars(mp_t('app_code_mode_label'), ENT_QUOTES, 'UTF-8'); ?>">
              <label class="mp-pc-segment__item" title="<?php echo htmlspecialchars(mp_t('app_code_mode_random_desc'), ENT_QUOTES, 'UTF-8'); ?>">
                <input type="radio" name="app_code_mode" value="random" checked>
                <span class="mp-pc-segment__card">
                  <span class="mp-pc-segment__icon" aria-hidden="true"><i class="fa-solid fa-dice"></i></span>
                  <span class="mp-pc-segment__title"><?php echo htmlspecialchars(mp_t('app_code_mode_random')); ?></span>
                </span>
              </label>
              <label class="mp-pc-segment__item" title="<?php echo htmlspecialchars(mp_t('app_code_mode_custom_desc'), ENT_QUOTES, 'UTF-8'); ?>">
                <input type="radio" name="app_code_mode" value="custom">
                <span class="mp-pc-segment__card">
                  <span class="mp-pc-segment__icon" aria-hidden="true"><i class="fa-solid fa-keyboard"></i></span>
                  <span class="mp-pc-segment__title"><?php echo htmlspecialchars(mp_t('app_code_mode_custom')); ?></span>
                </span>
              </label>
            </div>

            <label class="field-label" for="app_code_custom"><?php echo htmlspecialchars(mp_t('app_code_custom_label')); ?></label>
            <div class="mp-code-group" id="mpCodeGroup">
              <div class="input-wrap input-wrap--mono mp-code-group__field">
                <span class="ico"><i class="fa-solid fa-hashtag"></i></span>
                <input type="text"
                       id="app_code_custom"
                       name="app_code_custom"
                       class="code-field-input"
                       value="<?php echo htmlspecialchars($suggestedAppCode); ?>"
                       inputmode="numeric"
                       pattern="[0-9]{5,6}"
                       maxlength="6"
                       placeholder="••••••"
                       autocomplete="off"
                       readonly>
              </div>
              <button type="button" class="mp-code-group__gen" id="appCodeRegenBtn">
                <i class="fa-solid fa-dice"></i>
                <?php echo htmlspecialchars(mp_t('btn_regen_app_code')); ?>
              </button>
            </div>
            <p class="hint hint--tight" id="appCodeHint"><?php echo htmlspecialchars(mp_t('app_code_mode_random_desc')); ?></p>
          </div>

          <div class="actions actions--block">
            <button type="submit" class="btn btn-primary">
              <i class="fa-solid fa-wand-magic-sparkles"></i>
              <?php echo htmlspecialchars(mp_t('btn_generate_app_code')); ?>
            </button>
          </div>
        </div>
      </form>
      <script>
      (function () {
        var form = document.getElementById('appCodeForm');
        if (!form) return;
        var codeInput = document.getElementById('app_code_custom');
        var codeGroup = document.getElementById('mpCodeGroup');
        var regenBtn = document.getElementById('appCodeRegenBtn');
        var hintEl = document.getElementById('appCodeHint');
        var modeInputs = form.querySelectorAll('input[name="app_code_mode"]');
        var modeOpts = form.querySelectorAll('.mp-pc-segment__item');
        var hintRandom = <?php echo json_encode(mp_t('app_code_mode_random_desc'), JSON_UNESCAPED_UNICODE); ?>;
        var hintCustom = <?php echo json_encode(mp_t('app_code_custom_hint'), JSON_UNESCAPED_UNICODE); ?>;
        var lastRandomCode = codeInput ? codeInput.value : '';

        function genLocal() {
          var n = Math.floor(10000 + Math.random() * 900000);
          var s = String(n);
          if (s.length > 6) s = s.slice(0, 6);
          while (s.length < 5) s = '0' + s;
          if (s === '00000') s = '10001';
          return s;
        }

        function syncMode() {
          var mode = 'random';
          modeInputs.forEach(function (r) { if (r.checked) mode = r.value; });
          var isCustom = mode === 'custom';
          modeOpts.forEach(function (el) {
            var input = el.querySelector('input[type="radio"]');
            el.classList.toggle('is-active', !!(input && input.checked));
          });
          if (codeGroup) codeGroup.classList.toggle('mp-code-group--custom', isCustom);
          if (codeInput) {
            codeInput.readOnly = !isCustom;
            codeInput.required = isCustom;
            if (isCustom) {
              codeInput.value = '';
              codeInput.placeholder = '123456';
              codeInput.focus();
            } else {
              codeInput.placeholder = '••••••';
              codeInput.value = lastRandomCode || genLocal();
              lastRandomCode = codeInput.value;
            }
          }
          if (regenBtn) {
            regenBtn.hidden = isCustom;
            regenBtn.disabled = isCustom;
            regenBtn.style.display = isCustom ? 'none' : '';
            regenBtn.setAttribute('aria-hidden', isCustom ? 'true' : 'false');
          }
          if (hintEl) hintEl.textContent = isCustom ? hintCustom : hintRandom;
        }

        modeInputs.forEach(function (r) {
          r.addEventListener('change', syncMode);
          r.addEventListener('click', syncMode);
        });
        modeOpts.forEach(function (chip) {
          chip.addEventListener('click', function () {
            window.requestAnimationFrame(syncMode);
          });
        });
        if (regenBtn && codeInput) {
          regenBtn.addEventListener('click', function () {
            lastRandomCode = genLocal();
            codeInput.value = lastRandomCode;
          });
        }
        form.addEventListener('submit', function () {
          var mode = 'random';
          modeInputs.forEach(function (r) { if (r.checked) mode = r.value; });
          if (mode === 'random' && codeInput) codeInput.value = '';
        });
        syncMode();
      })();
      </script>
    </section>
    </div>
  </div>

  <div class="modal-backdrop" id="editModal" role="dialog" aria-modal="true">
    <div class="modal">
      <div class="modal-handle" aria-hidden="true"></div>
      <h3><i class="fa-solid fa-pen"></i> <?php echo htmlspecialchars(mp_t('modal_edit_title')); ?></h3>
      <p><?php echo htmlspecialchars(mp_t('modal_pin_required')); ?></p>
      <form method="post" class="form-grid" autocomplete="off">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="edit">
        <input type="hidden" name="playlist_id" id="editPlaylistId" value="">
        <div class="field">
          <label for="editName"><?php echo htmlspecialchars(mp_t('field_name')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-tag"></i></span>
            <input type="text" id="editName" name="name" required maxlength="255">
          </div>
        </div>
        <div class="field">
          <label for="editUrl"><?php echo htmlspecialchars(mp_t('field_url')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-link"></i></span>
            <input type="url" id="editUrl" name="m3u_url" placeholder="<?php echo htmlspecialchars(mp_t('field_url_keep')); ?>">
          </div>
          <div class="hint"><?php echo htmlspecialchars(mp_t('field_url_keep')); ?></div>
        </div>
        <div class="field">
          <label for="editPin"><?php echo htmlspecialchars(mp_t('field_pin_current')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-lock"></i></span>
            <input type="password" id="editPin" name="pin" required minlength="4" maxlength="32" autocomplete="off" inputmode="numeric">
          </div>
        </div>
        <div class="actions">
          <button type="button" class="btn btn-ghost" data-close-modal="editModal"><?php echo htmlspecialchars(mp_t('btn_cancel')); ?></button>
          <button type="submit" class="btn btn-primary"><i class="fa-solid fa-check"></i> <?php echo htmlspecialchars(mp_t('btn_save')); ?></button>
        </div>
      </form>
    </div>
  </div>

  <div class="modal-backdrop" id="revealModal" role="dialog" aria-modal="true">
    <div class="modal">
      <div class="modal-handle" aria-hidden="true"></div>
      <h3><i class="fa-solid fa-eye"></i> <?php echo htmlspecialchars(mp_t('modal_reveal_title')); ?></h3>
      <p><?php echo htmlspecialchars(mp_t('modal_reveal_lead')); ?> (<strong id="revealPlaylistName"></strong>)</p>
      <form method="post" class="form-grid" id="revealForm" autocomplete="off">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="reveal">
        <input type="hidden" name="ajax" value="1">
        <input type="hidden" name="playlist_id" id="revealPlaylistId" value="">
        <div class="field" id="revealPinField">
          <label for="revealPin"><?php echo htmlspecialchars(mp_t('field_pin_current')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-lock"></i></span>
            <input type="password" id="revealPin" name="pin" required minlength="4" maxlength="32" autocomplete="off" inputmode="numeric">
          </div>
        </div>
        <div class="reveal-error" id="revealError" hidden></div>
        <div class="reveal-result" id="revealResult" hidden>
          <label><?php echo htmlspecialchars(mp_t('field_url')); ?></label>
          <div class="reveal-url-box" id="revealUrlBox"></div>
        </div>
        <div class="actions">
          <button type="button" class="btn btn-ghost" data-close-modal="revealModal"><?php echo htmlspecialchars(mp_t('btn_cancel')); ?></button>
          <button type="submit" class="btn btn-primary" id="revealSubmitBtn">
            <i class="fa-solid fa-eye"></i>
            <span><?php echo htmlspecialchars(mp_t('btn_reveal')); ?></span>
          </button>
          <button type="button" class="btn btn-secondary" id="revealCopyBtn" hidden data-copied="<?php echo htmlspecialchars(mp_t('url_copied'), ENT_QUOTES, 'UTF-8'); ?>">
            <i class="fa-solid fa-copy"></i>
            <span><?php echo htmlspecialchars(mp_t('btn_copy')); ?></span>
          </button>
        </div>
      </form>
    </div>
  </div>

  <div class="modal-backdrop" id="deleteModal" role="dialog" aria-modal="true">
    <div class="modal">
      <div class="modal-handle" aria-hidden="true"></div>
      <h3><i class="fa-solid fa-trash"></i> <?php echo htmlspecialchars(mp_t('modal_delete_title')); ?></h3>
      <p>
        <?php echo htmlspecialchars(mp_t('modal_pin_required')); ?>
        (<strong id="deletePlaylistName"></strong>)
      </p>
      <form method="post" class="form-grid" autocomplete="off">
        <input type="hidden" name="_csrf" value="<?php echo htmlspecialchars(mp_csrf_token()); ?>">
        <input type="hidden" name="action" value="delete">
        <input type="hidden" name="playlist_id" id="deletePlaylistId" value="">
        <div class="field">
          <label for="deletePin"><?php echo htmlspecialchars(mp_t('field_pin_current')); ?></label>
          <div class="input-wrap">
            <span class="ico"><i class="fa-solid fa-lock"></i></span>
            <input type="password" id="deletePin" name="pin" required minlength="4" maxlength="32" autocomplete="off" inputmode="numeric">
          </div>
        </div>
        <div class="actions">
          <button type="button" class="btn btn-ghost" data-close-modal="deleteModal"><?php echo htmlspecialchars(mp_t('btn_cancel')); ?></button>
          <button type="submit" class="btn btn-danger-soft"><i class="fa-solid fa-trash"></i> <?php echo htmlspecialchars(mp_t('btn_confirm')); ?></button>
        </div>
      </form>
    </div>
  </div>
<?php
mp_render_footer();
