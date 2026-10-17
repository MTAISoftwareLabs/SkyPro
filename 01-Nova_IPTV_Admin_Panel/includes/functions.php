<?php
/**
 * تطبيع قائمة package names: إزالة الأسطر الفارغة والمسافات الزائدة.
 */
function normalizePiracyPackagesText($raw) {
    if ($raw === null || $raw === '') {
        return '';
    }
    $lines = preg_split('/\r\n|\r|\n/', (string) $raw);
    $out = [];
    foreach ($lines as $line) {
        $t = trim($line);
        if ($t !== '') {
            $out[] = $t;
        }
    }
    return implode("\n", $out);
}

function normalizeHomeTheme($raw): string
{
    $allowed = ['original', 'netflix_red', 'ramadan_gold', 'sports_sky', 'halloween_orange'];
    $t = strtolower(trim((string) $raw));
    return in_array($t, $allowed, true) ? $t : 'original';
}

/**
 * تحديث حالة الأجهزة المنتهية صلاحيتها تلقائياً في قاعدة البيانات.
 * أي جهاز status = 'active' وتاريخ expiry_date قد انتهى يُحدَّث إلى 'expired'.
 */
function syncExpiredStatus($conn) {
    try {
        $stmt = $conn->prepare("UPDATE activated_devices SET status = 'expired' WHERE status = 'active' AND expiry_date < NOW()");
        $stmt->execute();
    } catch (PDOException $e) {
        // تجاهل الخطأ لعدم التأثير على عرض الصفحة
    }
}

/**
 * تحويل تاريخ انتهاء Xtream (Unix أو نص) إلى صيغة MySQL DATETIME لتحديث التفعيل.
 */
function parse_iptv_expiry_to_mysql_datetime(?string $raw): ?string {
    if ($raw === null) {
        return null;
    }
    $raw = trim($raw);
    if ($raw === '' || strcasecmp($raw, 'null') === 0 || $raw === '0') {
        return null;
    }
    if (ctype_digit($raw)) {
        $ts = (int) $raw;
        if ($ts < 1000000000) {
            return null;
        }
        return date('Y-m-d H:i:s', $ts);
    }
    $ts = strtotime($raw);
    if ($ts === false) {
        return null;
    }
    return date('Y-m-d H:i:s', $ts);
}

/**
 * Return array of admin_user IDs whose customers the logged-in user is authorized to see/manage.
 * - Super admin: returns null (global access to all customers)
 * - Supervisor (Staff/Admin/Moderator): returns [$myId, ...resellerIdsCreatedByThisSupervisor]
 *   (Can see and manage their own customers PLUS all customers created by the Resellers they registered)
 * - Reseller: returns [$myId] (strictly only their own customers)
 * - Guest/unauthenticated: returns []
 */
function adminGetAllowedCustomerCreatorIds(PDO $conn): ?array
{
    if (empty($_SESSION['admin_user_id'])) {
        return [];
    }
    if (function_exists('adminIsSuperAdmin') && adminIsSuperAdmin()) {
        return null; // Global access
    }

    $myId = (int)$_SESSION['admin_user_id'];
    $isSupervisor = function_exists('adminIsSubAdminRole') && adminIsSubAdminRole();

    if ($isSupervisor) {
        $ids = [$myId];
        try {
            // Include all resellers registered by this supervisor
            $stmt = $conn->prepare("SELECT id FROM admin_users WHERE (created_by = ? OR created_by = ?) AND role = 'reseller'");
            $myUsername = !empty($_SESSION['admin_username']) ? trim((string)$_SESSION['admin_username']) : '';
            $stmt->execute([$myId, $myUsername]);
            $resellerIds = $stmt->fetchAll(PDO::FETCH_COLUMN);
            if (!empty($resellerIds)) {
                foreach ($resellerIds as $rid) {
                    $ridInt = (int)$rid;
                    if ($ridInt > 0 && !in_array($ridInt, $ids, true)) {
                        $ids[] = $ridInt;
                    }
                }
            }
        } catch (Throwable $e) {}
        return $ids;
    }

    // Default (e.g. Reseller): strictly their own customers
    return [$myId];
}

/** أجهزة نشطة تنتهي خلال N يوماً (تنبيه للأدمن). */
function getExpiringSoonDevicesCount(PDO $conn, int $withinDays = 7): int {
    if ($withinDays < 1) {
        $withinDays = 7;
    }
    syncExpiredStatus($conn);
    try {
        $allowedCreatorIds = adminGetAllowedCustomerCreatorIds($conn);

        if ($allowedCreatorIds !== null) {
            if (empty($allowedCreatorIds)) {
                return 0;
            }
            $placeholders = implode(',', array_fill(0, count($allowedCreatorIds), '?'));
            $sql = "SELECT COUNT(DISTINCT a.id) FROM activated_devices a
                    INNER JOIN iptv_customers c ON (
                        c.username = a.manual_login_username 
                        OR c.username = a.account_display_name 
                        OR a.account_key LIKE CONCAT(c.username, '#%') 
                        OR a.account_key = c.username
                    )
                    WHERE a.status = 'active' 
                    AND a.expiry_date > NOW() 
                    AND a.expiry_date <= DATE_ADD(NOW(), INTERVAL ? DAY)
                    AND c.created_by IN ($placeholders)";
            $params = array_merge([$withinDays], array_map('intval', $allowedCreatorIds));
            $stmt = $conn->prepare($sql);
            $stmt->execute($params);
            return (int) $stmt->fetchColumn();
        }

        $sql = "SELECT COUNT(*) FROM activated_devices 
                WHERE status = 'active' 
                AND expiry_date > NOW() 
                AND expiry_date <= DATE_ADD(NOW(), INTERVAL ? DAY)";
        $stmt = $conn->prepare($sql);
        $stmt->execute([$withinDays]);
        return (int) $stmt->fetchColumn();
    } catch (PDOException $e) {
        return 0;
    }
}

