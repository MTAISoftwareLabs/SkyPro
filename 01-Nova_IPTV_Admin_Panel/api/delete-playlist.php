<?php
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;

$deviceId = '';
$deviceToken = '';
$unlinkRemote = false;
$data = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    if (!is_array($data)) {
        $data = [];
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $deviceToken = isset($data['device_token']) ? trim((string)$data['device_token']) : '';
    $unlinkRemote = !empty($data['unlink_remote'])
        || $data['unlink_remote'] === 1
        || $data['unlink_remote'] === '1'
        || $data['unlink_remote'] === true
        || $data['unlink_remote'] === 'true';
}

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

// فك ربط من جهاز آخر (QR): لا تطلب ملكية الهدف — ولا تلمس status/expiry.
if (!$unlinkRemote) {
    // Ownership: if a token was issued for this device, require it for destructive clears.
    $storedHash = app_api_device_token_hash($conn, $deviceId);
    if ($storedHash !== '' && !app_api_verify_device_ownership($conn, $deviceId, $deviceToken)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'ownership_required'], JSON_UNESCAPED_UNICODE);
        exit();
    }
}

try {
    if ($unlinkRemote) {
        $stmt = $conn->prepare(
            "UPDATE activated_devices
             SET custom_domain = NULL,
                 account_key = NULL,
                 account_display_name = NULL
             WHERE device_id = ?"
        );
        $stmt->execute([$deviceId]);
        logActivity($conn, 'unlink_device', $deviceId, 'Remote playlist unlink (activation kept)');
    } else {
        $stmt = $conn->prepare("UPDATE activated_devices SET custom_domain = NULL WHERE device_id = ?");
        $stmt->execute([$deviceId]);
        if ($stmt->rowCount() > 0) {
            logActivity($conn, 'delete_playlist', $deviceId, 'Playlist URL cleared on app logout');
        }
    }
    echo json_encode(['success' => true, 'message' => 'Playlist cleared'], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
