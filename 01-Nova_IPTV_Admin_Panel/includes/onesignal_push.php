<?php
/**
 * إرسال إشعارات Push عبر OneSignal REST API (من لوحة التحكم).
 */

if (!function_exists('onesignal_push_configured')) {
    function onesignal_push_configured(array $settings): bool
    {
        if (empty($settings['onesignal_enabled'])) {
            return false;
        }
        $appId = trim((string)($settings['onesignal_app_id'] ?? ''));
        $apiKey = trim((string)($settings['onesignal_rest_api_key'] ?? ''));
        return $appId !== '' && $apiKey !== '';
    }
}

if (!function_exists('onesignal_rest_api_key_configured')) {
    function onesignal_rest_api_key_configured(array $settings): bool
    {
        return trim((string)($settings['onesignal_rest_api_key'] ?? '')) !== '';
    }
}

if (!function_exists('onesignal_mask_api_key')) {
    function onesignal_mask_api_key(string $key): string
    {
        $key = trim($key);
        if ($key === '') {
            return '';
        }
        $len = strlen($key);
        if ($len <= 8) {
            return str_repeat('•', $len);
        }
        return str_repeat('•', max(12, $len - 4)) . substr($key, -4);
    }
}

if (!function_exists('onesignal_push_status')) {
    /**
     * @return array{enabled:bool,app_id:bool,api_key:bool,configured:bool}
     */
    function onesignal_push_status(array $settings): array
    {
        $enabled = !empty($settings['onesignal_enabled']);
        $appId = trim((string)($settings['onesignal_app_id'] ?? '')) !== '';
        $apiKey = onesignal_rest_api_key_configured($settings);
        return [
            'enabled' => $enabled,
            'app_id' => $appId,
            'api_key' => $apiKey,
            'configured' => $enabled && $appId && $apiKey,
        ];
    }
}

if (!function_exists('onesignal_push_missing_labels')) {
    function onesignal_push_missing_labels(array $settings, string $lang = 'ar'): array
    {
        $st = onesignal_push_status($settings);
        $out = [];
        if (!$st['enabled']) {
            $out[] = $lang === 'ar'
                ? 'فعّل «تفعيل إشعارات Push» في الإعدادات واحفظ التغييرات'
                : 'Enable “Enable push notifications” in Settings and save changes';
        }
        if (!$st['app_id']) {
            $out[] = $lang === 'ar'
                ? 'أدخل OneSignal App ID واحفظ التغييرات'
                : 'Enter the OneSignal App ID and save changes';
        }
        if (!$st['api_key']) {
            $out[] = $lang === 'ar'
                ? 'أدخل REST API Key واحفظ التغييرات'
                : 'Enter the REST API Key and save changes';
        }
        return $out;
    }
}

if (!function_exists('onesignal_save_settings_patch')) {
    function onesignal_save_settings_patch(PDO $conn, int $enabled, string $appId, string $apiKey): bool
    {
        $patch = [
            'onesignal_enabled' => $enabled ? 1 : 0,
            'onesignal_app_id' => trim($appId),
        ];
        if (trim($apiKey) !== '') {
            $patch['onesignal_rest_api_key'] = trim($apiKey);
        }
        return updateSettingsPartial($conn, $patch);
    }
}

if (!function_exists('onesignal_normalize_notification_url')) {
    /**
     * Normalize optional notification link (http/https only).
     */
    function onesignal_normalize_notification_url(string $raw): string
    {
        $raw = trim($raw);
        if ($raw === '') {
            return '';
        }
        if (!preg_match('#^https?://#i', $raw)) {
            $raw = 'https://' . ltrim($raw, '/');
        }
        if (strlen($raw) > 1200) {
            $raw = substr($raw, 0, 1200);
        }
        $parts = @parse_url($raw);
        if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
            return '';
        }
        $scheme = strtolower((string) $parts['scheme']);
        if ($scheme !== 'http' && $scheme !== 'https') {
            return '';
        }
        return $raw;
    }
}

