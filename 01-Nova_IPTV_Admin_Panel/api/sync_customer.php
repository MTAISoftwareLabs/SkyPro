<?php
session_start();
header('Content-Type: application/json; charset=utf-8');

require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/admin_auth.php';
require_once '../includes/xtream_api.php';

if (!adminIsLoggedIn()) {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'Unauthorized']);
    exit;
}

$raw = file_get_contents('php://input');
$data = json_decode($raw, true) ?: $_POST;
$customerId = (int)($data['customer_id'] ?? 0);

if ($customerId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid customer ID']);
    exit;
}

$cust = getCustomerById($conn, $customerId);
if (!$cust) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Customer not found']);
    exit;
}

$syncResult = xtream_create_line($conn, [
    'username' => $cust['username'],
    'password' => $cust['password'],
    'expiry_date' => $cust['expiry_date'],
    'max_connections' => (int)($cust['max_connections'] ?? 1),
    'notes' => $cust['customer_name'] ?: ($cust['notes'] ?? ''),
]);

$syncStatus = $syncResult['synced'] ? 'synced' : 'pending';
$syncMsg = $syncResult['message'] ?? '';

try {
    $stmt = $conn->prepare("UPDATE iptv_customers SET server_sync_status = ?, server_sync_message = ? WHERE id = ?");
    $stmt->execute([$syncStatus, $syncMsg, $customerId]);
} catch (Throwable $e) {}

echo json_encode([
    'success' => true,
    'synced' => (bool)$syncResult['synced'],
    'sync_status' => $syncStatus,
    'message' => $syncMsg,
    'http_code' => $syncResult['http_code'] ?? 0,
], JSON_UNESCAPED_UNICODE);
