<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!function_exists('adminIsLoggedIn') || !adminIsLoggedIn()) {
    header('Location: login.php');
    exit;
}

$current_page = 'playlist_codes';
$canEdit = adminCan('devices_add');

// الضيف لا يرى تفاصيل الأكواد/الأجهزة المرتبطة.
if (!$canEdit) {
    header('Location: playlist_codes.php');
    exit;
}

$codeId = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$success = '';
$error = '';

$row = null;
if ($codeId > 0) {
    try {
        $st = $conn->prepare('SELECT id, label, code, max_devices FROM playlist_access_codes WHERE id = ? LIMIT 1');
        $st->execute([$codeId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $row = null;
    }
}

if (!$row) {
    header('Location: playlist_codes.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['remove_device_id']) && $canEdit) {
    admin_require_csrf();
    $rid = (int)$_POST['remove_device_id'];
    if ($rid > 0) {
        try {
            $d = $conn->prepare('DELETE FROM playlist_code_devices WHERE id = ? AND code_id = ?');
            $d->execute([$rid, $codeId]);
            header('Location: playlist_code_devices.php?id=' . $codeId . '&msg=removed');
            exit;
        } catch (Throwable $e) {
            $error = t('msg.db_error');
        }
    }
}

if (isset($_GET['msg']) && $_GET['msg'] === 'removed') {
    $success = t('playlist_code_devices.removed');
}

$devices = [];
try {
    $q = $conn->prepare('SELECT id, device_id, device_label, created_at FROM playlist_code_devices WHERE code_id = ? ORDER BY id ASC');
    $q->execute([$codeId]);
    $devices = $q->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    $devices = [];
}

$maxD = isset($row['max_devices']) ? (int)$row['max_devices'] : 1;
if ($maxD < 1) {
    $maxD = 1;
}
$lastSeenLabel = t('playlist_code_devices.col_last_seen');
if ($lastSeenLabel === 'playlist_code_devices.col_last_seen') {
    $lastSeenLabel = (isset($isRtl) && $isRtl) ? 'آخر ظهور' : 'Last seen';
}

?>
<!DOCTYPE html>
<html dir="<?php echo isset($isRtl) && $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang ?? 'ar'); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo htmlspecialchars(t('playlist_code_devices.title')); ?> - <?php echo htmlspecialchars(t('app.title')); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<style>
.table-responsive { overflow-x: auto; -webkit-overflow-scrolling: touch; }
#pcdDevicesTable{
    table-layout: fixed;
    width: 100%;
}
#pcdDevicesTable th, #pcdDevicesTable td{
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
@media (max-width: 991.98px) {
    #pcdDevicesTable { min-width: 720px; table-layout: auto; }
}
.pcd-badge{
    font-size: 0.78rem;
    padding: 4px 10px;
    border-radius: 999px;
}
.pcd-status{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    border-radius: 999px;
    font-size: 0.78rem;
    font-weight: 700;
    line-height: 1;
}
.pcd-status i{
    font-size: 0.76rem;
}
.pcd-status--online{
    background: rgba(22, 163, 74, 0.18);
    border: 1px solid rgba(34, 197, 94, 0.45);
    color: #86efac;
}
.pcd-status--offline{
    background: rgba(220, 38, 38, 0.16);
    border: 1px solid rgba(248, 113, 113, 0.42);
    color: #fecaca;
}
.pcd-status-sub{
    display: block;
    font-size: 0.68rem;
    font-weight: 600;
    margin-top: 4px;
    opacity: 0.95;
}
.pcd-hero{
    border-radius: 18px;
    border: 1px solid rgba(148,163,184,0.24);
    background: linear-gradient(145deg, rgba(15,23,42,0.88), rgba(2,6,23,0.95));
    padding: 1rem 1.1rem;
    margin-bottom: 1rem;
}
.pcd-back-btn{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    border-radius: 999px;
    padding: 0.45rem 0.95rem;
    font-size: 0.82rem;
    font-weight: 700;
    text-decoration: none;
    color: #e0f2fe;
    background: rgba(14,116,144,0.22);
    border: 1px solid rgba(56,189,248,0.42);
    transition: all .15s ease;
}
.pcd-back-btn:hover{
    color: #f8fafc;
    background: rgba(14,116,144,0.35);
    transform: translateY(-1px);
}
.pcd-title{
    margin: 0.65rem 0 0.45rem;
    color: #f8fafc;
    font-weight: 800;
    font-size: 1.18rem;
}
.pcd-meta{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0.45rem 0.75rem;
    border-radius: 12px;
    border: 1px solid rgba(148,163,184,0.25);
    background: rgba(15,23,42,0.55);
    color: #cbd5e1;
    font-size: 0.86rem;
}
.pcd-meta strong{
    color: #f8fafc;
}
.pcd-dot{
    opacity: 0.45;
}
</style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container-fluid px-2 px-md-3 admin-main py-4">
    <div class="pcd-hero">
        <a href="playlist_codes.php" class="pcd-back-btn">
            <i class="fas fa-arrow-left"></i>
            <?php echo htmlspecialchars(t('playlist_code_devices.back')); ?>
        </a>
        <h1 class="pcd-title"><?php echo htmlspecialchars(t('playlist_code_devices.title')); ?></h1>
        <div class="pcd-meta">
            <span><?php echo htmlspecialchars(t('playlist_code_devices.code_label')); ?>:</span>
            <strong><?php echo htmlspecialchars((string)$row['code']); ?></strong>
            <span class="pcd-dot">—</span>
            <strong><?php echo htmlspecialchars((string)$row['label']); ?></strong>
            <span class="pcd-dot">—</span>
            <span><?php echo htmlspecialchars(t('playlist_code_devices.slots')); ?>:</span>
            <strong><?php echo count($devices); ?> / <?php echo $maxD; ?></strong>
        </div>
    </div>

    <?php if ($success !== ''): ?>
        <div class="alert alert-success mt-3"><?php echo htmlspecialchars($success); ?></div>
    <?php endif; ?>
    <?php if ($error !== ''): ?>
        <div class="alert alert-danger mt-3"><?php echo htmlspecialchars($error); ?></div>
    <?php endif; ?>

    <div class="mt-4">
        <p class="admin-scroll-hint mb-2">
            <i class="fas fa-arrows-left-right" aria-hidden="true"></i>
            <span><?php echo $isRtl ? 'اسحب الجدول أفقياً لعرض كل الأعمدة' : 'Swipe the table sideways to see all columns'; ?></span>
        </p>
        <div class="table-responsive admin-table-scroll">
        <table class="table table-dark table-striped table-hover" id="pcdDevicesTable">
            <thead>
                <tr>
                    <th><?php echo htmlspecialchars(t('playlist_code_devices.col_device')); ?></th>
                    <th><?php echo htmlspecialchars(t('playlist_code_devices.col_id')); ?></th>
                    <th><?php echo htmlspecialchars(t('table.connection_status')); ?></th>
                    <th><?php echo htmlspecialchars(t('playlist_code_devices.col_date')); ?></th>
                    <?php if ($canEdit): ?>
                        <th style="text-align:right"><?php echo htmlspecialchars(t('table.actions')); ?></th>
                    <?php endif; ?>
                </tr>
            </thead>
            <tbody>
            <?php if (count($devices) === 0): ?>
                <tr><td colspan="<?php echo $canEdit ? 5 : 4; ?>" class="text-secondary"><?php echo htmlspecialchars(t('playlist_code_devices.empty')); ?></td></tr>
            <?php else: foreach ($devices as $d): ?>
                <?php
                $deviceId = (string)($d['device_id'] ?? '');
                $act = null;
                $online = false;
                $lastSeen = null;
                $activatedId = null;

                if ($deviceId !== '') {
                    try {
                        $st = $conn->prepare('SELECT id, last_seen_at FROM activated_devices WHERE device_id = ? LIMIT 1');
                        $st->execute([$deviceId]);
                        $act = $st->fetch(PDO::FETCH_ASSOC);
                    } catch (Throwable $e) {
                        $act = null;
                    }
                }

                $lastSeen = $act['last_seen_at'] ?? null;
                if ($lastSeen) {
                    $ts = strtotime((string)$lastSeen);
                    if ($ts !== false && (time() - $ts) <= 120) {
                        $online = true;
                    }
                }
                $activatedId = $act['id'] ?? null;
                ?>
                <tr>
                    <td><?php echo htmlspecialchars(trim((string)($d['device_label'] ?? '')) !== '' ? (string)$d['device_label'] : '—'); ?></td>
                    <td><code class="small"><?php echo htmlspecialchars((string)$d['device_id']); ?></code></td>
                    <td>
                        <?php if ($online): ?>
                            <span class="pcd-status pcd-status--online">
                                <i class="fas fa-circle-check"></i>
                                <?php echo htmlspecialchars(t('presence.online')); ?>
                            </span>
                        <?php else: ?>
                            <span class="pcd-status pcd-status--offline">
                                <i class="fas fa-circle-xmark"></i>
                                <?php echo htmlspecialchars(t('presence.offline')); ?>
                            </span>
                            <span class="pcd-status-sub">
                                <?php
                                if ($lastSeen) {
                                    echo htmlspecialchars($lastSeenLabel) . ': ' .
                                        htmlspecialchars(format_datetime_short((string)$lastSeen));
                                } else {
                                    echo htmlspecialchars($lastSeenLabel) . ': —';
                                }
                                ?>
                            </span>
                        <?php endif; ?>
                    </td>
                    <td><?php echo htmlspecialchars((string)$d['created_at']); ?></td>
                    <?php if ($canEdit): ?>
                        <td style="text-align:right">
                            <?php if ($activatedId): ?>
                                <a class="btn btn-sm btn-outline-info me-1" href="edit-device.php?id=<?php echo (int)$activatedId; ?>" title="<?php echo htmlspecialchars(t('button.edit')); ?>">
                                    <i class="fas fa-pen"></i>
                                </a>
                            <?php endif; ?>
                            <form method="post"
                                  class="d-inline"
                                  data-admin-confirm
                                  data-confirm-title="<?php echo htmlspecialchars(t('playlist_code_devices.remove_title'), ENT_QUOTES, 'UTF-8'); ?>"
                                  data-confirm-message="<?php echo htmlspecialchars(t('playlist_code_devices.remove_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                                  data-confirm-warning="<?php echo htmlspecialchars(t('playlist_code_devices.remove_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                                  data-confirm-ok="<?php echo htmlspecialchars(t('playlist_code_devices.remove'), ENT_QUOTES, 'UTF-8'); ?>"
                                  data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                  data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                      ['label' => t('playlist_code_devices.col_device'), 'value' => trim((string)($d['device_label'] ?? '')) !== '' ? (string)$d['device_label'] : '—'],
                                      ['label' => t('playlist_code_devices.col_id'), 'value' => (string)($d['device_id'] ?? ''), 'mono' => true],
                                  ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                <input type="hidden" name="remove_device_id" value="<?php echo (int)$d['id']; ?>">
                                <button type="submit" class="btn btn-sm btn-outline-danger" title="<?php echo htmlspecialchars(t('playlist_code_devices.remove')); ?>">
                                    <i class="fas fa-trash"></i>
                                </button>
                            </form>
                        </td>
                    <?php endif; ?>
                </tr>
            <?php endforeach; endif; ?>
            </tbody>
        </table>
        </div>
    </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
</body>
</html>
