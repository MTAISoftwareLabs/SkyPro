<?php
/**
 * SkyPro Xtream Codes / IPTV Server API Universal Integration Engine
 * Universal Compatibility with:
 * - Xtream Codes 1.x & 2.x
 * - Xtream UI (XC-UI)
 * - XUI.one (v1.x & v2.x)
 * - 1Stream / OneStream
 * - ZapX Panel
 * - Line-based API / Reseller Web APIs
 */

if (!function_exists('xtream_normalize_server_url')) {
    /**
     * Normalizes streaming server URL and auto-corrects HTTP vs HTTPS scheme.
     */
    function xtream_normalize_server_url(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return '';
        }
        if (!preg_match('~^https?://~i', $url)) {
            // Check known HTTPS ports
            if (preg_match('~:(25463|25500|443)/?$~', $url)) {
                $url = 'https://' . $url;
            } else {
                $url = 'http://' . $url;
            }
        } elseif (preg_match('~^http://~i', $url) && preg_match('~:(25463|25500|443)/?$~', $url)) {
            // Auto-upgrade plain http on SSL ports to prevent HTTP 400 Bad Request
            $url = preg_replace('~^http://~i', 'https://', $url);
        }
        return rtrim($url, '/');
    }
}

if (!function_exists('xtream_get_config')) {
    function xtream_get_config(PDO $conn): array
    {
        try {
            $stmt = $conn->query("SELECT default_server_url, xtream_api_url, xtream_api_key, xtream_api_username, xtream_api_password, xtream_api_type, xtream_sync_enabled FROM settings LIMIT 1");
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : [];
            if (!$row) {
                $row = [];
            }
            $rawUrl = trim((string)($row['xtream_api_url'] ?? $row['default_server_url'] ?? 'https://skypro-app.com:25463'));
            if ($rawUrl === '' || $rawUrl === 'http://skypro-app.com:25463') {
                $rawUrl = 'https://skypro-app.com:25463';
            }
            return [
                'server_url' => xtream_normalize_server_url($rawUrl),
                'api_key' => trim((string)($row['xtream_api_key'] ?? '')),
                'username' => trim((string)($row['xtream_api_username'] ?? '')),
                'password' => (string)($row['xtream_api_password'] ?? ''),
                'api_type' => trim((string)($row['xtream_api_type'] ?? 'auto')),
                'sync_enabled' => (bool)($row['xtream_sync_enabled'] ?? 1),
            ];
        } catch (Throwable $e) {
            return [
                'server_url' => 'https://skypro-app.com:25463',
                'api_key' => '',
                'username' => '',
                'password' => '',
                'api_type' => 'auto',
                'sync_enabled' => true,
            ];
        }
    }
}

if (!function_exists('xtream_http_call')) {
    /**
     * Executes HTTP/HTTPS requests with auto-retry for HTTPS SSL redirects and JSON detection.
     */
    function xtream_http_call(string $url, string $method = 'GET', $data = null, array $headers = [], int $timeout = 6, bool $sendJson = false): array
    {
        $start = microtime(true);
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 4);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_USERAGENT, 'SkyPro-IPTV-Hub/2.0');

        if ($method === 'POST') {
            curl_setopt($ch, CURLOPT_POST, true);
            if ($data !== null) {
                if ($sendJson) {
                    $jsonPayload = is_string($data) ? $data : json_encode($data);
                    curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonPayload);
                    $headers[] = 'Content-Type: application/json';
                    $headers[] = 'Content-Length: ' . strlen($jsonPayload);
                } else {
                    curl_setopt($ch, CURLOPT_POSTFIELDS, is_array($data) ? http_build_query($data) : $data);
                }
            }
        }

        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        }

        $res = curl_exec($ch);
        $latency = (int)round((microtime(true) - $start) * 1000);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        // Auto-handle "400 The plain HTTP request was sent to HTTPS port"
        if ($code === 400 && strpos((string)$res, 'The plain HTTP request was sent to HTTPS port') !== false && preg_match('~^http://~i', $url)) {
            $httpsUrl = preg_replace('~^http://~i', 'https://', $url);
            return xtream_http_call($httpsUrl, $method, $data, $headers, $timeout, $sendJson);
        }

        $json = @json_decode((string)$res, true);
        return [
            'success' => $code >= 200 && $code < 400,
            'http_code' => $code,
            'body' => $res,
            'json' => is_array($json) ? $json : null,
            'latency_ms' => $latency,
            'error' => $err,
            'url' => $url,
        ];
    }
}

