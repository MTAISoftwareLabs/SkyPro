<?php
/**
 * التحقق من رمز القائمة (5–6 أرقام) وإرجاع رابط M3U.
 * الرمز يمكن أن يتكرر لأجهزة مختلفة — كل صف مربوط بـ bound_device_id.
 */
require_once '../includes/api_boot.php';
require_once '../includes/credential_crypto.php';
$raw = $app_api_raw_body;

function respond(int $http, array $body): void {
    http_response_code($http);
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['success' => false, 'message' => 'method_not_allowed']);
}

$data = json_decode($raw, true);
if (!is_array($data)) {
    $data = [];
}

$code = isset($data['code']) ? preg_replace('/\D/', '', (string)$data['code']) : '';
if (strlen($code) < 5 || strlen($code) > 6) {
    respond(400, ['success' => false, 'message' => 'invalid_code']);
}

$deviceId = trim((string)($data['device_id'] ?? ''));
$deviceId = preg_replace('/[\x{200B}-\x{200D}\x{FEFF}]/u', '', $deviceId) ?? $deviceId;
$deviceId = preg_replace('/\s+/u', '', $deviceId) ?? $deviceId;
if ($deviceId === '') {
    respond(400, ['success' => false, 'message' => 'device_required']);
}

if (!credential_is_configured($conn)) {
    respond(503, ['success' => false, 'message' => 'credential_enc_key_not_configured']);
}

$resolved = resolveActivatedDeviceFromPayload($conn, $data, false);
$deviceId = $resolved['device_id'];

$deviceName = trim((string)($data['device_name'] ?? ''));
if (strlen($deviceName) > 255) {
    $deviceName = substr($deviceName, 0, 255);
}

try {
    $row = null;

    $stBound = $conn->prepare(
        'SELECT id, label, m3u_url, max_devices, bound_device_id
         FROM playlist_access_codes
         WHERE code = ? AND bound_device_id = ?
         LIMIT 1'
    );
    $stBound->execute([$code, $deviceId]);
    $row = $stBound->fetch(PDO::FETCH_ASSOC) ?: null;

    if (!$row) {
        $stLegacy = $conn->prepare(
            'SELECT id, label, m3u_url, max_devices, bound_device_id
             FROM playlist_access_codes
             WHERE code = ? AND (bound_device_id IS NULL OR bound_device_id = \'\')
             LIMIT 1'
        );
        $stLegacy->execute([$code]);
        $row = $stLegacy->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    if (!$row) {
        $stAny = $conn->prepare('SELECT id FROM playlist_access_codes WHERE code = ? LIMIT 1');
        $stAny->execute([$code]);
        if ($stAny->fetch()) {
            respond(403, ['success' => false, 'message' => 'code_wrong_device']);
        }
        respond(404, ['success' => false, 'message' => 'code_not_found']);
    }

    $url = trim((string)($row['m3u_url'] ?? ''));
    if ($url === '' || strcasecmp($url, 'null') === 0) {
        respond(404, ['success' => false, 'message' => 'invalid_playlist']);
    }

    $codeId = (int)$row['id'];
    $boundDevice = trim((string)($row['bound_device_id'] ?? ''));
    $maxDev = isset($row['max_devices']) ? (int)$row['max_devices'] : 1;
    if ($boundDevice !== '') {
        $maxDev = 1;
    } elseif ($maxDev < 1) {
        $maxDev = 1;
    }

    $settings = getSettings($conn);
    $defaultDays = isset($settings['default_expiry_days']) ? (int)$settings['default_expiry_days'] : 30;
    if ($defaultDays <= 0) {
        $defaultDays = 30;
    }
    $accountKey = build_account_key_from_playlist_url($conn, $url);

    $conn->beginTransaction();

    $stExisting = $conn->prepare('SELECT id FROM playlist_code_devices WHERE code_id = ? AND device_id = ? LIMIT 1');
    $stExisting->execute([$codeId, $deviceId]);
    if ($stExisting->fetch()) {
        if ($deviceName !== '') {
            $updName = $conn->prepare('UPDATE playlist_code_devices SET device_label = ? WHERE code_id = ? AND device_id = ?');
            $updName->execute([$deviceName, $codeId, $deviceId]);
        }
        $upsertActivated = $conn->prepare(
            "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, custom_domain, account_key, device_name)
             VALUES (?, NOW(), DATE_ADD(NOW(), INTERVAL $defaultDays DAY), 'active', ?, ?, ?)
             ON DUPLICATE KEY UPDATE custom_domain = VALUES(custom_domain), account_key = VALUES(account_key), device_name = COALESCE(NULLIF(VALUES(device_name), ''), device_name)"
        );
        $upsertActivated->execute([
            $deviceId,
            $url,
            $accountKey !== '' ? $accountKey : null,
            $deviceName !== '' ? $deviceName : null,
        ]);
        $conn->commit();
        $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
        $resp = [
            'success' => true,
            'm3u_url' => $url,
            'name' => (string)($row['label'] ?? ''),
        ];
        if ($tokenOut !== '') {
            $resp['device_token'] = $tokenOut;
        }
        respond(200, $resp);
    }

    if ($boundDevice === '') {
        $stCount = $conn->prepare('SELECT COUNT(*) FROM playlist_code_devices WHERE code_id = ?');
        $stCount->execute([$codeId]);
        $n = (int)$stCount->fetchColumn();
        if ($n >= $maxDev) {
            $conn->rollBack();
            respond(403, ['success' => false, 'message' => 'code_max_devices', 'max_devices' => $maxDev]);
        }
    } elseif ($deviceId !== $boundDevice) {
        $conn->rollBack();
        respond(403, ['success' => false, 'message' => 'code_wrong_device']);
    }

    $ins = $conn->prepare('INSERT INTO playlist_code_devices (code_id, device_id, device_label) VALUES (?, ?, ?)');
    $ins->execute([$codeId, $deviceId, $deviceName !== '' ? $deviceName : null]);

    $upsertActivated = $conn->prepare(
        "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, custom_domain, account_key, device_name)
         VALUES (?, NOW(), DATE_ADD(NOW(), INTERVAL $defaultDays DAY), 'active', ?, ?, ?)
         ON DUPLICATE KEY UPDATE custom_domain = VALUES(custom_domain), account_key = VALUES(account_key), device_name = COALESCE(NULLIF(VALUES(device_name), ''), device_name)"
    );
    $upsertActivated->execute([
        $deviceId,
        $url,
        $accountKey !== '' ? $accountKey : null,
        $deviceName !== '' ? $deviceName : null,
    ]);

    $conn->commit();

    $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
    $resp = [
        'success' => true,
        'm3u_url' => $url,
        'name' => (string)($row['label'] ?? ''),
    ];
    if ($tokenOut !== '') {
        $resp['device_token'] = $tokenOut;
    }
    respond(200, $resp);
} catch (Throwable $e) {
    try {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
    } catch (Throwable $ignored) {
    }
    respond(500, ['success' => false, 'message' => 'server_error']);
}
