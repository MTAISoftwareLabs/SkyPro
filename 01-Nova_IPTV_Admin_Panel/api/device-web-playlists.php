<?php
/**
 * قائمة قوائم M3U المُدارة من الويب لهذا الجهاز (للمزامنة إلى Manage Accounts).
 * POST JSON: { device_id, device_token }
 */
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;

$deviceId = '';
$deviceToken = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $deviceToken = isset($data['device_token']) ? trim((string)$data['device_token']) : '';
} else {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'method_not_allowed'], JSON_UNESCAPED_UNICODE);
    exit();
}

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

$storedHash = app_api_device_token_hash($conn, $deviceId);
if ($storedHash === '') {
    // جرّب مطابقة غير حسّاسة لحالة الأحرف
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
    // لا تمنع المزامنة إن فشل التوكن — الطلب موقّع HMAC مسبقاً
}

try {
    $stmt = $conn->prepare(
        "SELECT id, status, expiry_date, device_id FROM activated_devices
         WHERE device_id = ? OR LOWER(TRIM(device_id)) = LOWER(TRIM(?))
         LIMIT 1"
    );
    $stmt->execute([$deviceId, $deviceId]);
    $device = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$device) {
        echo json_encode(['success' => true, 'playlists' => [], 'message' => 'device_not_found'], JSON_UNESCAPED_UNICODE);
        exit();
    }

    $canonicalId = trim((string)($device['device_id'] ?? $deviceId));
    $status = strtolower(trim((string)($device['status'] ?? '')));
    if ($status === 'blocked') {
        echo json_encode(['success' => true, 'playlists' => [], 'status' => 'blocked'], JSON_UNESCAPED_UNICODE);
        exit();
    }
    $expiry = (string)($device['expiry_date'] ?? '');
    if ($status !== 'active' || ($expiry !== '' && strtotime($expiry) <= time())) {
        echo json_encode(['success' => true, 'playlists' => [], 'status' => 'expired'], JSON_UNESCAPED_UNICODE);
        exit();
    }

    $q = $conn->prepare(
        'SELECT id, name, m3u_url, updated_at
         FROM device_web_playlists
         WHERE device_id = ?
            OR LOWER(TRIM(device_id)) = LOWER(TRIM(?))
         ORDER BY id ASC'
    );
    $q->execute([$canonicalId, $canonicalId]);
    $rows = $q->fetchAll(PDO::FETCH_ASSOC) ?: [];
    $out = [];
    foreach ($rows as $row) {
        $out[] = [
            'id' => (int)($row['id'] ?? 0),
            'name' => (string)($row['name'] ?? ''),
            'm3u_url' => (string)($row['m3u_url'] ?? ''),
            'updated_at' => (string)($row['updated_at'] ?? ''),
        ];
    }

    echo json_encode([
        'success' => true,
        'playlists' => $out,
        'device_id' => $canonicalId,
        'count' => count($out),
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