if (!function_exists('onesignal_parse_schedule_local')) {
    /**
     * Parse datetime-local (server timezone). Must be ≥ ~2 minutes in the future.
     */
    function onesignal_parse_schedule_local(string $raw): ?DateTimeImmutable
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }
        $raw = str_replace(' ', 'T', $raw);
        $tz = new DateTimeZone(date_default_timezone_get());
        $dt = DateTimeImmutable::createFromFormat('Y-m-d\TH:i', $raw, $tz);
        if (!$dt) {
            $dt = DateTimeImmutable::createFromFormat('Y-m-d\TH:i:s', $raw, $tz);
        }
        if (!$dt) {
            try {
                $dt = new DateTimeImmutable($raw, $tz);
            } catch (Exception $e) {
                return null;
            }
        }
        if ($dt->getTimestamp() < (time() + 90)) {
            return null;
        }
        return $dt;
    }
}

if (!function_exists('onesignal_format_send_after')) {
    function onesignal_format_send_after(DateTimeImmutable $dt): string
    {
        // Example accepted by OneSignal: 2026-09-12 20:00:00 +0100
        return $dt->format('Y-m-d H:i:s O');
    }
}

if (!function_exists('onesignal_send_push')) {
    /**
     * @return array{ok:bool, id?:string, error?:string, http?:int, raw?:mixed, scheduled?:bool}
     */
    function onesignal_send_push(
        PDO $conn,
        string $title,
        string $message,
        ?string $deviceId = null,
        string $linkUrl = '',
        ?DateTimeImmutable $sendAfter = null
    ): array {
        $settings = getSettings($conn);
        if (!onesignal_push_configured($settings)) {
            return ['ok' => false, 'error' => 'not_configured'];
        }

        $title = trim($title);
        $message = trim($message);
        if ($title === '' || $message === '') {
            return ['ok' => false, 'error' => 'empty_fields'];
        }

        $appId = trim((string)$settings['onesignal_app_id']);
        $apiKey = trim((string)$settings['onesignal_rest_api_key']);
        $deviceId = $deviceId !== null ? trim($deviceId) : '';
        $linkUrl = onesignal_normalize_notification_url($linkUrl);

        $payload = [
            'app_id' => $appId,
            'headings' => ['en' => $title, 'ar' => $title],
            'contents' => ['en' => $message, 'ar' => $message],
            'target_channel' => 'push',
            'small_icon' => 'ic_stat_onesignal_default',
            'large_icon' => 'ic_onesignal_large_icon_default',
        ];

        if ($linkUrl !== '') {
            // data.url للتطبيق؛ url لفتح الرابط عند الضغط (موبايل/ويب).
            $payload['url'] = $linkUrl;
            $payload['data'] = ['url' => $linkUrl];
        }

        if ($sendAfter instanceof DateTimeImmutable) {
            $payload['send_after'] = onesignal_format_send_after($sendAfter);
        }

        // محاولات الاستهداف بالترتيب (الجديدة أولاً ثم التوافق مع الحسابات القديمة).
        $attempts = [];
        if ($deviceId !== '') {
            $attempts[] = [
                'include_external_user_ids' => [$deviceId],
                'channel_for_external_user_ids' => 'push',
            ];
            $attempts[] = [
                'include_aliases' => ['external_id' => [$deviceId]],
                'target_channel' => 'push',
            ];
        } else {
            // OneSignal الحالي: "Subscribed Users" — "All" قديم وقد يرجع 0 مستلمين.
            $attempts[] = [
                'included_segments' => ['Subscribed Users'],
                'target_channel' => 'push',
            ];
            $attempts[] = [
                'included_segments' => ['All'],
                'target_channel' => 'push',
            ];
        }

        $lastFail = ['ok' => false, 'error' => 'send_failed', 'http' => 0, 'raw' => null];
        foreach ($attempts as $target) {
            $tryPayload = array_merge($payload, $target);
            $result = onesignal_post_notification($apiKey, $tryPayload);
            if (!empty($result['ok'])) {
                $result['scheduled'] = $sendAfter instanceof DateTimeImmutable;
                return $result;
            }
            $lastFail = $result;
            $err = strtolower((string)($result['error'] ?? ''));
            // إن كان المفتاح/الإعدادات خاطئة لا نعيد المحاولة.
            if (strpos($err, 'http_401') !== false
                || strpos($err, 'http_403') !== false
                || strpos($err, 'not_configured') !== false
                || strpos($err, 'curl:') === 0) {
                break;
            }
        }

        if ($deviceId !== '') {
            $lastFail['error'] = 'device_not_subscribed';
        } elseif (($lastFail['error'] ?? '') === '' || ($lastFail['error'] ?? '') === 'empty_notification_id') {
            $lastFail['error'] = 'no_subscribed_users';
        }
        return $lastFail;
    }
}

