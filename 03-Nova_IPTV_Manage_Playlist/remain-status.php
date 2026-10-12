<?php
/**
 * حالة المدة المتبقية للجهاز الحالي (JSON) — للوحة القوائم مع أنيميشن التحديث.
 */
require_once __DIR__ . '/includes/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');

if (!mp_session_unlocked()) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'locked'], JSON_UNESCAPED_UNICODE);
    exit;
}

$deviceId = mp_session_device_id();
$device = $deviceId !== '' ? mp_find_active_device($conn, $deviceId) : null;
if (!$device || !mp_device_is_usable($device)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'expired'], JSON_UNESCAPED_UNICODE);
    exit;
}

$remain = mp_remaining_activation($device);

echo json_encode([
    'ok' => true,
    'usable' => true,
    'expiry_ts' => (int)$remain['expiry_ts'],
    'expiry_label' => !empty($remain['lifetime'])
        ? '∞'
        : ($remain['expiry_ts'] > 0
            ? date('Y-m-d H:i', (int)$remain['expiry_ts'])
            : ''),
    'seconds' => (int)$remain['seconds'],
    'days' => (int)$remain['days'],
    'hours' => (int)$remain['hours'],
    'mins' => (int)$remain['mins'],
    'percent' => (int)$remain['percent'],
    'max_seconds' => (int)($remain['max_seconds'] ?? 0),
    'active' => !empty($remain['ok']),
    'lifetime' => !empty($remain['lifetime']),
    'months' => !empty($remain['lifetime']) ? 0 : null,
], JSON_UNESCAPED_UNICODE);
