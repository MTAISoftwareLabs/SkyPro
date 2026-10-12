<?php
/**
 * حذف قائمة M3U مُدارة من الويب عند حذفها من التطبيق (Manage Accounts).
 * POST JSON: { device_id, device_token?, playlist_id }
 */
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;

$deviceId = '';
$deviceToken = '';
$playlistId = 0;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $deviceToken = isset($data['device_token']) ? trim((string)$data['device_token']) : '';
    $playlistId = isset($data['playlist_id']) ? (int)$data['playlist_id'] : 0;
} else {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'method_not_allowed'], JSON_UNESCAPED_UNICODE);
    exit();
}

if ($deviceId === '' || $playlistId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'device_id_and_playlist_id_required'], JSON_UNESCAPED_UNICODE);
    exit();
}

$storedHash = app_api_device_token_hash($conn, $deviceId);
if ($storedHash === '') {
    try {
        $hs = $conn->prepare(
            'SELECT device_api_token_hash FROM activated_devices
             WHERE LOWER(TRIM(device_id)) = LOWER(TRIM(?)) LIMIT 1'
        );
        $hs->execute([$deviceId]);
        $hr = $hs->fetch(PDO::FETCH_ASSOC);
        $storedHash = $hr ? trim((string)($hr['device_api_token_hash'] ?? '')) : '';
    } catch (PDOException $e) {
        $storedHash = '';
    }
}
if ($storedHash !== ''
    && $deviceToken !== ''
    && !app_api_verify_device_ownership($conn, $deviceId, $deviceToken)
) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'ownership_required'], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    $stmt = $conn->prepare(
        "SELECT id, device_id FROM activated_devices
         WHERE device_id = ? OR LOWER(TRIM(device_id)) = LOWER(TRIM(?))
         LIMIT 1"
    );
    $stmt->execute([$deviceId, $deviceId]);
    $device = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$device) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'device_not_found'], JSON_UNESCAPED_UNICODE);
        exit();
    }

    $canonicalId = trim((string)($device['device_id'] ?? $deviceId));

    $del = $conn->prepare(
        'DELETE FROM device_web_playlists
         WHERE id = ?
           AND (device_id = ? OR LOWER(TRIM(device_id)) = LOWER(TRIM(?)))'
    );
    $del->execute([$playlistId, $canonicalId, $canonicalId]);

    if (function_exists('logActivity')) {
        logActivity(
            $conn,
            'delete_web_playlist',
            $canonicalId,
            'Web playlist #' . $playlistId . ' deleted from app'
        );
    }

    echo json_encode([
        'success' => true,
        'deleted' => $del->rowCount() > 0,
        'playlist_id' => $playlistId,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
