<?php
/**
 * Real-time presence API for Customers Hub (admin session authenticated)
 */
header('Content-Type: application/json; charset=utf-8');

session_start();
require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!adminIsLoggedIn()) {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'Unauthorized'], JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $customers = getCustomers($conn);
    $onlineCount = 0;
    $streamingCount = 0;
    $list = [];

    foreach ($customers as $c) {
        $isOnline = !empty($c['is_online']);
        $isStreaming = !empty($c['is_streaming']);
        if ($isOnline) $onlineCount++;
        if ($isStreaming) $streamingCount++;

        $lastSeenStr = '—';
        if (!empty($c['device_last_seen'])) {
            $ts = strtotime($c['device_last_seen']);
            $diff = time() - $ts;
            if ($diff < 60) {
                $lastSeenStr = 'Just now';
            } elseif ($diff < 3600) {
                $lastSeenStr = floor($diff / 60) . 'm ago';
            } elseif ($diff < 86400) {
                $lastSeenStr = floor($diff / 3600) . 'h ago';
            } else {
                $lastSeenStr = date('Y-m-d', $ts);
            }
        }

        $list[] = [
            'id' => (int)$c['id'],
            'username' => (string)$c['username'],
            'status' => (string)$c['status'],
            'is_online' => $isOnline,
            'is_streaming' => $isStreaming,
            'watching_title' => (string)($c['watching_title'] ?? ''),
            'watching_type' => (string)($c['watching_type'] ?? ''),
            'last_seen' => $lastSeenStr,
        ];
    }

    echo json_encode([
        'success' => true,
        'online_count' => $onlineCount,
        'streaming_count' => $streamingCount,
        'total_count' => count($customers),
        'customers' => $list,
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
