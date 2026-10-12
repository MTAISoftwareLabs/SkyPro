<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

session_start();
require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
adminRequirePermission('devices_delete');
admin_require_csrf(true);

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) {
    $data = $_POST;
}
if (!is_array($data)) {
    $data = [];
}

$ids = $data['ids'] ?? [];
if (!is_array($ids) || count($ids) < 1) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'missing_ids'], JSON_UNESCAPED_UNICODE);
    exit();
}

$ids = array_values(array_unique(array_filter(array_map(function ($x) {
    return (int) $x;
}, $ids), function ($x) {
    return $x > 0;
})));

if (count($ids) < 1) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'missing_ids'], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    // fetch device_ids for logging before delete
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $stmt = $conn->prepare(
        "SELECT id, device_id FROM activated_devices
         WHERE id IN ($placeholders)
           AND (status IS NULL OR status <> 'deleted')"
    );
    $stmt->execute($ids);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $del = $conn->prepare(
        "UPDATE activated_devices
         SET status = 'deleted',
             expiry_date = NOW(),
             custom_domain = NULL,
             web_manage_code = NULL,
             web_manage_code_months = NULL,
             web_manage_unlocked_at = NULL,
             web_manage_unlocked_fp = NULL
         WHERE id = ?
           AND (status IS NULL OR status <> 'deleted')"
    );
    $deleted = 0;
    foreach ($rows as $r) {
        $id = (int)($r['id'] ?? 0);
        $deviceId = (string)($r['device_id'] ?? '');
        if ($id <= 0) continue;
        $ok = $del->execute([$id]);
        if ($ok) {
            $deleted++;
            // log per device for audit trail
            logActivity($conn, 'delete_device', $deviceId, 'Bulk deleted from admin panel');
        }
    }

    echo json_encode([
        'success' => true,
        'message' => 'deleted',
        'deleted' => $deleted,
        'requested' => count($ids),
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'db_error'], JSON_UNESCAPED_UNICODE);
}

