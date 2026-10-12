<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';
require_once 'includes/onesignal_push.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!adminCan('notifications_send')) {
    header('Location: access_denied.php?perm=notifications_send');
    exit();
}

$current_page = 'notifications';
$canSend = adminCan('notifications_send');
$isGuest = adminIsGuestRole();
$settings = getSettings($conn);
$configured = onesignal_push_configured($settings);
$pushMissing = onesignal_push_missing_labels($settings, $lang);
$devices = admin_list_devices_for_notifications($conn);
$history = get_recent_push_notifications($conn, 60);

$flashMsg = '';
$flashType = '';
$oldTitle = '';
$oldMessage = '';
$oldLink = '';
$oldTarget = 'all';
$oldDeviceId = '';
$oldWhen = 'now';
$oldScheduleAt = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['cancel_scheduled'])) {
    admin_require_csrf();
    if (!$canSend) {
        header('Location: access_denied.php?perm=notifications_send');
        exit();
    }
    $cancelId = (int)($_POST['cancel_log_id'] ?? 0);
    $cancelRes = cancel_scheduled_push_notification($conn, $cancelId);
    if (!empty($cancelRes['ok'])) {
        header('Location: notifications.php?msg=cancelled');
        exit();
    }
    $flashMsg = t('notifications.cancel_fail');
    if (!empty($cancelRes['error'])) {
        $flashMsg .= ' (' . htmlspecialchars((string)$cancelRes['error'], ENT_QUOTES, 'UTF-8') . ')';
    }
    $flashType = 'danger';
    $history = get_recent_push_notifications($conn, 60);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['send_push'])) {
    admin_require_csrf();
    if (!$canSend) {
        header('Location: access_denied.php?perm=notifications_send');
        exit();
    }

    $oldTitle = trim((string)($_POST['push_title'] ?? ''));
    $oldMessage = trim((string)($_POST['push_message'] ?? ''));
    $oldLinkRaw = trim((string)($_POST['push_link'] ?? ''));
    $oldLink = onesignal_normalize_notification_url($oldLinkRaw);
    $oldTarget = (($_POST['push_target'] ?? 'all') === 'device') ? 'device' : 'all';
    $oldDeviceId = trim((string)($_POST['push_device_id'] ?? ''));
    $oldWhen = (($_POST['push_when'] ?? 'now') === 'schedule') ? 'schedule' : 'now';
    $oldScheduleAt = trim((string)($_POST['push_schedule_at'] ?? ''));

    $sendAfter = null;
    if ($oldWhen === 'schedule') {
        $sendAfter = onesignal_parse_schedule_local($oldScheduleAt);
    }

    if (!$configured) {
        $flashMsg = t('notifications.not_configured');
        $flashType = 'warning';
    } elseif ($oldTitle === '' || $oldMessage === '') {
        $flashMsg = t('notifications.sent_fail');
        $flashType = 'danger';
    } elseif ($oldLinkRaw !== '' && $oldLink === '') {
        $flashMsg = t('notifications.invalid_link');
        $flashType = 'danger';
        $oldLink = $oldLinkRaw;
    } elseif ($oldWhen === 'schedule' && $sendAfter === null) {
        $flashMsg = t('notifications.schedule_invalid');
        $flashType = 'danger';
    } elseif ($oldTarget === 'device' && $oldDeviceId === '') {
        $flashMsg = t('notifications.sent_fail');
        $flashType = 'danger';
    } else {
        $deviceForSend = $oldTarget === 'device' ? $oldDeviceId : null;
        $result = onesignal_send_push($conn, $oldTitle, $oldMessage, $deviceForSend, $oldLink, $sendAfter);
        $adminId = isset($_SESSION['admin_user_id']) ? (int)$_SESSION['admin_user_id'] : null;
        $scheduledAtStr = $sendAfter instanceof DateTimeImmutable
            ? $sendAfter->format('Y-m-d H:i:s')
            : null;

        log_push_notification(
            $conn,
            $oldTitle,
            $oldMessage,
            $oldTarget,
            $deviceForSend,
            !empty($result['ok']),
            !empty($result['id']) ? (string)$result['id'] : null,
            !empty($result['error']) ? (string)$result['error'] : null,
            $adminId,
            $oldLink,
            $scheduledAtStr
        );

        if (!empty($result['ok'])) {
            if (function_exists('logActivity')) {
                logActivity(
                    $conn,
                    $sendAfter ? 'push_notification_scheduled' : 'push_notification',
                    $oldTarget === 'device' ? $oldDeviceId : 'all',
                    $oldTitle
                );
            }
            header('Location: notifications.php?msg=' . ($sendAfter ? 'scheduled' : 'sent'));
            exit();
        }

        $err = (string)($result['error'] ?? 'unknown');
        if ($err === 'device_not_subscribed') {
            $flashMsg = t('notifications.device_not_subscribed');
        } elseif ($err === 'no_subscribed_users' || stripos($err, 'not subscribed') !== false) {
            $flashMsg = t('notifications.no_subscribed_users');
        } else {
            $flashMsg = t('notifications.sent_fail') . ' (' . htmlspecialchars($err, ENT_QUOTES, 'UTF-8') . ')';
        }
        $flashType = 'danger';
        $history = get_recent_push_notifications($conn, 60);
    }
}