if (!function_exists('onesignal_post_notification')) {
    /**
     * @param array<string,mixed> $payload
     * @return array{ok:bool, id?:string, error?:string, http?:int, raw?:mixed, recipients?:int|null}
     */
    function onesignal_post_notification(string $apiKey, array $payload): array
    {
        $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
        if ($json === false) {
            return ['ok' => false, 'error' => 'json_encode_failed'];
        }

        $responseBody = '';
        $httpCode = 0;

        if (function_exists('curl_init')) {
            $ch = curl_init('https://api.onesignal.com/notifications');
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $json,
                CURLOPT_HTTPHEADER => [
                    'Content-Type: application/json; charset=utf-8',
                    'Authorization: Key ' . $apiKey,
                ],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 25,
                CURLOPT_CONNECTTIMEOUT => 10,
            ]);
            $responseBody = (string)curl_exec($ch);
            $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            if ($responseBody === '' && curl_errno($ch)) {
                $err = curl_error($ch);
                curl_close($ch);
                return ['ok' => false, 'error' => 'curl:' . $err, 'http' => 0];
            }
            curl_close($ch);
        } else {
            $ctx = stream_context_create([
                'http' => [
                    'method' => 'POST',
                    'header' => "Content-Type: application/json; charset=utf-8\r\nAuthorization: Key {$apiKey}\r\n",
                    'content' => $json,
                    'timeout' => 25,
                    'ignore_errors' => true,
                ],
            ]);
            $responseBody = (string)@file_get_contents('https://api.onesignal.com/notifications', false, $ctx);
            if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
                $httpCode = (int)$m[1];
            }
        }

        $data = json_decode($responseBody, true);
        if ($httpCode < 200 || $httpCode >= 300) {
            $errMsg = '';
            if (is_array($data)) {
                if (isset($data['errors']) && is_array($data['errors'])) {
                    $first = $data['errors'][0] ?? null;
                    if (is_string($first)) {
                        $errMsg = trim($first);
                    } elseif (is_array($data['errors']) && isset($data['errors'][0]) === false) {
                        // associative errors object
                        $errMsg = trim((string) json_encode($data['errors'], JSON_UNESCAPED_UNICODE));
                    } elseif (is_array($first)) {
                        $errMsg = trim((string) json_encode($first, JSON_UNESCAPED_UNICODE));
                    }
                }
                if ($errMsg === '') {
                    $errMsg = trim((string)($data['error'] ?? ''));
                }
            }
            if ($errMsg === '') {
                $errMsg = 'http_' . $httpCode;
            }
            return ['ok' => false, 'error' => $errMsg, 'http' => $httpCode, 'raw' => $data];
        }

        $id = '';
        $recipients = null;
        if (is_array($data)) {
            $id = trim((string)($data['id'] ?? ''));
            if (isset($data['recipients'])) {
                $recipients = (int) $data['recipients'];
            }
            $hasInvalid = false;
            if (isset($data['errors']) && is_array($data['errors'])) {
                if (!empty($data['errors']['invalid_external_user_ids'])
                    || !empty($data['errors']['invalid_aliases'])
                    || (isset($data['errors'][0]) && is_string($data['errors'][0])
                        && stripos($data['errors'][0], 'not subscribed') !== false)) {
                    $hasInvalid = true;
                }
            }
            $isScheduled = !empty($payload['send_after']);
            if ($id === '' || $hasInvalid || (!$isScheduled && $recipients !== null && $recipients <= 0)) {
                $err = $hasInvalid ? 'no_valid_recipients' : 'empty_notification_id';
                if (!$isScheduled && $recipients !== null && $recipients <= 0) {
                    $err = 'no_subscribed_users';
                }
                if (isset($data['errors'][0]) && is_string($data['errors'][0])) {
                    $err = trim($data['errors'][0]);
                }
                return [
                    'ok' => false,
                    'error' => $err,
                    'http' => $httpCode,
                    'raw' => $data,
                    'recipients' => $recipients,
                ];
            }
        }

        return [
            'ok' => true,
            'id' => $id,
            'http' => $httpCode,
            'raw' => $data,
            'recipients' => $recipients,
        ];
    }
}

