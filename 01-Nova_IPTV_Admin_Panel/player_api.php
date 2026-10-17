<?php
/**
 * SkyPro Native Xtream Codes API Engine (player_api.php)
 * Authenticates IPTV customers created in SkyPro Admin Panel and serves Xtream player protocol
 * for Live TV, Movies (VOD), Series, and EPG listings.
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
    $expTime = !empty($customer['expiry_date']) ? strtotime($customer['expiry_date']) : (time() + 86400 * 365);
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

    $createdAt = !empty($customer['created_at']) ? strtotime($customer['created_at']) : time();
    $maxConn = (string)max(1, (int)($customer['max_connections'] ?? 1));

    // Base authentication response (without action)
    if ($action === '') {
        $serverHost = $_SERVER['HTTP_HOST'] ?? 'skypro-app.com';
        $port = '25463';
        if (strpos($serverHost, ':') !== false) {
            $parts = explode(':', $serverHost);
            $serverHost = $parts[0];
            $port = $parts[1];
        }

        echo json_encode([
            'user_info' => [
                'username' => $customer['username'],
                'password' => $password,
                'message' => 'Welcome to SkyPro IPTV',
                'auth' => 1,
                'status' => 'Active',
                'exp_date' => (string)$expTime,
                'is_trial' => '0',
                'active_cons' => '0',
                'created_at' => (string)$createdAt,
                'max_connections' => $maxConn,
                'allowed_output_formats' => ['m3u8', 'ts', 'rtmp'],
            ],
            'server_info' => [
                'url' => $serverHost,
                'port' => $port,
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

    // ==========================================
    // 1. LIVE TV CATEGORIES & STREAMS
    // ==========================================
    if ($action === 'get_live_categories') {
        echo json_encode([
            ['category_id' => '1', 'category_name' => 'General / SkyPro Live', 'parent_id' => 0],
            ['category_id' => '2', 'category_name' => 'Sports', 'parent_id' => 0],
            ['category_id' => '3', 'category_name' => 'News', 'parent_id' => 0],
            ['category_id' => '4', 'category_name' => 'Entertainment', 'parent_id' => 0],
            ['category_id' => '5', 'category_name' => 'Movies & Cinema', 'parent_id' => 0],
            ['category_id' => '6', 'category_name' => 'Documentary', 'parent_id' => 0],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_live_streams') {
        $catId = trim((string)($_GET['category_id'] ?? ''));
        $channels = [
            // Category 1: General / SkyPro Live
            [
                'num' => 1, 'name' => 'Sky Cinema Action HD', 'stream_type' => 'live', 'stream_id' => 1,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'epg_channel_id' => 'skycinema', 'added' => (string)$createdAt, 'category_id' => '1',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 2, 'name' => 'Sky Showcase HD', 'stream_type' => 'live', 'stream_id' => 2,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
                'epg_channel_id' => 'skyshowcase', 'added' => (string)$createdAt, 'category_id' => '1',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            // Category 2: Sports
            [
                'num' => 3, 'name' => 'Sky Sports Main Event HD', 'stream_type' => 'live', 'stream_id' => 3,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/o0bgkH5Xq0mYnUeGg7v02bO9Y3.jpg',
                'epg_channel_id' => 'skysportsmain', 'added' => (string)$createdAt, 'category_id' => '2',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 4, 'name' => 'Sky Sports Premier League HD', 'stream_type' => 'live', 'stream_id' => 4,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/o0bgkH5Xq0mYnUeGg7v02bO9Y3.jpg',
                'epg_channel_id' => 'skysportspl', 'added' => (string)$createdAt, 'category_id' => '2',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 5, 'name' => 'Sky Sports F1 HD', 'stream_type' => 'live', 'stream_id' => 5,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/o0bgkH5Xq0mYnUeGg7v02bO9Y3.jpg',
                'epg_channel_id' => 'skysportsf1', 'added' => (string)$createdAt, 'category_id' => '2',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            // Category 3: News
            [
                'num' => 6, 'name' => 'Sky News HD', 'stream_type' => 'live', 'stream_id' => 6,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/6KErczPBROQty7QoIsaa6wJYXZi.jpg',
                'epg_channel_id' => 'skynews', 'added' => (string)$createdAt, 'category_id' => '3',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 7, 'name' => 'BBC News HD', 'stream_type' => 'live', 'stream_id' => 7,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/6KErczPBROQty7QoIsaa6wJYXZi.jpg',
                'epg_channel_id' => 'bbcnews', 'added' => (string)$createdAt, 'category_id' => '3',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 8, 'name' => 'CNN International HD', 'stream_type' => 'live', 'stream_id' => 8,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/6KErczPBROQty7QoIsaa6wJYXZi.jpg',
                'epg_channel_id' => 'cnn', 'added' => (string)$createdAt, 'category_id' => '3',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            // Category 4: Entertainment
            [
                'num' => 9, 'name' => 'Sky One HD', 'stream_type' => 'live', 'stream_id' => 9,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
                'epg_channel_id' => 'skyone', 'added' => (string)$createdAt, 'category_id' => '4',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 10, 'name' => 'Sky Comedy HD', 'stream_type' => 'live', 'stream_id' => 10,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
                'epg_channel_id' => 'skycomedy', 'added' => (string)$createdAt, 'category_id' => '4',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 11, 'name' => 'HBO HD', 'stream_type' => 'live', 'stream_id' => 11,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
                'epg_channel_id' => 'hbo', 'added' => (string)$createdAt, 'category_id' => '4',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            // Category 5: Movies & Cinema
            [
                'num' => 12, 'name' => 'Sky Cinema Premiere HD', 'stream_type' => 'live', 'stream_id' => 12,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'epg_channel_id' => 'skyprem', 'added' => (string)$createdAt, 'category_id' => '5',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 13, 'name' => 'Sky Cinema Hits HD', 'stream_type' => 'live', 'stream_id' => 13,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'epg_channel_id' => 'skyhits', 'added' => (string)$createdAt, 'category_id' => '5',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            // Category 6: Documentary
            [
                'num' => 14, 'name' => 'Discovery Channel HD', 'stream_type' => 'live', 'stream_id' => 14,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/9Pfqr5U0vE7yC2M47g68L36uI6U.jpg',
                'epg_channel_id' => 'discovery', 'added' => (string)$createdAt, 'category_id' => '6',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
            ],
            [
                'num' => 15, 'name' => 'National Geographic HD', 'stream_type' => 'live', 'stream_id' => 15,
                'stream_icon' => 'https://image.tmdb.org/t/p/w300/9Pfqr5U0vE7yC2M47g68L36uI6U.jpg',
                'epg_channel_id' => 'natgeo', 'added' => (string)$createdAt, 'category_id' => '6',
                'custom_sid' => '', 'tv_archive' => 0, 'direct_source' => '', 'tv_archive_duration' => 0,
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

    // ==========================================
    // 2. VOD / MOVIES CATEGORIES & STREAMS
    // ==========================================
    if ($action === 'get_vod_categories') {
        echo json_encode([
            ['category_id' => '1', 'category_name' => 'Action & Adventure', 'parent_id' => 0],
            ['category_id' => '2', 'category_name' => 'Sci-Fi & Fantasy', 'parent_id' => 0],
            ['category_id' => '3', 'category_name' => 'Comedy', 'parent_id' => 0],
            ['category_id' => '4', 'category_name' => 'Drama & Thriller', 'parent_id' => 0],
            ['category_id' => '5', 'category_name' => 'Animation & Family', 'parent_id' => 0],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_vod_streams') {
        $catId = trim((string)($_GET['category_id'] ?? ''));
        $movies = [
            [
                'num' => 1, 'name' => 'The Dark Knight', 'stream_type' => 'movie', 'stream_id' => 1,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'rating' => '9.0', 'rating_5based' => '4.5', 'added' => (string)($createdAt - 1000),
                'is_adult' => '0', 'category_id' => '1', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 2, 'name' => 'Gladiator II', 'stream_type' => 'movie', 'stream_id' => 2,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/2cxhvwyEwRlysAmRH4iodkvo0z5.jpg',
                'rating' => '8.2', 'rating_5based' => '4.1', 'added' => (string)($createdAt - 2000),
                'is_adult' => '0', 'category_id' => '1', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 3, 'name' => 'Inception', 'stream_type' => 'movie', 'stream_id' => 3,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg',
                'rating' => '8.8', 'rating_5based' => '4.4', 'added' => (string)($createdAt - 3000),
                'is_adult' => '0', 'category_id' => '2', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 4, 'name' => 'Interstellar', 'stream_type' => 'movie', 'stream_id' => 4,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
                'rating' => '8.7', 'rating_5based' => '4.3', 'added' => (string)($createdAt - 4000),
                'is_adult' => '0', 'category_id' => '2', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 5, 'name' => 'Deadpool & Wolverine', 'stream_type' => 'movie', 'stream_id' => 5,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
                'rating' => '8.0', 'rating_5based' => '4.0', 'added' => (string)($createdAt - 500),
                'is_adult' => '0', 'category_id' => '3', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 6, 'name' => 'The Hangover', 'stream_type' => 'movie', 'stream_id' => 6,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/uluhlXubGu1VxU63X9VHcLWDAYP.jpg',
                'rating' => '7.7', 'rating_5based' => '3.8', 'added' => (string)($createdAt - 5000),
                'is_adult' => '0', 'category_id' => '3', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 7, 'name' => 'Oppenheimer', 'stream_type' => 'movie', 'stream_id' => 7,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
                'rating' => '8.9', 'rating_5based' => '4.5', 'added' => (string)($createdAt - 1200),
                'is_adult' => '0', 'category_id' => '4', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 8, 'name' => 'Pulp Fiction', 'stream_type' => 'movie', 'stream_id' => 8,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
                'rating' => '8.9', 'rating_5based' => '4.5', 'added' => (string)($createdAt - 6000),
                'is_adult' => '0', 'category_id' => '4', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 9, 'name' => 'Spider-Man: Across the Spider-Verse', 'stream_type' => 'movie', 'stream_id' => 9,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
                'rating' => '8.7', 'rating_5based' => '4.3', 'added' => (string)($createdAt - 1500),
                'is_adult' => '0', 'category_id' => '5', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
            [
                'num' => 10, 'name' => 'Avatar: The Way of Water', 'stream_type' => 'movie', 'stream_id' => 10,
                'stream_icon' => 'https://image.tmdb.org/t/p/w500/t6HIqrRAclMCA60NsSmeqe9RmNV.jpg',
                'rating' => '7.6', 'rating_5based' => '3.8', 'added' => (string)($createdAt - 2500),
                'is_adult' => '0', 'category_id' => '2', 'container_extension' => 'mp4',
                'custom_sid' => '', 'direct_source' => '',
            ],
        ];

        if ($catId !== '' && $catId !== '0') {
            $filtered = [];
            foreach ($movies as $m) {
                if ($m['category_id'] === $catId) {
                    $filtered[] = $m;
                }
            }
            echo json_encode($filtered, JSON_UNESCAPED_UNICODE);
            exit();
        }

        echo json_encode($movies, JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_vod_info') {
        $vodId = (int)($_GET['vod_id'] ?? 1);
        echo json_encode([
            'info' => [
                'movie_image' => 'https://image.tmdb.org/t/p/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'tmdb_id' => '155',
                'name' => 'The Dark Knight',
                'o_name' => 'The Dark Knight',
                'cover_big' => 'https://image.tmdb.org/t/p/w1280/nMKdUUepR0i5zn0y1T4CsSB5chy.jpg',
                'movie_image' => 'https://image.tmdb.org/t/p/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
                'release_date' => '2008-07-18',
                'episode_run_time' => '152',
                'youtube_trailer' => 'EXeTwQWrcwY',
                'director' => 'Christopher Nolan',
                'actors' => 'Christian Bale, Heath Ledger, Aaron Eckhart, Michael Caine',
                'cast' => 'Christian Bale, Heath Ledger, Aaron Eckhart',
                'description' => 'Batman raises the stakes in his war on crime. With the help of Lt. Jim Gordon and District Attorney Harvey Dent, Batman sets out to dismantle the remaining criminal organizations that plague the streets.',
                'plot' => 'Batman raises the stakes in his war on crime. With the help of Lt. Jim Gordon and District Attorney Harvey Dent, Batman sets out to dismantle the remaining criminal organizations that plague the streets.',
                'age' => '16+',
                'country' => 'United States',
                'genre' => 'Action, Crime, Drama',
                'duration_secs' => 9120,
                'duration' => '02:32:00',
                'rating' => '9.0',
            ],
            'movie_data' => [
                'stream_id' => $vodId,
                'name' => 'The Dark Knight',
                'added' => (string)$createdAt,
                'category_id' => '1',
                'container_extension' => 'mp4',
                'custom_sid' => '',
                'direct_source' => '',
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    // ==========================================
    // 3. SERIES CATEGORIES & STREAMS
    // ==========================================
    if ($action === 'get_series_categories') {
        echo json_encode([
            ['category_id' => '1', 'category_name' => 'Action & Crime', 'parent_id' => 0],
            ['category_id' => '2', 'category_name' => 'Drama', 'parent_id' => 0],
            ['category_id' => '3', 'category_name' => 'Sci-Fi & Mystery', 'parent_id' => 0],
            ['category_id' => '4', 'category_name' => 'Comedy', 'parent_id' => 0],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_series') {
        $catId = trim((string)($_GET['category_id'] ?? ''));
        $series = [
            [
                'num' => 1, 'name' => 'Breaking Bad', 'series_id' => 1,
                'cover' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                'plot' => 'Walter White, a New Mexico chemistry teacher, is diagnosed with Stage III cancer and decides to enter the dangerous world of drugs to secure his family financial future.',
                'cast' => 'Bryan Cranston, Aaron Paul, Anna Gunn', 'director' => 'Vince Gilligan',
                'genre' => 'Crime, Drama, Thriller', 'releaseDate' => '2008-01-20',
                'rating' => '9.5', 'rating_5based' => '4.8', 'category_id' => '1', 'added' => (string)($createdAt - 1000),
            ],
            [
                'num' => 2, 'name' => 'The Boys', 'series_id' => 2,
                'cover' => 'https://image.tmdb.org/t/p/w500/7Ns6tO3aYjppI5LoNOFvTWh42nc.jpg',
                'plot' => 'A fun and irreverent take on what happens when superheroes abuse their superpowers rather than use them for good.',
                'cast' => 'Karl Urban, Jack Quaid, Antony Starr', 'director' => 'Eric Kripke',
                'genre' => 'Action, Sci-Fi', 'releaseDate' => '2019-07-26',
                'rating' => '8.7', 'rating_5based' => '4.3', 'category_id' => '1', 'added' => (string)($createdAt - 1500),
            ],
            [
                'num' => 3, 'name' => 'Game of Thrones', 'series_id' => 3,
                'cover' => 'https://image.tmdb.org/t/p/w500/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
                'plot' => 'Nine noble families fight for control over the lands of Westeros, while an ancient enemy returns after being dormant for millennia.',
                'cast' => 'Emilia Clarke, Peter Dinklage, Kit Harington', 'director' => 'David Benioff',
                'genre' => 'Action, Adventure, Drama', 'releaseDate' => '2011-04-17',
                'rating' => '9.2', 'rating_5based' => '4.6', 'category_id' => '2', 'added' => (string)($createdAt - 2000),
            ],
            [
                'num' => 4, 'name' => 'Succession', 'series_id' => 4,
                'cover' => 'https://image.tmdb.org/t/p/w500/775HwB11tVj8JvF5rC3xM7hS9.jpg',
                'plot' => 'The Roy family is known for controlling the biggest media and entertainment company in the world. However, their world changes when their aging father steps down from the company.',
                'cast' => 'Brian Cox, Jeremy Strong, Sarah Snook', 'director' => 'Jesse Armstrong',
                'genre' => 'Drama', 'releaseDate' => '2018-06-03',
                'rating' => '8.9', 'rating_5based' => '4.4', 'category_id' => '2', 'added' => (string)($createdAt - 2500),
            ],
            [
                'num' => 5, 'name' => 'Stranger Things', 'series_id' => 5,
                'cover' => 'https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
                'plot' => 'When a young boy vanishes, a small town uncovers a mystery involving secret experiments, terrifying supernatural forces and one strange little girl.',
                'cast' => 'Millie Bobby Brown, Finn Wolfhard, Winona Ryder', 'director' => 'The Duffer Brothers',
                'genre' => 'Drama, Fantasy, Horror', 'releaseDate' => '2016-07-15',
                'rating' => '8.7', 'rating_5based' => '4.3', 'category_id' => '3', 'added' => (string)($createdAt - 3000),
            ],
            [
                'num' => 6, 'name' => 'The Last of Us', 'series_id' => 6,
                'cover' => 'https://image.tmdb.org/t/p/w500/uKvVjHNqB5VmOrdxqAt2V7JMrHG.jpg',
                'plot' => 'Twenty years after a fungal outbreak ravages the planet, survivors Joel and Tess are tasked with a mission that could change everything.',
                'cast' => 'Pedro Pascal, Bella Ramsey', 'director' => 'Craig Mazin',
                'genre' => 'Action, Adventure, Drama', 'releaseDate' => '2023-01-15',
                'rating' => '8.8', 'rating_5based' => '4.4', 'category_id' => '3', 'added' => (string)($createdAt - 3500),
            ],
            [
                'num' => 7, 'name' => 'Ted Lasso', 'series_id' => 7,
                'cover' => 'https://image.tmdb.org/t/p/w500/5fhZdwP0DVJ0FySXUqVOE28BGp5.jpg',
                'plot' => 'American college football coach Ted Lasso heads to London to manage AFC Richmond, a struggling English Premier League football team.',
                'cast' => 'Jason Sudeikis, Hannah Waddingham, Brett Goldstein', 'director' => 'Brendan Hunt',
                'genre' => 'Comedy, Drama, Sport', 'releaseDate' => '2020-08-14',
                'rating' => '8.8', 'rating_5based' => '4.4', 'category_id' => '4', 'added' => (string)($createdAt - 4000),
            ],
            [
                'num' => 8, 'name' => 'House of the Dragon', 'series_id' => 8,
                'cover' => 'https://image.tmdb.org/t/p/w500/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg',
                'plot' => 'The story of the House Targaryen, set 200 years before the events of Game of Thrones.',
                'cast' => 'Matt Smith, Emma D\'Arcy, Olivia Cooke', 'director' => 'Ryan J. Condal',
                'genre' => 'Action, Adventure, Drama', 'releaseDate' => '2022-08-21',
                'rating' => '8.5', 'rating_5based' => '4.2', 'category_id' => '2', 'added' => (string)($createdAt - 4500),
            ],
        ];

        if ($catId !== '' && $catId !== '0') {
            $filtered = [];
            foreach ($series as $s) {
                if ($s['category_id'] === $catId) {
                    $filtered[] = $s;
                }
            }
            echo json_encode($filtered, JSON_UNESCAPED_UNICODE);
            exit();
        }

        echo json_encode($series, JSON_UNESCAPED_UNICODE);
        exit();
    }

    if ($action === 'get_series_info') {
        $serieId = (int)($_GET['series_id'] ?? 1);
        echo json_encode([
            'seasons' => [
                [
                    'air_date' => '2023-01-01',
                    'episode_count' => 3,
                    'id' => 1,
                    'name' => 'Season 1',
                    'overview' => 'Season 1 of this hit series.',
                    'season_number' => 1,
                    'cover' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                ],
            ],
            'info' => [
                'name' => 'Breaking Bad',
                'cover' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                'plot' => 'Walter White, a New Mexico chemistry teacher, is diagnosed with Stage III cancer and decides to enter the dangerous world of drugs to secure his family financial future.',
                'cast' => 'Bryan Cranston, Aaron Paul, Anna Gunn',
                'director' => 'Vince Gilligan',
                'genre' => 'Crime, Drama, Thriller',
                'releaseDate' => '2008-01-20',
                'rating' => '9.5',
            ],
            'episodes' => [
                '1' => [
                    [
                        'id' => '101',
                        'episode_num' => 1,
                        'title' => 'Episode 1: Pilot',
                        'container_extension' => 'mp4',
                        'info' => [
                            'duration_secs' => 3480,
                            'duration' => '00:58:00',
                            'plot' => 'Walter White, a high school chemistry teacher, is diagnosed with inoperable lung cancer.',
                            'movie_image' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                        ],
                        'custom_sid' => '',
                        'direct_source' => '',
                    ],
                    [
                        'id' => '102',
                        'episode_num' => 2,
                        'title' => 'Episode 2: Cat\'s in the Bag...',
                        'container_extension' => 'mp4',
                        'info' => [
                            'duration_secs' => 2880,
                            'duration' => '00:48:00',
                            'plot' => 'Walt and Jesse attempt to dispose of the two bodies in the RV, which becomes increasingly complicated.',
                            'movie_image' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                        ],
                        'custom_sid' => '',
                        'direct_source' => '',
                    ],
                    [
                        'id' => '103',
                        'episode_num' => 3,
                        'title' => 'Episode 3: ...And the Bag\'s in the River',
                        'container_extension' => 'mp4',
                        'info' => [
                            'duration_secs' => 2880,
                            'duration' => '00:48:00',
                            'plot' => 'Walt wrestles with the moral dilemma of whether or not to kill Krazy-8.',
                            'movie_image' => 'https://image.tmdb.org/t/p/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                        ],
                        'custom_sid' => '',
                        'direct_source' => '',
                    ],
                ],
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }

    // ==========================================
    // 4. EPG / PROGRAM GUIDE
    // ==========================================
    if ($action === 'get_short_epg' || $action === 'get_simple_data_table') {
        $streamId = (string)($_GET['stream_id'] ?? '1');
        $now = time();
        $start1 = date('Y-m-d H:i:s', $now - 1800);
        $end1   = date('Y-m-d H:i:s', $now + 1800);
        $start2 = date('Y-m-d H:i:s', $now + 1800);
        $end2   = date('Y-m-d H:i:s', $now + 5400);

        echo json_encode([
            'epg_listings' => [
                [
                    'id' => '1',
                    'epg_id' => 'epg_' . $streamId . '_1',
                    'title' => 'Live Coverage & Analysis',
                    'lang' => 'en',
                    'start' => $start1,
                    'end' => $end1,
                    'description' => 'Comprehensive live broadcast with breaking updates, in-depth reports and commentary.',
                    'channel_id' => $streamId,
                    'start_timestamp' => (string)($now - 1800),
                    'stop_timestamp' => (string)($now + 1800),
                ],
                [
                    'id' => '2',
                    'epg_id' => 'epg_' . $streamId . '_2',
                    'title' => 'Prime Time Highlights',
                    'lang' => 'en',
                    'start' => $start2,
                    'end' => $end2,
                    'description' => 'Tonight\'s prime time special presentation, featuring top highlights and exclusive features.',
                    'channel_id' => $streamId,
                    'start_timestamp' => (string)($now + 1800),
                    'stop_timestamp' => (string)($now + 5400),
                ],
            ],
        ], JSON_UNESCAPED_UNICODE);
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
            'status' => 'Disabled',
            'message' => 'Server error: ' . $e->getMessage(),
        ],
    ], JSON_UNESCAPED_UNICODE);
    exit();
}
