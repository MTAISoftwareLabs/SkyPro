<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';
require_once 'includes/pagination.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!adminCan('manage_activations') && !adminCan('dashboard') && !adminCan('devices_view')) {
    header('Location: access_denied.php?perm=manage_activations');
    exit();
}

$current_page = 'activity_log';
$isGuest = adminIsGuestRole();
$log_cleared = isset($_GET['log_cleared']) && $_GET['log_cleared'] === '1';
$perPage = 50;

// مسح السجل من هذه الصفحة مباشرة (بدون التحويل لصفحة أخرى)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['clear_activity_log'])) {
    admin_require_csrf();
    if (!adminCan('activity_log_clear')) {
        header('Location: access_denied.php?perm=activity_log_clear');
        exit();
    }
    try {
        $conn->exec('TRUNCATE TABLE activity_log');
    } catch (PDOException $e) {
        // الجدول قد يكون غير موجود
    }
    header('Location: activity_log.php?log_cleared=1');
    exit();
}

$total = 0;
try {
    $total = (int)$conn->query('SELECT COUNT(*) FROM activity_log')->fetchColumn();
} catch (PDOException $e) {
    $total = 0;
}

$pages = max(1, (int)ceil($total / $perPage));
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
if ($page < 1) {
    $page = 1;
}
if ($page > $pages) {
    $page = $pages;
}
$offset = ($page - 1) * $perPage;