if (!function_exists('onesignal_cancel_notification')) {
    /**
     * Cancel a scheduled OneSignal notification by id.
     * @return array{ok:bool, error?:string, http?:int}
     */
    function onesignal_cancel_notification(PDO $conn, string $onesignalId): array
    {
        $onesignalId = trim($onesignalId);
        if ($onesignalId === '') {
            return ['ok' => false, 'error' => 'missing_id'];
        }
        $settings = getSettings($conn);
        if (!onesignal_push_configured($settings)) {
            return ['ok' => false, 'error' => 'not_configured'];
        }
        $appId = trim((string)$settings['onesignal_app_id']);
        $apiKey = trim((string)$settings['onesignal_rest_api_key']);
        $url = 'https://api.onesignal.com/notifications/' . rawurlencode($onesignalId)
            . '?app_id=' . rawurlencode($appId);

        $responseBody = '';
        $httpCode = 0;
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_CUSTOMREQUEST => 'DELETE',
                CURLOPT_HTTPHEADER => [
                    'Content-Type: application/json; charset=utf-8',
                    'Authorization: Key ' . $apiKey,
                ],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 20,
                CURLOPT_CONNECTTIMEOUT => 10,
            ]);
            $responseBody = (string)curl_exec($ch);
            $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
        } else {
            $ctx = stream_context_create([
                'http' => [
                    'method' => 'DELETE',
                    'header' => "Content-Type: application/json; charset=utf-8\r\nAuthorization: Key {$apiKey}\r\n",
                    'timeout' => 20,
                    'ignore_errors' => true,
                ],
            ]);
            $responseBody = (string)@file_get_contents($url, false, $ctx);
            if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
                $httpCode = (int)$m[1];
            }
        }

        $ok = $httpCode >= 200 && $httpCode < 300;
        if (!$ok) {
            $data = json_decode($responseBody, true);
            $errMsg = is_array($data) ? trim((string)($data['errors'][0] ?? $data['error'] ?? '')) : '';
            if ($errMsg === '') {
                $errMsg = 'http_' . $httpCode;
            }
            return ['ok' => false, 'error' => $errMsg, 'http' => $httpCode];
        }
        return ['ok' => true, 'http' => $httpCode];
    }
}

