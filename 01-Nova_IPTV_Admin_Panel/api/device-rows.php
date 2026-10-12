<?php
/**
 * HTML rows for live dashboard sync (session-authenticated admin only).
 */
header('Content-Type: application/json; charset=utf-8');

session_start();
require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/lang.php';
require_once '../includes/admin_auth.php';
require_once '../includes/pagination.php';
require_once '../includes/devices_table_row.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!adminIsLoggedIn()) {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'unauthorized'], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!adminCan('devices_view') && !adminCan('dashboard') && !adminCan('manage_activations')) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'forbidden'], JSON_UNESCAPED_UNICODE);
    exit;
}

$rawIds = trim((string) ($_GET['ids'] ?? ''));
if ($rawIds === '') {
    echo json_encode(['success' => true, 'rows' => []], JSON_UNESCAPED_UNICODE);
    exit;
}

$ids = [];
foreach (explode(',', $rawIds) as $part) {
    $id = (int) trim($part);
    if ($id > 0) {
        $ids[$id] = $id;
    }
}

if (!$ids) {
    echo json_encode(['success' => true, 'rows' => []], JSON_UNESCAPED_UNICODE);
    exit;
}

$isGuest = adminIsGuestRole();
$listPage = admin_request_list_page();
$placeholders = implode(',', array_fill(0, count($ids), '?'));

try {
    $sql = "SELECT a.*,
        (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
        FROM activated_devices a
        WHERE a.id IN ($placeholders)
          AND (a.status IS NULL OR a.status <> 'deleted')
        ORDER BY a.activation_date DESC";
    $stmt = $conn->prepare($sql);
    $stmt->execute(array_values($ids));
    $rows = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $device) {
        $pk = (int) ($device['id'] ?? 0);
        if ($pk <= 0) {
            continue;
        }
        $rows[] = [
            'id' => $pk,
            'html' => admin_render_device_dashboard_row($device, $isGuest, $listPage),
        ];
    }
    echo json_encode(['success' => true, 'rows' => $rows], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
