<?php
/**
 * Live presence + now-watching for a single device (admin session only).
 * Used by edit-device.php auto-refresh (every ~15s).
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

session_start();
require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/lang.php';
require_once '../includes/admin_auth.php';
require_once '../includes/credential_crypto.php';

adminBootstrapLogin($conn);

if (!adminIsLoggedIn()) {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'unauthorized'], JSON_UNESCAPED_UNICODE);
    exit();
}

if (!adminCan('devices_view')) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'forbidden'], JSON_UNESCAPED_UNICODE);
    exit();
}

$id = admin_parse_positive_int_id($_GET['id'] ?? '');
if ($id <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'invalid_id'], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    $device = admin_find_managed_device($conn, $id);
    if (!$device) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'not_found'], JSON_UNESCAPED_UNICODE);
        exit();
    }

    $lastSeenAt = trim((string) ($device['last_seen_at'] ?? ''));
    $online = device_presence_is_online($lastSeenAt !== '' ? $lastSeenAt : null);

    $watchingType = strtolower(trim((string) ($device['watching_type'] ?? '')));
    $watchingTitle = trim((string) ($device['watching_title'] ?? ''));
    $watchingExtra = trim((string) ($device['watching_extra'] ?? ''));
    $watchingUpdatedAt = trim((string) ($device['watching_updated_at'] ?? ''));
    $watchingFresh = false;
    if ($watchingUpdatedAt !== '') {
        $wTs = strtotime($watchingUpdatedAt);
        if ($wTs !== false) {
            $watchingFresh = (time() - $wTs) <= 45;
        }
    }
    $showWatching = $online
        && $watchingFresh
        && in_array($watchingType, ['live', 'movie', 'series'], true)
        && $watchingTitle !== '';

    $lastSeenFmt = '';
    if ($lastSeenAt !== '') {
        $ts = strtotime($lastSeenAt);
        $lastSeenFmt = $ts !== false ? date('Y-m-d H:i:s', $ts) : $lastSeenAt;
    }

    echo json_encode([
        'success' => true,
        'online' => $online,
        'last_seen_at' => $lastSeenAt,
        'last_seen_fmt' => $lastSeenFmt,
        'watching' => $showWatching
            ? [
                'type' => $watchingType,
                'title' => $watchingTitle,
                'extra' => $watchingExtra,
            ]
            : null,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
