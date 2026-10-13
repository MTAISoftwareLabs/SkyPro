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

$url = trim((string)($data['server_url'] ?? ''));
$key = trim((string)($data['api_key'] ?? ''));
$user = trim((string)($data['username'] ?? ''));
$pass = (string)($data['password'] ?? '');
$type = trim((string)($data['api_type'] ?? 'xtream_codes'));

if ($url === '') {
    $cfg = xtream_get_config($conn);
    $url = $cfg['server_url'];
    if ($key === '') $key = $cfg['api_key'];
    if ($user === '') $user = $cfg['username'];
    if ($pass === '') $pass = $cfg['password'];
    if ($type === '') $type = $cfg['api_type'];
}

$result = xtream_test_connection($url, $key, $user, $pass, $type);
echo json_encode($result, JSON_UNESCAPED_UNICODE);
