<?php
/**
 * App ↔ Panel API authentication (HMAC-SHA256 + nonce + HTTPS).
 *
 * Client must send:
 *   X-Nova-Timestamp: unix seconds
 *   X-Nova-Nonce: unique random hex (≥16 chars)
 *   X-Nova-Signature: hex(hmac_sha256(secret, "{ts}\n{nonce}\n{METHOD}\n{path}\n{rawBody}"))
 *
 * Buyers configure the same secret in:
 *   - Admin panel Settings → App API Secret
 *   - Flutter: lib/core/config.dart → kAppApiSecret
 *
 * Optional ownership proof (for credential-bearing responses / destructive ops):
 *   JSON body field `device_token` matching the per-device token issued at activation.
 */

if (!function_exists('app_api_ensure_secret_column')) {
    function app_api_ensure_secret_column(PDO $conn): void
    {
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN app_api_secret VARCHAR(128) DEFAULT NULL");
        } catch (PDOException $e) {
            // column may already exist
        }
    }
}

if (!function_exists('app_api_generate_secret')) {
    function app_api_generate_secret(): string
    {
        try {
            return bin2hex(random_bytes(32));
        } catch (Throwable $e) {
            return hash('sha256', uniqid((string) mt_rand(), true) . microtime(true));
        }
    }
}

if (!function_exists('app_api_get_secret')) {
    /** Returns configured secret, or '' if the buyer has not set one yet. */
    function app_api_get_secret(PDO $conn): string
    {
        app_api_ensure_secret_column($conn);
        try {
            $stmt = $conn->query("SELECT app_api_secret FROM settings LIMIT 1");
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
            if (!$row) {
                return '';
            }
            return trim((string) ($row['app_api_secret'] ?? ''));
        } catch (PDOException $e) {
            return '';
        }
    }
}

if (!function_exists('app_api_get_or_create_secret')) {
    /**
     * @deprecated Prefer app_api_get_secret() + explicit regenerate in Settings.
     * Kept for backward compatibility with settings UI helpers.
     */
    function app_api_get_or_create_secret(PDO $conn): string
    {
        $secret = app_api_get_secret($conn);
        if ($secret !== '') {
            return $secret;
        }
        return app_api_regenerate_secret($conn);
    }
}

if (!function_exists('app_api_regenerate_secret')) {
    function app_api_regenerate_secret(PDO $conn): string
    {
        app_api_ensure_secret_column($conn);
        $secret = app_api_generate_secret();
        try {
            $stmt = $conn->query("SELECT id FROM settings LIMIT 1");
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
            if (!$row) {
                return '';
            }
            $upd = $conn->prepare("UPDATE settings SET app_api_secret = ? WHERE id = ?");
            $upd->execute([$secret, (int) $row['id']]);
            return $secret;
        } catch (PDOException $e) {
            return '';
        }
    }
}

if (!function_exists('app_api_request_path')) {
    function app_api_request_path(): string
    {
        $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
        $path = parse_url($uri, PHP_URL_PATH);
        if (!is_string($path) || $path === '') {
            $path = '/';
        }
        // Normalize to the /api/... suffix used by the Flutter client.
        if (preg_match('#(/api/[^?]*)#', $path, $m)) {
            $apiPath = rtrim((string) $m[1], '/');
            return $apiPath !== '' ? $apiPath : $m[1];
        }
        return $path;
    }
}

if (!function_exists('app_api_build_canonical')) {
    function app_api_build_canonical(string $timestamp, string $nonce, string $method, string $path, string $rawBody): string
    {
        return $timestamp . "\n" . $nonce . "\n" . strtoupper($method) . "\n" . $path . "\n" . $rawBody;
    }
}

