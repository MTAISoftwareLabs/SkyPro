<?php
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;

$deviceId = '';
$payload = [];
$hbWatchingType = null;
$hbWatchingTitle = null;
$hbWatchingStreamId = null;
$hbWatchingExtra = null;
$hbHasWatching = false;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    if (!is_array($data)) {
        $data = [];
    }
    $payload = $data;
    $deviceId = $data['device_id'] ?? '';
    $hbIptvExp = trim((string)($data['iptv_exp_date'] ?? ''));
    $hbDeviceName = trim((string)($data['device_name'] ?? ''));
    if (array_key_exists('watching_type', $data)
        || array_key_exists('watching_title', $data)
        || array_key_exists('watching_stream_id', $data)
        || array_key_exists('watching_extra', $data)
    ) {
        $hbHasWatching = true;
        $hbWatchingType = strtolower(trim((string)($data['watching_type'] ?? '')));
        $hbWatchingTitle = trim((string)($data['watching_title'] ?? ''));
        $hbWatchingStreamId = trim((string)($data['watching_stream_id'] ?? ''));
        $hbWatchingExtra = trim((string)($data['watching_extra'] ?? ''));
        if (!in_array($hbWatchingType, ['live', 'movie', 'series'], true)
            || $hbWatchingTitle === ''
        ) {
            $hbWatchingType = '';
            $hbWatchingTitle = '';
            $hbWatchingStreamId = '';
            $hbWatchingExtra = '';
        }
        if (function_exists('mb_substr')) {
            $hbWatchingTitle = mb_substr($hbWatchingTitle, 0, 255);
            $hbWatchingExtra = mb_substr($hbWatchingExtra, 0, 255);
            $hbWatchingStreamId = mb_substr($hbWatchingStreamId, 0, 64);
        } else {
            $hbWatchingTitle = substr($hbWatchingTitle, 0, 255);
            $hbWatchingExtra = substr($hbWatchingExtra, 0, 255);
            $hbWatchingStreamId = substr($hbWatchingStreamId, 0, 64);
        }
    }
    try {
        $hbAppVer = trim((string)($data['app_version'] ?? ''));
        if ($hbAppVer !== '') {
            maybeUpdateReportedAppVersion($conn, $hbAppVer);
        }
    } catch (Throwable $e) {
        // ignore
    }
} else {
    $deviceId = $_GET['device_id'] ?? '';
    $payload = [
        'device_id' => $deviceId,
        'mac_address' => $_GET['mac_address'] ?? '',
        'hardware_fingerprint' => $_GET['hardware_fingerprint'] ?? '',
    ];
    $hbIptvExp = '';
    $hbDeviceName = '';
}

$deviceId = trim((string)$deviceId);

if ($deviceId === '') {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Device ID is required',
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    $resolved = resolveActivatedDeviceFromPayload($conn, $payload, false);
    $deviceId = $resolved['device_id'];

    $settingsHb = getSettings($conn);
    // مزامنة التفعيل مع اشتراك IPTV إذا كانت مفعّلة من لوحة التحكم
    // لا تُطبَّق على أجهزة التجربة (trial) — وإلا يمكن تمديد التجربة بسيرفر طويل الصلاحية
    if (!empty($settingsHb['sync_activation_with_server']) && $hbIptvExp !== '') {
        $st = $conn->prepare("SELECT id, is_trial FROM activated_devices WHERE device_id = ? AND status = 'active' LIMIT 1");
        $st->execute([$deviceId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row && !deviceRowIsTrial($row)) {
            $newMysql = parse_iptv_expiry_to_mysql_datetime($hbIptvExp);
            if ($newMysql !== null) {
                $ts = strtotime($newMysql);
                $minTs = strtotime('2020-01-01');
                $maxTs = strtotime('+15 years');
                if ($ts !== false && $ts >= $minTs && $ts <= $maxTs) {
                    try {
                        $u = $conn->prepare("UPDATE activated_devices SET expiry_date = ? WHERE id = ? AND status = 'active' AND (is_trial IS NULL OR is_trial = 0)");
                        $u->execute([$newMysql, $row['id']]);
                    } catch (PDOException $e) {
                    }
                }
            }
        }
    }

    // تحديث آخر ظهور بغض النظر عن حالة التفعيل (نشط / منتهي / محظور)
    // حالة الاتصال في اللوحة = تواجد التطبيق، وليست حالة التفعيل
    if ($hbDeviceName !== '') {
        $stmt = $conn->prepare("UPDATE activated_devices SET last_seen_at = NOW(), device_name = ? WHERE device_id = ?");
        $stmt->execute([$hbDeviceName, $deviceId]);
    } else {
        $stmt = $conn->prepare("UPDATE activated_devices SET last_seen_at = NOW() WHERE device_id = ?");
        $stmt->execute([$deviceId]);
    }

    if ($hbHasWatching) {
        try {
            if ($hbWatchingType === '') {
                $w = $conn->prepare(
                    "UPDATE activated_devices
                     SET watching_type = NULL,
                         watching_title = NULL,
                         watching_stream_id = NULL,
                         watching_extra = NULL,
                         watching_updated_at = NOW()
                     WHERE device_id = ?"
                );
                $w->execute([$deviceId]);
            } else {
                $w = $conn->prepare(
                    "UPDATE activated_devices
                     SET watching_type = ?,
                         watching_title = ?,
                         watching_stream_id = ?,
                         watching_extra = ?,
                         watching_updated_at = NOW()
                     WHERE device_id = ?"
                );
                $w->execute([
                    $hbWatchingType,
                    $hbWatchingTitle,
                    $hbWatchingStreamId !== '' ? $hbWatchingStreamId : null,
                    $hbWatchingExtra !== '' ? $hbWatchingExtra : null,
                    $deviceId,
                ]);
            }
        } catch (PDOException $e) {
            // أعمدة قديمة قبل الترحيل — تجاهل
        }
    }

    $updated = $stmt->rowCount() > 0;

    echo json_encode([
        'success' => true,
        'online' => $updated,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database error',
    ], JSON_UNESCAPED_UNICODE);
}
