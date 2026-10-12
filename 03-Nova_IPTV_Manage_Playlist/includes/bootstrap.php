<?php
/**
 * Bootstrap لموقع Manage Playlist — مستقل تماماً عن لوحة التحكم.
 * يشارك نفس قاعدة البيانات فقط (عبر config/database.php).
 */
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/playlist_codes.php';

/**
 * ترحيل الجداول/الأعمدة اللازمة لهذا الموقع فقط (بدون تحميل ملفات اللوحة).
 */
function mp_ensure_web_manage_columns(PDO $pdo, string $table): void
{
    $cols = [
        'web_manage_code VARCHAR(12) DEFAULT NULL',
        'web_manage_code_updated_at DATETIME NULL',
        'web_manage_unlocked_at DATETIME NULL',
        'web_manage_unlocked_fp VARCHAR(64) DEFAULT NULL',
        'web_manage_code_months INT NULL DEFAULT NULL',
    ];
    foreach ($cols as $col) {
        try {
            $pdo->exec('ALTER TABLE `' . str_replace('`', '', $table) . '` ADD COLUMN ' . $col);
        } catch (PDOException $e) {
        }
    }
}

function mp_ensure_schema(PDO $conn): void
{
    mp_ensure_web_manage_columns($conn, 'activated_devices');
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

    global $conn_stv;
    if (isset($conn_stv) && $conn_stv instanceof PDO) {
        mp_ensure_web_manage_columns($conn_stv, 'devices');
    }
}

function mp_get_settings(PDO $conn): array
{
    try {
        $stmt = $conn->query('SELECT app_name, support_contact_url FROM settings LIMIT 1');
        $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
        if (is_array($row)) {
            return $row;
        }
    } catch (PDOException $e) {}
    return [
        'app_name' => 'Nova IPTV Player',
        'support_contact_url' => null,
    ];
}

mp_ensure_schema($conn);
mp_ensure_playlist_access_schema($conn);

$mpSettings = mp_get_settings($conn);
$mpAppName = trim((string)($mpSettings['app_name'] ?? 'Nova IPTV Player'));
if ($mpAppName === '') {
    $mpAppName = 'Nova IPTV Player';
}
$mpSupportUrl = trim((string)($mpSettings['support_contact_url'] ?? ''));

require_once __DIR__ . '/i18n.php';

function mp_normalize_device_id(string $raw): string
{
    // Remove invisible chars from copy/paste
    $id = trim($raw);
    $id = preg_replace('/[\x{200B}-\x{200D}\x{FEFF}]/u', '', $id) ?? $id;
    $id = preg_replace('/\s+/u', '', $id) ?? $id;
    return trim($id);
}

function mp_normalize_code(string $raw): string
{
    $code = strtoupper(trim($raw));
    $code = preg_replace('/[^A-Z0-9]/', '', $code) ?? '';
    return substr($code, 0, 12);
}

/** مدد الصلاحية المسموحة لكود التفعيل (بالأشهر). */
function mp_allowed_code_months(): array
{
    return [1, 3, 6, 12, 24, 0];
}

function mp_duration_is_lifetime(int $months): bool
{
    return $months === 0;
}

function mp_normalize_code_months($raw): int
{
    $months = (int)$raw;
    return in_array($months, mp_allowed_code_months(), true) ? $months : 1;
}

function mp_lifetime_expiry_date(): string
{
    return '2099-12-31 23:59:59';
}

/**
 * Lifetime: سنة ≥ 2090، أو (Smart TV فقط) تاريخ فارغ / 0000-00-00 مثل لوحة smartnova.
 */
function mp_expiry_is_lifetime($expiryDate, ?array $device = null): bool
{
    $raw = trim((string)$expiryDate);
    if ($raw === '' || $raw === '0000-00-00' || $raw === '0000-00-00 00:00:00' || strcasecmp($raw, 'null') === 0) {
        return $device !== null && mp_device_source($device) === 'smarttv';
    }
    $ts = is_numeric($raw) ? (int)$raw : strtotime($raw);
    if (!$ts) {
        return false;
    }
    return ((int) date('Y', $ts)) >= 2090;
}

