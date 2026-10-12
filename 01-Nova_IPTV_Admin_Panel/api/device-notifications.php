<?php
require_once '../includes/api_boot.php';
require_once '../includes/onesignal_push.php';

$raw = $app_api_raw_body;

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed'], JSON_UNESCAPED_UNICODE);
    exit();
}

$data = json_decode($raw, true);
if (!is_array($data)) {
    $data = $_POST;
}
if (!is_array($data)) {
    $data = [];
}

$deviceId = trim((string)($data['device_id'] ?? ''));
$limit = (int)($data['limit'] ?? 40);
$since = trim((string)($data['since'] ?? ''));

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

$items = get_push_notifications_for_device(
    $conn,
    $deviceId,
    $limit,
    $since !== '' ? $since : null
);

echo json_encode([
    'success' => true,
    'notifications' => $items,
], JSON_UNESCAPED_UNICODE);