if (!function_exists('xtream_test_connection')) {
    function xtream_test_connection(string $serverUrl, string $apiKey = '', string $user = '', string $pass = '', string $type = 'auto'): array
    {
        $serverUrl = xtream_normalize_server_url($serverUrl);
        if ($serverUrl === '') {
            return ['success' => false, 'message' => 'Streaming server URL is empty.', 'latency_ms' => 0];
        }

        $headers = [];
        if ($apiKey !== '') {
            $headers[] = 'Authorization: Bearer ' . $apiKey;
            $headers[] = 'X-API-KEY: ' . $apiKey;
        }

        $authOk = false;
        $bestCode = 0;
        $bestLatency = 0;
        $serverInfo = null;

        // Probes for universal compatibility across panels:
        // 1. player_api.php (Standard Xtream Codes / UI client & auth test)
        $probeUrl = $serverUrl . '/player_api.php';
        if ($user !== '' && $pass !== '') {
            $probeUrl .= '?username=' . urlencode($user) . '&password=' . urlencode($pass);
        }
        $res = xtream_http_call($probeUrl, 'GET', null, $headers, 5);
        $bestCode = $res['http_code'];
        $bestLatency = $res['latency_ms'];

        if (is_array($res['json']) && isset($res['json']['user_info'])) {
            $authOk = ($res['json']['user_info']['auth'] ?? 0) == 1;
            $serverInfo = $res['json']['server_info'] ?? null;
            if ($authOk) {
                return [
                    'success' => true,
                    'authenticated' => true,
                    'message' => 'Connected & Authenticated with Streaming Server (Xtream Codes API)!',
                    'latency_ms' => $bestLatency,
                    'http_code' => $bestCode,
                    'server_info' => $serverInfo,
                ];
            }
        }

        // 2. api.php (Xtream UI / Xtream Codes panel API)
        if ($res['http_code'] === 404 || $res['http_code'] === 400 || $res['http_code'] === 0) {
            $apiUrl = $serverUrl . '/api.php';
            if ($user !== '' && $pass !== '') {
                $apiUrl .= '?username=' . urlencode($user) . '&password=' . urlencode($pass) . '&action=user&sub=get';
            } elseif ($apiKey !== '') {
                $apiUrl .= '?api_key=' . urlencode($apiKey) . '&action=user&sub=get';
            }
            $resApi = xtream_http_call($apiUrl, 'GET', null, $headers, 4);
            if ($resApi['http_code'] >= 200 && $resApi['http_code'] < 400) {
                return [
                    'success' => true,
                    'authenticated' => is_array($resApi['json']),
                    'message' => "Connected to Xtream Panel API (HTTP {$resApi['http_code']})",
                    'latency_ms' => $resApi['latency_ms'],
                    'http_code' => $resApi['http_code'],
                    'server_info' => $resApi['json'],
                ];
            }
            if ($resApi['http_code'] > 0) {
                $bestCode = $resApi['http_code'];
                $bestLatency = $resApi['latency_ms'];
            }
        }

        // 3. XUI.one API probe
        if ($res['http_code'] === 404 || $res['http_code'] === 400 || $res['http_code'] === 0) {
            $xuiProbe = $serverUrl . '/api/';
            if ($apiKey !== '') {
                $xuiProbe = $serverUrl . '/' . urlencode($apiKey) . '/';
            }
            $resXui = xtream_http_call($xuiProbe, 'GET', null, $headers, 4);
            if ($resXui['http_code'] >= 200 && $resXui['http_code'] < 400) {
                return [
                    'success' => true,
                    'authenticated' => is_array($resXui['json']),
                    'message' => "Connected to XUI Panel API (HTTP {$resXui['http_code']})",
                    'latency_ms' => $resXui['latency_ms'],
                    'http_code' => $resXui['http_code'],
                ];
            }
        }

        // 4. Root host probe (server online check)
        $resRoot = xtream_http_call($serverUrl . '/', 'GET', null, $headers, 4);
        if ($resRoot['http_code'] >= 200 && $resRoot['http_code'] < 500) {
            return [
                'success' => true,
                'authenticated' => false,
                'message' => "Streaming host reachable (HTTP {$resRoot['http_code']}). Enter server API key or panel URL in Settings to sync.",
                'latency_ms' => $resRoot['latency_ms'],
                'http_code' => $resRoot['http_code'],
            ];
        }

        if ($resRoot['error'] !== '') {
            return [
                'success' => false,
                'message' => 'Connection failed: ' . $resRoot['error'],
                'latency_ms' => $resRoot['latency_ms'],
                'http_code' => $resRoot['http_code'],
            ];
        }

        return [
            'success' => $bestCode >= 200 && $bestCode < 400,
            'message' => "Server responded with HTTP {$bestCode}",
            'latency_ms' => $bestLatency,
            'http_code' => $bestCode,
            'authenticated' => false,
        ];
    }
}

