<?php
require_once '../includes/api_boot.php';
require_once '../includes/credential_crypto.php';
$raw = $app_api_raw_body;

$deviceId = '';
$username = '';
$password = '';
$serverHost = '';
$displayName = '';
$data = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $username = isset($data['username']) ? trim((string)$data['username']) : '';
    $password = isset($data['password']) ? trim((string)$data['password']) : '';
    $serverHost = isset($data['server_host']) ? trim((string)$data['server_host']) : '';
    $displayName = isset($data['display_name']) ? trim((string)$data['display_name']) : '';
}

if ($deviceId === '' || $username === '' || $password === '') {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'device_id, username and password are required',
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

if (!credential_is_configured($conn)) {
    http_response_code(503);
    echo json_encode([
        'success' => false,
        'message' => 'credential_enc_key_not_configured',
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    $resolved = resolveActivatedDeviceFromPayload($conn, $data, false);
    $deviceId = $resolved['device_id'];
    $mac = $resolved['mac_address'];
    $hardwareFingerprint = $resolved['hardware_fingerprint'];

    $settings = getSettings($conn);
    $maxDevices = isset($settings['max_devices_per_user']) ? (int)$settings['max_devices_per_user'] : 1;
    if ($maxDevices <= 0) $maxDevices = 1;

    $accountKey = build_account_key($conn, $username, $password);
    // Legacy plaintext account_key (username:password) — still match for existing rows.
    $legacyAccountKey = $username . ':' . $password;

    // حساب تاريخ الانتهاء الافتراضي (نفس منطق التفعيل التلقائي)
    $days = isset($settings['default_expiry_days']) ? (int)$settings['default_expiry_days'] : 30;
    if ($days <= 0) {
        $days = 30;
    }
    $now = new DateTime();
    $expiry = clone $now;
    $expiry->modify('+' . $days . ' days');
    $expiryStr = $expiry->format('Y-m-d H:i:s');

    // جلب الجهاز الحالي لمعرفة هل هو نفس الحساب أم لا
    $currStmt = $conn->prepare("SELECT account_key FROM activated_devices WHERE device_id = ? LIMIT 1");
    $currStmt->execute([$deviceId]);
    $current = $currStmt->fetch(PDO::FETCH_ASSOC);
    $currentKey = $current ? trim((string)($current['account_key'] ?? '')) : '';

    $sameAccount = ($currentKey !== '' && ($currentKey === $accountKey || $currentKey === $legacyAccountKey));

    // عدّ جميع الأجهزة المرتبطة بنفس الحساب (صيغة جديدة + قديمة) باستثناء هذا الجهاز
    $countStmt = $conn->prepare(
        "SELECT COUNT(*) FROM activated_devices
         WHERE (account_key = ? OR account_key = ?)
           AND device_id <> ?"
    );
    $countStmt->execute([$accountKey, $legacyAccountKey, $deviceId]);
    $activeForAccount = (int)$countStmt->fetchColumn();

    // إذا تجاوز الحد ولم يكن هذا الجهاز مرتبطاً بالفعل بنفس الحساب → منع
    if ($activeForAccount >= $maxDevices && !$sameAccount) {
        http_response_code(409);
        echo json_encode([
            'success' => false,
            'message' => 'Max devices reached for this account',
            'max_devices' => $maxDevices,
            'active_devices' => $activeForAccount,
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if (strlen($serverHost) > 500) {
        $serverHost = substr($serverHost, 0, 500);
    }
    $manUser = $username;
    $probeEnc = credential_encrypt_password_for_storage($conn, $password);
    if ($probeEnc === '' && $password !== '') {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'message' => 'credential_encryption_failed',
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }
    if (strlen($manUser) > 255) {
        $manUser = substr($manUser, 0, 255);
    }
    if (strlen($displayName) > 255) {
        $displayName = substr($displayName, 0, 255);
    }

    $hostForSession = $serverHost;
    if ($hostForSession === '' && $username !== '') {
        $hostForSession = '';
    }

    // إنشاء صف للجهاز إذا لم يكن موجوداً، أو تحديث account_key / expiry
    $stmt = $conn->prepare(
        "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, account_key, account_display_name)
         VALUES (?, NOW(), ?, 'active', ?, ?)
         ON DUPLICATE KEY UPDATE
           account_key = VALUES(account_key),
           account_display_name = COALESCE(VALUES(account_display_name), account_display_name)"
    );
    $stmt->execute([$deviceId, $expiryStr, $accountKey, $displayName !== '' ? $displayName : null]);

    persistActivatedDeviceBindingKeys($conn, $deviceId, $mac, $hardwareFingerprint);

    record_device_login_session(
        $conn,
        $deviceId,
        $hostForSession,
        $manUser,
        $password,
        $accountKey,
        $displayName,
        true,
        'app'
    );

    if ($stmt->rowCount() > 0) {
        logActivity($conn, 'bind_account', $deviceId, 'Account key bound from app login');
    }

    $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
    $okPayload = [
        'success' => true,
        'message' => 'Account bound',
        'max_devices' => $maxDevices,
    ];
    if ($tokenOut !== '') {
        $okPayload['device_token'] = $tokenOut;
    }
    echo json_encode($okPayload, JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database error',
    ], JSON_UNESCAPED_UNICODE);
}