/** قائمة الأجهزة القريبة من الانتهاء (للعرض في اللوحة). */
function getExpiringSoonDevices(PDO $conn, int $withinDays = 7, int $limit = 50): array {
    if ($withinDays < 1) {
        $withinDays = 7;
    }
    syncExpiredStatus($conn);
    try {
        $allowedCreatorIds = adminGetAllowedCustomerCreatorIds($conn);

        if ($allowedCreatorIds !== null) {
            if (empty($allowedCreatorIds)) {
                return [];
            }
            $placeholders = implode(',', array_fill(0, count($allowedCreatorIds), '?'));
            $sql = "SELECT DISTINCT a.id, a.device_id, a.device_name, a.expiry_date, a.last_seen_at 
                    FROM activated_devices a
                    INNER JOIN iptv_customers c ON (
                        c.username = a.manual_login_username 
                        OR c.username = a.account_display_name 
                        OR a.account_key LIKE CONCAT(c.username, '#%') 
                        OR a.account_key = c.username
                    )
                    WHERE a.status = 'active' 
                    AND a.expiry_date > NOW() 
                    AND a.expiry_date <= DATE_ADD(NOW(), INTERVAL ? DAY)
                    AND c.created_by IN ($placeholders)
                    ORDER BY a.expiry_date ASC
                    LIMIT " . (int) $limit;
            $params = array_merge([$withinDays], array_map('intval', $allowedCreatorIds));
            $stmt = $conn->prepare($sql);
            $stmt->execute($params);
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

        $sql = "SELECT id, device_id, device_name, expiry_date, last_seen_at 
                FROM activated_devices 
                WHERE status = 'active' 
                AND expiry_date > NOW() 
                AND expiry_date <= DATE_ADD(NOW(), INTERVAL ? DAY)
                ORDER BY expiry_date ASC
                LIMIT " . (int) $limit;
        $stmt = $conn->prepare($sql);
        $stmt->execute([$withinDays]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $e) {
        return [];
    }
}

// جلب قائمة الأجهزة المفعلة (مع مزامنة حالة الانتهاء تلقائياً ودعم البحث باسم المستخدم)
function getActivatedDevices($conn, $search = '') {
    syncExpiredStatus($conn);
    $search = trim((string)$search);
    $allowedCreatorIds = adminGetAllowedCustomerCreatorIds($conn);

    if ($allowedCreatorIds !== null) {
        if (empty($allowedCreatorIds)) {
            return [];
        }
        $placeholders = implode(',', array_fill(0, count($allowedCreatorIds), '?'));
        if ($search !== '') {
            $like = '%' . $search . '%';
            $stmt = $conn->prepare("SELECT a.*,
                (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
                FROM activated_devices a
                INNER JOIN iptv_customers c ON (
                    c.username = a.manual_login_username 
                    OR c.username = a.account_display_name 
                    OR a.account_key LIKE CONCAT(c.username, '#%') 
                    OR a.account_key = c.username
                )
                WHERE (a.status IS NULL OR a.status <> 'deleted')
                  AND c.created_by IN ($placeholders)
                  AND (
                      a.account_display_name LIKE ?
                      OR a.manual_login_username LIKE ?
                      OR a.account_key LIKE ?
                      OR a.device_name LIKE ?
                      OR a.device_id LIKE ?
                  )
                ORDER BY a.activation_date DESC");
            $params = array_merge(array_map('intval', $allowedCreatorIds), [$like, $like, $like, $like, $like]);
            $stmt->execute($params);
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

        $stmt = $conn->prepare("SELECT a.*,
            (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
            FROM activated_devices a
            INNER JOIN iptv_customers c ON (
                c.username = a.manual_login_username 
                OR c.username = a.account_display_name 
                OR a.account_key LIKE CONCAT(c.username, '#%') 
                OR a.account_key = c.username
            )
            WHERE (a.status IS NULL OR a.status <> 'deleted')
              AND c.created_by IN ($placeholders)
            ORDER BY a.activation_date DESC");
        $stmt->execute(array_map('intval', $allowedCreatorIds));
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    if ($search !== '') {
        $like = '%' . $search . '%';
        $stmt = $conn->prepare("SELECT a.*,
            (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
            FROM activated_devices a
            WHERE (a.status IS NULL OR a.status <> 'deleted')
              AND (
                  a.account_display_name LIKE ?
                  OR a.manual_login_username LIKE ?
                  OR a.account_key LIKE ?
                  OR a.device_name LIKE ?
                  OR a.device_id LIKE ?
              )
            ORDER BY a.activation_date DESC");
        $stmt->execute([$like, $like, $like, $like, $like]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    // نضيف عدد استخدام أكواد القوائم لكل جهاز (لاختيار مصدر الدخول: Username/Password أو Code).
    // الأجهزة المحذوفة من اللوحة (status=deleted) تبقى في القاعدة لإعادة التفعيل لاحقاً ولا تُعرض.
    $stmt = $conn->query("SELECT a.*,
        (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
        FROM activated_devices a
        WHERE a.status IS NULL OR a.status <> 'deleted'
        ORDER BY a.activation_date DESC");
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

// إضافة جهاز جديد
function addDevice($conn, $device_id, $expiry_date, $custom_domain = null, $device_name = null, $block_vpn = 0, $isTrial = false, $status = 'active') {
    $name = $device_name !== null && trim((string) $device_name) !== '' ? trim((string) $device_name) : null;
    $trial = $isTrial ? 1 : 0;
    $status = strtolower(trim((string) $status));
    if (!in_array($status, ['active', 'expired', 'blocked'], true)) {
        $status = 'active';
    }
    try {
        $stmt = $conn->prepare(
            "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, custom_domain, device_name, block_vpn, is_trial)
             VALUES (?, NOW(), ?, ?, ?, ?, ?, ?)"
        );
        return $stmt->execute([$device_id, $expiry_date, $status, $custom_domain ?: null, $name, (int) $block_vpn, $trial]);
    } catch (PDOException $e) {
        try {
            $stmt = $conn->prepare(
                "INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, custom_domain, device_name, block_vpn)
                 VALUES (?, NOW(), ?, ?, ?, ?, ?)"
            );
            return $stmt->execute([$device_id, $expiry_date, $status, $custom_domain ?: null, $name, (int) $block_vpn]);
        } catch (PDOException $e2) {
            try {
                $stmt = $conn->prepare(
                    "INSERT INTO activated_devices (device_id, activation_date, expiry_date, custom_domain, device_name, block_vpn)
                     VALUES (?, NOW(), ?, ?, ?, ?)"
                );
                return $stmt->execute([$device_id, $expiry_date, $custom_domain ?: null, $name, (int) $block_vpn]);
            } catch (PDOException $e3) {
                return false;
            }
        }
    }
}

/**
 * تحويل اختيار المدة من اللوحة إلى تاريخ انتهاء + هل هو وضع تجربة.
 * القيم: trial | 1 | 3 | 6 | 12 | 24 | 0 (مدى الحياة)
 * @return array{expiry:string,is_trial:bool}|null
 */
function adminExpiryFromDurationChoice(PDO $conn, $choice): ?array
{
    $choice = strtolower(trim((string) $choice));
    if ($choice === 'trial') {
        $settings = getSettings($conn);
        $days = isset($settings['default_expiry_days']) ? (int) $settings['default_expiry_days'] : 30;
        if ($days <= 0) {
            $days = 30;
        }
        $expiry = (new DateTime())->modify('+' . $days . ' days')->format('Y-m-d H:i:s');
        return ['expiry' => $expiry, 'is_trial' => true];
    }
    if ($choice === '' || !preg_match('/^\d+$/', $choice)) {
        return null;
    }
    $months = (int) $choice;
    if (!in_array($months, adminAllowedDurationMonths(), true)) {
        return null;
    }
    if (adminDurationIsLifetime($months)) {
        return ['expiry' => adminLifetimeExpiryDate(), 'is_trial' => false];
    }
    $expiry = (new DateTime())->modify('+' . $months . ' months')->format('Y-m-d H:i:s');
    return ['expiry' => $expiry, 'is_trial' => false];
}

function adminDateDiffAbsDays(DateTime $a, DateTime $b): int
{
    return (int) abs((int) $a->diff($b)->format('%r%a'));
}

/**
 * استنتاج بطاقة المدة المعروضة في تعديل الجهاز من بيانات قاعدة البيانات.
 * القيم: keep | trial | 1 | 3 | 6 | 12 | 24 | 0
 */
function adminInferDurationKeyFromDevice(PDO $conn, array $device): string
{
    $expiryRaw = trim((string) ($device['expiry_date'] ?? ''));
    if ($expiryRaw === '') {
        return 'keep';
    }
    if (deviceExpiryIsLifetime($expiryRaw)) {
        return '0';
    }
    if (!empty($device['is_trial'])) {
        return 'trial';
    }

    try {
        $expiryDt = new DateTime($expiryRaw);
    } catch (Exception $e) {
        return 'keep';
    }

    $settings = getSettings($conn);
    $trialDays = isset($settings['default_expiry_days']) ? (int) $settings['default_expiry_days'] : 30;
    if ($trialDays <= 0) {
        $trialDays = 30;
    }

    $activationRaw = trim((string) ($device['activation_date'] ?? ''));
    if ($activationRaw !== '') {
        try {
            $activationDt = new DateTime($activationRaw);
            if (adminDateDiffAbsDays($activationDt, $expiryDt) <= $trialDays + 2) {
                $trialExpected = (clone $activationDt)->modify('+' . $trialDays . ' days');
                if (adminDateDiffAbsDays($trialExpected, $expiryDt) <= 2) {
                    return 'trial';
                }
            }
            foreach (adminAllowedDurationMonths() as $months) {
                if (adminDurationIsLifetime($months)) {
                    continue;
                }
                $expected = (clone $activationDt)->modify('+' . $months . ' months');
                if (adminDateDiffAbsDays($expected, $expiryDt) <= 3) {
                    return (string) $months;
                }
            }
        } catch (Exception $e) {
            // ignore invalid activation date
        }
    }

    $expiryTs = $expiryDt->getTimestamp();
    if ($expiryTs > time()) {
        $now = new DateTime();
        foreach (adminAllowedDurationMonths() as $months) {
            if (adminDurationIsLifetime($months)) {
                continue;
            }
            $expected = (clone $now)->modify('+' . $months . ' months');
            if (adminDateDiffAbsDays($expected, $expiryDt) <= 3) {
                return (string) $months;
            }
        }
    }

    return 'keep';
}

// تحديث جهاز
function updateDevice($conn, $id, $expiry_date, $status = 'active', $notes = '', $custom_domain = null, $device_name = null, $block_vpn = null, $ads_enabled = null) {
    $id = (int) $id;
    if ($id <= 0) {
        return false;
    }
    $name = $device_name !== null && trim((string)$device_name) !== '' ? trim($device_name) : null;
    // أي تعديل يدوي من اللوحة = لم يعد وضع تجربة
    $sets = [
        'expiry_date = ?',
        'status = ?',
        'notes = ?',
        'custom_domain = ?',
        'device_name = ?',
    ];
    $vals = [$expiry_date, $status, $notes, $custom_domain, $name];
    if ($block_vpn !== null) {
        $sets[] = 'block_vpn = ?';
        $vals[] = (int) $block_vpn;
    }
    if ($ads_enabled !== null) {
        $sets[] = 'ads_enabled = ?';
        $vals[] = (int) $ads_enabled ? 1 : 0;
    }
    $setsWithTrial = array_merge($sets, ['is_trial = 0']);
    $vals[] = $id;
    $where = ' WHERE id = ? AND (status IS NULL OR status <> \'deleted\')';
    try {
        $sql = 'UPDATE activated_devices SET ' . implode(', ', $setsWithTrial) . $where;
        $stmt = $conn->prepare($sql);
        return $stmt->execute($vals);
    } catch (PDOException $e) {
        // Older schemas may lack is_trial / ads_enabled — retry without optional columns.
        try {
            $setsFallback = [
                'expiry_date = ?',
                'status = ?',
                'notes = ?',
                'custom_domain = ?',
                'device_name = ?',
            ];
            $valsFallback = [$expiry_date, $status, $notes, $custom_domain, $name];
            if ($block_vpn !== null) {
                $setsFallback[] = 'block_vpn = ?';
                $valsFallback[] = (int) $block_vpn;
            }
            if ($ads_enabled !== null) {
                $setsFallback[] = 'ads_enabled = ?';
                $valsFallback[] = (int) $ads_enabled ? 1 : 0;
            }
            $valsFallback[] = $id;
            $sql = 'UPDATE activated_devices SET ' . implode(', ', $setsFallback) . $where;
            $stmt = $conn->prepare($sql);
            return $stmt->execute($valsFallback);
        } catch (PDOException $e2) {
            if ($ads_enabled !== null) {
                // Column may not exist yet — save without ads_enabled.
                try {
                    $setsNoAds = [
                        'expiry_date = ?',
                        'status = ?',
                        'notes = ?',
                        'custom_domain = ?',
                        'device_name = ?',
                    ];
                    $valsNoAds = [$expiry_date, $status, $notes, $custom_domain, $name];
                    if ($block_vpn !== null) {
                        $setsNoAds[] = 'block_vpn = ?';
                        $valsNoAds[] = (int) $block_vpn;
                    }
                    $valsNoAds[] = $id;
                    $sql = 'UPDATE activated_devices SET ' . implode(', ', $setsNoAds) . $where;
                    $stmt = $conn->prepare($sql);
                    return $stmt->execute($valsNoAds);
                } catch (PDOException $e3) {
                    return false;
                }
            }
            return false;
        }
    }
}

/**
 * Effective ads flag for a device: global settings AND per-device toggle.
 */
function app_device_ads_enabled(array $settings, $device = null): bool
{
    $global = !isset($settings['ads_enabled']) ? true : ((int) $settings['ads_enabled'] === 1);
    if (!$global) {
        return false;
    }
    if (!is_array($device)) {
        return true;
    }
    if (!array_key_exists('ads_enabled', $device) || $device['ads_enabled'] === null || $device['ads_enabled'] === '') {
        return true;
    }
    return (int) $device['ads_enabled'] === 1;
}

/**
 * Merge panel public payload with per-device ads override.
 */
function app_panel_public_payload_for_device(array $settings, $device = null): array
{
    $pub = app_panel_public_payload($settings);
    $pub['ads_enabled'] = app_device_ads_enabled($settings, $device);
    $pub['device_ads_enabled'] = is_array($device)
        ? app_device_ads_enabled(['ads_enabled' => 1], $device)
        : true;
    return $pub;
}

// حذف جهاز من لوحة التحكم = حذف ناعم (status=deleted)
// يبقى السجل حتى يُعاد تسجيله كجهاز جديد عند فتح التطبيق — بدون منح فترة جديدة لمن يعيد تثبيت التطبيق فقط.
function deleteDevice($conn, $id) {
    $id = (int) $id;
    if ($id <= 0) {
        return false;
    }
    try {
        $stmt = $conn->prepare(
            "UPDATE activated_devices
             SET status = 'deleted',
                 expiry_date = NOW(),
                 custom_domain = NULL,
                 web_manage_code = NULL,
                 web_manage_code_months = NULL,
                 web_manage_unlocked_at = NULL,
                 web_manage_unlocked_fp = NULL,
                 notes = TRIM(CONCAT(IFNULL(notes, ''), ' [deleted by admin ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']'))
             WHERE id = ?
               AND (status IS NULL OR status <> 'deleted')"
        );
        return $stmt->execute([$id]);
    } catch (PDOException $e) {
        return false;
    }
}

/** إعادة تفعيل جهاز حُذف من اللوحة بمدة الأيام الافتراضية. */
function rearmAdminDeletedDevice(PDO $conn, string $deviceId, int $days, string $deviceName = ''): ?array
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return null;
    }
    if ($days <= 0) {
        $days = 30;
    }
    $expiryStr = (new DateTime())->modify('+' . $days . ' days')->format('Y-m-d H:i:s');
    if (!activateDevice($conn, $deviceId, $expiryStr, $deviceName, true)) {
        return null;
    }
    try {
        $stmt = $conn->prepare(
            "SELECT * FROM activated_devices WHERE device_id = ? AND status = 'active' AND expiry_date > NOW() LIMIT 1"
        );
        $stmt->execute([$deviceId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    } catch (PDOException $e) {
        return null;
    }
}

/** إيجاد صف الجهاز بمعرّف التطبيق (مع TRIM/حالة الأحرف عند الحاجة). */
function findActivatedDeviceRow(PDO $conn, string $deviceId): ?array
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return null;
    }
    try {
        $stmt = $conn->prepare('SELECT * FROM activated_devices WHERE device_id = ? LIMIT 1');
        $stmt->execute([$deviceId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (is_array($row)) {
            return $row;
        }
        $stmt2 = $conn->prepare(
            'SELECT * FROM activated_devices
             WHERE TRIM(device_id) = ?
                OR LOWER(TRIM(device_id)) = LOWER(?)
             LIMIT 1'
        );
        $stmt2->execute([$deviceId, $deviceId]);
        $row2 = $stmt2->fetch(PDO::FETCH_ASSOC);
        return is_array($row2) ? $row2 : null;
    } catch (PDOException $e) {
        return null;
    }
}

function normalizeMacAddress(string $mac): string
{
    $hex = strtoupper(preg_replace('/[^A-Fa-f0-9]/', '', $mac));
    if (strlen($hex) !== 12 || !ctype_xdigit($hex)) {
        return '';
    }
    if ($hex === '020000000000' || preg_match('/^0+$/', $hex)) {
        return '';
    }
    return implode(':', str_split($hex, 2));
}

function normalizeHardwareFingerprint(string $fingerprint): string
{
    $fp = strtolower(trim($fingerprint));
    if (!preg_match('/^[a-f0-9]{64}$/', $fp)) {
        return '';
    }
    return $fp;
}

function findActivatedDeviceByMac(PDO $conn, string $mac): ?array
{
    $mac = normalizeMacAddress($mac);
    if ($mac === '') {
        return null;
    }
    try {
        $stmt = $conn->prepare('SELECT * FROM activated_devices WHERE mac_address = ? LIMIT 1');
        $stmt->execute([$mac]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return is_array($row) ? $row : null;
    } catch (PDOException $e) {
        return null;
    }
}

function findActivatedDeviceByHardwareFingerprint(PDO $conn, string $fingerprint): ?array
{
    $fingerprint = normalizeHardwareFingerprint($fingerprint);
    if ($fingerprint === '') {
        return null;
    }
    try {
        $stmt = $conn->prepare('SELECT * FROM activated_devices WHERE hardware_fingerprint = ? LIMIT 1');
        $stmt->execute([$fingerprint]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return is_array($row) ? $row : null;
    } catch (PDOException $e) {
        return null;
    }
}

function findActivatedDeviceByPk(PDO $conn, int $id): ?array
{
    if ($id <= 0) {
        return null;
    }
    try {
        $stmt = $conn->prepare('SELECT * FROM activated_devices WHERE id = ? LIMIT 1');
        $stmt->execute([$id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return is_array($row) ? $row : null;
    } catch (PDOException $e) {
        return null;
    }
}

function relinkActivatedDeviceId(PDO $conn, string $oldId, string $newId): void
{
    $oldId = trim($oldId);
    $newId = trim($newId);
    if ($oldId === '' || $newId === '' || $oldId === $newId) {
        return;
    }
    $tables = [
        ['playlist_access_codes', 'bound_device_id'],
        ['playlist_code_devices', 'device_id'],
        ['device_web_playlists', 'device_id'],
        ['device_login_sessions', 'device_id'],
    ];
    foreach ($tables as $pair) {
        try {
            $sql = 'UPDATE ' . $pair[0] . ' SET ' . $pair[1] . ' = ? WHERE ' . $pair[1] . ' = ?';
            $conn->prepare($sql)->execute([$newId, $oldId]);
        } catch (PDOException $e) {
        }
    }
}

function backfillActivatedDeviceBindingKeys(
    PDO $conn,
    int $id,
    string $mac,
    string $hardwareFingerprint,
    array $row
): void {
    if ($id <= 0) {
        return;
    }
    if ($mac !== '' && trim((string) ($row['mac_address'] ?? '')) === '') {
        try {
            $conn->prepare('UPDATE activated_devices SET mac_address = ? WHERE id = ?')
                ->execute([$mac, $id]);
        } catch (PDOException $e) {
        }
    }
    if ($hardwareFingerprint !== '') {
        $current = trim((string) ($row['hardware_fingerprint'] ?? ''));
        if ($current === '' || $current !== $hardwareFingerprint) {
            try {
                $conn->prepare('UPDATE activated_devices SET hardware_fingerprint = ? WHERE id = ?')
                    ->execute([$hardwareFingerprint, $id]);
            } catch (PDOException $e) {
            }
        }
    }
}

function updateActivatedDeviceIdIfChanged(PDO $conn, array $row, string $deviceId): string
{
    $pk = (int) ($row['id'] ?? 0);
    $currentId = trim((string) ($row['device_id'] ?? ''));
    if ($deviceId !== '' && $deviceId !== $currentId) {
        relinkActivatedDeviceId($conn, $currentId, $deviceId);
        try {
            $conn->prepare(
                'UPDATE activated_devices SET previous_device_id = ?, device_id = ? WHERE id = ?'
            )->execute([$currentId, $deviceId, $pk]);
        } catch (PDOException $e) {
        }
        return $deviceId;
    }
    return $currentId !== '' ? $currentId : $deviceId;
}

/**
 * @return array{row: ?array, device_id: string, mac_address: string, hardware_fingerprint: string}
 */
function resolveActivatedDevice(
    PDO $conn,
    string $deviceId,
    string $macRaw,
    string $deviceName = '',
    bool $touch = true,
    string $hardwareFingerprintRaw = ''
): array {
    $deviceId = trim($deviceId);
    $mac = normalizeMacAddress($macRaw);
    $hardwareFingerprint = normalizeHardwareFingerprint($hardwareFingerprintRaw);

    $rowByMac = $mac !== '' ? findActivatedDeviceByMac($conn, $mac) : null;
    $rowByHw = !$rowByMac && $hardwareFingerprint !== ''
        ? findActivatedDeviceByHardwareFingerprint($conn, $hardwareFingerprint)
        : null;
    $rowById = $deviceId !== '' ? findActivatedDeviceRow($conn, $deviceId) : null;
    $row = $rowByMac ?: $rowByHw;

    if ($row) {
        $pk = (int) ($row['id'] ?? 0);
        $deviceId = updateActivatedDeviceIdIfChanged($conn, $row, $deviceId);
        backfillActivatedDeviceBindingKeys($conn, $pk, $mac, $hardwareFingerprint, $row);
        if ($touch) {
            touchDeviceName($conn, $deviceId, $deviceName);
        }
        $row = findActivatedDeviceByPk($conn, $pk);
        return [
            'row' => $row,
            'device_id' => $deviceId,
            'mac_address' => $mac !== '' ? $mac : trim((string) ($row['mac_address'] ?? '')),
            'hardware_fingerprint' => $hardwareFingerprint !== ''
                ? $hardwareFingerprint
                : trim((string) ($row['hardware_fingerprint'] ?? '')),
        ];
    }

    if ($rowById) {
        $pk = (int) ($rowById['id'] ?? 0);
        backfillActivatedDeviceBindingKeys($conn, $pk, $mac, $hardwareFingerprint, $rowById);
        if ($touch) {
            touchDeviceName($conn, $deviceId, $deviceName);
        }
        $row = findActivatedDeviceByPk($conn, $pk);
        return [
            'row' => $row,
            'device_id' => trim((string) ($row['device_id'] ?? $deviceId)),
            'mac_address' => $mac !== '' ? $mac : trim((string) ($row['mac_address'] ?? '')),
            'hardware_fingerprint' => $hardwareFingerprint !== ''
                ? $hardwareFingerprint
                : trim((string) ($row['hardware_fingerprint'] ?? '')),
        ];
    }

    return [
        'row' => null,
        'device_id' => $deviceId,
        'mac_address' => $mac,
        'hardware_fingerprint' => $hardwareFingerprint,
    ];
}

/**
 * @return array{row: ?array, device_id: string, mac_address: string, hardware_fingerprint: string}
 */
function resolveActivatedDeviceFromPayload(PDO $conn, array $data, bool $touch = true): array
{
    $deviceId = '';
    $mac = '';
    $hw = '';
    $deviceName = '';
    if (function_exists('app_api_field')) {
        $deviceId = app_api_field($data, 'device_id');
        $mac = app_api_field($data, 'mac_address');
        $hw = app_api_field($data, 'hardware_fingerprint');
        $deviceName = app_api_field($data, 'device_name');
    } else {
        $deviceId = trim((string) ($data['device_id'] ?? ''));
        $mac = trim((string) ($data['mac_address'] ?? ''));
        $hw = trim((string) ($data['hardware_fingerprint'] ?? ''));
        $deviceName = trim((string) ($data['device_name'] ?? ''));
    }
    return resolveActivatedDevice($conn, $deviceId, $mac, $deviceName, $touch, $hw);
}

function persistActivatedDeviceBindingKeys(
    PDO $conn,
    string $deviceId,
    string $mac,
    string $hardwareFingerprint
): void {
    $row = findActivatedDeviceRow($conn, $deviceId);
    if (!$row) {
        return;
    }
    backfillActivatedDeviceBindingKeys(
        $conn,
        (int) ($row['id'] ?? 0),
        $mac,
        $hardwareFingerprint,
        $row
    );
}

/** هل تاريخ الانتهاء لا يزال في المستقبل حسب ساعة MySQL. */
function deviceExpiryIsInFuture(PDO $conn, int $id, $expiryDate = null): bool
{
    if ($id <= 0) {
        return false;
    }
    try {
        $stmt = $conn->prepare('SELECT (expiry_date > NOW()) FROM activated_devices WHERE id = ?');
        $stmt->execute([$id]);
        return ((int) $stmt->fetchColumn()) === 1;
    } catch (PDOException $e) {
        if ($expiryDate === null || trim((string) $expiryDate) === '') {
            return false;
        }
        $ts = strtotime((string) $expiryDate);
        return $ts !== false && $ts > time();
    }
}

/** 0 = مدى الحياة. بقية القيم بالأشهر. */
function adminAllowedDurationMonths(): array
{
    return [1, 3, 6, 12, 24, 0];
}

function adminDurationIsLifetime(int $months): bool
{
    return $months === 0;
}

function adminNormalizeDurationMonths($raw): int
{
    $months = (int) $raw;
    return in_array($months, adminAllowedDurationMonths(), true) ? $months : 1;
}

function adminLifetimeExpiryDate(): string
{
    return '2099-12-31 23:59:59';
}

function deviceExpiryIsLifetime($expiryDate): bool
{
    $ts = is_numeric($expiryDate) ? (int) $expiryDate : strtotime((string) $expiryDate);
    if (!$ts) {
        return false;
    }
    return ((int) date('Y', $ts)) >= 2090;
}

function format_device_expiry($time): string
{
    if (deviceExpiryIsLifetime($time)) {
        return '∞';
    }
    return function_exists('format_datetime_short') ? format_datetime_short($time) : (string) $time;
}

/**
 * إعادة تفعيل الجهاز من الآن لمدة الأشهر المحددة (نفس سلوك موقع إدارة القوائم).
 * الأشهر = 0 تعني مدى الحياة.
 */
function applyDeviceDurationFromNow(PDO $conn, int $id, int $months): bool
{
    $months = adminNormalizeDurationMonths($months);
    if ($id <= 0) {
        return false;
    }
    $expirySql = adminDurationIsLifetime($months)
        ? "'" . adminLifetimeExpiryDate() . "'"
        : "DATE_ADD(NOW(), INTERVAL {$months} MONTH)";
    try {
        $stmt = $conn->prepare(
            "UPDATE activated_devices
             SET activation_date = NOW(),
                 expiry_date = {$expirySql},
                 status = 'active'
             WHERE id = ?
               AND status <> 'blocked'"
        );
        $stmt->execute([$id]);
        return true;
    } catch (PDOException $e) {
        return false;
    }
}

// دالة للتحقق من حالة الجهاز
function checkDeviceStatus($conn, $deviceId) {
    $stmt = $conn->prepare("SELECT * FROM activated_devices WHERE device_id = ? AND status = 'active' AND expiry_date > NOW()");
    $stmt->execute([$deviceId]);
    return $stmt->fetch(PDO::FETCH_ASSOC);
}

// دالة لتفعيل جهاز
function touchDeviceName(PDO $conn, string $deviceId, string $deviceName): void
{
    $name = trim($deviceName);
    if ($deviceId === '' || $name === '') {
        return;
    }
    if (function_exists('mb_substr')) {
        $name = mb_substr($name, 0, 255);
    } elseif (strlen($name) > 255) {
        $name = substr($name, 0, 255);
    }
    try {
        $stmt = $conn->prepare("UPDATE activated_devices SET device_name = ? WHERE device_id = ?");
        $stmt->execute([$name, $deviceId]);
    } catch (PDOException $e) {
        // ignore missing column / transient errors
    }
}

function deviceRowIsTrial(?array $device): bool
{
    if (!$device) {
        return false;
    }
    $v = $device['is_trial'] ?? 0;
    return $v === true || $v === 1 || $v === '1';
}

function activateDevice($conn, $deviceId, $expiryDate, $deviceName = null, $isTrial = false) {
    $name = $deviceName !== null ? trim((string) $deviceName) : '';
    if ($name === '') {
        $name = null;
    }
    $trial = $isTrial ? 1 : 0;
    try {
        $stmt = $conn->prepare("INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, device_name, is_trial) 
                               VALUES (?, NOW(), ?, 'active', ?, ?)
                               ON DUPLICATE KEY UPDATE 
                               activation_date = NOW(),
                               expiry_date = VALUES(expiry_date),
                               status = 'active',
                               device_name = COALESCE(NULLIF(VALUES(device_name), ''), device_name),
                               is_trial = VALUES(is_trial)");
        return $stmt->execute([$deviceId, $expiryDate, $name, $trial]);
    } catch (PDOException $e) {
        try {
            $stmt = $conn->prepare("INSERT INTO activated_devices (device_id, activation_date, expiry_date, status, device_name) 
                                   VALUES (?, NOW(), ?, 'active', ?)
                                   ON DUPLICATE KEY UPDATE 
                                   activation_date = NOW(),
                                   expiry_date = VALUES(expiry_date),
                                   status = 'active',
                                   device_name = COALESCE(NULLIF(VALUES(device_name), ''), device_name)");
            return $stmt->execute([$deviceId, $expiryDate, $name]);
        } catch (PDOException $e2) {
            try {
                $stmt = $conn->prepare("INSERT INTO activated_devices (device_id, activation_date, expiry_date, status) 
                                       VALUES (?, NOW(), ?, 'active')
                                       ON DUPLICATE KEY UPDATE 
                                       activation_date = NOW(),
                                       expiry_date = VALUES(expiry_date),
                                       status = 'active'");
                return $stmt->execute([$deviceId, $expiryDate]);
            } catch (PDOException $e3) {
                return false;
            }
        }
    }
}

// دالة لإلغاء تفعيل جهاز
function deactivateDevice($conn, $deviceId) {
    try {
        $stmt = $conn->prepare("UPDATE activated_devices SET status = 'blocked' WHERE device_id = ?");
        return $stmt->execute([$deviceId]);
    } catch (PDOException $e) {
        return false;
    }
}

// دالة لتسجيل النشاط
function logActivity($conn, $action, $deviceId, $details = null) {
    try {
        $stmt = $conn->prepare("INSERT INTO activity_log (action, device_id, details) VALUES (?, ?, ?)");
        return $stmt->execute([$action, $deviceId, $details]);
    } catch (Throwable $e) {
        return false;
    }
}

// دالة للتحقق من صحة تسجيل الدخول
function checkLogin() {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true || empty($_SESSION['admin_user_id'])) {
        header('Location: login.php');
        exit();
    }
}

// دالة لتنظيف المدخلات
function sanitizeInput($input) {
    return htmlspecialchars(trim($input), ENT_QUOTES, 'UTF-8');
}

// دالة للتحقق من صلاحية التاريخ
function validateDate($date) {
    $d = DateTime::createFromFormat('Y-m-d', $date);
    return $d && $d->format('Y-m-d') === $date;
}

// دالة لجلب إحصائيات لوحة التحكم
function getDashboardStats($conn) {
    $stats = [];
    
    // إجمالي الأجهزة المفعلة
    $stmt = $conn->query("SELECT COUNT(*) FROM activated_devices WHERE status = 'active'");
    $stats['active_devices'] = $stmt->fetchColumn();
    
    // الأجهزة المنتهية
    $stmt = $conn->query("SELECT COUNT(*) FROM activated_devices WHERE status = 'expired'");
    $stats['expired_devices'] = $stmt->fetchColumn();
    
    // الأجهزة المحظورة
    $stmt = $conn->query("SELECT COUNT(*) FROM activated_devices WHERE status = 'blocked'");
    $stats['blocked_devices'] = $stmt->fetchColumn();
    
    return $stats;
}

function submitClientFeedback($conn, $deviceId, $deviceName, $deviceUrl, $note) {
    $stmt = $conn->prepare("INSERT INTO client_feedback (device_id, device_name, device_url, note, is_read) VALUES (?, ?, ?, ?, 0)");
    return $stmt->execute([
        trim((string)$deviceId),
        trim((string)$deviceName),
        trim((string)$deviceUrl),
        trim((string)$note),
    ]);
}

function getClientFeedbacks($conn) {
    $stmt = $conn->query("SELECT * FROM client_feedback ORDER BY created_at DESC, id DESC");
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function getUnreadFeedbackCount($conn) {
    $stmt = $conn->query("SELECT COUNT(*) FROM client_feedback WHERE is_read = 0");
    return (int)$stmt->fetchColumn();
}

function markAllFeedbackAsRead($conn) {
    $stmt = $conn->prepare("UPDATE client_feedback SET is_read = 1 WHERE is_read = 0");
    return $stmt->execute();
}

/** حذف ملاحظة عميل واحدة (لوحة التحكم). */
function deleteClientFeedbackById(PDO $conn, int $id): bool {
    if ($id <= 0) {
        return false;
    }
    try {
        $stmt = $conn->prepare('DELETE FROM client_feedback WHERE id = ? LIMIT 1');
        $stmt->execute([$id]);
        return $stmt->rowCount() > 0;
    } catch (PDOException $e) {
        return false;
    }
}

// إنشاء جدول قاعدة البيانات
function createDatabaseTable($conn) {
    try {
        // إنشاء جدول الأجهزة المفعلة
        $sql = "CREATE TABLE IF NOT EXISTS activated_devices (
            id INT AUTO_INCREMENT PRIMARY KEY,
            device_id VARCHAR(255) NOT NULL UNIQUE,
            activation_date DATETIME NOT NULL,
            expiry_date DATETIME NOT NULL,
            status ENUM('active', 'expired', 'blocked', 'deleted') DEFAULT 'active',
            notes TEXT,
            custom_domain VARCHAR(1024) DEFAULT NULL,
            account_key VARCHAR(255) DEFAULT NULL,
            device_name VARCHAR(255) DEFAULT NULL,
            block_vpn TINYINT(1) NOT NULL DEFAULT 0,
            ads_enabled TINYINT(1) NOT NULL DEFAULT 1,
            last_seen_at DATETIME NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        // دعم الحذف الناعم من لوحة التحكم (إعادة تفعيل كجهاز جديد عند فتح التطبيق فقط)
        try {
            $conn->exec("ALTER TABLE activated_devices MODIFY COLUMN status ENUM('active', 'expired', 'blocked', 'deleted') DEFAULT 'active'");
        } catch (PDOException $e) {
            // تجاهل
        }

        // إضافة عمود custom_domain إذا لم يكن موجوداً (للجداول القديمة)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN custom_domain VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {
            // تجاهل الخطأ إذا كان العمود موجوداً مسبقاً
        }
        // روابط get.php كاملة قد تتجاوز 255 حرفاً
        try {
            $conn->exec("ALTER TABLE activated_devices MODIFY COLUMN custom_domain VARCHAR(1024) DEFAULT NULL");
        } catch (PDOException $e) {}
        // إضافة عمود account_key (تمييز الحساب/الاشتراك للحد الأقصى للأجهزة)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN account_key VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        // Index اختياري لتسريع العد حسب الحساب
        try {
            $conn->exec("ALTER TABLE activated_devices ADD INDEX idx_account_key (account_key)");
        } catch (PDOException $e) {}
        // إضافة عمود device_name إذا لم يكن موجوداً (اسم اختياري للجهاز)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN device_name VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        // إضافة عمود device_name إذا لم يكن موجوداً (اسم اختياري للجهاز)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN device_name VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        // إضافة عمود block_vpn (منع VPN لكل جهاز)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN block_vpn TINYINT(1) NOT NULL DEFAULT 0");
        } catch (PDOException $e) {}
        // إعلانات AdMob لكل جهاز (1 = مفعّل، يخضع أيضاً للإعداد العام)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN ads_enabled TINYINT(1) NOT NULL DEFAULT 1");
        } catch (PDOException $e) {}
        // إضافة عمود last_seen_at لتتبع آخر تواجد للجهاز (لإظهار حالة الاتصال)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN last_seen_at DATETIME NULL");
        } catch (PDOException $e) {}
        // هوست الكود + يوزر/باس يدوي بعد رمز القائمة (host-only)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN code_server_host VARCHAR(500) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN manual_login_username VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN manual_login_password VARCHAR(512) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            // Encrypted payloads need more room than plaintext passwords.
            $conn->exec("ALTER TABLE activated_devices MODIFY COLUMN manual_login_password VARCHAR(1024) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN account_display_name VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN device_api_token_hash VARCHAR(64) DEFAULT NULL");
        } catch (PDOException $e) {}
        // كود إدارة القوائم من موقع Manage Playlist (يُولَّد من Edit Device)
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN web_manage_code VARCHAR(12) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN web_manage_code_updated_at DATETIME NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN web_manage_unlocked_at DATETIME NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN web_manage_unlocked_fp VARCHAR(64) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN web_manage_code_months INT NULL DEFAULT NULL");
        } catch (PDOException $e) {}
        // وضع التجربة (تفعيل تلقائي بالأيام الافتراضية) — يُلغى عند تعديل الأدمن للجهاز
        $addedIsTrialColumn = false;
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN is_trial TINYINT(1) NOT NULL DEFAULT 0");
            $addedIsTrialColumn = true;
        } catch (PDOException $e) {}
        // ترحيل أجهزة التفعيل التلقائي الحالية مرة واحدة فقط عند إضافة العمود
        if ($addedIsTrialColumn) {
            try {
                $conn->exec(
                    "UPDATE activated_devices ad
                     INNER JOIN (
                         SELECT DISTINCT device_id FROM activity_log
                         WHERE action IN ('add_device', 'auto_register')
                           AND (
                               details LIKE '%automatically%'
                               OR details LIKE '%default expiry%'
                               OR details LIKE '%Re-registered%'
                           )
                     ) al ON al.device_id = ad.device_id
                     SET ad.is_trial = 1
                     WHERE ad.status = 'active'"
                );
            } catch (PDOException $e) {}
        }
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN mac_address VARCHAR(64) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN previous_device_id VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN hardware_fingerprint VARCHAR(64) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD UNIQUE KEY uq_activated_mac_address (mac_address)");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD UNIQUE KEY uq_activated_hardware_fingerprint (hardware_fingerprint)");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN watching_type VARCHAR(16) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN watching_title VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN watching_stream_id VARCHAR(64) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN watching_extra VARCHAR(255) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE activated_devices ADD COLUMN watching_updated_at DATETIME NULL");
        } catch (PDOException $e) {}

        try {
            $conn->exec("CREATE TABLE IF NOT EXISTS activity_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                action VARCHAR(64) NOT NULL,
                device_id VARCHAR(255) DEFAULT NULL,
                details TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_activity_created (created_at),
                KEY idx_activity_device (device_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        } catch (PDOException $e) {}

        // قوائم M3U المُدارة من الويب لكل جهاز → تُزامَن إلى Manage Accounts
        try {
            $conn->exec("CREATE TABLE IF NOT EXISTS device_web_playlists (
                id INT AUTO_INCREMENT PRIMARY KEY,
                device_id VARCHAR(255) NOT NULL,
                name VARCHAR(255) NOT NULL,
                m3u_url TEXT NOT NULL,
                pin_hash VARCHAR(255) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                KEY idx_device_web_playlists_device (device_id),
                UNIQUE KEY uniq_device_m3u (device_id, m3u_url(191))
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        } catch (PDOException $e) {}

        // إنشاء جدول الإعدادات
        $sql = "CREATE TABLE IF NOT EXISTS settings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            app_name VARCHAR(255) DEFAULT 'Nova IPTV Player',
            home_theme VARCHAR(50) NOT NULL DEFAULT 'original',
            default_expiry_days INT NOT NULL DEFAULT 30,
            max_devices_per_user INT NOT NULL DEFAULT 1,
            auto_block_expired BOOLEAN NOT NULL DEFAULT 0,
            device_registration TINYINT(1) NOT NULL DEFAULT 1,
            block_vpn_global TINYINT(1) NOT NULL DEFAULT 0,
            default_server_url VARCHAR(500) DEFAULT NULL,
            login_servers TEXT DEFAULT NULL,
            piracy_detection_enabled TINYINT(1) NOT NULL DEFAULT 0,
            piracy_packages TEXT DEFAULT NULL,
            piracy_message TEXT DEFAULT NULL,
            ads_enabled TINYINT(1) NOT NULL DEFAULT 1,
            banner_home_only TINYINT(1) NOT NULL DEFAULT 1,
            banner_ad_unit_android VARCHAR(100) DEFAULT NULL,
            banner_ad_unit_ios VARCHAR(100) DEFAULT NULL,
            interstitial_ad_unit_android VARCHAR(100) DEFAULT NULL,
            interstitial_ad_unit_ios VARCHAR(100) DEFAULT NULL,
            admob_app_id_android VARCHAR(120) DEFAULT NULL,
            admob_app_id_ios VARCHAR(120) DEFAULT NULL,
            show_add_change_button TINYINT(1) NOT NULL DEFAULT 1,
            show_username_login TINYINT(1) NOT NULL DEFAULT 1,
            sync_activation_with_server TINYINT(1) NOT NULL DEFAULT 0,
            app_version VARCHAR(50) DEFAULT '1.0.0',
            support_contact_url VARCHAR(700) DEFAULT NULL,
            purchase_url VARCHAR(1200) DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        // ترحيل أعمدة settings مبكراً (قبل أي منطق قد يفشل ويقطع الباقي)
        if (function_exists('ensureSettingsColumns')) {
            ensureSettingsColumns($conn);
        }

        // إعدادات إضافية للتطبيق (سياسة خصوصية، من نحن، فرض التفعيل في الواجهة)
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN activation_enforced TINYINT(1) NOT NULL DEFAULT 1");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN block_screenshots TINYINT(1) NOT NULL DEFAULT 1");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN privacy_policy_url VARCHAR(1200) DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN privacy_policy_html MEDIUMTEXT DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN about_us_html MEDIUMTEXT DEFAULT NULL");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN privacy_policy_mode VARCHAR(16) NOT NULL DEFAULT 'url'");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN app_activation_url VARCHAR(1200) DEFAULT NULL");
        } catch (PDOException $e) {}

        // SkyPro Xtream Codes / IPTV Server API Settings & Customers Table
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_api_url VARCHAR(500) DEFAULT 'https://skypro-app.com:25463'");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_api_key VARCHAR(255) DEFAULT ''");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_api_username VARCHAR(255) DEFAULT ''");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_api_password VARCHAR(255) DEFAULT ''");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_api_type VARCHAR(50) DEFAULT 'xtream_codes'");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN xtream_sync_enabled TINYINT(1) DEFAULT 1");
        } catch (PDOException $e) {}

        try {
            // تنظيف أي صلاحية إعدادات متبقية لغير المسؤول الأعلى لضمان الحظر التام
            $conn->exec("DELETE FROM admin_role_permissions WHERE permission_key = 'settings' AND role != 'super_admin'");
        } catch (PDOException $e) {}

        try {
            $conn->exec("CREATE TABLE IF NOT EXISTS iptv_customers (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(255) NOT NULL UNIQUE,
                password VARCHAR(255) NOT NULL,
                customer_name VARCHAR(255) DEFAULT NULL,
                email VARCHAR(255) DEFAULT NULL,
                phone VARCHAR(100) DEFAULT NULL,
                expiry_date DATETIME NOT NULL,
                max_connections INT DEFAULT 1,
                package_name VARCHAR(255) DEFAULT 'Standard',
                status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
                created_by INT DEFAULT NULL,
                server_sync_status ENUM('synced', 'pending', 'error') DEFAULT 'pending',
                server_sync_message TEXT DEFAULT NULL,
                notes TEXT DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_cust_username (username),
                INDEX idx_cust_status (status),
                INDEX idx_cust_expiry (expiry_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        } catch (PDOException $e) {}

        // إنشاء جدول ملاحظات العملاء
        $sql = "CREATE TABLE IF NOT EXISTS client_feedback (
            id INT AUTO_INCREMENT PRIMARY KEY,
            device_id VARCHAR(255) DEFAULT NULL,
            device_name VARCHAR(255) DEFAULT NULL,
            device_url VARCHAR(1000) DEFAULT NULL,
            note TEXT NOT NULL,
            is_read TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        // ترقية الجداول القديمة إذا كانت تفتقد بعض أعمدة الملاحظات
        try { $conn->exec("ALTER TABLE client_feedback ADD COLUMN device_name VARCHAR(255) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE client_feedback ADD COLUMN device_url VARCHAR(1000) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE client_feedback ADD COLUMN is_read TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}

        // أكواد وصول سريعة لقوائم M3U (5–6 أرقام فقط للتطبيق)
        $sql = "CREATE TABLE IF NOT EXISTS playlist_access_codes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(255) NOT NULL,
            m3u_url TEXT NOT NULL,
            code VARCHAR(6) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_playlist_code (code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        try { $conn->exec("ALTER TABLE playlist_access_codes ADD COLUMN max_devices INT NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE playlist_access_codes ADD COLUMN bound_device_id VARCHAR(255) NULL DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE playlist_access_codes DROP INDEX uq_playlist_code"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE playlist_access_codes ADD UNIQUE KEY uq_playlist_code_device (code, bound_device_id)"); } catch (PDOException $e) {}

        $sql = "CREATE TABLE IF NOT EXISTS playlist_code_devices (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code_id INT NOT NULL,
            device_id VARCHAR(255) NOT NULL,
            device_label VARCHAR(255) DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_playlist_code_device (code_id, device_id),
            KEY idx_pcd_code_id (code_id),
            CONSTRAINT fk_pcd_playlist_code FOREIGN KEY (code_id) REFERENCES playlist_access_codes(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        try {
            $conn->exec($sql);
        } catch (PDOException $e) {
            // بدون مفتاح أجنبي إن فشل (مثلاً محرك قديم)
            $conn->exec("CREATE TABLE IF NOT EXISTS playlist_code_devices (
                id INT AUTO_INCREMENT PRIMARY KEY,
                code_id INT NOT NULL,
                device_id VARCHAR(255) NOT NULL,
                device_label VARCHAR(255) DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_playlist_code_device (code_id, device_id),
                KEY idx_pcd_code_id (code_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        }

        $sql = "CREATE TABLE IF NOT EXISTS device_login_sessions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            device_id VARCHAR(255) NOT NULL,
            code_server_host VARCHAR(500) DEFAULT NULL,
            manual_login_username VARCHAR(255) DEFAULT NULL,
            manual_login_password VARCHAR(1024) DEFAULT NULL,
            account_key VARCHAR(255) DEFAULT NULL,
            account_display_name VARCHAR(255) DEFAULT NULL,
            is_current TINYINT(1) NOT NULL DEFAULT 0,
            source VARCHAR(32) NOT NULL DEFAULT 'app',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_dls_device (device_id),
            KEY idx_dls_device_current (device_id, is_current)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        try {
            $conn->exec($sql);
        } catch (PDOException $e) {}
        try {
            $conn->exec('ALTER TABLE device_login_sessions ADD COLUMN last_login_at TIMESTAMP NULL DEFAULT NULL');
        } catch (PDOException $e) {}

        // محاولات إضافة الأعمدة الجديدة للجداول القديمة (لن ترمي خطأ لو العمود موجود)
        try { $conn->exec("ALTER TABLE settings ADD COLUMN app_name VARCHAR(255) DEFAULT 'Nova IPTV Player'"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN default_server_url VARCHAR(500) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN login_servers TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN auto_activation_enabled TINYINT(1) NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec('ALTER TABLE settings CHANGE COLUMN auto_activation_enabled device_registration TINYINT(1) NOT NULL DEFAULT 1'); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN block_vpn_global TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN piracy_detection_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN piracy_packages TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN piracy_message TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN ads_enabled TINYINT(1) NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN banner_home_only TINYINT(1) NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN banner_ad_unit_android VARCHAR(100) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN banner_ad_unit_ios VARCHAR(100) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN interstitial_ad_unit_android VARCHAR(100) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN interstitial_ad_unit_ios VARCHAR(100) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN admob_app_id_android VARCHAR(120) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN admob_app_id_ios VARCHAR(120) DEFAULT NULL"); } catch (PDOException $e) {}
        // TV AdMob fallback: image and/or HTML page banner (Google Mobile Ads is unreliable on Android TV).
        try { $conn->exec("ALTER TABLE settings ADD COLUMN tv_banner_image_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN tv_banner_click_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN tv_banner_html_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN show_add_change_button TINYINT(1) NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN show_username_login TINYINT(1) NOT NULL DEFAULT 1"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN app_version VARCHAR(50) DEFAULT '1.0.0'"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN support_contact_url VARCHAR(700) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN purchase_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        // Home theme for the Flutter home screen
        try { $conn->exec("ALTER TABLE settings ADD COLUMN home_theme VARCHAR(50) NOT NULL DEFAULT 'original'"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN sync_activation_with_server TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN tmdb_api_key VARCHAR(128) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN subdl_api_key VARCHAR(256) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN opensubtitles_api_key VARCHAR(256) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN opensubtitles_username VARCHAR(128) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN opensubtitles_password VARCHAR(256) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN app_api_secret VARCHAR(128) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN onesignal_app_id VARCHAR(64) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN onesignal_rest_api_key VARCHAR(256) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN onesignal_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN live_tv_promo_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN live_tv_promo_image_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN live_tv_promo_text VARCHAR(500) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN live_tv_promo_link_url VARCHAR(1200) DEFAULT NULL"); } catch (PDOException $e) {}
        // TV Home hero: promo slide + count + movies/series filter
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_promo_enabled TINYINT(1) NOT NULL DEFAULT 0"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_promo_image_url TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_promo_title VARCHAR(255) DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_promo_text TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_promo_link_url TEXT DEFAULT NULL"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_banner_count INT NOT NULL DEFAULT 5"); } catch (PDOException $e) {}
        try { $conn->exec("ALTER TABLE settings ADD COLUMN hero_content_mode VARCHAR(20) NOT NULL DEFAULT 'auto'"); } catch (PDOException $e) {}
        try { ensureHeroSettingsColumns($conn); } catch (Throwable $e) {}

        $conn->exec("CREATE TABLE IF NOT EXISTS push_notifications_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            link_url VARCHAR(1200) DEFAULT NULL,
            target_type ENUM('all', 'device') NOT NULL DEFAULT 'all',
            device_id VARCHAR(255) DEFAULT NULL,
            status ENUM('sent', 'failed', 'scheduled', 'cancelled') NOT NULL DEFAULT 'sent',
            onesignal_id VARCHAR(64) DEFAULT NULL,
            error_message VARCHAR(500) DEFAULT NULL,
            admin_user_id INT DEFAULT NULL,
            scheduled_at DATETIME DEFAULT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_push_log_created (created_at),
            INDEX idx_push_log_device (device_id),
            INDEX idx_push_log_scheduled (scheduled_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        try {
            $conn->exec("ALTER TABLE push_notifications_log ADD COLUMN link_url VARCHAR(1200) DEFAULT NULL AFTER message");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE push_notifications_log ADD COLUMN scheduled_at DATETIME DEFAULT NULL AFTER admin_user_id");
        } catch (PDOException $e) {}
        try {
            $conn->exec("ALTER TABLE push_notifications_log MODIFY COLUMN status ENUM('sent', 'failed', 'scheduled', 'cancelled') NOT NULL DEFAULT 'sent'");
        } catch (PDOException $e) {}

        // إدخال الإعدادات الافتراضية إذا كان الجدول فارغاً
        $stmt = $conn->query("SELECT COUNT(*) FROM settings");
        if ($stmt->fetchColumn() == 0) {
            $sql = "INSERT INTO settings (default_expiry_days, max_devices_per_user, auto_block_expired) VALUES (30, 1, 0)";
            $conn->exec($sql);
        }

        // App API HMAC secret + credential encryption key:
        // تُولَّد تلقائياً عند أول setup (أو عند أول دخول إن نقصت). إعادة التوليد من الإعدادات.
        require_once __DIR__ . '/api_auth.php';
        if (function_exists('app_api_ensure_secret_column')) {
            app_api_ensure_secret_column($conn);
        }
        if (function_exists('app_api_ensure_nonce_table')) {
            app_api_ensure_nonce_table($conn);
        }

        require_once __DIR__ . '/credential_crypto.php';
        if (function_exists('credential_ensure_key_column')) {
            credential_ensure_key_column($conn);
        }
        // Migrate legacy plaintext only when a key is configured.
        if (function_exists('credential_is_configured') && credential_is_configured($conn)
            && function_exists('credential_migrate_plaintext_passwords')) {
            credential_migrate_plaintext_passwords($conn);
        }

        // مستخدمو لوحة التحكم (أدوار وصلاحيات)
        $sql = "CREATE TABLE IF NOT EXISTS admin_users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(64) NOT NULL,
            email VARCHAR(255) DEFAULT NULL,
            password_hash VARCHAR(255) NOT NULL,
            role VARCHAR(32) NOT NULL DEFAULT 'viewer',
            is_active TINYINT(1) NOT NULL DEFAULT 1,
            created_by INT NULL DEFAULT NULL,
            last_login_at DATETIME NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_admin_username (username),
            UNIQUE KEY uq_admin_email (email)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        try {
            $conn->exec("ALTER TABLE admin_users ADD COLUMN created_by INT NULL DEFAULT NULL AFTER is_active");
        } catch (Throwable $e) {}

        // Do NOT seed a default admin password. Buyers create the first
        // super admin via setup.php on first visit (see adminNeedsInitialSetup).

        // صلاحيات قابلة للتخصيص لكل دور (مسؤول / مشرف / عرض فقط) — يعدّلها المسؤول الأعلى من صفحة المسؤولين
        $sql = "CREATE TABLE IF NOT EXISTS admin_role_permissions (
            role VARCHAR(32) NOT NULL,
            permission_key VARCHAR(64) NOT NULL,
            PRIMARY KEY (role, permission_key),
            KEY idx_role_perm_role (role)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
        $conn->exec($sql);

        // Ensure sub-admin and supervisor roles have users_create permission enabled
        try {
            $insPerm = $conn->prepare("INSERT IGNORE INTO admin_role_permissions (role, permission_key) VALUES ('admin', 'users_create'), ('moderator', 'users_create')");
            $insPerm->execute();
        } catch (Throwable $e) {}

        require_once __DIR__ . '/admin_auth.php';
        if (function_exists('adminSeedRolePermissionsIfEmpty')) {
            adminSeedRolePermissionsIfEmpty($conn);
        }

        return true;
    } catch(PDOException $e) {
        return false;
    }
}

// جلب الإعدادات
function settingsTableColumns(PDO $conn, bool $refresh = false): array
{
    static $cache = null;
    if ($refresh) {
        $cache = null;
    }
    if (is_array($cache)) {
        return $cache;
    }
    $cache = [];
    try {
        $stmt = $conn->query('SHOW COLUMNS FROM settings');
        if ($stmt) {
            while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
                $name = strtolower((string) ($row['Field'] ?? ''));
                if ($name !== '') {
                    $cache[$name] = true;
                }
            }
        }
    } catch (PDOException $e) {
        $cache = [];
    }
    return $cache;
}

/** يضمن أعمدة settings الناقصة (مفيد بعد استيراد SQL قديم أو استضافة بلا ALTER سابق). */
function ensureSettingsColumns(PDO $conn): void
{
    static $ran = false;
    $cols = settingsTableColumns($conn);
    $heroMissing = empty($cols['hero_promo_enabled'])
        || empty($cols['hero_promo_image_url'])
        || empty($cols['hero_promo_title'])
        || empty($cols['hero_promo_text'])
        || empty($cols['hero_promo_link_url'])
        || empty($cols['hero_banner_count'])
        || empty($cols['hero_content_mode']);
    if ($ran && !$heroMissing) {
        return;
    }
    $ran = true;
    $alters = [
        "ALTER TABLE settings ADD COLUMN app_name VARCHAR(255) DEFAULT 'Nova IPTV Player'",
        "ALTER TABLE settings ADD COLUMN default_server_url VARCHAR(500) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN login_servers TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN block_vpn_global TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE settings ADD COLUMN piracy_detection_enabled TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE settings ADD COLUMN piracy_packages TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN piracy_message TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN ads_enabled TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN banner_home_only TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN banner_ad_unit_android VARCHAR(100) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN banner_ad_unit_ios VARCHAR(100) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN interstitial_ad_unit_android VARCHAR(100) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN interstitial_ad_unit_ios VARCHAR(100) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN admob_app_id_android VARCHAR(120) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN admob_app_id_ios VARCHAR(120) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN tv_banner_image_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN tv_banner_click_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN tv_banner_html_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN show_add_change_button TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN show_username_login TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN app_version VARCHAR(50) DEFAULT '1.0.0'",
        "ALTER TABLE settings ADD COLUMN support_contact_url VARCHAR(700) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN purchase_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN home_theme VARCHAR(50) NOT NULL DEFAULT 'original'",
        "ALTER TABLE settings ADD COLUMN sync_activation_with_server TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE settings ADD COLUMN tmdb_api_key VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN opensubtitles_api_key VARCHAR(256) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN opensubtitles_username VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN opensubtitles_password VARCHAR(256) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN app_api_secret VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN activation_enforced TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN block_screenshots TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE settings ADD COLUMN privacy_policy_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN privacy_policy_html MEDIUMTEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN about_us_html MEDIUMTEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN privacy_policy_mode VARCHAR(16) NOT NULL DEFAULT 'url'",
        "ALTER TABLE settings ADD COLUMN app_activation_url VARCHAR(1200) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN onesignal_app_id VARCHAR(64) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN onesignal_rest_api_key VARCHAR(256) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN onesignal_enabled TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE settings ADD COLUMN credential_enc_key VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN hero_promo_enabled TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE settings ADD COLUMN hero_promo_image_url TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN hero_promo_title VARCHAR(255) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN hero_promo_text TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN hero_promo_link_url TEXT DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN hero_banner_count INT NOT NULL DEFAULT 5",
        "ALTER TABLE settings ADD COLUMN hero_content_mode VARCHAR(20) NOT NULL DEFAULT 'auto'",
        "ALTER TABLE settings ADD COLUMN xtream_api_url VARCHAR(500) DEFAULT 'https://skypro-app.com:25463'",
        "ALTER TABLE settings ADD COLUMN xtream_api_key VARCHAR(256) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN xtream_api_username VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN xtream_api_password VARCHAR(256) DEFAULT NULL",
        "ALTER TABLE settings ADD COLUMN xtream_api_type VARCHAR(64) NOT NULL DEFAULT 'xtream_codes'",
        "ALTER TABLE settings ADD COLUMN xtream_sync_enabled TINYINT(1) NOT NULL DEFAULT 1",
    ];
    foreach ($alters as $sql) {
        try {
            $conn->exec($sql);
        } catch (PDOException $e) {
            // العمود موجود أو الاستضافة ترفض ALTER — نكمل الباقي
        }
    }
    // تأكيد أعمدة الهيرو بـ TEXT (تجاوز فشل VARCHAR الطويل على بعض الاستضافات).
    ensureHeroSettingsColumns($conn);
    settingsTableColumns($conn, true);
}

function getSettings($conn) {
    ensureSettingsColumns($conn);
    $defaults = [
        'default_expiry_days' => 30,
        'max_devices_per_user' => 1,
        'auto_block_expired' => 0,
        'device_registration' => 1,
        'block_vpn_global' => 0,
        'default_server_url' => null,
        'login_servers' => null,
        'piracy_detection_enabled' => 0,
        'piracy_packages' => null,
        'piracy_message' => null,
        'ads_enabled' => 1,
        'banner_home_only' => 0,
        'banner_ad_unit_android' => null,
        'banner_ad_unit_ios' => null,
        'interstitial_ad_unit_android' => null,
        'interstitial_ad_unit_ios' => null,
        'admob_app_id_android' => null,
        'admob_app_id_ios' => null,
        'tv_banner_image_url' => null,
        'tv_banner_click_url' => null,
        'tv_banner_html_url' => null,
        'show_add_change_button' => 1,
        'show_username_login' => 1,
        'sync_activation_with_server' => 0,
        'app_version' => '1.0.0',
        'app_name' => 'Nova IPTV Player',
        'home_theme' => 'original',
        'support_contact_url' => null,
        'purchase_url' => null,
        'app_activation_url' => null,
        'activation_enforced' => 1,
        'block_screenshots' => 1,
        'privacy_policy_url' => null,
        'privacy_policy_html' => null,
        'privacy_policy_mode' => 'url',
        'about_us_html' => null,
        'tmdb_api_key' => null,
        'opensubtitles_api_key' => null,
        'opensubtitles_username' => null,
        'opensubtitles_password' => null,
        'onesignal_app_id' => null,
        'onesignal_rest_api_key' => null,
        'onesignal_enabled' => 0,
        'live_tv_promo_enabled' => 0,
        'live_tv_promo_image_url' => null,
        'live_tv_promo_text' => null,
        'live_tv_promo_link_url' => null,
        'hero_promo_enabled' => 0,
        'hero_promo_image_url' => null,
        'hero_promo_title' => null,
        'hero_promo_text' => null,
        'hero_promo_link_url' => null,
        'hero_banner_count' => 5,
        'hero_content_mode' => 'auto',
        'xtream_api_url' => 'https://skypro-app.com:25463',
        'xtream_api_key' => '',
        'xtream_api_username' => '',
        'xtream_api_password' => '',
        'xtream_api_type' => 'xtream_codes',
        'xtream_sync_enabled' => 1,
    ];
    try {
        $stmt = $conn->query("SELECT * FROM settings LIMIT 1");
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return is_array($row) ? $row : $defaults;
    } catch(PDOException $e) {
        return $defaults;
    }
}

/**
 * Normalize TV home hero content mode from admin / API.
 */
function hero_content_mode_normalize($raw): string
{
    $mode = strtolower(trim((string) $raw));
    if ($mode === 'movies' || $mode === 'series') {
        return $mode;
    }
    return 'auto';
}

/**
 * يضمن أعمدة هيرو الرئيسية — TEXT للروابط (VARCHAR(1200) يفشل على بعض الاستضافات).
 *
 * @return array<string, bool> اسم العمود => موجود؟
 */
function ensureHeroSettingsColumns(PDO $conn): array
{
    $defs = [
        'hero_promo_enabled' => 'TINYINT(1) NOT NULL DEFAULT 0',
        'hero_promo_image_url' => 'TEXT DEFAULT NULL',
        'hero_promo_title' => 'VARCHAR(255) DEFAULT NULL',
        'hero_promo_text' => 'TEXT DEFAULT NULL',
        'hero_promo_link_url' => 'TEXT DEFAULT NULL',
        'hero_banner_count' => 'INT NOT NULL DEFAULT 5',
        'hero_content_mode' => "VARCHAR(20) NOT NULL DEFAULT 'auto'",
    ];
    $existing = settingsTableColumns($conn, true);
    foreach ($defs as $col => $ddl) {
        if (!empty($existing[strtolower($col)])) {
            // حوّل VARCHAR الضيق إلى TEXT إن وُجد (روابط طويلة).
            if ($col === 'hero_promo_image_url' || $col === 'hero_promo_link_url' || $col === 'hero_promo_text') {
                try {
                    $conn->exec("ALTER TABLE settings MODIFY COLUMN `$col` TEXT DEFAULT NULL");
                } catch (PDOException $e) {
                    // ignore
                }
            }
            continue;
        }
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN `$col` $ddl");
        } catch (PDOException $e) {
            // ignore duplicate / permission
        }
    }
    return settingsTableColumns($conn, true);
}

/**
 * حفظ إعدادات هيرو الرئيسية عموداً بعمود (ما يفشلش الكل بسبب عمود واحد).
 *
 * @param array<string, mixed> $data
 */
function saveHeroSettings(PDO $conn, array $data): bool
{
    $cols = ensureHeroSettingsColumns($conn);
    $enabled = !empty($data['hero_promo_enabled']) ? 1 : 0;
    // أسماء بديلة بدون _url — بعض الجدران النارية تحجب حقول *_url مع https://
    $image = trim((string)($data['hero_promo_image_url'] ?? $data['hero_promo_image'] ?? ''));
    $title = trim((string)($data['hero_promo_title'] ?? ''));
    $text = trim((string)($data['hero_promo_text'] ?? ''));
    $link = trim((string)($data['hero_promo_link_url'] ?? $data['hero_promo_link'] ?? ''));
    $count = max(1, min(10, (int)($data['hero_banner_count'] ?? 5)));
    $mode = hero_content_mode_normalize($data['hero_content_mode'] ?? 'auto');

    $map = [
        'hero_promo_enabled' => $enabled,
        'hero_promo_image_url' => $image !== '' ? $image : null,
        'hero_promo_title' => $title !== '' ? $title : null,
        'hero_promo_text' => $text !== '' ? $text : null,
        'hero_promo_link_url' => $link !== '' ? $link : null,
        'hero_banner_count' => $count,
        'hero_content_mode' => $mode,
    ];

    $okAny = false;
    foreach ($map as $col => $val) {
        if (empty($cols[strtolower($col)])) {
            continue;
        }
        try {
            $stmt = $conn->prepare("UPDATE settings SET `$col` = ?");
            if ($stmt->execute([$val])) {
                $okAny = true;
            }
        } catch (PDOException $e) {
            // جرّب TEXT إن كان العمود ضيقاً
            if ($col === 'hero_promo_image_url' || $col === 'hero_promo_link_url' || $col === 'hero_promo_text') {
                try {
                    $conn->exec("ALTER TABLE settings MODIFY COLUMN `$col` TEXT DEFAULT NULL");
                    $stmt = $conn->prepare("UPDATE settings SET `$col` = ?");
                    if ($stmt->execute([$val])) {
                        $okAny = true;
                    }
                } catch (PDOException $e2) {
                    // ignore
                }
            }
        }
    }
    return $okAny;
}

/**
 * حقول تُرسل للتطبيق مع كل فحص تفعيل (إعلانات، سياسة، فرض الواجهة، إلخ).
 */
function app_panel_public_payload(array $settings): array
{
    $appVersion = trim((string)($settings['app_version'] ?? '1.0.0'));
    if ($appVersion === '') {
        $appVersion = '1.0.0';
    }
    return [
        'ads_enabled' => isset($settings['ads_enabled']) ? (bool)$settings['ads_enabled'] : true,
        'banner_home_only' => isset($settings['banner_home_only']) ? (bool)$settings['banner_home_only'] : false,
        'banner_ad_unit_android' => $settings['banner_ad_unit_android'] ?? '',
        'banner_ad_unit_ios' => $settings['banner_ad_unit_ios'] ?? '',
        'interstitial_ad_unit_android' => $settings['interstitial_ad_unit_android'] ?? '',
        'interstitial_ad_unit_ios' => $settings['interstitial_ad_unit_ios'] ?? '',
        'admob_app_id_android' => $settings['admob_app_id_android'] ?? '',
        'admob_app_id_ios' => $settings['admob_app_id_ios'] ?? '',
        'tv_banner_image_url' => trim((string)($settings['tv_banner_image_url'] ?? '')),
        'tv_banner_click_url' => trim((string)($settings['tv_banner_click_url'] ?? '')),
        'tv_banner_html_url' => trim((string)($settings['tv_banner_html_url'] ?? '')),
        'hero_promo_enabled' => !empty($settings['hero_promo_enabled']),
        'hero_promo_image_url' => trim((string)($settings['hero_promo_image_url'] ?? '')),
        'hero_promo_title' => trim((string)($settings['hero_promo_title'] ?? '')),
        'hero_promo_text' => trim((string)($settings['hero_promo_text'] ?? '')),
        'hero_promo_link_url' => trim((string)($settings['hero_promo_link_url'] ?? '')),
        'hero_banner_count' => max(1, min(10, (int)($settings['hero_banner_count'] ?? 5))),
        'hero_content_mode' => hero_content_mode_normalize($settings['hero_content_mode'] ?? 'auto'),
        'show_add_change_button' => isset($settings['show_add_change_button'])
            ? (bool)$settings['show_add_change_button']
            : true,
        'show_username_login' => isset($settings['show_username_login'])
            ? (bool)$settings['show_username_login']
            : true,
        'app_version' => $appVersion,
        'app_name' => $settings['app_name'] ?? 'Nova IPTV Player',
        'app_activation_url' => trim((string)($settings['app_activation_url'] ?? '')),
        'support_contact_url' => trim((string)($settings['support_contact_url'] ?? '')),
        'purchase_url' => trim((string)($settings['purchase_url'] ?? '')),
        'activation_enforced' => !isset($settings['activation_enforced'])
            ? true
            : ((int) $settings['activation_enforced'] === 1),
        'block_screenshots' => !isset($settings['block_screenshots'])
            ? true
            : ((int) $settings['block_screenshots'] === 1),
        'privacy_policy_url' => trim((string)($settings['privacy_policy_url'] ?? '')),
        'privacy_policy_html' => (string)($settings['privacy_policy_html'] ?? ''),
        'privacy_policy_mode' => (($settings['privacy_policy_mode'] ?? 'url') === 'html') ? 'html' : 'url',
        'about_us_html' => (string)($settings['about_us_html'] ?? ''),
        'tmdb_api_key' => trim((string)($settings['tmdb_api_key'] ?? '')),
        'opensubtitles_api_key' => trim((string)($settings['opensubtitles_api_key'] ?? '')),
        'opensubtitles_username' => trim((string)($settings['opensubtitles_username'] ?? '')),
        'opensubtitles_password' => trim((string)($settings['opensubtitles_password'] ?? '')),
        'default_server_url' => (function() use ($settings) {
            $u = trim((string)($settings['default_server_url'] ?? ''));
            if ($u !== '' && preg_match('~^http://~i', $u) && preg_match('~:(25463|25500|443)/?$~', $u)) {
                $u = preg_replace('~^http://~i', 'https://', $u);
            }
            return $u;
        })(),
        'login_servers' => parse_login_servers_json($settings['login_servers'] ?? null),
        'piracy_detection_enabled' => !empty($settings['piracy_detection_enabled']),
        'piracy_packages' => (string)($settings['piracy_packages'] ?? ''),
        'piracy_message' => (string)($settings['piracy_message'] ?? ''),
        'onesignal_app_id' => trim((string)($settings['onesignal_app_id'] ?? '')),
        'onesignal_enabled' => !empty($settings['onesignal_enabled']),
    ];
}

/**
 * Normalize a reported app version for comparison/storage (strip build suffix).
 * Accepts forms like "1.2.7", "1.2.7+28", "v1.2.7".
 */
function app_normalize_reported_version(string $raw): string
{
    $v = trim($raw);
    if ($v === '') {
        return '';
    }
    if (isset($v[0]) && ($v[0] === 'v' || $v[0] === 'V')) {
        $v = substr($v, 1);
    }
    $v = trim($v);
    if ($v === '') {
        return '';
    }
    // Keep marketing version + optional +build for display; compare on core only.
    if (!preg_match('/^\d+(\.\d+){0,3}(\+[0-9A-Za-z._-]+)?$/', $v)) {
        return '';
    }
    return $v;
}

function app_version_core_for_compare(string $normalized): string
{
    $parts = explode('+', $normalized, 2);
    return $parts[0] !== '' ? $parts[0] : $normalized;
}

/**
 * When the app reports its PackageInfo version, update settings.app_version
 * if the reported marketing version is newer (so old installs cannot roll back).
 */
function maybeUpdateReportedAppVersion(PDO $conn, $reported): bool
{
    $normalized = app_normalize_reported_version((string) $reported);
    if ($normalized === '') {
        return false;
    }
    // Store marketing version only (e.g. 1.2.8), never +build.
    $core = app_version_core_for_compare($normalized);
    if ($core === '') {
        return false;
    }
    try {
        $settings = getSettings($conn);
        $current = app_normalize_reported_version((string) ($settings['app_version'] ?? '1.0.0'));
        if ($current === '') {
            $current = '1.0.0';
        }
        $currentCore = app_version_core_for_compare($current);
        $cmp = version_compare($core, $currentCore);
        if ($cmp < 0) {
            return false;
        }
        if ($cmp === 0 && $core === $currentCore && $current === $core) {
            return false;
        }
        // Same or newer marketing version → refresh stored label without +build.
        return updateSettingsPartial($conn, ['app_version' => $core]);
    } catch (Throwable $e) {
        return false;
    }
}

// تحديث الإعدادات
/**
 * Update only selected settings columns (whitelist). Used by AJAX quick-save.
 *
 * @param array<string, mixed> $patch field => value
 */
function updateSettingsPartial(PDO $conn, array $patch): bool
{
    if (!$patch) {
        return false;
    }
    ensureSettingsColumns($conn);
    $existing = settingsTableColumns($conn, true);

    $intFields = [
        'default_expiry_days', 'max_devices_per_user', 'auto_block_expired',
        'block_vpn_global', 'piracy_detection_enabled', 'ads_enabled', 'banner_home_only',
        'sync_activation_with_server', 'activation_enforced',
        'block_screenshots', 'onesignal_enabled',
        'hero_promo_enabled', 'hero_banner_count',
        'xtream_sync_enabled',
    ];
    $stringFields = [
        'default_server_url', 'login_servers', 'piracy_packages', 'piracy_message',
        'banner_ad_unit_android', 'banner_ad_unit_ios',
        'interstitial_ad_unit_android', 'interstitial_ad_unit_ios',
        'admob_app_id_android', 'admob_app_id_ios',
        'tv_banner_image_url', 'tv_banner_click_url', 'tv_banner_html_url',
        'hero_promo_image_url', 'hero_promo_title', 'hero_promo_text', 'hero_promo_link_url',
        'hero_content_mode',
        'app_version', 'app_name', 'app_activation_url', 'support_contact_url', 'purchase_url',
        'privacy_policy_url', 'privacy_policy_html', 'privacy_policy_mode', 'about_us_html',
        'tmdb_api_key', 'opensubtitles_api_key', 'opensubtitles_username', 'opensubtitles_password',
        'onesignal_app_id', 'onesignal_rest_api_key',
        'xtream_api_url', 'xtream_api_key', 'xtream_api_username', 'xtream_api_password', 'xtream_api_type',
    ];
    $allowed = array_merge($intFields, $stringFields);

    // إن نقص عمود hero رغم ensure — حاول إضافته فوراً ثم أعد قراءة الأعمدة.
    $heroAlters = [
        'hero_promo_enabled' => "ALTER TABLE settings ADD COLUMN hero_promo_enabled TINYINT(1) NOT NULL DEFAULT 0",
        'hero_promo_image_url' => "ALTER TABLE settings ADD COLUMN hero_promo_image_url TEXT DEFAULT NULL",
        'hero_promo_title' => "ALTER TABLE settings ADD COLUMN hero_promo_title VARCHAR(255) DEFAULT NULL",
        'hero_promo_text' => "ALTER TABLE settings ADD COLUMN hero_promo_text TEXT DEFAULT NULL",
        'hero_promo_link_url' => "ALTER TABLE settings ADD COLUMN hero_promo_link_url TEXT DEFAULT NULL",
        'hero_banner_count' => "ALTER TABLE settings ADD COLUMN hero_banner_count INT NOT NULL DEFAULT 5",
        'hero_content_mode' => "ALTER TABLE settings ADD COLUMN hero_content_mode VARCHAR(20) NOT NULL DEFAULT 'auto'",
    ];
    $needRefresh = false;
    foreach ($patch as $key => $_) {
        if (!is_string($key) || !isset($heroAlters[$key])) {
            continue;
        }
        if (!empty($existing[strtolower($key)])) {
            continue;
        }
        try {
            $conn->exec($heroAlters[$key]);
            $needRefresh = true;
        } catch (PDOException $e) {
            // ignore duplicate / permission
        }
    }
    if ($needRefresh) {
        $existing = settingsTableColumns($conn, true);
    }

    $sets = [];
    $vals = [];
    foreach ($patch as $key => $value) {
        if (!is_string($key) || !in_array($key, $allowed, true)) {
            continue;
        }
        if (empty($existing[strtolower($key)])) {
            continue;
        }
        if (in_array($key, $intFields, true)) {
            if ($key === 'hero_banner_count') {
                $sets[] = "`$key` = ?";
                $vals[] = max(1, min(10, (int) $value));
                continue;
            }
            $sets[] = "`$key` = ?";
            $vals[] = (int) $value;
            continue;
        }
        if ($key === 'hero_content_mode') {
            $sets[] = '`hero_content_mode` = ?';
            $vals[] = hero_content_mode_normalize($value);
            continue;
        }
        if ($key === 'privacy_policy_mode') {
            $mode = ((string) $value === 'html') ? 'html' : 'url';
            $sets[] = '`privacy_policy_mode` = ?';
            $vals[] = $mode;
            continue;
        }
        if ($key === 'piracy_packages') {
            $norm = normalizePiracyPackagesText($value);
            $sets[] = '`piracy_packages` = ?';
            $vals[] = $norm !== '' ? $norm : null;
            continue;
        }
        if ($key === 'app_name') {
            $t = trim((string) $value);
            $sets[] = '`app_name` = ?';
            $vals[] = $t !== '' ? $t : 'Nova IPTV Player';
            continue;
        }
        if ($key === 'app_version') {
            $t = trim((string) $value);
            $sets[] = '`app_version` = ?';
            $vals[] = $t !== '' ? $t : '1.0.0';
            continue;
        }
        $t = trim((string) $value);
        $sets[] = "`$key` = ?";
        $vals[] = $t !== '' ? $t : null;
    }

    if (!$sets) {
        return false;
    }

    try {
        $sql = 'UPDATE settings SET ' . implode(', ', $sets);
        $stmt = $conn->prepare($sql);
        return $stmt->execute($vals);
    } catch (PDOException $e) {
        return false;
    }
}

function updateSettings(
    $conn,
    $default_expiry_days,
    $max_devices_per_user,
    $auto_block_expired,
    $block_vpn_global = 0,
    $default_server_url = null,
    $piracy_detection_enabled = 0,
    $piracy_packages = null,
    $piracy_message = null,
    $ads_enabled = 1,
    $banner_home_only = 1,
    $banner_ad_unit_android = null,
    $banner_ad_unit_ios = null,
    $interstitial_ad_unit_android = null,
    $interstitial_ad_unit_ios = null,
    $show_add_change_button = 1,
    $show_username_login = 1,
    $sync_activation_with_server = 0,
    $app_version = '1.0.0',
    $app_name = null,
    $app_activation_url = null,
    $support_contact_url = null,
    $purchase_url = null,
    $activation_enforced = 1,
    $privacy_policy_url = null,
    $privacy_policy_html = null,
    $privacy_policy_mode = 'url',
    $about_us_html = null,
    $tmdb_api_key = null,
    $opensubtitles_api_key = null,
    $opensubtitles_username = null,
    $opensubtitles_password = null,
    $block_screenshots = 1
) {
    $mode = ($privacy_policy_mode === 'html') ? 'html' : 'url';
    if ($mode === 'url') {
        $privacy_policy_html = null;
    } else {
        $privacy_policy_url = null;
    }
    ensureSettingsColumns($conn);
    $existing = settingsTableColumns($conn);
    $map = [
        'default_expiry_days' => (int) $default_expiry_days,
        'max_devices_per_user' => (int) $max_devices_per_user,
        'auto_block_expired' => (int) $auto_block_expired,
        'block_vpn_global' => (int) $block_vpn_global,
        'default_server_url' => $default_server_url ? trim($default_server_url) : null,
        'piracy_detection_enabled' => (int) $piracy_detection_enabled,
        'piracy_packages' => $piracy_packages,
        'piracy_message' => $piracy_message ? trim($piracy_message) : null,
        'ads_enabled' => (int) $ads_enabled,
        'banner_home_only' => (int) $banner_home_only,
        'banner_ad_unit_android' => $banner_ad_unit_android ?: null,
        'banner_ad_unit_ios' => $banner_ad_unit_ios ?: null,
        'interstitial_ad_unit_android' => $interstitial_ad_unit_android ?: null,
        'interstitial_ad_unit_ios' => $interstitial_ad_unit_ios ?: null,
        'show_add_change_button' => (int) $show_add_change_button,
        'show_username_login' => (int) $show_username_login,
        'sync_activation_with_server' => (int) $sync_activation_with_server,
        'app_version' => $app_version ? trim($app_version) : '1.0.0',
        'app_name' => $app_name ? trim($app_name) : 'Nova IPTV Player',
        'app_activation_url' => $app_activation_url ? trim($app_activation_url) : null,
        'support_contact_url' => $support_contact_url ? trim($support_contact_url) : null,
        'purchase_url' => $purchase_url ? trim($purchase_url) : null,
        'activation_enforced' => (int) $activation_enforced,
        'privacy_policy_url' => $privacy_policy_url !== null && trim((string) $privacy_policy_url) !== '' ? trim((string) $privacy_policy_url) : null,
        'privacy_policy_html' => $privacy_policy_html !== null && trim((string) $privacy_policy_html) !== '' ? trim((string) $privacy_policy_html) : null,
        'privacy_policy_mode' => $mode,
        'about_us_html' => $about_us_html !== null && trim((string) $about_us_html) !== '' ? trim((string) $about_us_html) : null,
        'tmdb_api_key' => $tmdb_api_key !== null && trim((string) $tmdb_api_key) !== '' ? trim((string) $tmdb_api_key) : null,
        'opensubtitles_api_key' => $opensubtitles_api_key !== null && trim((string) $opensubtitles_api_key) !== '' ? trim((string) $opensubtitles_api_key) : null,
        'opensubtitles_username' => $opensubtitles_username !== null && trim((string) $opensubtitles_username) !== '' ? trim((string) $opensubtitles_username) : null,
        'opensubtitles_password' => $opensubtitles_password !== null && trim((string) $opensubtitles_password) !== '' ? trim((string) $opensubtitles_password) : null,
        'block_screenshots' => (int) $block_screenshots,
    ];
    $sets = [];
    $vals = [];
    foreach ($map as $col => $val) {
        if (empty($existing[strtolower($col)])) {
            continue;
        }
        $sets[] = "`$col` = ?";
        $vals[] = $val;
    }
    if (!$sets) {
        return false;
    }
    try {
        $stmt = $conn->prepare('UPDATE settings SET ' . implode(', ', $sets));
        return $stmt->execute($vals);
    } catch (PDOException $e) {
        return false;
    }
}

function normalize_login_server_url(string $url): ?string
{
    $url = trim($url);
    if ($url === '') {
        return null;
    }
    if (!preg_match('#^https?://#i', $url)) {
        $url = 'http://' . $url;
    }
    $parts = parse_url($url);
    if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
        return null;
    }
    $scheme = strtolower((string) $parts['scheme']);
    if ($scheme !== 'http' && $scheme !== 'https') {
        return null;
    }
    $host = strtolower((string) $parts['host']);
    if ($host === '') {
        return null;
    }
    $validHost = false;
    if (filter_var($host, FILTER_VALIDATE_IP)) {
        $validHost = true;
    } elseif ($host === 'localhost') {
        $validHost = true;
    } elseif (preg_match('/^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i', $host)) {
        $validHost = true;
    }
    if (!$validHost) {
        return null;
    }
    $port = isset($parts['port']) ? (int) $parts['port'] : 0;
    if ($port < 0 || $port > 65535) {
        return null;
    }
    $out = $scheme . '://' . $parts['host'];
    if (!empty($parts['port'])) {
        $out .= ':' . $parts['port'];
    }
    $path = isset($parts['path']) ? (string) $parts['path'] : '';
    if ($path !== '' && $path !== '/') {
        $out .= rtrim($path, '/');
    }
    return $out;
}

function parse_login_servers_json($raw): array
{
    if (is_array($raw)) {
        $decoded = $raw;
    } else {
        $decoded = json_decode((string) $raw, true);
    }
    if (!is_array($decoded)) {
        return [];
    }
    $out = [];
    foreach ($decoded as $row) {
        if (!is_array($row)) {
            continue;
        }
        $name = trim((string) ($row['name'] ?? ''));
        $url = trim((string) ($row['url'] ?? ''));
        $url = normalize_login_server_url($url) ?? '';
        if ($url === '') {
            continue;
        }
        if ($name === '') {
            $name = $url;
        }
        $out[] = ['name' => $name, 'url' => $url];
    }
    return $out;
}

function login_servers_for_settings(array $settings): array
{
    $list = parse_login_servers_json($settings['login_servers'] ?? null);
    if ($list) {
        return $list;
    }
    $fallback = trim((string) ($settings['default_server_url'] ?? ''));
    $fallback = normalize_login_server_url($fallback);
    if ($fallback) {
        return [['name' => 'Server 1', 'url' => $fallback]];
    }
    return [];
}

function login_servers_from_post(array $post): array
{
    $names = $post['login_server_name'] ?? [];
    $urls = $post['login_server_url'] ?? [];
    if (!is_array($names)) {
        $names = [];
    }
    if (!is_array($urls)) {
        $urls = [];
    }
    $out = [];
    $n = max(count($names), count($urls));
    for ($i = 0; $i < $n; $i++) {
        $name = trim((string) ($names[$i] ?? ''));
        $url = trim((string) ($urls[$i] ?? ''));
        if ($name === '' && $url === '') {
            continue;
        }
        if ($url === '') {
            return [
                'ok' => false,
                'servers' => [],
                'error' => function_exists('t')
                    ? t('settings.login_server_url_invalid')
                    : 'Invalid server URL',
            ];
        }
        $normalized = normalize_login_server_url($url);
        if ($normalized === null) {
            return [
                'ok' => false,
                'servers' => [],
                'error' => function_exists('t')
                    ? t('settings.login_server_url_invalid')
                    : 'Invalid server URL',
            ];
        }
        if ($name === '') {
            $name = 'Server ' . (count($out) + 1);
        }
        $out[] = ['name' => $name, 'url' => $normalized];
    }
    return ['ok' => true, 'servers' => $out, 'error' => ''];
}

function save_login_servers(PDO $conn, array $servers): bool
{
    $json = json_encode($servers, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        $json = '[]';
    }
    try {
        $stmt = $conn->prepare('UPDATE settings SET login_servers = ?');
        return $stmt->execute([$json]);
    } catch (PDOException $e) {
        return false;
    }
}

/**
 * SkyPro Customer / Line Management Helpers
 */
function syncExpiredCustomers(PDO $conn): void
{
    try {
        $stmt = $conn->prepare("UPDATE iptv_customers SET status = 'expired' WHERE status = 'active' AND expiry_date < NOW()");
        $stmt->execute();
    } catch (Throwable $e) {}
}

function syncCustomersWithActivatedDevices(PDO $conn): void
{
    try {
        $st = $conn->query("SELECT id, device_id, device_name, account_key, manual_login_username, manual_login_password, account_display_name, expiry_date, status FROM activated_devices WHERE (status IS NULL OR status <> 'deleted')");
        $rows = $st ? $st->fetchAll(PDO::FETCH_ASSOC) : [];
        if (!$rows) return;

        $checkStmt = $conn->prepare("SELECT id FROM iptv_customers WHERE username = ? LIMIT 1");
        $insStmt = $conn->prepare("INSERT INTO iptv_customers (username, password, customer_name, expiry_date, status, server_sync_status, server_sync_message) VALUES (?, ?, ?, ?, ?, 'synced', 'Auto-imported from active device line')");

        foreach ($rows as $r) {
            $ak = trim((string)($r['account_key'] ?? ''));
            $manualUser = trim((string)($r['manual_login_username'] ?? ''));
            $dispName = trim((string)($r['account_display_name'] ?? ''));
            $pass = trim((string)($r['manual_login_password'] ?? ''));
            if ($pass === '') $pass = '123456';

            $uname = '';
            if ($manualUser !== '') {
                $uname = $manualUser;
            } elseif ($ak !== '') {
                if (strpos($ak, '#') !== false) {
                    $parts = explode('#', $ak, 2);
                    $uname = ($parts[0] !== 'url') ? $parts[0] : '';
                } elseif (strpos($ak, ':') !== false) {
                    $uname = explode(':', $ak, 2)[0];
                } else {
                    $uname = $ak;
                }
            } elseif ($dispName !== '') {
                $uname = $dispName;
            }

            $uname = trim($uname);
            if ($uname === '') continue;

            $checkStmt->execute([$uname]);
            if (!$checkStmt->fetch()) {
                $cname = $dispName !== '' ? $dispName : (trim((string)($r['device_name'] ?? '')) ?: $uname);
                $exp = !empty($r['expiry_date']) ? $r['expiry_date'] : date('Y-m-d H:i:s', strtotime('+30 days'));
                $devStatus = strtolower(trim((string)($r['status'] ?? 'active')));
                $custStatus = ($devStatus === 'blocked') ? 'disabled' : (($devStatus === 'expired') ? 'expired' : 'active');
                $insStmt->execute([$uname, $pass, $cname, $exp, $custStatus]);
            }
        }
    } catch (Throwable $e) {}
}

function getCustomers(PDO $conn, string $filter = '', string $search = '', ?int $resellerId = null): array
{
    syncExpiredCustomers($conn);
    syncCustomersWithActivatedDevices($conn);

    // Strict Data Isolation: Supervisors see their own customers + their registered resellers' customers. Resellers see only their customers.
    $allowedCreatorIds = null;
    if ($resellerId !== null && $resellerId > 0) {
        $allowedCreatorIds = [$resellerId];
    } else {
        $allowedCreatorIds = adminGetAllowedCustomerCreatorIds($conn);
    }

    try {
        $sql = "SELECT c.*, 
                       u.username AS creator_username,
                       d.last_seen_at AS device_last_seen,
                       d.watching_type,
                       d.watching_title,
                       d.watching_updated_at,
                       d.device_name,
                       d.device_id,
                       d.device_status,
                       (CASE 
                           WHEN d.last_seen_at IS NOT NULL AND TIMESTAMPDIFF(SECOND, d.last_seen_at, NOW()) <= 90 THEN 1 
                           ELSE 0 
                        END) AS is_online,
                       (CASE 
                           WHEN d.watching_title IS NOT NULL 
                                AND d.watching_title <> '' 
                                AND d.watching_updated_at IS NOT NULL 
                                AND TIMESTAMPDIFF(SECOND, d.watching_updated_at, NOW()) <= 90 THEN 1 
                           ELSE 0 
                        END) AS is_streaming
                FROM iptv_customers c
                LEFT JOIN admin_users u ON c.created_by = u.id
                LEFT JOIN (
                    SELECT 
                        CASE 
                            WHEN manual_login_username IS NOT NULL AND manual_login_username <> '' THEN manual_login_username
                            WHEN account_key IS NOT NULL AND account_key LIKE '%#%' THEN SUBSTRING_INDEX(account_key, '#', 1)
                            WHEN account_display_name IS NOT NULL AND account_display_name <> '' THEN account_display_name
                            ELSE ''
                        END AS match_user,
                        device_id,
                        device_name,
                        status AS device_status,
                        watching_type,
                        watching_title,
                        watching_updated_at,
                        MAX(last_seen_at) AS last_seen_at
                    FROM activated_devices
                    WHERE status IS NULL OR status <> 'deleted'
                    GROUP BY match_user
                ) d ON (d.match_user = c.username)
                WHERE 1=1";

        $params = [];
        if ($allowedCreatorIds !== null) {
            if (empty($allowedCreatorIds)) {
                $sql .= " AND 1=0";
            } else {
                $placeholders = implode(',', array_fill(0, count($allowedCreatorIds), '?'));
                $sql .= " AND c.created_by IN ($placeholders)";
                foreach ($allowedCreatorIds as $aid) {
                    $params[] = (int)$aid;
                }
            }
        }

        if ($filter === 'active') {
            $sql .= " AND c.status = 'active'";
        } elseif ($filter === 'expired') {
            $sql .= " AND c.status = 'expired'";
        } elseif ($filter === 'disabled' || $filter === 'blocked') {
            $sql .= " AND (c.status = 'disabled' OR c.status = 'blocked')";
        } elseif ($filter === 'online') {
            $sql .= " AND d.last_seen_at IS NOT NULL AND TIMESTAMPDIFF(SECOND, d.last_seen_at, NOW()) <= 90";
        } elseif ($filter === 'streaming') {
            $sql .= " AND d.watching_title IS NOT NULL AND d.watching_title <> '' AND d.watching_updated_at IS NOT NULL AND TIMESTAMPDIFF(SECOND, d.watching_updated_at, NOW()) <= 90";
        }

        if ($search !== '') {
            $sql .= " AND (c.username LIKE ? OR c.customer_name LIKE ? OR c.email LIKE ? OR c.phone LIKE ?)";
            $q = '%' . $search . '%';
            $params[] = $q;
            $params[] = $q;
            $params[] = $q;
            $params[] = $q;
        }

        $sql .= " ORDER BY is_streaming DESC, is_online DESC, c.id DESC";
        $stmt = $conn->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
        try {
            if ($allowedCreatorIds !== null) {
                if (empty($allowedCreatorIds)) return [];
                $placeholders = implode(',', array_fill(0, count($allowedCreatorIds), '?'));
                $stmt = $conn->prepare("SELECT * FROM iptv_customers WHERE created_by IN ($placeholders) ORDER BY id DESC");
                $stmt->execute(array_map('intval', $allowedCreatorIds));
                return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
            }
            $stmt = $conn->query("SELECT * FROM iptv_customers ORDER BY id DESC");
            return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        } catch (Throwable $e2) {
            return [];
        }
    }
}

function getCustomerById(PDO $conn, int $id, bool $enforceResellerScope = true): ?array
{
    try {
        $stmt = $conn->prepare("SELECT c.*, u.username AS creator_username 
            FROM iptv_customers c 
            LEFT JOIN admin_users u ON c.created_by = u.id 
            WHERE c.id = ? LIMIT 1");
        $stmt->execute([$id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
        if (!$row) {
            return null;
        }
        if ($enforceResellerScope && !empty($_SESSION['admin_user_id'])) {
            $allowedIds = adminGetAllowedCustomerCreatorIds($conn);
            if ($allowedIds !== null) {
                $custCreatorId = (int)($row['created_by'] ?? 0);
                if (!in_array($custCreatorId, $allowedIds, true)) {
                    return null;
                }
            }
        }
        return $row;
    } catch (Throwable $e) {
        return null;
    }
}

function addCustomer(PDO $conn, array $data): array
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) {
        return ['success' => false, 'message' => 'Read-only access: Viewers cannot create customers.'];
    }

    $username = trim((string)($data['username'] ?? ''));
    $password = (string)($data['password'] ?? '');
    $customerName = trim((string)($data['customer_name'] ?? ''));
    $email = trim((string)($data['email'] ?? ''));
    $phone = trim((string)($data['phone'] ?? ''));
    $expiryDate = (string)($data['expiry_date'] ?? '');
    $maxConnections = max(1, (int)($data['max_connections'] ?? 1));
    $packageName = trim((string)($data['package_name'] ?? 'Standard'));
    $notes = trim((string)($data['notes'] ?? ''));
    $createdBy = isset($_SESSION['admin_user_id']) ? (int)$_SESSION['admin_user_id'] : null;

    if ($username === '' || $password === '' || $expiryDate === '') {
        return ['success' => false, 'message' => 'Username, password and expiry date are required.'];
    }

    try {
        $check = $conn->prepare("SELECT id FROM iptv_customers WHERE username = ? LIMIT 1");
        $check->execute([$username]);
        if ($check->fetch()) {
            return ['success' => false, 'message' => 'A customer with this username already exists.'];
        }

        $ins = $conn->prepare("INSERT INTO iptv_customers (username, password, customer_name, email, phone, expiry_date, max_connections, package_name, notes, created_by, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')");
        $ins->execute([$username, $password, $customerName ?: null, $email ?: null, $phone ?: null, $expiryDate, $maxConnections, $packageName, $notes ?: null, $createdBy]);
        $newId = (int)$conn->lastInsertId();

        // Sync with Xtream Codes IPTV streaming server
        require_once __DIR__ . '/xtream_api.php';
        $syncResult = xtream_create_line($conn, [
            'username' => $username,
            'password' => $password,
            'expiry_date' => $expiryDate,
            'max_connections' => $maxConnections,
            'notes' => $customerName ?: $notes,
        ]);

        $syncStatus = $syncResult['synced'] ? 'synced' : 'pending';
        $syncMsg = $syncResult['message'] ?? '';
        $upd = $conn->prepare("UPDATE iptv_customers SET server_sync_status = ?, server_sync_message = ? WHERE id = ?");
        $upd->execute([$syncStatus, $syncMsg, $newId]);

        return [
            'success' => true,
            'id' => $newId,
            'synced' => $syncResult['synced'] ?? false,
            'sync_message' => $syncMsg,
        ];
    } catch (Throwable $e) {
        return ['success' => false, 'message' => 'Database error: ' . $e->getMessage()];
    }
}

function updateCustomer(PDO $conn, int $id, array $data): array
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) {
        return ['success' => false, 'message' => 'Read-only access: Viewers cannot edit customers.'];
    }

    try {
        $c = getCustomerById($conn, $id);
        if (!$c) {
            return ['success' => false, 'message' => 'Customer not found or outside your authorized scope.'];
        }

        $customerName = trim((string)($data['customer_name'] ?? $c['customer_name'] ?? ''));
        $email = trim((string)($data['email'] ?? $c['email'] ?? ''));
        $phone = trim((string)($data['phone'] ?? $c['phone'] ?? ''));
        $password = (string)($data['password'] ?? '');
        $newPass = ($password !== '') ? $password : $c['password'];
        $maxConnections = max(1, (int)($data['max_connections'] ?? $c['max_connections'] ?? 1));
        $packageName = trim((string)($data['package_name'] ?? $c['package_name'] ?? 'Standard'));
        $notes = trim((string)($data['notes'] ?? $c['notes'] ?? ''));
        $expiryDate = trim((string)($data['expiry_date'] ?? $c['expiry_date'] ?? ''));
        if ($expiryDate === '') {
            $expiryDate = $c['expiry_date'];
        }

        $stmt = $conn->prepare("UPDATE iptv_customers 
            SET customer_name = ?, email = ?, phone = ?, password = ?, max_connections = ?, package_name = ?, notes = ?, expiry_date = ? 
            WHERE id = ?");
        $stmt->execute([
            $customerName ?: null,
            $email ?: null,
            $phone ?: null,
            $newPass,
            $maxConnections,
            $packageName,
            $notes ?: null,
            $expiryDate,
            $id
        ]);

        // Sync updated credentials/line with streaming server
        require_once __DIR__ . '/xtream_api.php';
        $syncResult = xtream_create_line($conn, [
            'username' => $c['username'],
            'password' => $newPass,
            'expiry_date' => $expiryDate,
            'max_connections' => $maxConnections,
            'notes' => $customerName ?: $notes,
        ]);

        $syncStatus = $syncResult['synced'] ? 'synced' : 'pending';
        $syncMsg = $syncResult['message'] ?? '';
        $upd = $conn->prepare("UPDATE iptv_customers SET server_sync_status = ?, server_sync_message = ? WHERE id = ?");
        $upd->execute([$syncStatus, $syncMsg, $id]);

        return [
            'success' => true,
            'synced' => (bool)($syncResult['synced'] ?? false),
            'sync_message' => $syncMsg,
        ];
    } catch (Throwable $e) {
        return ['success' => false, 'message' => 'Database error: ' . $e->getMessage()];
    }
}

function extendCustomer(PDO $conn, int $id, int $days): bool
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) return false;
    try {
        $c = getCustomerById($conn, $id);
        if (!$c) return false;
        $curExp = strtotime((string)$c['expiry_date']);
        $base = ($curExp && $curExp > time()) ? $curExp : time();
        $newExp = date('Y-m-d H:i:s', $base + ($days * 86400));
        $stmt = $conn->prepare("UPDATE iptv_customers SET expiry_date = ?, status = 'active' WHERE id = ?");
        $res = $stmt->execute([$newExp, $id]);

        // Auto sync updated expiry date with streaming server
        if ($res) {
            require_once __DIR__ . '/xtream_api.php';
            xtream_create_line($conn, [
                'username' => $c['username'],
                'password' => $c['password'],
                'expiry_date' => $newExp,
                'max_connections' => (int)($c['max_connections'] ?? 1),
                'notes' => $c['customer_name'] ?: ($c['notes'] ?? ''),
            ]);
        }
        return $res;
    } catch (Throwable $e) {
        return false;
    }
}

function deleteCustomer(PDO $conn, int $id): bool
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) return false;
    try {
        $c = getCustomerById($conn, $id);
        if (!$c) return false;
        $username = trim((string)$c['username']);
        $stmt = $conn->prepare("DELETE FROM iptv_customers WHERE id = ?");
        $res = $stmt->execute([$id]);

        if ($username !== '') {
            $likeUser = $username . '#%';
            $stmtDev = $conn->prepare("DELETE FROM activated_devices 
                WHERE account_display_name = ? 
                   OR manual_login_username = ? 
                   OR account_key LIKE ? 
                   OR account_key = ?");
            $stmtDev->execute([$username, $username, $likeUser, $username]);
        }
        return $res;
    } catch (Throwable $e) {
        return false;
    }
}

function blockCustomer(PDO $conn, int $id): bool
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) return false;
    try {
        $c = getCustomerById($conn, $id);
        if (!$c) return false;
        $username = trim((string)$c['username']);
        $stmt = $conn->prepare("UPDATE iptv_customers SET status = 'disabled' WHERE id = ?");
        $res = $stmt->execute([$id]);

        if ($username !== '') {
            $likeUser = $username . '#%';
            $stmtDev = $conn->prepare("UPDATE activated_devices 
                SET status = 'blocked' 
                WHERE account_display_name = ? 
                   OR manual_login_username = ? 
                   OR account_key LIKE ? 
                   OR account_key = ?");
            $stmtDev->execute([$username, $username, $likeUser, $username]);
        }
        return $res;
    } catch (Throwable $e) {
        return false;
    }
}

function unblockCustomer(PDO $conn, int $id): bool
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) return false;
    try {
        $c = getCustomerById($conn, $id);
        if (!$c) return false;
        $username = trim((string)$c['username']);
        $stmt = $conn->prepare("UPDATE iptv_customers SET status = 'active' WHERE id = ?");
        $res = $stmt->execute([$id]);

        if ($username !== '') {
            $likeUser = $username . '#%';
            $stmtDev = $conn->prepare("UPDATE activated_devices 
                SET status = 'active' 
                WHERE account_display_name = ? 
                   OR manual_login_username = ? 
                   OR account_key LIKE ? 
                   OR account_key = ?");
            $stmtDev->execute([$username, $username, $likeUser, $username]);
        }
        return $res;
    } catch (Throwable $e) {
        return false;
    }
}

function toggleCustomerStatus(PDO $conn, int $id): bool
{
    if (function_exists('adminIsGuestRole') && adminIsGuestRole()) return false;
    $c = getCustomerById($conn, $id);
    if (!$c) return false;
    if ($c['status'] === 'disabled' || $c['status'] === 'blocked') {
        return unblockCustomer($conn, $id);
    } else {
        return blockCustomer($conn, $id);
    }
}