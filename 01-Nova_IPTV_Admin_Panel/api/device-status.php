<?php
/**
 * Device presence list for the admin UI only (session-authenticated).
 * Not a public app endpoint — do not call from the Flutter client.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

session_start();
require_once '../config/database.php';
require_once '../includes/functions.php';
require_once '../includes/lang.php';
require_once '../includes/admin_auth.php';
require_once '../includes/devices_table_row.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

if (!adminIsLoggedIn()) {
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'message' => 'unauthorized',
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

if (!adminCan('devices_view') && !adminCan('dashboard') && !adminCan('manage_activations')) {
    http_response_code(403);
    echo json_encode([
        'success' => false,
        'message' => 'forbidden',
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

$thresholdSeconds = 60; // مدة اعتبار الجهاز متصل حاليًا (ثوانٍ)

try {
    $resellerId = null;
    if (function_exists('adminRoleIsReseller') && adminRoleIsReseller(adminSessionRole()) && !empty($_SESSION['admin_user_id'])) {
        $resellerId = (int)$_SESSION['admin_user_id'];
    }

    if ($resellerId !== null) {
        $stmt = $conn->prepare(
            "SELECT a.id, a.device_id, a.device_name, a.status, a.activation_date, a.expiry_date, a.last_seen_at,
                    a.account_key, a.account_display_name, a.code_server_host,
                    (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
             FROM activated_devices a
             INNER JOIN iptv_customers c ON (
                 c.username = a.manual_login_username 
                 OR c.username = a.account_display_name 
                 OR a.account_key LIKE CONCAT(c.username, '#%') 
                 OR a.account_key = c.username
             )
             WHERE (a.status IS NULL OR a.status <> 'deleted')
               AND c.created_by = ?"
        );
        $stmt->execute([$resellerId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } else {
        $stmt = $conn->query(
            "SELECT a.id, a.device_id, a.device_name, a.status, a.activation_date, a.expiry_date, a.last_seen_at,
                    a.account_key, a.account_display_name, a.code_server_host,
                    (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.device_id = a.device_id) AS code_usage_count
             FROM activated_devices a
             WHERE a.status IS NULL OR a.status <> 'deleted'"
        );
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    $isGuest = adminIsGuestRole();

    $now = time();
    $devices = [];
    $statsTotal = count($rows);
    $statsActive = 0;
    $statsExpired = 0;

    foreach ($rows as $row) {
        $expiryTs = !empty($row['expiry_date']) ? strtotime((string) $row['expiry_date']) : 0;
        $status = strtolower(trim((string) ($row['status'] ?? '')));
        if ($status === 'active' && $expiryTs > $now) {
            $statsActive++;
        }
        if ($expiryTs > 0 && $expiryTs <= $now) {
            $statsExpired++;
        }

        $lastSeen = !empty($row['last_seen_at']) ? strtotime($row['last_seen_at']) : 0;
        // متصل = ظهر مؤخراً من التطبيق فقط (لا يعتمد على نشط/منتهي/محظور)
        $isOnline = $lastSeen > 0 && ($now - $lastSeen) <= $thresholdSeconds;

        // نص مقروء يوضح حالة الاتصال / آخر ظهور (يعتمد على لغة لوحة التحكم)
        if ($lang === 'en') {
            $lastSeenHuman = 'Never connected yet';
            if ($lastSeen > 0) {
                $diff = $now - $lastSeen;
                if ($diff <= $thresholdSeconds) {
                    $lastSeenHuman = 'Online now';
                } else {
                    $minutes = floor($diff / 60);
                    $hours = floor($minutes / 60);
                    if ($diff < 120) {
                        $lastSeenHuman = 'Last seen about a minute ago';
                    } elseif ($diff < 3600) {
                        $lastSeenHuman = 'Last seen ' . $minutes . ' minute(s) ago';
                    } elseif ($diff < 86400) {
                        $lastSeenHuman = 'Last seen ' . $hours . ' hour(s) ago';
                    } else {
                        $lastSeenHuman = 'Last seen ' . format_datetime_short($lastSeen);
                    }
                }
            }
        } else {
            $lastSeenHuman = 'لم يتم الاتصال بعد';
            if ($lastSeen > 0) {
                $diff = $now - $lastSeen;
                if ($diff <= $thresholdSeconds) {
                    $lastSeenHuman = 'متصل حاليًا';
                } else {
                    $minutes = floor($diff / 60);
                    $hours = floor($minutes / 60);
                    if ($diff < 120) {
                        // أقل من دقيقتين
                        $lastSeenHuman = 'آخر ظهور قبل دقيقة تقريبًا';
                    } elseif ($diff < 3600) {
                        // أقل من ساعة
                        $lastSeenHuman = 'آخر ظهور قبل ' . $minutes . ' دقيقة';
                    } elseif ($diff < 86400) {
                        // أقل من يوم
                        $lastSeenHuman = 'آخر ظهور قبل ' . $hours . ' ساعة';
                    } else {
                        $lastSeenHuman = 'آخر ظهور ' . format_datetime_short($lastSeen);
                    }
                }
            }
        }

        $devices[] = [
            'id' => (int)($row['id'] ?? 0),
            // للضيف لا نُرجع Device ID الكامل في الـ JSON.
            'device_id' => $isGuest ? '' : $row['device_id'],
            'status' => $status,
            'sync_sig' => admin_device_dashboard_sync_sig($row),
            'online' => $isOnline,
            'last_seen_at' => $row['last_seen_at'],
            'last_seen_human' => $lastSeenHuman,
        ];
    }

    echo json_encode([
        'success' => true,
        'threshold_seconds' => $thresholdSeconds,
        'stats' => [
            'total' => $statsTotal,
            'active' => $statsActive,
            'expired' => $statsExpired,
        ],
        'devices' => $devices,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database error',
    ], JSON_UNESCAPED_UNICODE);
}

