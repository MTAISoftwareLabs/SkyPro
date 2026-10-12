<?php
/**
 * Shared bootstrap for public app↔panel API endpoints.
 * Include this file from api/*.php (not wrapped in a function) so $conn stays in scope.
 *
 * Sets JSON headers (no wildcard CORS), loads DB, ensures schema, verifies
 * HTTPS + HMAC + timestamp + nonce. Exposes: $conn, $app_api_raw_body
 */
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/api_auth.php';
require_once __DIR__ . '/activation_token.php';
app_api_cors_headers();

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/functions.php';

createDatabaseTable($conn);
app_api_ensure_nonce_table($conn);
app_api_ensure_device_token_column($conn);
$app_api_raw_body = app_api_require_signed_request($conn);
if (!is_string($app_api_raw_body) || $app_api_raw_body === '') {
    $app_api_raw_body = (string) ($GLOBALS['APP_API_RAW_BODY'] ?? '');
}
