<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
require_once __DIR__ . '/includes/pagination.php';

$id = admin_parse_positive_int_id($_POST['id'] ?? $_GET['id'] ?? 0);
$canDeleteDevice = adminCan('devices_delete');
$canViewDevices = adminCan('devices_view') || $canDeleteDevice;
$homeUrl = admin_devices_home_url();

if ($id <= 0 || !$canViewDevices) {
    $_SESSION['error'] = t('msg.device_not_found');
    header('Location: ' . $homeUrl);
    exit();
}

try {
    $device = admin_find_managed_device($conn, $id);
    if (!$device) {
        $_SESSION['error'] = t('msg.device_not_found');
        header('Location: ' . $homeUrl);
        exit();
    }

    // State-changing delete: POST + CSRF + devices_delete only (no GET confirm=yes).
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        admin_require_csrf();
        if (!$canDeleteDevice) {
            header('Location: access_denied.php?perm=devices_delete');
            exit();
        }
        $confirm = (string) ($_POST['confirm'] ?? '');
        if ($confirm !== 'yes') {
            header('Location: delete-device.php?id=' . $id);
            exit();
        }
        // Re-scope after CSRF to avoid acting on a stale/out-of-scope id.
        $device = admin_find_managed_device($conn, $id);
        if (!$device) {
            $_SESSION['error'] = t('msg.device_not_found');
            header('Location: ' . $homeUrl);
            exit();
        }
        if (deleteDevice($conn, $id)) {
            $stmt = $conn->prepare('INSERT INTO activity_log (action, device_id, details) VALUES (?, ?, ?)');
            $stmt->execute(['delete_device', $device['device_id'], 'Device deleted']);
            $_SESSION['success'] = t('msg.device_deleted');
        } else {
            $_SESSION['error'] = t('msg.device_delete_error');
        }
        header('Location: ' . $homeUrl);
        exit();
    }
} catch (PDOException $e) {
    $_SESSION['error'] = t('msg.db_error');
    header('Location: ' . $homeUrl);
    exit();
}

$isGuest = adminIsGuestRole();
$displayDeviceId = $isGuest
    ? adminMaskDeviceId((string) ($device['device_id'] ?? ''))
    : (string) ($device['device_id'] ?? '');
$listPage = admin_request_list_page();
?>

