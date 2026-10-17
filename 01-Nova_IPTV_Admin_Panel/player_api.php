<?php
/**
 * SkyPro Native Xtream Codes API Engine (player_api.php)
 * Authenticates IPTV customers created in SkyPro Admin Panel and serves Xtream player protocol.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/includes/credential_crypto.php';

$username = trim((string)($_GET['username'] ?? $_POST['username'] ?? ''));
$password = trim((string)($_GET['password'] ?? $_POST['password'] ?? ''));
$action   = trim((string)($_GET['action'] ?? $_POST['action'] ?? ''));

if ($username === '' || $password === '') {
    echo json_encode([
        'user_info' => [
            'auth' => 0,
            'status' => 'Disabled',
            'message' => 'Username and password are required',
        ],
    ], JSON_UNESCAPED_UNICODE);
    exit();
}

try {
    // 1. Look up customer in iptv_customers
    $stmt = $conn->prepare("SELECT * FROM iptv_customers WHERE username = ? LIMIT 1");
    $stmt->execute([$username]);
    $customer = $stmt->fetch(PDO::FETCH_ASSOC);

    $matched = false;
    if ($customer) {
        $storedPass = (string)($customer['password'] ?? '');
        if (credential_is_encrypted($storedPass)) {
            $dec = credential_decrypt_password_from_storage($conn, $storedPass);
            if ($dec !== '' && $dec === $password) {
                $matched = true;
            }
        } elseif ($storedPass === $password) {
            $matched = true;
        }

        if (!$matched) {
            echo json_encode([
                'user_info' => [
                    'auth' => 0,
                    'status' => 'Disabled',
                    'message' => 'Invalid username or password',
                ],
            ], JSON_UNESCAPED_UNICODE);
            exit();
        }
    } else {
        // Fallback: check activated_devices for bound lines
        $accKey = build_account_key($conn, $username, $password);
        $legacyKey = $username . ':' . $password;
        $dStmt = $conn->prepare("SELECT * FROM activated_devices WHERE (account_key = ? OR account_key = ? OR manual_login_username = ?) AND (status = 'active' OR status IS NULL) LIMIT 1");
        $dStmt->execute([$accKey, $legacyKey, $username]);
        $dev = $dStmt->fetch(PDO::FETCH_ASSOC);
        if ($dev) {
            $customer = [
                'username' => $username,
                'password' => $password,
                'expiry_date' => $dev['expiry_date'] ?? date('Y-m-d H:i:s', time() + 86400 * 30),
                'status' => 'active',
                'max_connections' => 1,
            ];
            $matched = true;
        }
    }

    if (!$matched || !$customer) {
        echo json_encode([
            'user_info' => [
                'auth' => 0,
                'status' => 'Disabled',
                'message' => 'Invalid username or password',
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    // Check expiry & status
    $status = strtolower(trim((string)($customer['status'] ?? 'active')));
    $expTime = !empty($customer['expiry_date']) ? strtotime($customer['expiry_date']) : (time() + 86400 * 30);
    $isExpired = $expTime !== false && $expTime < time();

    if ($status === 'disabled' || $status === 'blocked' || $isExpired) {
        echo json_encode([
            'user_info' => [
                'username' => $customer['username'],
                'auth' => 0,
                'status' => $isExpired ? 'Expired' : 'Disabled',
                'message' => $isExpired ? 'Your subscription has expired' : 'Your account is disabled',
                'exp_date' => (string)$expTime,
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    $createdAt = !empty($customer['created_at']) ? strtotime($customer['created_at']) : (time() - 86400);
    $maxConnections = max(1, (int)($customer['max_connections'] ?? 1));

    // Handle authentication handshake (no action)
    if ($action === '') {
        $serverHost = $_SERVER['HTTP_HOST'] ?? 'skypro-app.com:25463';
        $hostParts = explode(':', $serverHost);
        $serverDomain = $hostParts[0];
        $serverPort = $hostParts[1] ?? '25463';

        echo json_encode([
            'user_info' => [
                'username' => $customer['username'],
                'password' => $customer['password'],
                'message' => 'Welcome to SkyPro IPTV',
                'auth' => 1,
                'status' => 'Active',
                'exp_date' => (string)$expTime,
                'is_trial' => '0',
                'active_cons' => '0',
                'created_at' => (string)$createdAt,
                'max_connections' => (string)$maxConnections,
                'allowed_output_formats' => ['m3u8', 'ts', 'rtmp'],
            ],
            'server_info' => [
                'url' => $serverDomain,
                'port' => $serverPort,
                'https_port' => '25463',
                'server_protocol' => 'https',
                'rtmp_port' => '25462',
                'timezone' => 'UTC',
                'time_now' => date('Y-m-d H:i:s'),
                'timestamp_now' => time(),
                'process' => true,
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    // Helper: find custom M3U playlist assigned to this user/device
    $assignedM3u = '';
    try {
        $stM3u = $conn->prepare("SELECT custom_domain FROM activated_devices WHERE (manual_login_username = ? OR account_display_name = ?) AND custom_domain IS NOT NULL AND custom_domain <> '' LIMIT 1");
        $stM3u->execute([$username, $username]);
        $rowM3u = $stM3u->fetch(PDO::FETCH_ASSOC);
        if ($rowM3u && !empty($rowM3u['custom_domain'])) {
            $assignedM3u = trim($rowM3u['custom_domain']);
        }
    } catch (Throwable $e) {}

    // Actions
    if ($action === 'get_live_categories') {
        echo json_encode([
            [
                'category_id' => '1',
                'category_name' => 'General / SkyPro Live',
                'parent_id' => 0,
            ],
            [
                'category_id' => '2',
                'category_name' => 'Sports',
                'parent_id' => 0,
            ],
            [
                'category_id' => '3',
                'category_name' => 'News',
                'parent_id' => 0,
            ],
            [
                'category_id' => '4',
                'category_name' => 'Entertainment',
                'parent_id' => 0,
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_live_streams') {
        $catId = trim((string)($_GET['category_id'] ?? ''));
        $channels = [
            [
                'num' => 1,
                'name' => 'Sky Cinema Action HD',
                'stream_type' => 'live',
                'stream_id' => 1,
                'stream_icon' => 'https://skypro-app.com/assets/images/favicon-32x32.png',
                'epg_channel_id' => 'skycinema',
                'added' => (string)$createdAt,
                'category_id' => '1',
                'custom_sid' => '',
                'tv_archive' => 0,
                'direct_source' => '',
                'tv_archive_duration' => 0,
            ],
            [
                'num' => 2,
                'name' => 'Sky Showcase HD',
                'stream_type' => 'live',
                'stream_id' => 2,
                'stream_icon' => 'https://skypro-app.com/assets/images/favicon-32x32.png',
                'epg_channel_id' => 'skyshowcase',
                'added' => (string)$createdAt,
                'category_id' => '1',
                'custom_sid' => '',
                'tv_archive' => 0,
                'direct_source' => '',
                'tv_archive_duration' => 0,
            ],
            [
                'num' => 3,
                'name' => 'Sky Sports 1 HD',
                'stream_type' => 'live',
                'stream_id' => 3,
                'stream_icon' => 'https://skypro-app.com/assets/images/favicon-32x32.png',
                'epg_channel_id' => 'skysports1',
                'added' => (string)$createdAt,
                'category_id' => '2',
                'custom_sid' => '',
                'tv_archive' => 0,
                'direct_source' => '',
                'tv_archive_duration' => 0,
            ],
            [
                'num' => 4,
                'name' => 'Sky News HD',
                'stream_type' => 'live',
                'stream_id' => 4,
                'stream_icon' => 'https://skypro-app.com/assets/images/favicon-32x32.png',
                'epg_channel_id' => 'skynews',
                'added' => (string)$createdAt,
                'category_id' => '3',
                'custom_sid' => '',
                'tv_archive' => 0,
                'direct_source' => '',
                'tv_archive_duration' => 0,
            ],
            [
                'num' => 5,
                'name' => 'Sky One HD',
                'stream_type' => 'live',
                'stream_id' => 5,
                'stream_icon' => 'https://skypro-app.com/assets/images/favicon-32x32.png',
                'epg_channel_id' => 'skyone',
                'added' => (string)$createdAt,
                'category_id' => '4',
                'custom_sid' => '',
                'tv_archive' => 0,
                'direct_source' => '',
                'tv_archive_duration' => 0,
            ],
        ];

        if ($catId !== '' && $catId !== '0') {
            $filtered = [];
            foreach ($channels as $ch) {
                if ($ch['category_id'] === $catId) {
                    $filtered[] = $ch;
                }
            }
            echo json_encode($filtered, JSON_UNESCAPED_UNICODE);
            exit();
        }

        echo json_encode($channels, JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_vod_categories') {
        echo json_encode([
            [
                'category_id' => '1',
                'category_name' => 'Movies',
                'parent_id' => 0,
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_vod_streams') {
        echo json_encode([], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_series_categories') {
        echo json_encode([
            [
                'category_id' => '1',
                'category_name' => 'Series',
                'parent_id' => 0,
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_series') {
        echo json_encode([], JSON_UNESCAPED_UNICODE);
        exit();
    }

    // Default response for unhandled action
    echo json_encode([], JSON_UNESCAPED_UNICODE);
    exit();

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'user_info' => [
            'auth' => 0,
            'message' => 'Server error: ' . $e->getMessage(),
        ],
    ], JSON_UNESCAPED_UNICODE);
    exit();
}
