<?php
/**
 * SkyPro Xtream Codes / IPTV Server API Integration
 */

if (!function_exists('xtream_get_config')) {
    function xtream_get_config(PDO $conn): array
    {
        try {
            $stmt = $conn->query("SELECT default_server_url, xtream_api_url, xtream_api_key, xtream_api_username, xtream_api_password, xtream_api_type, xtream_sync_enabled FROM settings LIMIT 1");
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : [];
            if (!$row) {
                $row = [];
            }
            $baseUrl = trim((string)($row['xtream_api_url'] ?? $row['default_server_url'] ?? 'http://skypro-app.com:25463'));
            if ($baseUrl === '') {
                $baseUrl = 'http://skypro-app.com:25463';
            }
            return [
                'server_url' => rtrim($baseUrl, '/'),
                'api_key' => trim((string)($row['xtream_api_key'] ?? '')),
                'username' => trim((string)($row['xtream_api_username'] ?? '')),
                'password' => (string)($row['xtream_api_password'] ?? ''),
                'api_type' => trim((string)($row['xtream_api_type'] ?? 'xtream_codes')),
                'sync_enabled' => (bool)($row['xtream_sync_enabled'] ?? 1),
            ];
        } catch (Throwable $e) {
            return [
                'server_url' => 'http://skypro-app.com:25463',
                'api_key' => '',
                'username' => '',
                'password' => '',
                'api_type' => 'xtream_codes',
                'sync_enabled' => true,
            ];
        }
    }
}

if (!function_exists('xtream_test_connection')) {
    function xtream_test_connection(string $serverUrl, string $apiKey = '', string $user = '', string $pass = '', string $type = 'xtream_codes'): array
    {
        $serverUrl = rtrim(trim($serverUrl), '/');
        if ($serverUrl === '') {
            return ['success' => false, 'message' => 'Server URL is empty', 'latency_ms' => 0];
        }

        $probeUrl = $serverUrl . '/player_api.php';
        if ($user !== '' && $pass !== '') {
            $probeUrl .= '?username=' . urlencode($user) . '&password=' . urlencode($pass);
        }

        $start = microtime(true);
        $ch = curl_init($probeUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 6);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 4);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_USERAGENT, 'SkyPro-Xtream-Client/1.0');

        $headers = [];
        if ($apiKey !== '') {
            $headers[] = 'Authorization: Bearer ' . $apiKey;
            $headers[] = 'X-API-KEY: ' . $apiKey;
        }
        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        }

        $response = curl_exec($ch);
        $latency = (int)round((microtime(true) - $start) * 1000);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if ($curlError !== '') {
            return [
                'success' => false,
                'message' => 'Connection failed: ' . $curlError,
                'latency_ms' => $latency,
                'http_code' => $httpCode,
            ];
        }

        $json = @json_decode((string)$response, true);
        $authOk = is_array($json) && isset($json['user_info']) && ($json['user_info']['auth'] ?? 0) == 1;

        return [
            'success' => $httpCode >= 200 && $httpCode < 400,
            'message' => $authOk ? 'Authenticated with Streaming Server!' : ($httpCode === 200 ? 'Server responded (HTTP 200)' : "Server reachable (HTTP $httpCode)"),
            'latency_ms' => $latency,
            'http_code' => $httpCode,
            'authenticated' => $authOk,
            'server_info' => $json['server_info'] ?? null,
        ];
    }
}

if (!function_exists('xtream_create_line')) {
    function xtream_create_line(PDO $conn, array $customer): array
    {
        $config = xtream_get_config($conn);
        if (!$config['sync_enabled'] || $config['server_url'] === '') {
            return ['success' => true, 'synced' => false, 'message' => 'Local line saved (API sync disabled or no server URL)'];
        }

        $username = trim((string)($customer['username'] ?? ''));
        $password = (string)($customer['password'] ?? '');
        $expiryDate = (string)($customer['expiry_date'] ?? '');
        $expTimestamp = strtotime($expiryDate);
        if ($expTimestamp === false) {
            $expTimestamp = time() + (30 * 86400);
        }

        $serverUrl = $config['server_url'];
        $type = $config['api_type'];

        // Endpoints supported by Xtream UI, XUI.one, and standard Xtream APIs
        $postData = [
            'action' => 'user',
            'sub' => 'create',
            'username' => $username,
            'password' => $password,
            'exp_date' => date('Y-m-d H:i:s', $expTimestamp),
            'max_connections' => (int)($customer['max_connections'] ?? 1),
            'notes' => (string)($customer['notes'] ?? ''),
        ];

        if ($config['api_key'] !== '') {
            $postData['api_key'] = $config['api_key'];
        }

        $url = $serverUrl . '/api.php';
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
        curl_setopt($ch, CURLOPT_TIMEOUT, 6);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 4);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);

        $headers = [];
        if ($config['api_key'] !== '') {
            $headers[] = 'Authorization: Bearer ' . $config['api_key'];
            $headers[] = 'X-API-KEY: ' . $config['api_key'];
        }
        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        }

        $res = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        if ($err !== '') {
            return ['success' => false, 'synced' => false, 'message' => 'API connection error: ' . $err];
        }

        $json = @json_decode((string)$res, true);
        $isOk = ($code >= 200 && $code < 300) || (is_array($json) && ($json['result'] ?? '') === 'success');

        return [
            'success' => $isOk,
            'synced' => $isOk,
            'http_code' => $code,
            'response' => $json ?: $res,
            'message' => $isOk ? 'Line successfully synced to IPTV server' : "Server responded with HTTP $code",
        ];
    }
}
