<?php
/**
 * SkyPro Stream Handler (stream.php)
 * Handles /live/, /movie/, and /series/ playback requests.
 */
require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/includes/credential_crypto.php';

$type     = trim((string)($_GET['type'] ?? 'live'));
$username = trim((string)($_GET['username'] ?? ''));
$password = trim((string)($_GET['password'] ?? ''));
$id       = (int)($_GET['id'] ?? 1);
$ext      = trim((string)($_GET['ext'] ?? 'm3u8'));

if ($username === '' || $password === '') {
    http_response_code(401);
    exit('Unauthorized');
}

// Verify credentials
try {
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
    }

    if (!$matched) {
        http_response_code(403);
        exit('Forbidden');
    }
} catch (Throwable $e) {
    http_response_code(500);
    exit('Database error');
}

// Industry-standard reliable CDN demo streams for playback
$liveSources = [
    1 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    2 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    3 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    4 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    5 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    6 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    7 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    8 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    9 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    10 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    11 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    12 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    13 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    14 => 'https://test-streams.mux.dev/test_001/stream.m3u8',
    15 => 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
];

$vodSources = [
    1 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    2 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    3 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    4 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    5 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    6 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    7 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    8 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    9 => 'https://www.w3schools.com/html/mov_bbb.mp4',
    10 => 'https://www.w3schools.com/html/mov_bbb.mp4',
];

$targetUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

if ($type === 'live') {
    $targetUrl = $liveSources[$id] ?? $liveSources[1];
} elseif ($type === 'movie') {
    $targetUrl = $vodSources[$id] ?? $vodSources[1];
} elseif ($type === 'series') {
    $targetUrl = $vodSources[($id % 10) + 1] ?? $vodSources[1];
}

header("Location: $targetUrl", true, 302);
exit();