function mp_device_source(?array $device): string
{
    return (string)($device['_mp_source'] ?? 'flutter');
}

function mp_device_table(?array $device): string
{
    return mp_device_source($device) === 'smarttv' ? 'devices' : 'activated_devices';
}

function mp_device_pdo(?array $device): ?PDO
{
    global $conn, $conn_stv;
    if (mp_device_source($device) === 'smarttv') {
        return (isset($conn_stv) && $conn_stv instanceof PDO) ? $conn_stv : null;
    }
    return (isset($conn) && $conn instanceof PDO) ? $conn : null;
}

function mp_tag_device_row(array $row, string $source): array
{
    $row['_mp_source'] = $source;
    $row['_mp_table'] = $source === 'smarttv' ? 'devices' : 'activated_devices';
    return $row;
}

function mp_lookup_device_in_table(PDO $pdo, string $table, string $deviceId): ?array
{
    $table = str_replace('`', '', $table);
    try {
        $stmt = $pdo->prepare("SELECT * FROM `{$table}` WHERE device_id = ? LIMIT 1");
        $stmt->execute([$deviceId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
        $stmt2 = $pdo->prepare("SELECT * FROM `{$table}` WHERE TRIM(device_id) = ? LIMIT 1");
        $stmt2->execute([$deviceId]);
        $row2 = $stmt2->fetch(PDO::FETCH_ASSOC);
        return $row2 ?: null;
    } catch (PDOException $e) {
        return null;
    }
}

/**
 * تطبيق مدة كود الإدارة على الجهاز من لحظة التفعيل.
 * يرفض الأجهزة المحظورة. يعيد صف الجهاز المحدّث أو null.
 */
function mp_apply_code_activation(PDO $conn, array $device): ?array
{
    $id = (int)($device['id'] ?? 0);
    $deviceId = trim((string)($device['device_id'] ?? ''));
    if ($id <= 0 || $deviceId === '') {
        return null;
    }
    $status = strtolower(trim((string)($device['status'] ?? '')));
    if ($status === 'blocked') {
        return null;
    }
    $months = mp_normalize_code_months($device['web_manage_code_months'] ?? 1);
    $expirySql = mp_duration_is_lifetime($months)
        ? "'" . mp_lifetime_expiry_date() . "'"
        : "DATE_ADD(NOW(), INTERVAL {$months} MONTH)";
    $pdo = mp_device_pdo($device) ?: $conn;
    $table = mp_device_table($device);
    try {
        // الأشهر مُحقَّقة من قائمة بيضاء فقط — آمنة داخل SQL
        if ($table === 'devices') {
            $stmt = $pdo->prepare(
                "UPDATE `devices`
                 SET expiry_date = {$expirySql},
                     status = 'active'
                 WHERE id = ?
                   AND status <> 'blocked'"
            );
        } else {
            $stmt = $pdo->prepare(
                "UPDATE activated_devices
                 SET activation_date = NOW(),
                     expiry_date = {$expirySql},
                     status = 'active'
                 WHERE id = ?
                   AND status <> 'blocked'"
            );
        }
        $stmt->execute([$id]);
    } catch (PDOException $e) {
        return null;
    }
    return mp_find_active_device($conn, $deviceId);
}

function mp_find_active_device(PDO $conn, string $deviceId): ?array
{
    if ($deviceId === '') {
        return null;
    }

    $row = mp_lookup_device_in_table($conn, 'activated_devices', $deviceId);
    if ($row) {
        $tagged = mp_tag_device_row($row, 'flutter');
        $_SESSION['mp_device_source'] = 'flutter';
        return $tagged;
    }

    global $conn_stv;
    if (isset($conn_stv) && $conn_stv instanceof PDO) {
        $stv = mp_lookup_device_in_table($conn_stv, 'devices', $deviceId);
        if ($stv) {
            $tagged = mp_tag_device_row($stv, 'smarttv');
            $_SESSION['mp_device_source'] = 'smarttv';
            return $tagged;
        }
    }

    return null;
}

function mp_device_is_usable(?array $device): bool
{
    if (!$device) {
        return false;
    }
    $status = strtolower(trim((string)($device['status'] ?? '')));
    if ($status === 'blocked' || $status === 'deleted') {
        return false;
    }
    $expiry = (string)($device['expiry_date'] ?? '');
    if ($expiry === '') {
        // Smart TV قد يستخدم صلاحية مفتوحة بدون expiry في بعض الإعدادات القديمة
        return mp_device_source($device) === 'smarttv' && ($status === '' || $status === 'active');
    }
    if (mp_expiry_is_lifetime($expiry, $device)) {
        return true;
    }
    if (strtotime($expiry) <= time()) {
        return false;
    }
    // تاريخ الانتهاء في المستقبل يكفي — حتى لو لم تُحدَّث خانة status بعد
    return true;
}

/**
 * تفعيل ساري (تجريبي أو مدفوع) → إدارة القوائم بدون كود التفعيل.
 * الكود يُطلب فقط بعد انتهاء الصلاحية.
 */
function mp_can_skip_activation_pin(?array $device): bool
{
    return mp_device_is_usable($device);
}

/** فتح جلسة إدارة القوائم لجهاز مفعّل وصلاحيته سارية. */
function mp_open_active_session(array $device): void
{
    $storedId = trim((string)($device['device_id'] ?? ''));
    if ($storedId === '') {
        return;
    }
    $_SESSION['mp_device_id'] = $storedId;
    $_SESSION['mp_unlocked'] = true;
    $_SESSION['mp_unlocked_at'] = time();
}

function mp_session_device_id(): string
{
    return trim((string)($_SESSION['mp_device_id'] ?? ''));
}

function mp_session_unlocked(): bool
{
    return !empty($_SESSION['mp_unlocked']) && mp_session_device_id() !== '';
}

function mp_require_device_step(): void
{
    if (mp_session_device_id() === '') {
        header('Location: index.php');
        exit;
    }
}

function mp_csrf_token(): string
{
    if (empty($_SESSION['mp_csrf'])) {
        $_SESSION['mp_csrf'] = bin2hex(random_bytes(16));
    }
    return (string)$_SESSION['mp_csrf'];
}

function mp_csrf_ok(?string $token): bool
{
    $expected = (string)($_SESSION['mp_csrf'] ?? '');
    return $expected !== '' && is_string($token) && hash_equals($expected, $token);
}

function mp_flash_set(string $type, string $message): void
{
    $_SESSION['mp_flash'] = ['type' => $type, 'message' => $message];
}

function mp_flash_take(): ?array
{
    if (empty($_SESSION['mp_flash'])) {
        return null;
    }
    $f = $_SESSION['mp_flash'];
    unset($_SESSION['mp_flash']);
    return is_array($f) ? $f : null;
}

function mp_list_playlists(PDO $conn, string $deviceId): array
{
    try {
        $stmt = $conn->prepare(
            'SELECT id, name, m3u_url, created_at, updated_at
             FROM device_web_playlists
             WHERE device_id = ?
             ORDER BY id DESC'
        );
        $stmt->execute([$deviceId]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (PDOException $e) {
        return [];
    }
}

function mp_code_fingerprint(string $code): string
{
    return substr(hash('sha256', 'nova-mp|' . mp_normalize_code($code)), 0, 32);
}

/**
 * هل الجهاز مفتوح لإدارة القوائم على السيرفر (بدون طلب PIN)؟
 * يبطل تلقائياً إذا تغيّر كود اللوحة أو انتهت الصلاحية.
 */
function mp_device_server_unlocked(?array $device): bool
{
    if (!$device || !mp_device_is_usable($device)) {
        return false;
    }
    $fp = trim((string)($device['web_manage_unlocked_fp'] ?? ''));
    $code = mp_normalize_code((string)($device['web_manage_code'] ?? ''));
    if ($fp === '' || $code === '') {
        return false;
    }
    return hash_equals($fp, mp_code_fingerprint($code));
}

/** حفظ نجاح إدخال PIN على السيرفر لهذا الجهاز. */
function mp_server_unlock_save(PDO $conn, array $device): void
{
    $id = (int)($device['id'] ?? 0);
    $code = mp_normalize_code((string)($device['web_manage_code'] ?? ''));
    if ($id <= 0 || $code === '') {
        return;
    }
    $pdo = mp_device_pdo($device) ?: $conn;
    $table = mp_device_table($device);
    try {
        $stmt = $pdo->prepare(
            "UPDATE `{$table}`
             SET web_manage_unlocked_at = NOW(), web_manage_unlocked_fp = ?
             WHERE id = ?"
        );
        $stmt->execute([mp_code_fingerprint($code), $id]);
    } catch (PDOException $e) {
        // تجاهل
    }
}

/** إلغاء تذكر PIN على السيرفر (Switch device أو تغيير الكود). */
function mp_server_unlock_clear(PDO $conn, string $deviceId): void
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return;
    }
    global $conn_stv;
    $targets = [
        [$conn, 'activated_devices'],
    ];
    if (isset($conn_stv) && $conn_stv instanceof PDO) {
        $targets[] = [$conn_stv, 'devices'];
    }
    foreach ($targets as [$pdo, $table]) {
        try {
            $stmt = $pdo->prepare(
                "UPDATE `{$table}`
                 SET web_manage_unlocked_at = NULL, web_manage_unlocked_fp = NULL
                 WHERE device_id = ?"
            );
            $stmt->execute([$deviceId]);
        } catch (PDOException $e) {
            // تجاهل
        }
    }
}

/** مسح كوكي التذكر القديم إن وُجد (ترحيل من النسخة القديمة). */
function mp_remember_clear(): void
{
    if (isset($_COOKIE['mp_remember'])) {
        setcookie('mp_remember', '', [
            'expires' => time() - 3600,
            'path' => '/',
            'secure' => (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off'),
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
    }
    unset($_COOKIE['mp_remember']);
}

function mp_mark_unlocked(PDO $conn, array $device): void
{
    $_SESSION['mp_device_id'] = trim((string)($device['device_id'] ?? ''));
    $_SESSION['mp_unlocked'] = true;
    $_SESSION['mp_unlocked_at'] = time();
    $_SESSION['mp_bound_code'] = mp_normalize_code((string)($device['web_manage_code'] ?? ''));
    mp_server_unlock_save($conn, $device);
    mp_remember_clear();
}

function mp_logout_full(?PDO $conn = null): void
{
    $deviceId = mp_session_device_id();
    unset($_SESSION['mp_device_id'], $_SESSION['mp_unlocked'], $_SESSION['mp_unlocked_at'], $_SESSION['mp_bound_code']);
    mp_remember_clear();
    if ($conn instanceof PDO && $deviceId !== '') {
        mp_server_unlock_clear($conn, $deviceId);
    }
}

/**
 * معلومات المدة المتبقية لتفعيل التطبيق (من expiry_date في اللوحة).
 * نسبة الشريط = المتبقي نسبةً إلى سنتين (أقصى مدة) لإظهار أنيميشن واضح عند التمديد/التقليص.
 */
/** نفس عتبة التطبيق: أقل من 5 أيام كاملة → يُعرض زر التواصل للتجديد. */
function mp_activation_renew_within_days(): int
{
    return 5;
}

/**
 * هل نعرض CTA الدعم؟
 * - Lifetime → لا
 * - منتهي → نعم (Activate)
 * - متبقي < 5 أيام → نعم (Renew)
 * - متبقي ≥ 5 أيام → لا
 */
function mp_activation_needs_support_contact(array $remain): bool
{
    if (!empty($remain['lifetime'])) {
        return false;
    }
    if (empty($remain['ok'])) {
        return true;
    }
    $sec = (int)($remain['seconds'] ?? 0);
    if ($sec <= 0) {
        return true;
    }
    $daysLeft = (int) floor($sec / 86400);
    return $daysLeft < mp_activation_renew_within_days();
}

function mp_support_contact_kind(array $remain): string
{
    if (empty($remain['ok']) || (int)($remain['seconds'] ?? 0) <= 0) {
        return 'expired';
    }
    return 'renew';
}

function mp_build_support_contact_url(string $deviceId, string $kind = 'renew'): string
{
    global $mpSupportUrl;
    $deviceId = trim($deviceId);
    $url = trim((string)$mpSupportUrl);
    if ($url === '' || $deviceId === '') {
        return '';
    }
    if (!preg_match('#^(https?|mailto|tel):#i', $url)) {
        $url = 'https://' . $url;
    }
    $msgKey = $kind === 'expired' ? 'contact_wa_expired' : 'contact_wa_renew';
    $message = str_replace('@device', $deviceId, mp_t($msgKey));
    $isWa = stripos($url, 'whatsapp.com') !== false || stripos($url, 'wa.me') !== false;
    if ($isWa) {
        $sep = strpos($url, '?') !== false ? '&' : '?';
        return $url . $sep . 'text=' . rawurlencode($message);
    }
    $sep = strpos($url, '?') !== false ? '&' : '?';
    return $url . $sep . 'device_id=' . rawurlencode($deviceId);
}

function mp_remaining_activation(array $device): array
{
    $expiryRaw = trim((string)($device['expiry_date'] ?? ''));
    $lifetime = mp_expiry_is_lifetime($expiryRaw, $device);
    $now = time();

    if ($lifetime) {
        $expiryTs = strtotime(mp_lifetime_expiry_date()) ?: ($now + (80 * 365 * 86400));
        return [
            'expiry_ts' => $expiryTs,
            'expiry_raw' => $expiryRaw !== '' ? $expiryRaw : mp_lifetime_expiry_date(),
            'seconds' => max(0, $expiryTs - $now),
            'days' => 0,
            'hours' => 0,
            'mins' => 0,
            'percent' => 100,
            'max_seconds' => (int)max(1, strtotime('+2 years', $now) - $now),
            'ok' => true,
            'lifetime' => true,
        ];
    }

    $expiryTs = strtotime($expiryRaw) ?: 0;
    $sec = max(0, $expiryTs - $now);
    $days = (int)floor($sec / 86400);
    $hours = (int)floor(($sec % 86400) / 3600);
    $mins = (int)floor(($sec % 3600) / 60);

    // أقصى مدة في بطاقات التفعيل = سنتان → الشريط الممتلئ بالكامل = سنتان
    $maxSec = (int)max(1, strtotime('+2 years', $now) - $now);
    $pct = (int)max(0, min(100, round(($sec / $maxSec) * 100)));
    if ($sec <= 0) {
        $pct = 0;
    }

    return [
        'expiry_ts' => $expiryTs,
        'expiry_raw' => $expiryRaw,
        'seconds' => $sec,
        'days' => $days,
        'hours' => $hours,
        'mins' => $mins,
        'percent' => $pct,
        'max_seconds' => $maxSec,
        'ok' => $sec > 0,
        'lifetime' => false,
    ];
}

function mp_require_unlocked(): void
{
    global $conn;
    $sid = mp_session_device_id();
    if ($sid === '') {
        header('Location: index.php');
        exit;
    }
    if (isset($conn) && $conn instanceof PDO) {
        $device = mp_find_active_device($conn, $sid);
        if ($device && mp_device_is_usable($device)) {
            mp_open_active_session($device);
            return;
        }
        unset($_SESSION['mp_unlocked'], $_SESSION['mp_unlocked_at'], $_SESSION['mp_bound_code']);
        mp_flash_set('err', mp_t('err_device_expired'));
        header('Location: index.php');
        exit;
    }
    if (mp_session_unlocked()) {
        return;
    }
    header('Location: index.php');
    exit;
}