<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('delete.title'); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Cairo', sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background:
                radial-gradient(circle at top left, #1e3a8a 0, #1d4ed8 22%, transparent 55%),
                radial-gradient(circle at bottom right, #4c1d95 0, #020617 55%);
            color: #e5e7eb;
        }
        .delete-card {
            border-radius: 20px;
            background: radial-gradient(circle at top left, rgba(248,250,252,0.10), rgba(15,23,42,0.98));
            box-shadow:
                0 30px 90px rgba(15,23,42,0.95),
                0 0 0 1px rgba(148,163,184,0.25);
            border: none;
            width: 100%;
            max-width: 520px;
            overflow: hidden;
        }
        .delete-card-header {
            background: radial-gradient(circle at top left, rgba(248,113,113,0.65), rgba(127,29,29,1));
            border-bottom: 1px solid rgba(248,113,113,0.8);
            padding: 14px 18px;
        }
        .delete-card-header h5 {
            margin: 0;
            display: flex;
            align-items: center;
            gap: .55rem;
            font-size: 1.02rem;
        }
        .delete-card-header h5 i { color: #fee2e2; }
        .warning-icon { font-size: 3rem; color: #fca5a5; margin-bottom: 16px; }
        .device-info { font-size: 0.95rem; margin: 4px 0; }
        .device-info-label { color: #9ca3af; }
        .device-box {
            border-radius: 14px;
            padding: 14px 16px;
            background: rgba(15,23,42,0.95);
            border: 1px solid rgba(148,163,184,0.55);
            text-align: start;
        }
        .badge-date {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            border-radius: 999px;
            font-size: 0.8rem;
            font-weight: 500;
            white-space: nowrap;
        }
        .badge-date i { font-size: 0.8rem; }
        .badge-date-start {
            background: rgba(59,130,246,0.22);
            color: #bfdbfe;
            border: 1px solid rgba(59,130,246,0.75);
        }
        .badge-date-end {
            background: rgba(248,113,113,0.22);
            color: #fecaca;
            border: 1px solid rgba(248,113,113,0.75);
        }
        .alert-danger-soft {
            border-radius: 14px;
            padding: 10px 14px;
            background: rgba(248,113,113,0.18);
            border: 1px solid rgba(248,113,113,0.75);
            color: #fee2e2;
            font-size: 0.9rem;
        }
        .btn {
            border-radius: 999px;
            padding: 10px 22px;
            font-weight: 500;
            transition: all 0.22s ease;
        }
        .btn-danger {
            background: linear-gradient(135deg, #ef4444, #b91c1c);
            border: none;
            box-shadow: 0 18px 36px rgba(15,23,42,0.95);
        }
        .btn-secondary {
            background: linear-gradient(135deg, #4b5563, #111827);
            border: none;
        }
        .btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 22px 44px rgba(15,23,42,1);
        }
    </style>
</head>
<body>
    <div class="container px-3 d-flex justify-content-center">
        <div class="delete-card">
            <div class="delete-card-header text-white">
                <h5 class="mb-0">
                    <i class="fas fa-trash-alt"></i>
                    <?php echo t('delete.title'); ?>
                </h5>
            </div>
            <div class="card-body text-center">
                <div class="warning-icon">
                    <i class="fas fa-exclamation-triangle"></i>
                </div>

                <h5 class="mb-3"><?php echo t('delete.question'); ?></h5>

                <div class="device-box mb-3">
                    <div class="device-info mb-1">
                        <span class="device-info-label"><i class="fas fa-mobile-alt me-1"></i><?php echo t('table.device_id'); ?>:</span>
                        <strong><?php echo htmlspecialchars($displayDeviceId); ?></strong>
                    </div>
                    <div class="device-info mb-2">
                        <span class="device-info-label d-block mb-1"><?php echo t('delete.period_label'); ?></span>
                        <span class="badge-date badge-date-start me-2">
                            <i class="fas fa-calendar-plus"></i>
                            <span><?php echo format_datetime_short($device['activation_date']); ?></span>
                        </span>
                        <span class="badge-date badge-date-end">
                            <i class="fas fa-calendar-times"></i>
                            <span><?php echo format_device_expiry($device['expiry_date']); ?></span>
                        </span>
                    </div>
                    <?php if (!empty($device['notes']) && !$isGuest): ?>
                    <div class="device-info mt-2 text-start">
                        <span class="device-info-label d-block mb-1"><i class="fas fa-sticky-note me-1"></i><?php echo t('delete.notes_label'); ?></span>
                        <span><?php echo htmlspecialchars($device['notes']); ?></span>
                    </div>
                    <?php endif; ?>
                </div>

                <div class="alert-danger-soft mb-4">
                    <i class="fas fa-exclamation-triangle me-2"></i>
                    <?php echo t('delete.warning'); ?>
                </div>

                <?php if (!$canDeleteDevice): ?>
                <?php $viewOnlyLangKey = 'view_only.delete_hint'; require_once __DIR__ . '/includes/view_only_banner.php'; ?>
                <?php endif; ?>
                <div class="d-grid gap-2">
                    <?php if ($canDeleteDevice): ?>
                    <form method="POST" action="delete-device.php" data-admin-perm="devices_delete">
                        <?php echo admin_csrf_field(); ?>
                        <input type="hidden" name="id" value="<?php echo (int) $id; ?>">
                        <input type="hidden" name="confirm" value="yes">
                        <?php if ($listPage > 1): ?>
                        <input type="hidden" name="page" value="<?php echo (int) $listPage; ?>">
                        <?php endif; ?>
                        <button type="submit" class="btn btn-danger w-100">
                            <i class="fas fa-trash-alt me-2"></i><?php echo t('delete.confirm_button'); ?>
                        </button>
                    </form>
                    <?php else: ?>
                    <a href="#" class="btn btn-danger opacity-75" data-admin-perm="devices_delete" onclick="return false;">
                        <i class="fas fa-trash-alt me-2"></i><?php echo t('delete.confirm_button'); ?>
                    </a>
                    <?php endif; ?>
                    <a href="<?php echo htmlspecialchars($homeUrl); ?>" class="btn btn-secondary">
                        <i class="fas fa-times me-2"></i><?php echo t('delete.cancel_button'); ?>
                    </a>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
