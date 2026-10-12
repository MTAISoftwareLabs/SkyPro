<?php
require_once '../includes/api_boot.php';
$raw = $app_api_raw_body;
$postData = app_api_json_payload($raw);
// App reports its installed version → keep settings.app_version in sync.
try {
    $reportedVer = app_api_field($postData, 'app_version');
    if ($reportedVer !== '') {
        maybeUpdateReportedAppVersion($conn, $reportedVer);
    }
} catch (Throwable $e) {
    // ignore version sync errors
}
try {
    $resolved = resolveActivatedDeviceFromPayload($conn, $postData, false);
} catch (Throwable $resolveErr) {
    error_log('[NovaAPI] resolve device failed: ' . $resolveErr->getMessage());
    $resolved = [
        'row' => null,
        'device_id' => app_api_field($postData, 'device_id'),
        'mac_address' => '',
        'hardware_fingerprint' => '',
    ];
}
$deviceId = $resolved['device_id'];
$deviceToken = app_api_field($postData, 'device_token');
$deviceName = app_api_field($postData, 'device_name');

if ($deviceId === '') {
    error_log('[NovaAPI] check-activation missing device_id bodyLen=' . strlen((string) $raw));
    app_emit_activation_json($conn, '', [
        'activated' => false,
        'message' => 'Device ID is required',
    ], 400);
}