if (!function_exists('app_api_reject')) {
    function app_api_reject(int $http, string $message): void
    {
        http_response_code($http);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode([
            'success' => false,
            'message' => $message,
            'debug' => [
                'method' => strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? '')),
                'path' => (string) ($_SERVER['REQUEST_URI'] ?? ''),
                'https' => !empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off',
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit();
    }
}

if (!function_exists('app_api_is_https_request')) {
    function app_api_is_https_request(): bool
    {
        if (!empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
            return true;
        }
        if ((int) ($_SERVER['SERVER_PORT'] ?? 0) === 443) {
            return true;
        }
        $fwd = strtolower(trim((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')));
        if ($fwd === 'https') {
            return true;
        }
        $fwdSsl = strtolower(trim((string) ($_SERVER['HTTP_X_FORWARDED_SSL'] ?? '')));
        return $fwdSsl === 'on' || $fwdSsl === '1';
    }
}

if (!function_exists('app_api_is_local_request_host')) {
    /** Allow plain HTTP only on loopback for local panel development. */
    function app_api_is_local_request_host(): bool
    {
        $host = (string) ($_SERVER['HTTP_HOST'] ?? '');
        if ($host === '') {
            $host = (string) ($_SERVER['SERVER_NAME'] ?? '');
        }
        $host = strtolower(preg_replace('/:\d+$/', '', $host) ?? '');
        return in_array($host, ['localhost', '127.0.0.1', '::1'], true);
    }
}

if (!function_exists('app_api_require_https')) {
    function app_api_require_https(): void
    {
        // Opt-out for rare reverse-proxy edge cases (buyer-controlled).
        if (getenv('NOVA_API_ALLOW_HTTP') === '1') {
            return;
        }
        if (app_api_is_https_request() || app_api_is_local_request_host()) {
            return;
        }
        app_api_reject(403, 'https_required');
    }
}

if (!function_exists('app_api_ensure_nonce_table')) {
    function app_api_ensure_nonce_table(PDO $conn): void
    {
        try {
            $conn->exec(
                "CREATE TABLE IF NOT EXISTS api_request_nonces (
                    nonce VARCHAR(64) NOT NULL,
                    created_at INT UNSIGNED NOT NULL,
                    PRIMARY KEY (nonce),
                    KEY idx_api_nonce_created (created_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
            );
        } catch (PDOException $e) {
            // ignore
        }
    }
}

if (!function_exists('app_api_consume_nonce')) {
    /**
     * Rejects reused nonces within the replay window. Returns false on reuse/DB error.
     */
    function app_api_consume_nonce(PDO $conn, string $nonce): bool
    {
        app_api_ensure_nonce_table($conn);
        $now = time();
        // Drop expired nonces (keep slightly longer than timestamp skew window).
        try {
            $conn->exec('DELETE FROM api_request_nonces WHERE created_at < ' . (int) ($now - 600));
        } catch (PDOException $e) {
            // ignore cleanup failures
        }
        try {
            $ins = $conn->prepare('INSERT INTO api_request_nonces (nonce, created_at) VALUES (?, ?)');
            $ins->execute([$nonce, $now]);
            return true;
        } catch (PDOException $e) {
            // Duplicate primary key = replay
            return false;
        }
    }
}

if (!function_exists('app_api_ensure_device_token_column')) {
    function app_api_ensure_device_token_column(PDO $conn): void
    {
        try {
            $conn->exec(
                "ALTER TABLE activated_devices ADD COLUMN device_api_token_hash VARCHAR(64) DEFAULT NULL"
            );
        } catch (PDOException $e) {
            // may already exist
        }
    }
}

if (!function_exists('app_api_hash_device_token')) {
    function app_api_hash_device_token(string $token): string
    {
        return hash('sha256', $token);
    }
}

if (!function_exists('app_api_issue_device_token')) {
    /**
     * Creates (or rotates) a per-device ownership token. Returns plaintext token once.
     */
    function app_api_issue_device_token(PDO $conn, string $deviceId): string
    {
        app_api_ensure_device_token_column($conn);
        try {
            $token = bin2hex(random_bytes(32));
        } catch (Throwable $e) {
            $token = hash('sha256', uniqid((string) mt_rand(), true) . microtime(true) . $deviceId);
        }
        $hash = app_api_hash_device_token($token);
        try {
            $upd = $conn->prepare(
                'UPDATE activated_devices SET device_api_token_hash = ? WHERE device_id = ?'
            );
            $upd->execute([$hash, $deviceId]);
        } catch (PDOException $e) {
            return '';
        }
        return $token;
    }
}

if (!function_exists('app_api_device_token_hash')) {
    function app_api_device_token_hash(PDO $conn, string $deviceId): string
    {
        app_api_ensure_device_token_column($conn);
        try {
            $stmt = $conn->prepare(
                'SELECT device_api_token_hash FROM activated_devices WHERE device_id = ? LIMIT 1'
            );
            $stmt->execute([$deviceId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            return $row ? trim((string) ($row['device_api_token_hash'] ?? '')) : '';
        } catch (PDOException $e) {
            return '';
        }
    }
}

if (!function_exists('app_api_verify_device_ownership')) {
    /**
     * True when the caller presents the correct per-device token.
     * Devices without a stored hash are treated as not yet bound (false).
     */
    function app_api_verify_device_ownership(PDO $conn, string $deviceId, string $presentedToken): bool
    {
        $deviceId = trim($deviceId);
        $presentedToken = trim($presentedToken);
        if ($deviceId === '' || $presentedToken === '' || strlen($presentedToken) < 32) {
            return false;
        }
        $stored = app_api_device_token_hash($conn, $deviceId);
        if ($stored === '') {
            return false;
        }
        return hash_equals($stored, app_api_hash_device_token($presentedToken));
    }
}

if (!function_exists('app_api_ensure_device_token_for_response')) {
    /**
     * Ensures the device has an ownership token. Returns plaintext token when newly
     * issued (or re-issued when $forceRotate). Empty string if token already exists
     * and was not rotated (client should keep its stored copy).
     */
    function app_api_ensure_device_token_for_response(PDO $conn, string $deviceId, bool $forceRotate = false): string
    {
        $existing = app_api_device_token_hash($conn, $deviceId);
        if ($existing !== '' && !$forceRotate) {
            return '';
        }
        return app_api_issue_device_token($conn, $deviceId);
    }
}

if (!function_exists('app_api_strip_playlist_credentials')) {
    /**
     * Removes username/password (and similar) query params before any public response.
     * Defense-in-depth when a playlist URL must be acknowledged without leaking secrets.
     */
    function app_api_strip_playlist_credentials(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return '';
        }
        $parts = parse_url($url);
        if ($parts === false || empty($parts['scheme']) || empty($parts['host'])) {
            return '';
        }
        $out = $parts['scheme'] . '://' . $parts['host'];
        if (!empty($parts['port'])) {
            $out .= ':' . $parts['port'];
        }
        if (!empty($parts['path'])) {
            $out .= $parts['path'];
        }
        if (!empty($parts['query'])) {
            parse_str((string) $parts['query'], $qs);
            foreach (['password', 'pass', 'pwd', 'username', 'user', 'login', 'token', 'auth'] as $k) {
                unset($qs[$k]);
            }
            if ($qs) {
                $out .= '?' . http_build_query($qs);
            }
        }
        return $out;
    }
}

if (!function_exists('app_api_require_signed_request')) {
    /**
     * Verifies HTTPS, HMAC signature, timestamp skew, and nonce replay protection.
     * Must be called after database.php + createDatabaseTable().
     *
     * @return string Raw request body (may be empty).
     */
    function app_api_require_signed_request(PDO $conn, ?string $rawBodyOverride = null): string
    {
        app_api_require_https();

        $secret = app_api_get_secret($conn);
        if ($secret === '') {
            app_api_reject(500, 'api_secret_not_configured');
        }

        $tsHeader = trim((string) ($_SERVER['HTTP_X_NOVA_TIMESTAMP'] ?? ''));
        $nonceHeader = strtolower(trim((string) ($_SERVER['HTTP_X_NOVA_NONCE'] ?? '')));
        $sigHeader = strtolower(trim((string) ($_SERVER['HTTP_X_NOVA_SIGNATURE'] ?? '')));

        if ($tsHeader === '' || $sigHeader === '' || !ctype_digit($tsHeader)) {
            app_api_reject(401, 'missing_or_invalid_signature');
        }
        if ($nonceHeader === '' || !preg_match('/^[a-f0-9]{16,64}$/', $nonceHeader)) {
            app_api_reject(401, 'missing_or_invalid_nonce');
        }

        $ts = (int) $tsHeader;
        $now = time();
        // Allow ±5 minutes clock skew.
        if (abs($now - $ts) > 300) {
            app_api_reject(401, 'timestamp_expired');
        }

        if (!app_api_consume_nonce($conn, $nonceHeader)) {
            app_api_reject(401, 'nonce_reused');
        }

        $rawBody = $rawBodyOverride;
        if ($rawBody === null) {
            $rawBody = file_get_contents('php://input');
            if ($rawBody === false) {
                $rawBody = '';
            }
        }

        $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
        $path = rtrim(app_api_request_path(), '/');
        if ($path === '') {
            $path = '/';
        }
        $pathCandidates = [$path];
        if (preg_match('#(/api/[^?]*)#', $path, $m)) {
            $apiPath = rtrim((string) $m[1], '/');
            if ($apiPath !== '' && !in_array($apiPath, $pathCandidates, true)) {
                $pathCandidates[] = $apiPath;
            }
        }
        $file = basename($path);
        if ($file !== '' && $file !== '/' && $file !== '.') {
            $apiFile = '/api/' . $file;
            if (!in_array($apiFile, $pathCandidates, true)) {
                $pathCandidates[] = $apiFile;
            }
        }

        $matched = false;
        foreach ($pathCandidates as $p) {
            $canonical = app_api_build_canonical($tsHeader, $nonceHeader, $method, $p, $rawBody);
            $expected = hash_hmac('sha256', $canonical, $secret);
            if (hash_equals($expected, $sigHeader)) {
                $matched = true;
                break;
            }
        }
        if (!$matched) {
            error_log(
                '[NovaAPI] invalid_signature method=' . $method
                . ' path=' . $path
                . ' bodyLen=' . strlen($rawBody)
                . ' uri=' . (string) ($_SERVER['REQUEST_URI'] ?? '')
            );
            app_api_reject(401, 'invalid_signature');
        }

        error_log(
            '[NovaAPI] hmac_ok method=' . $method
            . ' path=' . $path
            . ' bodyLen=' . strlen($rawBody)
        );

        $GLOBALS['APP_API_RAW_BODY'] = $rawBody;
        return $rawBody;
    }
}

if (!function_exists('app_api_json_payload')) {
    /** JSON body from HMAC read, with POST fallback when php://input was already consumed. */
    function app_api_json_payload(?string $raw = null): array
    {
        if ($raw === null) {
            $raw = (string) ($GLOBALS['APP_API_RAW_BODY'] ?? '');
        }
        $data = json_decode((string) $raw, true);
        if (!is_array($data)) {
            $data = is_array($_POST) ? $_POST : [];
        }
        return is_array($data) ? $data : [];
    }
}

if (!function_exists('app_api_field')) {
    function app_api_field(array $data, string $key, string $default = ''): string
    {
        $v = $data[$key] ?? $_POST[$key] ?? $_GET[$key] ?? $default;
        return trim((string) $v);
    }
}

if (!function_exists('app_api_cors_headers')) {
    /**
     * Mobile app clients do not need browser CORS. Avoid wildcard ACAO which
     * reviewers flag on credential-bearing endpoints.
     */
    function app_api_cors_headers(): void
    {
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, X-Nova-Timestamp, X-Nova-Nonce, X-Nova-Signature');
        // Intentionally omit Access-Control-Allow-Origin.
    }
}