if (!function_exists('xtream_create_line')) {
    /**
     * Creates a customer streaming line across ANY IPTV panel platform.
     * Iterates through supported protocol formats until one successfully accepts the creation request.
     */
    function xtream_create_line(PDO $conn, array $customer): array
    {
        $config = xtream_get_config($conn);
        if (!$config['sync_enabled'] || $config['server_url'] === '') {
            return [
                'success' => true,
                'synced' => false,
                'message' => 'Saved locally in SkyPro (API sync disabled or no server URL)',
            ];
        }

        $serverUrl = xtream_normalize_server_url($config['server_url']);
        $username = trim((string)($customer['username'] ?? ''));
        $password = (string)($customer['password'] ?? '');
        $expiryDate = (string)($customer['expiry_date'] ?? '');
        $expTimestamp = strtotime($expiryDate);
        if ($expTimestamp === false) {
            $expTimestamp = time() + (30 * 86400);
        }

        $maxConnections = max(1, (int)($customer['max_connections'] ?? 1));
        $notes = (string)($customer['notes'] ?? '');
        $formattedDate = date('Y-m-d H:i:s', $expTimestamp);

        $headers = [];
        if ($config['api_key'] !== '') {
            $headers[] = 'Authorization: Bearer ' . $config['api_key'];
            $headers[] = 'X-API-KEY: ' . $config['api_key'];
        }

        // Shared authentication credentials for panel requests
        $adminUser = $config['username'];
        $adminPass = $config['password'];
        $apiKey = $config['api_key'];

        // Define Universal Trial Pipeline: All recognized panel endpoints and payload formats
        $attempts = [];

        // 1. Xtream Codes / Xtream UI standard api.php (POST with user_data array)
        $attempts[] = [
            'name' => 'Xtream Codes api.php (POST user_data)',
            'url' => $serverUrl . '/api.php',
            'method' => 'POST',
            'json' => false,
            'data' => [
                'action' => 'user',
                'sub' => 'create',
                'username' => $adminUser ?: $username,
                'password' => $adminPass ?: $password,
                'user_data' => [
                    'username' => $username,
                    'password' => $password,
                    'exp_date' => $formattedDate,
                    'max_connections' => $maxConnections,
                    'notes' => $notes,
                    'bouquet' => '["1"]',
                ],
                'api_key' => $apiKey,
            ],
        ];

        // 2. Xtream UI Flat Form (api.php POST flat params)
        $attempts[] = [
            'name' => 'Xtream UI api.php (POST flat parameters)',
            'url' => $serverUrl . '/api.php',
            'method' => 'POST',
            'json' => false,
            'data' => [
                'action' => 'user_create',
                'username' => $adminUser,
                'password' => $adminPass,
                'user_username' => $username,
                'user_password' => $password,
                'new_username' => $username,
                'new_password' => $password,
                'exp_date' => $formattedDate,
                'expire_date' => $expTimestamp,
                'max_connections' => $maxConnections,
                'notes' => $notes,
                'api_key' => $apiKey,
            ],
        ];

        // 3. Xtream Codes GET API (api.php via query string)
        $attempts[] = [
            'name' => 'Xtream Codes api.php (GET action=user&sub=create)',
            'url' => $serverUrl . '/api.php?action=user&sub=create&username=' . urlencode($adminUser) . '&password=' . urlencode($adminPass) .
                '&user_data%5Busername%5D=' . urlencode($username) . '&user_data%5Bpassword%5D=' . urlencode($password) .
                '&user_data%5Bexp_date%5D=' . urlencode($formattedDate) . '&user_data%5Bmax_connections%5D=' . $maxConnections .
                ($apiKey !== '' ? '&api_key=' . urlencode($apiKey) : ''),
            'method' => 'GET',
            'json' => false,
            'data' => null,
        ];

        // 4. XUI.one API Endpoint (/api/?action=user_create)
        $attempts[] = [
            'name' => 'XUI.one /api/?action=user_create',
            'url' => $serverUrl . '/api/?action=user_create',
            'method' => 'POST',
            'json' => false,
            'data' => [
                'username' => $username,
                'password' => $password,
                'exp_date' => $expTimestamp,
                'max_connections' => $maxConnections,
                'notes' => $notes,
                'api_key' => $apiKey,
            ],
        ];

        // 5. XUI.one Token Endpoint (/{api_key}/?action=user_create)
        if ($apiKey !== '') {
            $attempts[] = [
                'name' => 'XUI.one Token URL /{api_key}/?action=user_create',
                'url' => $serverUrl . '/' . urlencode($apiKey) . '/?action=user_create',
                'method' => 'POST',
                'json' => false,
                'data' => [
                    'username' => $username,
                    'password' => $password,
                    'exp_date' => $expTimestamp,
                    'max_connections' => $maxConnections,
                    'notes' => $notes,
                ],
            ];
        }

        // 6. XUI.one JSON API (/api/user/create)
        $attempts[] = [
            'name' => 'XUI JSON Endpoint /api/user/create',
            'url' => $serverUrl . '/api/user/create',
            'method' => 'POST',
            'json' => true,
            'data' => [
                'username' => $username,
                'password' => $password,
                'exp_date' => $expTimestamp,
                'max_connections' => $maxConnections,
                'notes' => $notes,
            ],
        ];

        // 7. ZapX / 1Stream /panel_api.php
        $attempts[] = [
            'name' => '1Stream / ZapX /panel_api.php',
            'url' => $serverUrl . '/panel_api.php',
            'method' => 'POST',
            'json' => false,
            'data' => [
                'username' => $adminUser,
                'password' => $adminPass,
                'api_key' => $apiKey,
                'action' => 'user_create',
                'user_username' => $username,
                'user_password' => $password,
                'exp_date' => $expTimestamp,
            ],
        ];

        // 8. player_api.php registration endpoint fallback
        $attempts[] = [
            'name' => 'Xtream player_api.php user registration',
            'url' => $serverUrl . '/player_api.php?action=register&username=' . urlencode($username) . '&password=' . urlencode($password) .
                '&exp_date=' . urlencode($formattedDate) . ($apiKey !== '' ? '&api_key=' . urlencode($apiKey) : ''),
            'method' => 'GET',
            'json' => false,
            'data' => null,
        ];

        $lastError = '';
        $lastCode = 0;
        $lastResponse = null;

        // Execute attempts sequentially until an endpoint successfully accepts the creation
        foreach ($attempts as $attempt) {
            $res = xtream_http_call($attempt['url'], $attempt['method'], $attempt['data'], $headers, 5, $attempt['json']);
            $lastCode = $res['http_code'];
            $lastResponse = $res['json'] ?: $res['body'];

            // Check if attempt succeeded
            $json = $res['json'];
            $isSuccess = false;
            $msg = '';

            if (is_array($json)) {
                $resultStr = strtolower((string)($json['result'] ?? $json['status'] ?? ''));
                if (
                    $resultStr === 'success' ||
                    $resultStr === 'ok' ||
                    ($json['status'] ?? 0) === 200 ||
                    !empty($json['user_id']) ||
                    !empty($json['id']) ||
                    (!empty($json['data']) && is_array($json['data']))
                ) {
                    $isSuccess = true;
                    $msg = 'Line synced to IPTV server via ' . $attempt['name'];
                } elseif (!empty($json['message']) || !empty($json['error'])) {
                    // Server returned a business logic error (e.g., username taken, credit limit, bouquet required)
                    $errText = (string)($json['message'] ?? $json['error']);
                    // If server actively responded with a specific user error, we know the endpoint is correct!
                    return [
                        'success' => false,
                        'synced' => false,
                        'http_code' => $res['http_code'],
                        'response' => $json,
                        'message' => "Streaming Server error: {$errText}",
                    ];
                }
            } elseif ($res['http_code'] >= 200 && $res['http_code'] < 300 && strlen(trim((string)$res['body'])) > 0) {
                // HTTP 200 with non-empty body and no error keywords
                $bodyLower = strtolower((string)$res['body']);
                if (strpos($bodyLower, 'error') === false && strpos($bodyLower, 'failed') === false && strpos($bodyLower, 'not found') === false) {
                    $isSuccess = true;
                    $msg = 'Line synced to IPTV server (HTTP ' . $res['http_code'] . ')';
                }
            }

            if ($isSuccess) {
                return [
                    'success' => true,
                    'synced' => true,
                    'http_code' => $res['http_code'],
                    'response' => $lastResponse,
                    'message' => $msg,
                ];
            }

            // Record last meaningful error
            if ($res['http_code'] > 0 && $res['http_code'] !== 404) {
                $lastError = "Server responded with HTTP {$res['http_code']}";
            }
        }

        // If all remote API endpoints returned 404 or connection failures:
        // Provide actionable, clear explanation
        $finalMsg = '';
        if ($lastCode === 404) {
            $finalMsg = "Streaming server reached ({$serverUrl}), but API endpoints returned HTTP 404. Verify panel URL & port in Settings.";
        } elseif ($lastError !== '') {
            $finalMsg = $lastError;
        } else {
            $finalMsg = "Could not sync line to IPTV server (HTTP {$lastCode})";
        }

        return [
            'success' => false,
            'synced' => false,
            'http_code' => $lastCode,
            'response' => $lastResponse,
            'message' => $finalMsg,
        ];
    }
}