$anyDevice = null;
try {
    $anyDevice = $resolved['row'] ?? findActivatedDeviceRow($conn, $deviceId);

    // أي فحص من التطبيق = تواجد، حتى لو كان محظوراً أو منتهياً
    if ($anyDevice) {
        try {
            $touch = $conn->prepare("UPDATE activated_devices SET last_seen_at = NOW() WHERE id = ?");
            $touch->execute([$anyDevice['id']]);
        } catch (PDOException $e) {
            // تجاهل
        }
        touchDeviceName($conn, $deviceId, $deviceName);
    }

    if ($anyDevice && ($anyDevice['status'] ?? '') === 'blocked') {
        $settings = getSettings($conn);
        $pub = app_panel_public_payload_for_device($settings, $anyDevice);
        app_emit_activation_json($conn, $deviceId, array_merge([
            'activated' => false,
            'status' => 'blocked',
            'message' => 'Device is blocked by admin panel',
            'expiry_date' => $anyDevice['expiry_date'] ?? null,
        ], $pub));
    }

    // حُذف من لوحة التحكم فقط → عند إعادة فتح التطبيق يُسجَّل كجهاز جديد بمدة الأيام الافتراضية
    if ($anyDevice && ($anyDevice['status'] ?? '') === 'deleted') {
        $settings = getSettings($conn);
        $pub = app_panel_public_payload_for_device($settings, $anyDevice);
        $days = isset($settings['default_expiry_days']) ? (int)$settings['default_expiry_days'] : 30;
        $device = rearmAdminDeletedDevice($conn, $deviceId, $days, $deviceName);
        if ($device) {
            try {
                logActivity(
                    $conn,
                    'auto_register',
                    $deviceId,
                    'Re-registered after admin delete with default expiry days'
                );
            } catch (Throwable $e) {
                // تجاهل
            }
            try {
                $touch = $conn->prepare("UPDATE activated_devices SET last_seen_at = NOW() WHERE id = ?");
                $touch->execute([$device['id']]);
            } catch (PDOException $e) {
                // تجاهل
            }
            $issuedToken = app_api_ensure_device_token_for_response($conn, $deviceId);
            $blockVpn = !empty($settings['block_vpn_global'])
                ? true
                : !empty($device['block_vpn']);
            $pub = app_panel_public_payload_for_device($settings, $device);
            $payload = array_merge([
                'activated' => true,
                'status' => 'active',
                'expiry_date' => $device['expiry_date'],
            'lifetime' => deviceExpiryIsLifetime($device['expiry_date'] ?? null),
                'trial' => true,
                'username' => 'user_' . substr($deviceId, 0, 8),
                'domain' => '',
                'has_playlist' => false,
                'ownership_ok' => $issuedToken !== '',
                'block_vpn' => $blockVpn,
                'web_playlists' => [],
                'auto_registered' => true,
                'reregistered_after_admin_delete' => true,
            ], $pub);
            if ($issuedToken !== '') {
                $payload['device_token'] = $issuedToken;
            }
            app_emit_activation_json($conn, $deviceId, $payload);
        }
        app_emit_activation_json($conn, $deviceId, array_merge([
            'activated' => false,
            'status' => 'inactive',
            'message' => 'Device is not activated',
        ], $pub));
    }

    $expiryOk = $anyDevice
        ? deviceExpiryIsInFuture($conn, (int) ($anyDevice['id'] ?? 0), $anyDevice['expiry_date'] ?? null)
        : false;

    if ($anyDevice && !$expiryOk) {
        $stNow = strtolower(trim((string) ($anyDevice['status'] ?? '')));
        if ($stNow === 'active') {
            try {
                $u = $conn->prepare("UPDATE activated_devices SET status = 'expired' WHERE id = ?");
                $u->execute([$anyDevice['id']]);
            } catch (PDOException $e) {
                // تجاهل
            }
        }
        $settings = getSettings($conn);
        $pub = app_panel_public_payload_for_device($settings, $anyDevice);
        app_emit_activation_json($conn, $deviceId, array_merge([
            'activated' => false,
            'status' => 'expired',
            'message' => 'Device activation has expired',
            'expiry_date' => $anyDevice['expiry_date'] ?? null,
        ], $pub));
    }

    // صلاحية سارية: اعتبر الجهاز مفعّلاً حتى لو بقي status=expired بعد إعادة التفعيل من اللوحة/الموقع
    $device = null;
    if ($anyDevice && $expiryOk) {
        $stNow = strtolower(trim((string) ($anyDevice['status'] ?? '')));
        if ($stNow !== 'active' && $stNow !== 'blocked' && $stNow !== 'deleted') {
            try {
                $heal = $conn->prepare(
                    "UPDATE activated_devices SET status = 'active' WHERE id = ? AND status <> 'blocked' AND status <> 'deleted'"
                );
                $heal->execute([(int) $anyDevice['id']]);
                $anyDevice['status'] = 'active';
            } catch (PDOException $e) {
                // تجاهل
            }
        }
        $device = $anyDevice;
    }
    
    if ($device) {
        // تحديث آخر ظهور للجهاز عند كل فحص ناجح
        try {
            $update = $conn->prepare("UPDATE activated_devices SET last_seen_at = NOW() WHERE id = ?");
            $update->execute([$device['id']]);
        } catch (PDOException $e) {
            // تجاهل الخطأ في حال فشل التحديث حتى لا يؤثر على عملية التفعيل
        }

        $settings = getSettings($conn);

        // مزامنة تاريخ التفعيل مع اشتراك IPTV (عند تفعيل الخيار من لوحة التحكم)
        // أجهزة التجربة (trial) مستثناة — التجربة للتجربة فقط ولا تُمدَّد بانتهاء السيرفر
        if (!empty($settings['sync_activation_with_server']) && !deviceRowIsTrial($device)) {
            $iptvRaw = trim((string)($postData['iptv_exp_date'] ?? ''));
            if ($iptvRaw !== '') {
                $newMysql = parse_iptv_expiry_to_mysql_datetime($iptvRaw);
                if ($newMysql !== null) {
                    $ts = strtotime($newMysql);
                    $minTs = strtotime('2020-01-01');
                    $maxTs = strtotime('+15 years');
                    if ($ts !== false && $ts >= $minTs && $ts <= $maxTs) {
                        try {
                            $u = $conn->prepare("UPDATE activated_devices SET expiry_date = ? WHERE id = ? AND status = 'active' AND (is_trial IS NULL OR is_trial = 0)");
                            $u->execute([$newMysql, $device['id']]);
                            $device['expiry_date'] = $newMysql;
                        } catch (PDOException $e) {
                            // تجاهل
                        }
                    }
                }
            }
        }

        $customDomain = $device['custom_domain'] ?? null;
        $rawPlaylist = ($customDomain !== null && trim((string)$customDomain) !== '')
            ? trim((string)$customDomain)
            : '';
        $hasPlaylist = $rawPlaylist !== '';

        // Ownership: only the device holding device_token may receive playlist credentials.
        $storedHash = app_api_device_token_hash($conn, $deviceId);
        $ownsDevice = app_api_verify_device_ownership($conn, $deviceId, $deviceToken);
        $issuedToken = '';
        $domain = '';

        if ($hasPlaylist) {
            if ($ownsDevice) {
                $domain = $rawPlaylist;
            } elseif ($storedHash === '') {
                // Legacy device with no token yet: issue one (HMAC already verified)
                // and return playlist once so the app can persist ownership.
                $issuedToken = app_api_issue_device_token($conn, $deviceId);
                if ($issuedToken !== '') {
                    $domain = $rawPlaylist;
                    $ownsDevice = true;
                }
            }
            // else: token required but missing/wrong → omit credentials
        } elseif ($storedHash === '') {
            $issuedToken = app_api_ensure_device_token_for_response($conn, $deviceId);
        }

        // إذا الميزة العامة مفعلة → منع VPN للجميع. إذا معطلة → استخدام إعداد الجهاز فقط (لمستخدم معين)
        $blockVpn = !empty($settings['block_vpn_global']) ? true : !empty($device['block_vpn']);
        try {
            logActivity($conn, 'check_activation', $deviceId, 'Successful activation check');
        } catch (Throwable $e) {
            // سجل النشاط لا يجب أن يُسقط فحص التفعيل
        }

        $pub = app_panel_public_payload_for_device($settings, $device);

        // قوائم Manage Playlist لهذا الجهاز → تُزامَن إلى Manage Accounts في التطبيق
        $webPlaylists = [];
        try {
            $wq = $conn->prepare(
                'SELECT id, name, m3u_url, updated_at
                 FROM device_web_playlists
                 WHERE device_id = ?
                    OR LOWER(TRIM(device_id)) = LOWER(TRIM(?))
                 ORDER BY id ASC'
            );
            $wq->execute([$deviceId, $deviceId]);
            foreach ($wq->fetchAll(PDO::FETCH_ASSOC) ?: [] as $wrow) {
                $webPlaylists[] = [
                    'id' => (int)($wrow['id'] ?? 0),
                    'name' => (string)($wrow['name'] ?? ''),
                    'm3u_url' => (string)($wrow['m3u_url'] ?? ''),
                    'updated_at' => (string)($wrow['updated_at'] ?? ''),
                ];
            }
        } catch (PDOException $e) {
            $webPlaylists = [];
        }

        $payload = array_merge([
            'activated' => true,
            'status' => 'active',
            'expiry_date' => $device['expiry_date'],
            'lifetime' => deviceExpiryIsLifetime($device['expiry_date'] ?? null),
            'trial' => deviceRowIsTrial($device),
            'username' => 'user_' . substr($deviceId, 0, 8),
            // Full playlist URL only when ownership is proven; never leak to enumerators.
            'domain' => $domain,
            'has_playlist' => $hasPlaylist,
            'ownership_ok' => $ownsDevice || ($issuedToken !== ''),
            'block_vpn' => $blockVpn,
            'web_playlists' => $webPlaylists,
        ], $pub);
        if ($issuedToken !== '') {
            $payload['device_token'] = $issuedToken;
        }
        app_emit_activation_json($conn, $deviceId, $payload);
    }

    // جهاز غير موجود — رد JSON صريح (التطبيق قد يسجّله تلقائياً)
    $settings = getSettings($conn);
    $pub = app_panel_public_payload_for_device($settings, null);
    app_emit_activation_json($conn, $deviceId, array_merge([
        'activated' => false,
        'status' => 'inactive',
        'message' => 'Device is not activated',
    ], $pub));
} catch (Throwable $e) {
    error_log('[NovaAPI] check-activation error: ' . $e->getMessage());
    $settings = [];
    try {
        $settings = getSettings($conn);
    } catch (Throwable $ignored) {
        $settings = [];
    }
    if (!is_array($settings)) {
        $settings = [];
    }
    $pub = app_panel_public_payload_for_device($settings, $anyDevice ?? null);
    $status = strtolower(trim((string)($anyDevice['status'] ?? '')));
    $expiry = $anyDevice['expiry_date'] ?? null;
    $stillActive = $anyDevice
        && $status === 'active'
        && (empty($expiry) || strtotime((string)$expiry) > time());
    app_emit_activation_json($conn, $deviceId, array_merge([
        'activated' => (bool)$stillActive,
        'status' => $stillActive ? 'active' : 'inactive',
        'expiry_date' => $expiry,
        'message' => $stillActive ? 'ok' : 'Database error',
    ], $pub));
}
