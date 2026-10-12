<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$current_page = 'feedbacks';
$canDeleteFeedback = adminCan('feedbacks_delete');

$flashMsg = '';
$flashType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_feedback_id'])) {
    admin_require_csrf();
    if (!adminCan('feedbacks_delete')) {
        header('Location: access_denied.php?perm=feedbacks_delete');
        exit();
    }
    $fid = (int)$_POST['delete_feedback_id'];
    if ($fid > 0 && deleteClientFeedbackById($conn, $fid)) {
        header('Location: feedbacks.php?msg=deleted');
        exit();
    }
    header('Location: feedbacks.php?msg=error');
    exit();
}

if (isset($_GET['msg'])) {
    if ($_GET['msg'] === 'deleted') {
        $flashMsg = t('feedbacks.deleted_ok');
        $flashType = 'success';
    } elseif ($_GET['msg'] === 'error') {
        $flashMsg = t('feedbacks.delete_error');
        $flashType = 'danger';
    }
}

markAllFeedbackAsRead($conn);
$feedbacks = getClientFeedbacks($conn);
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('nav.feedbacks'); ?> - <?php echo t('app.title'); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Cairo', system-ui, sans-serif; }
        .fb-shell { margin-top: 8px; }
        .fb-alert {
            border-radius: 14px;
            border: 1px solid rgba(148,163,184,0.35);
            padding: 0.85rem 1.1rem;
            margin-bottom: 1.25rem;
        }
        .fb-card {
            border-radius: 14px;
            overflow: hidden;
            margin-bottom: 0.65rem;
            background: radial-gradient(circle at 0% 0%, rgba(56,189,248,0.08), transparent 50%),
                        radial-gradient(circle at 100% 100%, rgba(99,102,241,0.07), transparent 45%),
                        linear-gradient(165deg, rgba(15,23,42,0.97), rgba(3,7,18,0.99));
            border: 1px solid rgba(148,163,184,0.22);
            box-shadow: 0 8px 24px rgba(2,6,23,0.4);
        }
        .fb-card-head {
            padding: 0.65rem 0.9rem;
            background: linear-gradient(135deg, rgba(56,189,248,0.18), rgba(99,102,241,0.12));
            border-bottom: 1px solid rgba(148,163,184,0.18);
            display: flex;
            flex-wrap: wrap;
            align-items: flex-start;
            justify-content: space-between;
            gap: 1rem;
        }
        .fb-device-name {
            font-size: 0.92rem;
            font-weight: 800;
            color: #f8fafc;
            display: flex;
            align-items: center;
            gap: 0.45rem;
        }
        .fb-device-name i {
            width: 32px;
            height: 32px;
            border-radius: 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #38bdf8, #6366f1);
            color: #0b1120;
            font-size: 0.85rem;
            flex-shrink: 0;
        }
        .fb-meta-row {
            display: flex;
            flex-wrap: wrap;
            gap: 0.35rem;
            margin-top: 0.4rem;
        }
        .fb-pill {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.22rem 0.55rem;
            border-radius: 999px;
            font-size: 0.72rem;
            font-weight: 600;
            background: rgba(15,23,42,0.75);
            border: 1px solid rgba(148,163,184,0.25);
            color: #cbd5e1;
        }
        .fb-pill code {
            color: #38bdf8;
            font-size: 0.78rem;
            background: transparent;
        }
        .fb-actions {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            align-items: center;
        }
        .fb-btn {
            border-radius: 999px;
            padding: 0.32rem 0.75rem;
            font-size: 0.75rem;
            font-weight: 700;
            border: none;
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            transition: filter 0.15s ease, transform 0.12s ease;
        }
        .fb-btn:hover { filter: brightness(1.08); transform: translateY(-1px); }
        .fb-btn-open {
            background: linear-gradient(135deg, #38bdf8, #6366f1);
            color: #0b1120;
        }
        .fb-btn-copy {
            background: rgba(148,163,184,0.2);
            color: #e2e8f0;
            border: 1px solid rgba(148,163,184,0.35);
        }
        .fb-btn-del {
            background: rgba(239,68,68,0.2);
            color: #fecaca;
            border: 1px solid rgba(248,113,113,0.45);
        }
        .fb-body { padding: 0.55rem 0.9rem 0.65rem; }
        .fb-note-label {
            font-size: 0.65rem;
            text-transform: uppercase;
            letter-spacing: 0.1em;
            color: #64748b;
            font-weight: 700;
            margin-bottom: 0.35rem;
        }
        .fb-note-box {
            border-radius: 10px;
            padding: 0.55rem 0.7rem;
            background: rgba(2,6,23,0.65);
            border: 1px solid rgba(51,65,85,0.65);
            color: #e2e8f0;
            font-size: 0.82rem;
            line-height: 1.5;
            white-space: pre-wrap;
            word-break: break-word;
            position: relative;
            transition: max-height 0.2s ease;
        }
        .fb-note-box.is-collapsed {
            max-height: 4.6em;
            overflow: hidden;
        }
        .fb-note-box.is-collapsed::after {
            content: '';
            position: absolute;
            left: 0; right: 0; bottom: 0;
            height: 1.4em;
            background: linear-gradient(to bottom, transparent, rgba(2,6,23,0.97));
            pointer-events: none;
        }
        .fb-note-box.is-expanded {
            max-height: none;
            overflow: visible;
        }
        .fb-note-box.is-expanded::after { display: none; }
        .fb-toggle-note {
            margin-top: 0.35rem;
            padding: 0;
            border: none;
            background: none;
            color: #38bdf8;
            font-size: 0.72rem;
            font-weight: 700;
            cursor: pointer;
            text-decoration: underline;
            text-underline-offset: 2px;
        }
        .fb-toggle-note:hover { color: #7dd3fc; }
        .fb-url-block {
            margin-top: 0.55rem;
            padding-top: 0.55rem;
            border-top: 1px solid rgba(148,163,184,0.12);
        }
        .fb-url-label {
            font-size: 0.78rem;
            font-weight: 700;
            color: #fbbf24;
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
            gap: 0.45rem;
        }
        .fb-url-box {
            border-radius: 8px;
            padding: 0.45rem 0.55rem;
            background: rgba(15,23,42,0.9);
            border: 1px solid rgba(251,191,36,0.25);
            font-family: ui-monospace, 'Cairo', monospace;
            font-size: 0.68rem;
            line-height: 1.4;
            color: #e2e8f0;
            word-break: break-all;
            user-select: all;
            max-height: 2.8em;
            overflow: hidden;
            position: relative;
        }
        .fb-url-box.is-expanded {
            max-height: none;
            overflow: visible;
        }
        .fb-toggle-url {
            margin-top: 0.3rem;
            padding: 0;
            border: none;
            background: none;
            color: #fbbf24;
            font-size: 0.68rem;
            font-weight: 700;
            cursor: pointer;
            text-decoration: underline;
        }
        .fb-empty {
            border-radius: 20px;
            padding: 3rem 1.5rem;
            text-align: center;
            background: radial-gradient(circle at top, rgba(56,189,248,0.08), transparent 55%),
                        rgba(15,23,42,0.6);
            border: 1px dashed rgba(148,163,184,0.3);
            color: #94a3b8;
        }
        .fb-empty i {
            font-size: 2.75rem;
            margin-bottom: 1rem;
            color: #38bdf8;
            opacity: 0.85;
        }
    </style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container admin-main fb-shell">
    <div class="page-header">
        <div class="page-header-title">
            <i class="fas fa-comments text-info"></i>
            <span><?php echo t('nav.feedbacks'); ?></span>
        </div>
        <p class="page-header-subtitle"><?php echo t('feedbacks.page_subtitle'); ?></p>
    </div>

    <?php if ($flashMsg !== ''): ?>
        <div class="fb-alert alert alert-<?php echo htmlspecialchars($flashType); ?> mb-3 shadow-sm">
            <?php echo htmlspecialchars($flashMsg); ?>
        </div>
    <?php endif; ?>

    <?php if (!$canDeleteFeedback): ?>
        <?php $viewOnlyLangKey = 'view_only.feedbacks_hint'; require_once __DIR__ . '/includes/view_only_banner.php'; ?>
    <?php endif; ?>

    <?php if (empty($feedbacks)): ?>
        <div class="fb-empty">
            <i class="fas fa-inbox"></i>
            <p class="mb-0 fs-5 fw-semibold text-white"><?php echo t('feedbacks.empty'); ?></p>
        </div>
    <?php else: ?>
        <?php foreach ($feedbacks as $item):
            $fid = (int)($item['id'] ?? 0);
            $noteText = (string)($item['note'] ?? '');
            $noteNeedsToggle = (mb_strlen($noteText) > 110) || (substr_count($noteText, "\n") >= 2);
            $urlRaw = (string)($item['device_url'] ?? '');
            $urlNeedsToggle = mb_strlen($urlRaw) > 72;
            ?>
            <article class="fb-card">
                <div class="fb-card-head">
                    <div>
                        <div class="fb-device-name">
                            <i class="fas fa-mobile-screen-button"></i>
                            <span><?php echo htmlspecialchars($item['device_name'] ?: '—'); ?></span>
                        </div>
                        <div class="fb-meta-row">
                            <span class="fb-pill"><i class="fas fa-fingerprint text-info"></i><code><?php echo htmlspecialchars($item['device_id'] ?: '—'); ?></code></span>
                            <span class="fb-pill"><i class="fas fa-clock text-warning"></i><?php echo htmlspecialchars(format_datetime_short($item['created_at'])); ?></span>
                        </div>
                    </div>
                    <div class="fb-actions">
                        <?php if (!empty($item['device_url'])): ?>
                            <a class="btn fb-btn fb-btn-open" href="<?php echo htmlspecialchars($item['device_url']); ?>" target="_blank" rel="noopener noreferrer">
                                <i class="fas fa-external-link-alt"></i><?php echo t('feedbacks.open_url'); ?>
                            </a>
                            <button type="button" class="btn fb-btn fb-btn-copy fb-copy-btn" data-url="<?php echo htmlspecialchars($item['device_url'], ENT_QUOTES, 'UTF-8'); ?>">
                                <i class="fas fa-copy"></i><span class="fb-copy-label"><?php echo t('feedbacks.copy_url'); ?></span>
                            </button>
                        <?php endif; ?>
                        <form method="post"
                              class="d-inline"
                              data-admin-perm="feedbacks_delete"
                              data-admin-confirm
                              data-confirm-title="<?php echo htmlspecialchars(t('feedbacks.delete_title'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-message="<?php echo htmlspecialchars(t('feedbacks.delete_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-warning="<?php echo htmlspecialchars(t('feedbacks.delete_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-ok="<?php echo htmlspecialchars(t('feedbacks.delete'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                  ['label' => t('table.device_name'), 'value' => (string)($item['device_name'] ?? '')],
                                  ['label' => t('table.device_id'), 'value' => (string)($item['device_id'] ?? ''), 'mono' => true],
                              ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                            <input type="hidden" name="delete_feedback_id" value="<?php echo $fid; ?>">
                            <button type="submit" class="btn fb-btn fb-btn-del">
                                <i class="fas fa-trash-alt"></i><?php echo t('feedbacks.delete'); ?>
                            </button>
                        </form>
                    </div>
                </div>
                <div class="fb-body">
                    <div class="fb-note-label"><?php echo t('feedbacks.note_title'); ?></div>
                    <div id="fb-note-<?php echo $fid; ?>" class="fb-note-box <?php echo $noteNeedsToggle ? 'is-collapsed' : 'is-expanded'; ?>"><?php echo nl2br(htmlspecialchars($noteText)); ?></div>
                    <?php if ($noteNeedsToggle): ?>
                        <button type="button" class="fb-toggle-note" data-target="fb-note-<?php echo $fid; ?>"><?php echo t('feedbacks.show_more'); ?></button>
                    <?php endif; ?>

                    <?php if ($urlRaw !== ''): ?>
                        <div class="fb-url-block">
                            <div class="fb-url-label"><i class="fas fa-plug"></i><?php echo t('feedbacks.playlist_url_label'); ?></div>
                            <div id="fb-url-<?php echo $fid; ?>" class="fb-url-box <?php echo $urlNeedsToggle ? '' : 'is-expanded'; ?>"><?php echo htmlspecialchars($urlRaw); ?></div>
                            <?php if ($urlNeedsToggle): ?>
                                <button type="button" class="fb-toggle-url" data-target="fb-url-<?php echo $fid; ?>"><?php echo t('feedbacks.url_expand'); ?></button>
                            <?php endif; ?>
                        </div>
                    <?php endif; ?>
                </div>
            </article>
        <?php endforeach; ?>
    <?php endif; ?>
</div>

<script>
(function () {
  var moreText = <?php echo json_encode(t('feedbacks.show_more'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>;
  var lessText = <?php echo json_encode(t('feedbacks.show_less'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>;
  var urlExpand = <?php echo json_encode(t('feedbacks.url_expand'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>;
  var urlCollapse = <?php echo json_encode(t('feedbacks.show_less'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>;

  document.querySelectorAll('.fb-toggle-note').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var id = btn.getAttribute('data-target');
      var box = document.getElementById(id);
      if (!box) return;
      var open = box.classList.contains('is-expanded');
      if (open) {
        box.classList.remove('is-expanded');
        box.classList.add('is-collapsed');
        btn.textContent = moreText;
      } else {
        box.classList.add('is-expanded');
        box.classList.remove('is-collapsed');
        btn.textContent = lessText;
      }
    });
  });

  document.querySelectorAll('.fb-toggle-url').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var id = btn.getAttribute('data-target');
      var box = document.getElementById(id);
      if (!box) return;
      var open = box.classList.contains('is-expanded');
      if (open) {
        box.classList.remove('is-expanded');
        btn.textContent = urlExpand;
      } else {
        box.classList.add('is-expanded');
        btn.textContent = urlCollapse;
      }
    });
  });

  var copiedText = <?php echo json_encode(t('feedbacks.copied'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>;
  document.querySelectorAll('.fb-copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var url = btn.getAttribute('data-url') || '';
      var label = btn.querySelector('.fb-copy-label');
      if (!url) return;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(function () {
          if (label) { label.textContent = copiedText; setTimeout(function () { label.textContent = <?php echo json_encode(t('feedbacks.copy_url'), JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP); ?>; }, 2000); }
        });
      } else {
        var ta = document.createElement('textarea');
        ta.value = url;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); if (label) label.textContent = copiedText; } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  });
})();
</script>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
</body>
</html>
