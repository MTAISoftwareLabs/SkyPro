<?php
require_once '../includes/api_boot.php';
require_once '../includes/credential_crypto.php';
$raw = $app_api_raw_body;

$deviceId = '';
$playlistUrl = '';
$data = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    $deviceId = isset($data['device_id']) ? trim((string)$data['device_id']) : '';
    $playlistUrl = isset($data['playlist_url']) ? trim((string)$data['playlist_url']) : '';
}

if (!credential_is_configured($conn)) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'credential_enc_key_not_configured'], JSON_UNESCAPED_UNICODE);
    exit();
}

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

if ($playlistUrl === '' || (stripos($playlistUrl, 'http://') !== 0 && stripos($playlistUrl, 'https://') !== 0)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Valid playlist URL is required'], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    // ربط جهاز بعيد عبر QR: ثبّت device_id الهدف فقط.
    // لا تُحلّ عبر MAC/بصمة الجهاز الماسح وإلا يُحفظ الرابط على الجهاز الخطأ.
    $linkRemote = !empty($data['link_remote'])
        || $data['link_remote'] === 1
        || $data['link_remote'] === '1'
        || $data['link_remote'] === true
        || $data['link_remote'] === 'true';

    $mac = '';
    $hardwareFingerprint = '';
    if ($linkRemote) {
        $deviceId = isset($data['device_id']) ? trim((string) $data['device_id']) : '';
        if ($deviceId === '') {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Device ID is required'], JSON_UNESCAPED_UNICODE);
            exit();
        }
    } else {
        $resolved = resolveActivatedDeviceFromPayload($conn, $data, false);
        $deviceId = $resolved['device_id'];
        $mac = $resolved['mac_address'];
        $hardwareFingerprint = $resolved['hardware_fingerprint'];
    }

    // بصمة حساب بدون تخزين كلمة المرور كنص واضح في account_key
    $accountKey = build_account_key_from_playlist_url($conn, $playlistUrl);
    $legacyAccountKey = '';
    try {
        $u = parse_url($playlistUrl);
        $qs = [];
        if (!empty($u['query'])) {
            parse_str($u['query'], $qs);
        }
        $user = isset($qs['username']) ? trim((string)$qs['username']) : '';
        $pass = isset($qs['password']) ? trim((string)$qs['password']) : '';
        if ($user !== '' && $pass !== '') {
            $legacyAccountKey = $user . ':' . $pass;
        }
    } catch (Throwable $e) {
        $legacyAccountKey = '';
    }

    // جلب إعدادات الحد الأقصى
    $settings = getSettings($conn);
    $maxDevices = isset($settings['max_devices_per_user']) ? (int)$settings['max_devices_per_user'] : 1;
    if ($maxDevices <= 0) $maxDevices = 1;

    // جلب الجهاز الحالي لمعرفة إن كان نفس الحساب أو تغيير حساب
    $currStmt = $conn->prepare("SELECT id, account_key FROM activated_devices WHERE device_id = ? LIMIT 1");
    $currStmt->execute([$deviceId]);
    $current = $currStmt->fetch(PDO::FETCH_ASSOC);
    $currentKey = $current ? trim((string)($current['account_key'] ?? '')) : '';
    $newKey = trim((string)$accountKey);
    $sameAccount = ($currentKey !== '' && (
        $currentKey === $newKey
        || ($legacyAccountKey !== '' && $currentKey === $legacyAccountKey)
    ));

    // إذا كان هناك حد أقصى: نعد جميع الأجهزة لنفس الحساب (بغضّ النظر عن حالة الانتهاء)
    // ويسمح دائماً بتحديث نفس الجهاز حتى لو وصل الحد (لا نعده كجهاز جديد)
    if ($newKey !== '') {
        if ($legacyAccountKey !== '') {
            $countStmt = $conn->prepare(
                "SELECT COUNT(*) FROM activated_devices
                 WHERE (account_key = ? OR account_key = ?)
                   AND device_id <> ?
                   AND (device_id NOT LIKE 'line_%')
                   AND (status = 'active' OR status IS NULL)
                   AND (expiry_date IS NULL OR expiry_date > NOW())"
            );
            $countStmt->execute([$newKey, $legacyAccountKey, $deviceId]);
        } else {
            $countStmt = $conn->prepare(
                "SELECT COUNT(*) FROM activated_devices
                 WHERE account_key = ?
                   AND device_id <> ?
                   AND (device_id NOT LIKE 'line_%')
                   AND (status = 'active' OR status IS NULL)
                   AND (expiry_date IS NULL OR expiry_date > NOW())"
            );
            $countStmt->execute([$newKey, $deviceId]);
        }
        $activeForAccount = (int)$countStmt->fetchColumn();
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
    }

    // قراءة عدد أيام الانتهاء الافتراضية من الإعدادات
    $defaultDays = isset($settings['default_expiry_days']) ? (int)$settings['default_expiry_days'] : 30;
    if ($defaultDays <= 0) {
        $defaultDays = 30;
    }

    // محظور / منتهي: لا ربط playlist ولا إعادة تفعيل عبر QR.
    $currFullStmt = $conn->prepare(
        "SELECT id, account_key, status, expiry_date FROM activated_devices WHERE device_id = ? LIMIT 1"
    );
    $currFullStmt->execute([$deviceId]);
    $currentFull = $currFullStmt->fetch(PDO::FETCH_ASSOC);
    if ($currentFull) {
        $stNow = strtolower(trim((string) ($currentFull['status'] ?? '')));
        $expiredByDate = false;
        try {
            $expOk = deviceExpiryIsInFuture(
                $conn,
                (int) ($currentFull['id'] ?? 0),
                $currentFull['expiry_date'] ?? null
            );
            $expiredByDate = !$expOk;
        } catch (Throwable $e) {
            $expiredByDate = false;
        }
        if ($stNow === 'blocked') {
            http_response_code(403);
            echo json_encode([
                'success' => false,
                'message' => 'Device is blocked',
                'status' => 'blocked',
            ], JSON_UNESCAPED_UNICODE);
            exit();
        }
        if ($stNow === 'expired' || $expiredByDate) {
            http_response_code(403);
            echo json_encode([
                'success' => false,
                'message' => 'Device activation has expired',
                'status' => 'expired',
            ], JSON_UNESCAPED_UNICODE);
            exit();
        }
    }

    // إنشاء صف جديد للجهاز إن لم يكن موجوداً، أو تحديث الرابط والحساب إن كان موجوداً.
    // لا نغيّر status/expiry هنا لإعادة تفعيل منتهٍ أو محظور — ممنوع أعلاه.
    $stmt = $conn->prepare(
        "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, custom_domain, account_key)
         VALUES (?, NOW(), DATE_ADD(NOW(), INTERVAL $defaultDays DAY), 'active', ?, ?)
         ON DUPLICATE KEY UPDATE
           custom_domain = VALUES(custom_domain),
           account_key = VALUES(account_key)"
    );
    $stmt->execute([$deviceId, $playlistUrl, $newKey]);

    if ($linkRemote) {
        // امسح token قديم خاطئ (مثلاً أُصدر للماسح سابقاً) حتى يدّعي الهدف الملكية في check-activation.
        try {
            $clr = $conn->prepare(
                'UPDATE activated_devices SET device_api_token_hash = NULL WHERE device_id = ?'
            );
            $clr->execute([$deviceId]);
        } catch (PDOException $e) {
            // العمود قد لا يوجد في نسخ قديمة
        }
    } else {
        persistActivatedDeviceBindingKeys($conn, $deviceId, $mac, $hardwareFingerprint);
    }

    logActivity(
        $conn,
        'edit_device',
        $deviceId,
        $linkRemote ? 'Playlist URL linked from another device (QR)' : 'Playlist URL saved from app'
    );

    $ok = ['success' => true, 'message' => 'Playlist saved'];
    // لا تُصدر device_token للماسح عند الربط عن بُعد — الهدف يأخذه عند فحصه.
    if (!$linkRemote) {
        $tokenOut = app_api_ensure_device_token_for_response($conn, $deviceId);
        if ($tokenOut !== '') {
            $ok['device_token'] = $tokenOut;
        }
    }
    echo json_encode($ok, JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error'], JSON_UNESCAPED_UNICODE);
}
