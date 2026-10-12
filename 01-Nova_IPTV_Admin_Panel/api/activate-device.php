<?php
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;
$data = app_api_json_payload($raw);
try {
    $resolved = resolveActivatedDeviceFromPayload($conn, $data, false);
} catch (Throwable $resolveErr) {
    error_log('[NovaAPI] activate resolve failed: ' . $resolveErr->getMessage());
    $resolved = [
        'row' => null,
        'device_id' => app_api_field($data, 'device_id'),
        'mac_address' => '',
        'hardware_fingerprint' => '',
    ];
}
$deviceId = $resolved['device_id'];
$deviceName = app_api_field($data, 'device_name');
$mac = $resolved['mac_address'];
$hardwareFingerprint = $resolved['hardware_fingerprint'];

if ($deviceId === '') {
    app_emit_activation_json($conn, '', [
        'success' => false,
        'activated' => false,
        'message' => 'Device ID is required',
    ], 400);
}

try {
    $settings = getSettings($conn);

    $days = isset($settings['default_expiry_days']) ? (int)$settings['default_expiry_days'] : 30;
    if ($days <= 0) {
        $days = 30;
    }

    $existing = $resolved['row'];
    if (!$existing) {
        $stmt = $conn->prepare("SELECT * FROM activated_devices WHERE device_id = ?");
        $stmt->execute([$deviceId]);
        $existing = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    if ($existing && $existing['status'] === 'blocked') {
        app_emit_activation_json($conn, $deviceId, [
            'success' => false,
            'activated' => false,
            'already_active' => false,
            'status' => 'blocked',
            'message' => 'blocked_by_panel',
        ]);
    }

    if ($existing && $existing['status'] !== 'deleted' && (
        $existing['status'] === 'expired'
        || (!empty($existing['expiry_date']) && strtotime((string)$existing['expiry_date']) <= time())
    )) {
        app_emit_activation_json($conn, $deviceId, [
            'success' => false,
            'activated' => false,
            'already_active' => false,
            'status' => 'expired',
            'message' => 'expired_by_panel',
            'expiry_date' => $existing['expiry_date'] ?? null,
        ]);
    }

    if ($existing && $existing['status'] === 'active' && strtotime($existing['expiry_date']) > time()) {
        touchDeviceName($conn, $deviceId, $deviceName);
        $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
        $payload = array_merge([
            'success' => true,
            'activated' => true,
            'already_active' => true,
            'status' => 'active',
            'expiry_date' => $existing['expiry_date'],
            'lifetime' => deviceExpiryIsLifetime($existing['expiry_date'] ?? null),
            'trial' => deviceRowIsTrial($existing),
            'message' => 'Device is already activated',
        ], app_panel_public_payload_for_device(is_array($settings) ? $settings : [], $existing));
        if ($tokenOut !== '') {
            $payload['device_token'] = $tokenOut;
        }
        app_emit_activation_json($conn, $deviceId, $payload);
    }

    $now = new DateTime();
    $expiry = clone $now;
    $expiry->modify('+' . $days . ' days');
    $expiryStr = $expiry->format('Y-m-d H:i:s');

    if (!activateDevice($conn, $deviceId, $expiryStr, $deviceName, true)) {
        app_emit_activation_json($conn, $deviceId, [
            'success' => false,
            'activated' => false,
            'message' => 'Failed to activate device',
        ], 500);
    }

    persistActivatedDeviceBindingKeys($conn, $deviceId, $mac, $hardwareFingerprint);

    logActivity($conn, 'add_device', $deviceId, 'Activated automatically from app');

    $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
    $payload = array_merge([
        'success' => true,
        'activated' => true,
        'already_active' => false,
        'status' => 'active',
        'expiry_date' => $expiryStr,
        'lifetime' => deviceExpiryIsLifetime($expiryStr),
        'trial' => true,
        'message' => 'Device activated successfully',
    ], app_panel_public_payload_for_device(is_array($settings) ? $settings : [], ['ads_enabled' => 1]));
    if ($tokenOut !== '') {
        $payload['device_token'] = $tokenOut;
    }
    app_emit_activation_json($conn, $deviceId, $payload);
} catch (PDOException $e) {
    app_emit_activation_json($conn, $deviceId, [
        'success' => false,
        'activated' => false,
        'message' => 'Database error',
    ], 500);
}