if (isset($_GET['msg'])) {
    if ($_GET['msg'] === 'sent') {
        $flashMsg = t('notifications.sent_ok');
        $flashType = 'success';
    } elseif ($_GET['msg'] === 'scheduled') {
        $flashMsg = t('notifications.scheduled_ok');
        $flashType = 'success';
    } elseif ($_GET['msg'] === 'cancelled') {
        $flashMsg = t('notifications.cancel_ok');
        $flashType = 'success';
    }
}
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('notifications.title'); ?> - <?php echo t('app.title'); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Cairo', system-ui, sans-serif; }
        .push-shell { margin-top: 8px; }
        .push-alert {
            border-radius: 14px;
            border: 1px solid rgba(148,163,184,0.35);
            padding: 0.85rem 1.1rem;
            margin-bottom: 1.25rem;
        }
        .push-card {
            border-radius: 16px;
            padding: 1.25rem 1.35rem;
            margin-bottom: 1.25rem;
            background: radial-gradient(circle at 0% 0%, rgba(56,189,248,0.1), transparent 50%),
                        linear-gradient(165deg, rgba(15,23,42,0.97), rgba(3,7,18,0.99));
            border: 1px solid rgba(148,163,184,0.22);
            box-shadow: 0 8px 24px rgba(2,6,23,0.4);
        }
        .push-card h3 {
            font-size: 1.05rem;
            font-weight: 800;
            color: #f8fafc;
            margin: 0 0 1rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .push-card label { color: #cbd5e1; font-weight: 700; font-size: 0.88rem; }
        .push-card .form-control, .push-card .form-select {
            background: rgba(15,23,42,0.85);
            border: 1px solid rgba(148,163,184,0.35);
            color: #f8fafc;
            border-radius: 12px;
            min-height: 44px;
        }
        .push-card .form-control:focus, .push-card .form-select:focus {
            background: rgba(15,23,42,0.95);
            border-color: rgba(56,189,248,0.55);
            color: #fff;
            box-shadow: 0 0 0 0.2rem rgba(56,189,248,0.15);
        }
        .push-card textarea.form-control { min-height: 120px; resize: vertical; }
        .push-target-row { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 1rem; }
        .push-target-opt {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 10px 14px;
            border-radius: 999px;
            border: 1px solid rgba(148,163,184,0.35);
            background: rgba(15,23,42,0.65);
            color: #e2e8f0;
            cursor: pointer;
            font-weight: 700;
            font-size: 0.86rem;
        }
        .push-target-opt input { accent-color: #38bdf8; }
        .push-device-wrap { display: none; margin-bottom: 1rem; }
        .push-device-wrap.is-visible { display: block; }
        .push-schedule-wrap { display: none; margin-bottom: 1rem; }
        .push-schedule-wrap.is-visible { display: block; }
        .push-badge-sched {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 999px;
            background: rgba(56,189,248,0.15);
            color: #7dd3fc;
            font-weight: 700;
            font-size: 0.75rem;
        }
        .push-badge-cancel {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 999px;
            background: rgba(148,163,184,0.18);
            color: #cbd5e1;
            font-weight: 700;
            font-size: 0.75rem;
        }
        .btn-push-cancel {
            appearance: none;
            border: 1px solid rgba(239,68,68,0.35);
            background: rgba(127,29,29,0.25);
            color: #fca5a5;
            border-radius: 999px;
            padding: 4px 12px;
            font-size: 0.75rem;
            font-weight: 700;
            cursor: pointer;
            margin-inline-start: 6px;
        }
        .btn-push-cancel:hover { border-color: rgba(239,68,68,0.6); color: #fecaca; }
        .btn-push-send {
            appearance: none;
            border: 0;
            border-radius: 999px;
            padding: 0 26px;
            min-height: 48px;
            font-weight: 800;
            color: #fff;
            background: linear-gradient(135deg, #0ea5e9, #4f46e5);
            box-shadow: 0 14px 32px rgba(37,99,235,0.35);
        }
        .btn-push-send:disabled { opacity: 0.55; cursor: not-allowed; }
        .push-history-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.84rem;
        }
        .push-history-table th, .push-history-table td {
            padding: 10px 12px;
            border-bottom: 1px solid rgba(148,163,184,0.15);
            color: #e2e8f0;
            vertical-align: top;
        }
        .push-history-table th { color: #94a3b8; font-weight: 700; }
        .push-badge-ok {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 999px;
            background: rgba(34,197,94,0.15);
            color: #86efac;
            font-weight: 700;
            font-size: 0.75rem;
        }
        .push-badge-fail {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 999px;
            background: rgba(239,68,68,0.15);
            color: #fca5a5;
            font-weight: 700;
            font-size: 0.75rem;
        }
        .field-mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.82rem; }
        .btn-push-details {
            appearance: none;
            border: 1px solid rgba(148,163,184,0.35);
            background: rgba(15,23,42,0.75);
            color: #e2e8f0;
            border-radius: 999px;
            padding: 4px 12px;
            font-size: 0.78rem;
            font-weight: 700;
            cursor: pointer;
        }
        .btn-push-details:hover { border-color: rgba(56,189,248,0.55); color: #7dd3fc; }
        .push-detail-modal .modal-content {
            background: linear-gradient(165deg, rgba(15,23,42,0.98), rgba(3,7,18,0.99));
            border: 1px solid rgba(148,163,184,0.28);
            border-radius: 16px;
            color: #e2e8f0;
        }
        .push-detail-modal .modal-header {
            border-bottom: 1px solid rgba(148,163,184,0.18);
        }
        .push-detail-modal .modal-footer {
            border-top: 1px solid rgba(148,163,184,0.18);
        }
        .push-detail-row { margin-bottom: 12px; }
        .push-detail-label {
            display: block;
            color: #94a3b8;
            font-size: 0.78rem;
            font-weight: 700;
            margin-bottom: 4px;
        }
        .push-detail-value {
            color: #f1f5f9;
            white-space: pre-wrap;
            word-break: break-word;
            line-height: 1.45;
        }
        .push-detail-link a { color: #7dd3fc; word-break: break-all; }
        .push-device-picker { position: relative; margin-bottom: 10px; }
        .push-device-results {
            position: absolute;
            z-index: 40;
            left: 0; right: 0;
            top: calc(100% + 4px);
            max-height: 260px;
            overflow: auto;
            border-radius: 12px;
            border: 1px solid rgba(148,163,184,0.35);
            background: rgba(15,23,42,0.98);
            box-shadow: 0 16px 32px rgba(2,6,23,0.55);
            display: none;
        }
        .push-device-results.is-open { display: block; }
        .push-device-option {
            display: block;
            width: 100%;
            text-align: start;
            border: 0;
            background: transparent;
            color: #e2e8f0;
            padding: 10px 12px;
            cursor: pointer;
            border-bottom: 1px solid rgba(148,163,184,0.12);
        }
        .push-device-option:hover,
        .push-device-option.is-active {
            background: rgba(56,189,248,0.12);
            color: #fff;
        }
        .push-device-option__name { font-weight: 700; font-size: 0.86rem; }
        .push-device-option__id {
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 0.74rem;
            color: #94a3b8;
            margin-top: 2px;
            word-break: break-all;
        }
        .push-device-empty {
            padding: 12px;
            color: #94a3b8;
            font-size: 0.84rem;
        }
    </style>
</head>
<body class="admin-app">
<?php require_once 'includes/header.php'; ?>
<div class="container admin-main push-shell">
    <div class="admin-shell-card p-3 p-md-4">
        <div class="page-header">
            <div class="page-header-title">
                <i class="fas fa-bell" style="color:#38bdf8;"></i>
                <?php echo t('notifications.title'); ?>
            </div>
            <div class="page-header-subtitle"><?php echo t('notifications.subtitle'); ?></div>
        </div>

        <?php if ($flashMsg !== ''): ?>
        <div class="push-alert alert alert-<?php echo htmlspecialchars($flashType, ENT_QUOTES, 'UTF-8'); ?> mb-3">
            <?php echo $flashMsg; ?>
        </div>
        <?php endif; ?>

        <?php if (!$configured): ?>
        <div class="push-alert alert alert-warning">
            <div class="mb-1"><?php echo t('notifications.not_configured'); ?></div>
            <?php if (!empty($pushMissing)): ?>
            <ul class="mb-2 ps-3">
                <?php foreach ($pushMissing as $item): ?>
                <li><?php echo htmlspecialchars($item, ENT_QUOTES, 'UTF-8'); ?></li>
                <?php endforeach; ?>
            </ul>
            <?php endif; ?>
            <?php if (adminCan('settings')): ?>
            <a href="settings.php#flutter-settings-push" class="alert-link"><?php echo t('notifications.open_settings'); ?></a>
            <?php endif; ?>
        </div>
        <?php endif; ?>

        <div class="push-card">
            <h3><i class="fas fa-paper-plane" style="color:#38bdf8;"></i> <?php echo t('notifications.send_btn'); ?></h3>
            <form method="POST" action="">
                <?php echo admin_csrf_field(); ?>
                <input type="hidden" name="send_push" value="1">

                <div class="mb-3">
                    <label for="push_title" class="form-label"><?php echo t('notifications.form_title'); ?></label>
                    <input type="text" class="form-control" id="push_title" name="push_title" maxlength="120"
                           value="<?php echo htmlspecialchars($oldTitle, ENT_QUOTES, 'UTF-8'); ?>"
                           placeholder="<?php echo t('notifications.form_title_placeholder'); ?>"
                           <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                </div>

                <div class="mb-3">
                    <label for="push_message" class="form-label"><?php echo t('notifications.form_message'); ?></label>
                    <textarea class="form-control" id="push_message" name="push_message" maxlength="500"
                              placeholder="<?php echo t('notifications.form_message_placeholder'); ?>"
                              <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>><?php echo htmlspecialchars($oldMessage, ENT_QUOTES, 'UTF-8'); ?></textarea>
                </div>

                <div class="mb-3">
                    <label for="push_link" class="form-label"><?php echo t('notifications.form_link'); ?></label>
                    <input type="text" class="form-control field-mono" id="push_link" name="push_link" maxlength="1200"
                           value="<?php echo htmlspecialchars($oldLink, ENT_QUOTES, 'UTF-8'); ?>"
                           placeholder="<?php echo t('notifications.form_link_placeholder'); ?>"
                           inputmode="url" autocomplete="off"
                           <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                    <div class="form-text" style="color:#94a3b8;margin-top:6px;"><?php echo t('notifications.form_link_help'); ?></div>
                </div>

                <div class="mb-2"><label class="form-label"><?php echo t('notifications.when_label'); ?></label></div>
                <div class="push-target-row">
                    <label class="push-target-opt">
                        <input type="radio" name="push_when" value="now" <?php echo $oldWhen !== 'schedule' ? 'checked' : ''; ?>
                               <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                        <i class="fas fa-bolt"></i> <?php echo t('notifications.when_now'); ?>
                    </label>
                    <label class="push-target-opt">
                        <input type="radio" name="push_when" value="schedule" <?php echo $oldWhen === 'schedule' ? 'checked' : ''; ?>
                               <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                        <i class="fas fa-clock"></i> <?php echo t('notifications.when_schedule'); ?>
                    </label>
                </div>
                <div class="push-schedule-wrap<?php echo $oldWhen === 'schedule' ? ' is-visible' : ''; ?>" id="pushScheduleWrap">
                    <label for="push_schedule_at" class="form-label"><?php echo t('notifications.schedule_at'); ?></label>
                    <input type="datetime-local" class="form-control" id="push_schedule_at" name="push_schedule_at"
                           value="<?php echo htmlspecialchars($oldScheduleAt, ENT_QUOTES, 'UTF-8'); ?>"
                           <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                    <div class="form-text" style="color:#94a3b8;margin-top:6px;"><?php echo t('notifications.schedule_help'); ?></div>
                </div>

                <div class="mb-2"><label class="form-label"><?php echo t('notifications.target_label'); ?></label></div>
                <div class="push-target-row">
                    <label class="push-target-opt">
                        <input type="radio" name="push_target" value="all" <?php echo $oldTarget !== 'device' ? 'checked' : ''; ?>
                               <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                        <i class="fas fa-users"></i> <?php echo t('notifications.target_all'); ?>
                    </label>
                    <label class="push-target-opt">
                        <input type="radio" name="push_target" value="device" <?php echo $oldTarget === 'device' ? 'checked' : ''; ?>
                               <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                        <i class="fas fa-mobile-alt"></i> <?php echo t('notifications.target_device'); ?>
                    </label>
                </div>

                <div class="push-device-wrap<?php echo $oldTarget === 'device' ? ' is-visible' : ''; ?>" id="pushDeviceWrap">
                    <label for="push_device_search" class="form-label"><?php echo t('notifications.device_label'); ?></label>
                    <?php
                    $devicePickerList = [];
                    if (!$isGuest) {
                        foreach ($devices as $dev) {
                            $did = trim((string)($dev['device_id'] ?? ''));
                            if ($did === '') continue;
                            $dname = trim((string)($dev['device_name'] ?? ''));
                            $devicePickerList[] = [
                                'id' => $did,
                                'name' => $dname,
                                'label' => $dname !== '' ? ($dname . ' — ' . $did) : $did,
                            ];
                        }
                    }
                    ?>
                    <div class="push-device-picker" id="pushDevicePicker">
                        <input type="search" class="form-control" id="push_device_search" autocomplete="off"
                               placeholder="<?php echo t('notifications.device_search'); ?>"
                               value=""
                               <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                        <div class="push-device-results" id="pushDeviceResults" role="listbox"></div>
                    </div>
                    <input type="text" class="form-control field-mono" id="push_device_id" name="push_device_id"
                           value="<?php echo htmlspecialchars($oldDeviceId, ENT_QUOTES, 'UTF-8'); ?>"
                           placeholder="<?php echo t('notifications.device_placeholder'); ?>"
                           <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                    <div class="form-text" style="color:#94a3b8;margin-top:6px;"><?php echo t('notifications.device_help'); ?></div>
                    <script>
                      window.__pushDevices = <?php echo json_encode($devicePickerList, JSON_UNESCAPED_UNICODE); ?>;
                      window.__pushDeviceNoMatch = <?php echo json_encode(t('notifications.device_no_match'), JSON_UNESCAPED_UNICODE); ?>;
                    </script>
                </div>

                <button type="submit" class="btn-push-send mt-2" id="pushSubmitBtn" <?php echo ($canSend && $configured) ? '' : 'disabled'; ?>>
                    <i class="fas fa-paper-plane" id="pushSubmitIcon"></i>
                    <span id="pushSubmitLabel"><?php echo $oldWhen === 'schedule' ? t('notifications.schedule_btn') : t('notifications.send_btn'); ?></span>
                </button>
            </form>
        </div>

        <div class="push-card">
            <h3><i class="fas fa-clock-rotate-left" style="color:#a78bfa;"></i> <?php echo t('notifications.history_title'); ?></h3>
            <?php if (count($history) === 0): ?>
                <p style="color:#94a3b8;margin:0;"><?php echo t('notifications.history_empty'); ?></p>
            <?php else: ?>
            <div class="table-responsive">
                <table class="push-history-table">
                    <thead>
                    <tr>
                        <th><?php echo t('notifications.col_when'); ?></th>
                        <th><?php echo t('notifications.col_target'); ?></th>
                        <th><?php echo t('notifications.col_title'); ?></th>
                        <th><?php echo t('notifications.col_status'); ?></th>
                        <th><?php echo t('notifications.col_admin'); ?></th>
                        <th><?php echo t('notifications.col_actions'); ?></th>
                    </tr>
                    </thead>
                    <tbody>
                    <?php foreach ($history as $row):
                        $targetLabel = ($row['target_type'] ?? '') === 'device'
                            ? htmlspecialchars((string)($row['device_id'] ?? ''), ENT_QUOTES, 'UTF-8')
                            : t('notifications.target_all_short');
                        $statusKey = (string)($row['status'] ?? 'failed');
                        $statusLabel = t('notifications.status_failed');
                        if ($statusKey === 'sent') {
                            $statusLabel = t('notifications.status_sent');
                        } elseif ($statusKey === 'scheduled') {
                            $statusLabel = t('notifications.status_scheduled');
                        } elseif ($statusKey === 'cancelled') {
                            $statusLabel = t('notifications.status_cancelled');
                        }
                        $scheduledAt = trim((string)($row['scheduled_at'] ?? ''));
                        $detailPayload = [
                            'when' => (string)($row['created_at'] ?? ''),
                            'target' => ($row['target_type'] ?? '') === 'device'
                                ? (string)($row['device_id'] ?? '')
                                : t('notifications.target_all_short'),
                            'title' => (string)($row['title'] ?? ''),
                            'message' => (string)($row['message'] ?? ''),
                            'link' => trim((string)($row['link_url'] ?? '')),
                            'status' => $statusLabel,
                            'status_key' => $statusKey,
                            'scheduled_at' => $scheduledAt,
                            'error' => (string)($row['error_message'] ?? ''),
                            'admin' => (string)($row['admin_username'] ?? '—'),
                        ];
                        $canCancelRow = $canSend && $statusKey === 'scheduled' && (int)($row['id'] ?? 0) > 0;
                        ?>
                    <tr>
                        <td>
                            <?php echo htmlspecialchars((string)($row['created_at'] ?? ''), ENT_QUOTES, 'UTF-8'); ?>
                            <?php if ($statusKey === 'scheduled' && $scheduledAt !== ''): ?>
                              <div style="color:#7dd3fc;font-size:0.72rem;margin-top:3px;">
                                <i class="fas fa-clock"></i> <?php echo htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8'); ?>
                              </div>
                            <?php endif; ?>
                        </td>
                        <td class="field-mono"><?php echo $targetLabel; ?></td>
                        <td><?php echo htmlspecialchars((string)($row['title'] ?? ''), ENT_QUOTES, 'UTF-8'); ?></td>
                        <td>
                            <?php if ($statusKey === 'sent'): ?>
                                <span class="push-badge-ok"><?php echo t('notifications.status_sent'); ?></span>
                            <?php elseif ($statusKey === 'scheduled'): ?>
                                <span class="push-badge-sched"><?php echo t('notifications.status_scheduled'); ?></span>
                            <?php elseif ($statusKey === 'cancelled'): ?>
                                <span class="push-badge-cancel"><?php echo t('notifications.status_cancelled'); ?></span>
                            <?php else: ?>
                                <span class="push-badge-fail"><?php echo t('notifications.status_failed'); ?></span>
                                <?php if (!empty($row['error_message'])): ?>
                                    <div style="color:#94a3b8;font-size:0.75rem;margin-top:4px;"><?php echo htmlspecialchars((string)$row['error_message'], ENT_QUOTES, 'UTF-8'); ?></div>
                                <?php endif; ?>
                            <?php endif; ?>
                        </td>
                        <td><?php echo htmlspecialchars((string)($row['admin_username'] ?? '—'), ENT_QUOTES, 'UTF-8'); ?></td>
                        <td>
                            <button type="button"
                                    class="btn-push-details js-push-details"
                                    data-detail="<?php echo htmlspecialchars(json_encode($detailPayload, JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                <i class="fas fa-eye"></i> <?php echo t('notifications.details_btn'); ?>
                            </button>
                            <?php if ($canCancelRow): ?>
                            <form method="POST" action="" style="display:inline;" class="js-cancel-scheduled-form"
                                  onsubmit="return confirm(<?php echo htmlspecialchars(json_encode(t('notifications.cancel_btn') . '?'), ENT_QUOTES, 'UTF-8'); ?>);">
                                <?php echo admin_csrf_field(); ?>
                                <input type="hidden" name="cancel_scheduled" value="1">
                                <input type="hidden" name="cancel_log_id" value="<?php echo (int)$row['id']; ?>">
                                <button type="submit" class="btn-push-cancel">
                                    <i class="fas fa-ban"></i> <?php echo t('notifications.cancel_btn'); ?>
                                </button>
                            </form>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<div class="modal fade push-detail-modal" id="pushDetailModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-bell me-2" style="color:#38bdf8;"></i><?php echo t('notifications.details_title'); ?></h5>
        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.col_when'); ?></span>
          <div class="push-detail-value" id="pdWhen">—</div>
        </div>
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.col_target'); ?></span>
          <div class="push-detail-value field-mono" id="pdTarget">—</div>
        </div>
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.form_title'); ?></span>
          <div class="push-detail-value" id="pdTitle">—</div>
        </div>
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.details_message'); ?></span>
          <div class="push-detail-value" id="pdMessage">—</div>
        </div>
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.details_link'); ?></span>
          <div class="push-detail-value push-detail-link" id="pdLink">—</div>
        </div>
        <div class="push-detail-row" id="pdSchedWrap" hidden>
          <span class="push-detail-label"><?php echo t('notifications.details_scheduled_at'); ?></span>
          <div class="push-detail-value" id="pdSched">—</div>
        </div>
        <div class="push-detail-row">
          <span class="push-detail-label"><?php echo t('notifications.col_status'); ?></span>
          <div class="push-detail-value" id="pdStatus">—</div>
        </div>
        <div class="push-detail-row" id="pdErrorWrap" hidden>
          <span class="push-detail-label"><?php echo t('notifications.status_failed'); ?></span>
          <div class="push-detail-value" id="pdError" style="color:#fca5a5;">—</div>
        </div>
        <div class="push-detail-row mb-0">
          <span class="push-detail-label"><?php echo t('notifications.col_admin'); ?></span>
          <div class="push-detail-value" id="pdAdmin">—</div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"><?php echo t('notifications.details_close'); ?></button>
      </div>
    </div>
  </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
(function(){
  var radios = document.querySelectorAll('input[name="push_target"]');
  var wrap = document.getElementById('pushDeviceWrap');
  function syncTarget(){
    if (!wrap) return;
    var device = false;
    radios.forEach(function(r){ if (r.checked && r.value === 'device') device = true; });
    wrap.classList.toggle('is-visible', device);
    if (device) {
      var s = document.getElementById('push_device_search');
      if (s) setTimeout(function(){ s.focus(); }, 50);
    }
  }
  radios.forEach(function(r){ r.addEventListener('change', syncTarget); });
  syncTarget();
})();

(function(){
  var devices = Array.isArray(window.__pushDevices) ? window.__pushDevices : [];
  var search = document.getElementById('push_device_search');
  var results = document.getElementById('pushDeviceResults');
  var inp = document.getElementById('push_device_id');
  if (!search || !results || !inp) return;
  var active = -1;
  var filtered = [];

  function escapeHtml(s){
    return String(s || '').replace(/[&<>"']/g, function(c){
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
    });
  }

  function openList(){ results.classList.add('is-open'); }
  function closeList(){ results.classList.remove('is-open'); active = -1; }

  function selectDevice(dev){
    if (!dev) return;
    inp.value = dev.id || '';
    search.value = dev.label || dev.id || '';
    closeList();
  }

  function render(q){
    q = String(q || '').trim().toLowerCase();
    filtered = !q ? devices.slice(0, 40) : devices.filter(function(d){
      var hay = ((d.name || '') + ' ' + (d.id || '') + ' ' + (d.label || '')).toLowerCase();
      return hay.indexOf(q) !== -1;
    }).slice(0, 40);

    if (!filtered.length) {
      results.innerHTML = '<div class="push-device-empty">' + escapeHtml(window.__pushDeviceNoMatch || 'No match') + '</div>';
      openList();
      return;
    }
    results.innerHTML = filtered.map(function(d, i){
      return '<button type="button" class="push-device-option' + (i === active ? ' is-active' : '') + '" data-idx="' + i + '">'
        + '<div class="push-device-option__name">' + escapeHtml(d.name || d.id) + '</div>'
        + '<div class="push-device-option__id">' + escapeHtml(d.id) + '</div>'
        + '</button>';
    }).join('');
    openList();
  }

  // Prefill search label if device id already set
  if (inp.value) {
    var cur = devices.find(function(d){ return d.id === inp.value; });
    if (cur) search.value = cur.label || cur.id;
    else search.value = inp.value;
  }

  search.addEventListener('focus', function(){ render(search.value); });
  search.addEventListener('input', function(){
    // typing in search also mirrors into id field if it looks like a full id paste
    render(search.value);
  });
  search.addEventListener('keydown', function(e){
    if (!results.classList.contains('is-open')) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      active = Math.min(active + 1, filtered.length - 1);
      render(search.value);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      active = Math.max(active - 1, 0);
      render(search.value);
    } else if (e.key === 'Enter') {
      if (active >= 0 && filtered[active]) {
        e.preventDefault();
        selectDevice(filtered[active]);
      }
    } else if (e.key === 'Escape') {
      closeList();
    }
  });

  results.addEventListener('mousedown', function(e){
    var btn = e.target.closest('.push-device-option');
    if (!btn) return;
    e.preventDefault();
    var idx = parseInt(btn.getAttribute('data-idx') || '-1', 10);
    if (idx >= 0 && filtered[idx]) selectDevice(filtered[idx]);
  });

  document.addEventListener('click', function(e){
    if (!e.target.closest('#pushDevicePicker')) closeList();
  });
})();

(function(){
  var whenRadios = document.querySelectorAll('input[name="push_when"]');
  var schedWrap = document.getElementById('pushScheduleWrap');
  var schedInput = document.getElementById('push_schedule_at');
  var label = document.getElementById('pushSubmitLabel');
  var icon = document.getElementById('pushSubmitIcon');
  var labelNow = <?php echo json_encode(t('notifications.send_btn'), JSON_UNESCAPED_UNICODE); ?>;
  var labelSched = <?php echo json_encode(t('notifications.schedule_btn'), JSON_UNESCAPED_UNICODE); ?>;

  function syncWhen(){
    var schedule = false;
    whenRadios.forEach(function(r){ if (r.checked && r.value === 'schedule') schedule = true; });
    if (schedWrap) schedWrap.classList.toggle('is-visible', schedule);
    if (label) label.textContent = schedule ? labelSched : labelNow;
    if (icon) icon.className = schedule ? 'fas fa-clock' : 'fas fa-paper-plane';
    if (schedInput && schedule && !schedInput.value) {
      var d = new Date(Date.now() + 10 * 60 * 1000);
      var pad = function(n){ return String(n).padStart(2, '0'); };
      schedInput.value = d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate())
        + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
  }
  whenRadios.forEach(function(r){ r.addEventListener('change', syncWhen); });
  syncWhen();
})();

(function(){
  var modalEl = document.getElementById('pushDetailModal');
  if (!modalEl || typeof bootstrap === 'undefined') return;
  var modal = bootstrap.Modal.getOrCreateInstance(modalEl);
  var noLink = <?php echo json_encode(t('notifications.details_no_link'), JSON_UNESCAPED_UNICODE); ?>;

  function setText(id, value) {
    var el = document.getElementById(id);
    if (el) el.textContent = value || '—';
  }

  document.querySelectorAll('.js-push-details').forEach(function(btn){
    btn.addEventListener('click', function(){
      var raw = btn.getAttribute('data-detail') || '{}';
      var data = {};
      try { data = JSON.parse(raw); } catch (e) { data = {}; }
      setText('pdWhen', data.when);
      setText('pdTarget', data.target);
      setText('pdTitle', data.title);
      setText('pdMessage', data.message);
      setText('pdStatus', data.status);
      setText('pdAdmin', data.admin);

      var linkEl = document.getElementById('pdLink');
      var link = (data.link || '').trim();
      if (linkEl) {
        if (link) {
          linkEl.innerHTML = '';
          var a = document.createElement('a');
          a.href = link;
          a.target = '_blank';
          a.rel = 'noopener noreferrer';
          a.textContent = link;
          linkEl.appendChild(a);
        } else {
          linkEl.textContent = noLink;
        }
      }

      var schedWrap = document.getElementById('pdSchedWrap');
      var sched = (data.scheduled_at || '').trim();
      if (schedWrap) {
        if (sched) {
          schedWrap.removeAttribute('hidden');
          setText('pdSched', sched);
        } else {
          schedWrap.setAttribute('hidden', '');
        }
      }

      var errWrap = document.getElementById('pdErrorWrap');
      var err = (data.error || '').trim();
      if (errWrap) {
        if (err) {
          errWrap.removeAttribute('hidden');
          setText('pdError', err);
        } else {
          errWrap.setAttribute('hidden', '');
        }
      }
      modal.show();
    });
  });
})();
</script>
</body>
</html>