if (!function_exists('log_push_notification')) {
    function log_push_notification(
        PDO $conn,
        string $title,
        string $message,
        string $targetType,
        ?string $deviceId,
        bool $success,
        ?string $onesignalId = null,
        ?string $errorMessage = null,
        ?int $adminUserId = null,
        string $linkUrl = '',
        ?string $scheduledAt = null
    ): void {
        $linkUrl = onesignal_normalize_notification_url($linkUrl);
        $isScheduled = $scheduledAt !== null && trim($scheduledAt) !== '';
        if ($success) {
            $status = $isScheduled ? 'scheduled' : 'sent';
        } else {
            $status = 'failed';
        }
        $scheduledAtDb = $isScheduled ? date('Y-m-d H:i:s', strtotime($scheduledAt)) : null;
        if ($scheduledAtDb === false) {
            $scheduledAtDb = null;
        }

        try {
            $stmt = $conn->prepare(
                'INSERT INTO push_notifications_log
                    (title, message, link_url, target_type, device_id, status, onesignal_id, error_message, admin_user_id, scheduled_at, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'
            );
            $stmt->execute([
                $title,
                $message,
                $linkUrl !== '' ? $linkUrl : null,
                $targetType === 'device' ? 'device' : 'all',
                $deviceId !== null && trim($deviceId) !== '' ? trim($deviceId) : null,
                $status,
                $onesignalId !== null && $onesignalId !== '' ? $onesignalId : null,
                $errorMessage !== null && trim($errorMessage) !== '' ? trim($errorMessage) : null,
                $adminUserId !== null && $adminUserId > 0 ? $adminUserId : null,
                $scheduledAtDb,
            ]);
        } catch (PDOException $e) {
            // Fallback if new columns missing on older DBs mid-deploy
            try {
                $stmt = $conn->prepare(
                    'INSERT INTO push_notifications_log
                        (title, message, target_type, device_id, status, onesignal_id, error_message, admin_user_id, created_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())'
                );
                $stmt->execute([
                    $title,
                    $message,
                    $targetType === 'device' ? 'device' : 'all',
                    $deviceId !== null && trim($deviceId) !== '' ? trim($deviceId) : null,
                    in_array($status, ['sent', 'failed'], true) ? $status : ($success ? 'sent' : 'failed'),
                    $onesignalId !== null && $onesignalId !== '' ? $onesignalId : null,
                    $errorMessage !== null && trim($errorMessage) !== '' ? trim($errorMessage) : null,
                    $adminUserId !== null && $adminUserId > 0 ? $adminUserId : null,
                ]);
            } catch (PDOException $e2) {
                // لا نوقف الإرسال إن فشل السجل
            }
        }
    }
}

if (!function_exists('cancel_scheduled_push_notification')) {
    /**
     * Cancel a locally logged scheduled push (and on OneSignal when possible).
     * @return array{ok:bool, error?:string}
     */
    function cancel_scheduled_push_notification(PDO $conn, int $logId): array
    {
        if ($logId <= 0) {
            return ['ok' => false, 'error' => 'invalid_id'];
        }
        try {
            $st = $conn->prepare(
                "SELECT id, status, onesignal_id, scheduled_at
                 FROM push_notifications_log
                 WHERE id = ? LIMIT 1"
            );
            $st->execute([$logId]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                return ['ok' => false, 'error' => 'not_found'];
            }
            if (($row['status'] ?? '') !== 'scheduled') {
                return ['ok' => false, 'error' => 'not_scheduled'];
            }
            $osId = trim((string)($row['onesignal_id'] ?? ''));
            if ($osId !== '') {
                $cancel = onesignal_cancel_notification($conn, $osId);
                if (empty($cancel['ok'])) {
                    // If already delivered / gone, still mark cancelled locally when past due.
                    $err = (string)($cancel['error'] ?? 'cancel_failed');
                    $schedTs = !empty($row['scheduled_at']) ? strtotime((string)$row['scheduled_at']) : 0;
                    if ($schedTs > 0 && $schedTs <= time()) {
                        return ['ok' => false, 'error' => 'already_due'];
                    }
                    // Some OneSignal errors still allow local cancel if notification vanished.
                    if (stripos($err, 'not found') === false && stripos($err, '404') === false) {
                        return ['ok' => false, 'error' => $err];
                    }
                }
            }
            $upd = $conn->prepare(
                "UPDATE push_notifications_log
                 SET status = 'cancelled', error_message = NULL
                 WHERE id = ? AND status = 'scheduled'"
            );
            $upd->execute([$logId]);
            return ['ok' => true];
        } catch (PDOException $e) {
            return ['ok' => false, 'error' => 'db_error'];
        }
    }
}

if (!function_exists('get_recent_push_notifications')) {
    function get_recent_push_notifications(PDO $conn, int $limit = 50): array
    {
        $limit = max(1, min(200, $limit));
        try {
            $sql = 'SELECT l.*, u.username AS admin_username
                    FROM push_notifications_log l
                    LEFT JOIN admin_users u ON u.id = l.admin_user_id
                    ORDER BY l.id DESC
                    LIMIT ' . (int)$limit;
            $stmt = $conn->query($sql);
            return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        } catch (PDOException $e) {
            return [];
        }
    }
}

if (!function_exists('get_push_notifications_for_device')) {
    /**
     * إشعارات مرسلة للجهاز (الكل أو موجّهة لهذا device_id فقط) لعرضها داخل التطبيق.
     * لا تُرجع إشعارات موجّهة لأجهزة أخرى.
     * @param string|null $sinceIso اختياري: لا تُرجع ما قبل هذا الوقت (تثبيت التطبيق).
     * @return list<array{id:string,title:string,message:string,url:string,created_at:string}>
     */
    function get_push_notifications_for_device(
        PDO $conn,
        string $deviceId,
        int $limit = 40,
        ?string $sinceIso = null
    ): array {
        $deviceId = trim($deviceId);
        $limit = max(1, min(100, $limit));
        if ($deviceId === '') {
            return [];
        }

        $sinceTs = null;
        if ($sinceIso !== null && trim($sinceIso) !== '') {
            $parsed = strtotime(trim($sinceIso));
            if ($parsed !== false) {
                $sinceTs = $parsed;
            }
        }

        try {
            // فقط: all أو device المطابق — لا نرجع موجّه لجهاز آخر أبداً.
            $sql = "SELECT id, onesignal_id, title, message, link_url, created_at, scheduled_at, status, target_type, device_id
                    FROM push_notifications_log
                    WHERE status IN ('sent', 'scheduled')
                      AND (
                        target_type = 'all'
                        OR (target_type = 'device' AND device_id = ?)
                      )
                    ORDER BY id DESC
                    LIMIT " . (int)$limit;
            $st = $conn->prepare($sql);
            $st->execute([$deviceId]);
            $rows = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
            $out = [];
            $now = time();
            foreach ($rows as $row) {
                $targetType = (string)($row['target_type'] ?? '');
                $rowDevice = trim((string)($row['device_id'] ?? ''));
                // حراسة إضافية ضد بيانات قديمة/خاطئة.
                if ($targetType === 'device' && ($rowDevice === '' || $rowDevice !== $deviceId)) {
                    continue;
                }
                if ($targetType !== 'all' && $targetType !== 'device') {
                    continue;
                }

                $status = (string)($row['status'] ?? '');
                $created = trim((string)($row['created_at'] ?? ''));
                $scheduledAt = trim((string)($row['scheduled_at'] ?? ''));

                // المجدولة: لا نعرضها قبل موعدها؛ وقت الظهور = scheduled_at.
                $effectiveTs = $created !== '' ? strtotime($created) : false;
                if ($status === 'scheduled') {
                    $schedTs = $scheduledAt !== '' ? strtotime($scheduledAt) : false;
                    if ($schedTs === false || $schedTs > $now) {
                        continue;
                    }
                    $effectiveTs = $schedTs;
                    if ($created === '') {
                        $created = $scheduledAt;
                    }
                }

                if ($sinceTs !== null) {
                    if ($effectiveTs === false || $effectiveTs < $sinceTs) {
                        continue;
                    }
                }

                $osId = trim((string)($row['onesignal_id'] ?? ''));
                $localId = (int)($row['id'] ?? 0);
                $id = $osId !== '' ? $osId : ('panel_' . $localId);
                $out[] = [
                    'id' => $id,
                    'title' => (string)($row['title'] ?? ''),
                    'message' => (string)($row['message'] ?? ''),
                    'url' => trim((string)($row['link_url'] ?? '')),
                    'created_at' => $created !== '' ? $created : date('Y-m-d H:i:s', $effectiveTs ?: $now),
                ];
            }
            return $out;
        } catch (PDOException $e) {
            return [];
        }
    }
}

if (!function_exists('admin_list_devices_for_notifications')) {
    function admin_list_devices_for_notifications(PDO $conn, int $limit = 500): array
    {
        $limit = max(1, min(2000, $limit));
        try {
            syncExpiredStatus($conn);
            $sql = "SELECT device_id, device_name, status
                    FROM activated_devices
                    WHERE device_id IS NOT NULL AND TRIM(device_id) <> ''
                    ORDER BY last_seen_at DESC, id DESC
                    LIMIT " . (int)$limit;
            return $conn->query($sql)->fetchAll(PDO::FETCH_ASSOC) ?: [];
        } catch (PDOException $e) {
            return [];
        }
    }
}