$activity_log = [];
try {
    $limit = (int)$perPage;
    $off = (int)$offset;
    $stmt = $conn->query(
        "SELECT * FROM activity_log ORDER BY created_at DESC LIMIT {$limit} OFFSET {$off}"
    );
    if ($stmt) {
        $activity_log = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
} catch (PDOException $e) {
    $activity_log = [];
}

function activity_log_action_label($action)
{
    global $lang;
    $action = (string)$action;
    if ($lang === 'en') {
        $labels = [
            'edit_device' => 'Edit device',
            'delete_device' => 'Delete device',
            'check_activation' => 'Check activation',
            'add_device' => 'Add device',
            'auto_register' => 'Auto register',
            'bind_account' => 'Bind account',
            'save_playlist' => 'Save playlist',
            'delete_playlist' => 'Delete playlist',
            'redeem_playlist_code' => 'Redeem playlist code',
        ];
    } else {
        $labels = [
            'edit_device' => 'تعديل جهاز',
            'delete_device' => 'حذف جهاز',
            'check_activation' => 'فحص تفعيل',
            'add_device' => 'إضافة جهاز',
            'auto_register' => 'تسجيل تلقائي',
            'bind_account' => 'ربط حساب',
            'save_playlist' => 'حفظ قائمة',
            'delete_playlist' => 'حذف قائمة',
            'redeem_playlist_code' => 'استخدام رمز قائمة',
        ];
    }
    return $labels[$action] ?? $action;
}

$from = $total === 0 ? 0 : ($offset + 1);
$to = min($offset + count($activity_log), $total);
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo htmlspecialchars(t('activity_log.title')); ?> - <?php echo htmlspecialchars(t('app.title')); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
body { font-family: 'Cairo', system-ui, sans-serif; }
.al-shell { margin-top: 8px; }
.al-hero {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1.25rem;
}
.al-hero h1 {
    font-size: 1.45rem;
    font-weight: 800;
    margin: 0 0 0.35rem;
    color: #f8fafc;
    display: flex;
    align-items: center;
    gap: 0.65rem;
}
.al-hero h1 .al-icon {
    width: 42px;
    height: 42px;
    border-radius: 14px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(145deg, rgba(56,189,248,0.28), rgba(99,102,241,0.22));
    border: 1px solid rgba(125,211,252,0.35);
    color: #7dd3fc;
    font-size: 1.05rem;
}
.al-hero p {
    margin: 0;
    color: #94a3b8;
    font-size: 0.92rem;
}
.al-meta {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 8px 14px;
    border-radius: 999px;
    background: rgba(15,23,42,0.9);
    border: 1px solid rgba(148,163,184,0.28);
    color: #cbd5e1;
    font-size: 0.85rem;
    font-weight: 600;
}
.al-card {
    border-radius: 18px;
    background: linear-gradient(145deg, #0f172a, #020617);
    border: 1px solid rgba(148,163,184,0.25);
    box-shadow: 0 20px 40px rgba(0,0,0,.45);
    padding: 1rem 1.1rem 1.15rem;
}
.al-card .table {
    color: #e5e7eb;
    margin-bottom: 0;
}
.al-card .table thead th {
    background: #0f172a;
    color: #f1f5f9;
    font-weight: 700;
    border-bottom-color: rgba(148,163,184,0.25);
    white-space: nowrap;
}
.al-card .table tbody td {
    border-color: rgba(51,65,85,0.55);
    vertical-align: middle;
}
.al-card .table tbody tr:hover {
    background: rgba(30,41,59,0.45);
}
.al-action {
    display: inline-flex;
    align-items: center;
    padding: 4px 10px;
    border-radius: 999px;
    background: rgba(24, 24, 24, 0.9);
    border: 1px solid rgba(0, 7, 10, 0.45);
    color: #f0f9ff !important;
    font-size: 0.82rem;
    font-weight: 700;
    text-shadow: 0 1px 0 rgba(2, 6, 23, 0.35);
}
.al-device {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.82rem;
    color: #e2e8f0;
    background: rgba(15,23,42,0.9);
    border: 1px solid rgba(71,85,105,0.55);
    border-radius: 8px;
    padding: 3px 8px;
}
.al-empty {
    text-align: center;
    padding: 3rem 1rem;
    color: #64748b;
}
.al-empty i {
    font-size: 2rem;
    display: block;
    margin-bottom: 0.75rem;
    color: #334155;
}
.btn-delete-log {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    border-radius: 999px;
    padding: 0.45rem 1rem;
    font-weight: 700;
    background: linear-gradient(135deg, #f97373, #ef4444);
    border: none;
    color: #fff !important;
    text-decoration: none !important;
    cursor: pointer;
    font-family: inherit;
}
.btn-delete-log:hover {
    color: #fff !important;
    filter: brightness(1.05);
}
.alert-success {
    background: rgba(22,163,74,.15);
    border: 1px solid rgba(34,197,94,.6);
    color: #bbf7d0;
    border-radius: 14px;
}
</style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container admin-main al-shell">
    <?php if ($log_cleared): ?>
    <div class="alert alert-success">
        <i class="fas fa-check-circle me-2"></i><?php echo htmlspecialchars(t('manage.log_cleared')); ?>
    </div>
    <?php endif; ?>

    <div class="al-hero">
        <div>
            <h1>
                <span class="al-icon" aria-hidden="true"><i class="fas fa-timeline"></i></span>
                <?php echo htmlspecialchars(t('activity_log.title')); ?>
            </h1>
            <p><?php echo htmlspecialchars(t('activity_log.subtitle')); ?></p>
        </div>
        <div class="d-flex flex-wrap align-items-center gap-2">
            <span class="al-meta">
                <i class="fas fa-layer-group" aria-hidden="true"></i>
                <?php
                if ($total === 0) {
                    echo htmlspecialchars(t('activity_log.empty_meta'));
                } else {
                    echo htmlspecialchars(t('activity_log.showing_prefix'))
                        . ' ' . (int)$from . '–' . (int)$to . ' '
                        . htmlspecialchars(t('activity_log.showing_of'))
                        . ' ' . (int)$total;
                }
                ?>
            </span>
            <?php if ($total > 0 && adminCan('activity_log_clear')): ?>
            <form method="post"
                  class="d-inline"
                  data-admin-perm="activity_log_clear"
                  data-admin-confirm
                  data-confirm-title="<?php echo htmlspecialchars(t('manage.log_delete_title'), ENT_QUOTES, 'UTF-8'); ?>"
                  data-confirm-message="<?php echo htmlspecialchars(t('manage.log_delete_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                  data-confirm-warning="<?php echo htmlspecialchars(t('manage.log_delete_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                  data-confirm-ok="<?php echo htmlspecialchars(t('manage.log_delete_button'), ENT_QUOTES, 'UTF-8'); ?>"
                  data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>">
                <input type="hidden" name="clear_activity_log" value="1">
                <button type="submit" class="btn-delete-log">
                    <i class="fas fa-trash"></i>
                    <?php echo htmlspecialchars(t('manage.log_delete_button')); ?>
                </button>
            </form>
            <?php endif; ?>
        </div>
    </div>

    <div class="al-card">
        <div class="table-responsive">
            <table class="table table-sm align-middle">
                <thead>
                    <tr>
                        <th><?php echo htmlspecialchars(t('manage.log_col_date')); ?></th>
                        <th><?php echo htmlspecialchars(t('manage.log_col_action')); ?></th>
                        <th><?php echo htmlspecialchars(t('manage.log_col_device_id')); ?></th>
                        <th><?php echo htmlspecialchars(t('manage.log_col_details')); ?></th>
                    </tr>
                </thead>
                <tbody>
                <?php if (empty($activity_log)): ?>
                    <tr>
                        <td colspan="4">
                            <div class="al-empty">
                                <i class="fas fa-inbox" aria-hidden="true"></i>
                                <?php echo htmlspecialchars(t('activity_log.empty')); ?>
                            </div>
                        </td>
                    </tr>
                <?php else: ?>
                    <?php foreach ($activity_log as $log): ?>
                    <tr>
                        <td><?php echo htmlspecialchars(date('Y-m-d H:i', strtotime((string)$log['created_at']))); ?></td>
                        <td><span class="al-action"><?php echo htmlspecialchars(activity_log_action_label($log['action'] ?? '')); ?></span></td>
                        <td>
                            <code class="al-device"><?php
                                echo htmlspecialchars(
                                    $isGuest
                                        ? adminMaskDeviceId((string)($log['device_id'] ?? ''))
                                        : (string)($log['device_id'] ?? '')
                                );
                            ?></code>
                        </td>
                        <td class="text-secondary"><?php echo htmlspecialchars((string)($log['details'] ?? '-')); ?></td>
                    </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
                </tbody>
            </table>
        </div>
        <?php
        $pq = $_GET;
        unset($pq['log_cleared']);
        echo admin_render_pagination($page, $pages, ['query' => $pq]);
        ?>
    </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
</body>
</html>
