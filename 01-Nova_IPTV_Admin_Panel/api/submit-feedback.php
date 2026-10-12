<?php
require_once '../includes/api_boot.php';
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

$deviceId = trim((string)($data['device_id'] ?? ''));
$deviceName = trim((string)($data['device_name'] ?? ''));
$deviceUrl = trim((string)($data['device_url'] ?? ''));
$note = trim((string)($data['note'] ?? ''));

if ($note === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Note is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

if ($deviceName === '') {
    $deviceName = 'Unknown Device';
}

try {
    $ok = submitClientFeedback($conn, $deviceId, $deviceName, $deviceUrl, $note);
    if ($ok) {
        echo json_encode(['success' => true], JSON_UNESCAPED_UNICODE);
    } else {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Failed to save feedback'], JSON_UNESCAPED_UNICODE);
    }
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
