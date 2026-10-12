<?php
/**
 * At-rest encryption for third-party IPTV credentials + account fingerprints.
 * Uses AES-256-GCM. Key material lives in settings.credential_enc_key
 * (independent from App API HMAC secret so regenerating the API secret
 * does not wipe stored credentials).
 */

if (!function_exists('credential_ensure_key_column')) {
    function credential_ensure_key_column(PDO $conn): void
    {
        try {
            $conn->exec("ALTER TABLE settings ADD COLUMN credential_enc_key VARCHAR(128) DEFAULT NULL");
        } catch (PDOException $e) {
            // may already exist
        }
    }
}

if (!function_exists('credential_get_key')) {
    /**
     * Returns the buyer-configured at-rest key, or '' if not set.
     * Never auto-generates — buyers must set/generate it in Settings.
     */
    function credential_get_key(PDO $conn): string
    {
        credential_ensure_key_column($conn);
        try {
            $stmt = $conn->query('SELECT credential_enc_key FROM settings LIMIT 1');
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
            if (!$row) {
                return '';
            }
            return trim((string) ($row['credential_enc_key'] ?? ''));
        } catch (PDOException $e) {
            return '';
        }
    }
}

if (!function_exists('credential_is_configured')) {
    function credential_is_configured(PDO $conn): bool
    {
        return credential_get_key($conn) !== '';
    }
}

if (!function_exists('credential_generate_and_save_key')) {
    /** Generates a unique 64-char hex key for this installation. */
    function credential_generate_and_save_key(PDO $conn): string
    {
        credential_ensure_key_column($conn);
        try {
            $key = bin2hex(random_bytes(32));
        } catch (Throwable $e) {
            $key = hash('sha256', uniqid((string) mt_rand(), true) . microtime(true));
        }
        try {
            $stmt = $conn->query('SELECT id FROM settings LIMIT 1');
            $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : false;
            if (!$row) {
                return '';
            }
            $upd = $conn->prepare('UPDATE settings SET credential_enc_key = ? WHERE id = ?');
            $upd->execute([$key, (int) $row['id']]);
            return $key;
        } catch (PDOException $e) {
            return '';
        }
    }
}

if (!function_exists('credential_get_or_create_key')) {
    /**
     * @deprecated Does not auto-create anymore (CodeCanyon: no shared/default key).
     * Returns configured key or ''.
     */
    function credential_get_or_create_key(PDO $conn): string
    {
        return credential_get_key($conn);
    }
}

if (!function_exists('credential_derive_aes_key')) {
    function credential_derive_aes_key(string $keyMaterial): string
    {
        return hash('sha256', $keyMaterial, true);
    }
}

if (!function_exists('credential_encrypt')) {
    /**
     * Encrypt plaintext. Returns enc:v1:... or '' on failure / empty input.
     */
    function credential_encrypt(string $plain, string $keyMaterial): string
    {
        $plain = (string) $plain;
        if ($plain === '' || $keyMaterial === '') {
            return '';
        }
        if (!function_exists('openssl_encrypt')) {
            return '';
        }
        $key = credential_derive_aes_key($keyMaterial);
        $iv = random_bytes(12);
        $tag = '';
        $cipher = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, '', 16);
        if ($cipher === false || $tag === '') {
            return '';
        }
        return 'enc:v1:' . base64_encode($iv . $tag . $cipher);
    }
}

if (!function_exists('credential_is_encrypted')) {
    function credential_is_encrypted(string $stored): bool
    {
        return strncmp($stored, 'enc:v1:', 7) === 0;
    }
}

if (!function_exists('credential_decrypt')) {
    /**
     * Decrypt enc:v1:... payload. Legacy plaintext is returned as-is.
     */
    function credential_decrypt(string $stored, string $keyMaterial): string
    {
        $stored = (string) $stored;
        if ($stored === '') {
            return '';
        }
        if (!credential_is_encrypted($stored)) {
            // Legacy plaintext row — still return so admin UI / migration works.
            return $stored;
        }
        if ($keyMaterial === '' || !function_exists('openssl_decrypt')) {
            return '';
        }
        $raw = base64_decode(substr($stored, 7), true);
        if ($raw === false || strlen($raw) < 29) {
            return '';
        }
        $iv = substr($raw, 0, 12);
        $tag = substr($raw, 12, 16);
        $cipher = substr($raw, 28);
        $key = credential_derive_aes_key($keyMaterial);
        $plain = openssl_decrypt($cipher, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
        return $plain === false ? '' : $plain;
    }
}

if (!function_exists('credential_encrypt_password_for_storage')) {
    function credential_encrypt_password_for_storage(PDO $conn, string $plainPassword): string
    {
        $plainPassword = trim($plainPassword);
        if ($plainPassword === '') {
            return '';
        }
        $key = credential_get_key($conn);
        if ($key === '') {
            return '';
        }
        $enc = credential_encrypt($plainPassword, $key);
        // Never fall back to plaintext when OpenSSL is available.
        return $enc;
    }
}

if (!function_exists('credential_decrypt_password_from_storage')) {
    function credential_decrypt_password_from_storage(PDO $conn, string $stored): string
    {
        $stored = trim($stored);
        if ($stored === '') {
            return '';
        }
        $key = credential_get_key($conn);
        if ($key === '') {
            return '';
        }
        return credential_decrypt($stored, $key);
    }
}

if (!function_exists('build_account_key')) {
    /**
     * Opaque account fingerprint for device-limit matching.
     * Format: {username}#{hmac} — password is never stored in account_key.
     * Legacy rows may still be "username:password"; display helpers handle both.
     */
    function build_account_key(PDO $conn, string $username, string $password): string
    {
        $username = trim($username);
        $password = (string) $password;
        if ($username === '') {
            return '';
        }
        $secret = credential_get_key($conn);
        if ($secret === '') {
            // No shared fallback key — fingerprints require a configured enc key.
            return '';
        }
        $hmac = hash_hmac('sha256', $username . "\0" . $password, $secret);
        return $username . '#' . $hmac;
    }
}

if (!function_exists('build_account_key_from_playlist_url')) {
    function build_account_key_from_playlist_url(PDO $conn, string $playlistUrl): string
    {
        $playlistUrl = trim($playlistUrl);
        if ($playlistUrl === '') {
            return '';
        }
        try {
            $parts = parse_url($playlistUrl);
            $query = [];
            if (!empty($parts['query'])) {
                parse_str((string) $parts['query'], $query);
            }
            $user = isset($query['username']) ? trim((string) $query['username']) : '';
            $pass = isset($query['password']) ? trim((string) $query['password']) : '';
            if ($user !== '' && $pass !== '') {
                return build_account_key($conn, $user, $pass);
            }
        } catch (Throwable $e) {
            // fall through
        }
        $secret = credential_get_key($conn);
        if ($secret === '') {
            return '';
        }
        return 'url#' . hash_hmac('sha256', $playlistUrl, $secret);
    }
}

if (!function_exists('account_key_display_label')) {
    /**
     * Human-readable username (or short url tag) from account_key without exposing secrets.
     */
    function account_key_display_label(string $accountKey): string
    {
        $accountKey = trim($accountKey);
        if ($accountKey === '') {
            return '';
        }
        if (strpos($accountKey, '#') !== false) {
            $left = explode('#', $accountKey, 2)[0];
            return $left === 'url' ? 'playlist' : $left;
        }
        // Legacy username:password
        if (strpos($accountKey, ':') !== false) {
            return explode(':', $accountKey, 2)[0];
        }
        return $accountKey;
    }
}

if (!function_exists('parse_xtream_credentials_from_url')) {
    /**
     * Extract Xtream server base + optional username/password from get.php / M3U URLs.
     *
     * @return array{server_base:string,username:string,password:string}|null
     */
    function parse_xtream_credentials_from_url(string $raw): ?array
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }
        $parts = @parse_url($raw);
        if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
            return null;
        }
        $query = [];
        if (!empty($parts['query'])) {
            parse_str((string) $parts['query'], $query);
        }
        $username = isset($query['username']) ? trim((string) $query['username']) : '';
        $password = isset($query['password']) ? trim((string) $query['password']) : '';
        $base = strtolower((string) $parts['scheme']) . '://' . $parts['host'];
        if (!empty($parts['port'])) {
            $base .= ':' . (int) $parts['port'];
        }
        return [
            'server_base' => $base,
            'username' => $username,
            'password' => $password,
        ];
    }
}

if (!function_exists('is_xtream_host_only_url')) {
    function is_xtream_host_only_url(string $raw): bool
    {
        $raw = trim($raw);
        if ($raw === '') {
            return false;
        }
        $parts = @parse_url($raw);
        if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
            return false;
        }
        $path = (string) ($parts['path'] ?? '');
        $query = (string) ($parts['query'] ?? '');

        return ($path === '' || $path === '/') && $query === '';
    }
}

if (!function_exists('build_xtream_m3u_playlist_url')) {
    /**
     * Build classic Xtream get.php playlist URL from separate host + user + pass.
     * Example: http://host:port/get.php?username=u&password=p&type=m3u_plus&output=m3u8
     */
    function build_xtream_m3u_playlist_url(string $serverHost, string $username, string $password): string
    {
        $serverHost = trim($serverHost);
        $username = trim($username);
        $password = (string) $password;
        if ($serverHost === '' || $username === '' || $password === '') {
            return '';
        }
        // Accept bare host:port as well as full scheme://host[:port][/...]
        if (!preg_match('#^https?://#i', $serverHost)) {
            $serverHost = 'http://' . ltrim($serverHost, '/');
        }
        $parts = @parse_url($serverHost);
        if (!is_array($parts) || empty($parts['host'])) {
            return '';
        }
        $scheme = strtolower((string) ($parts['scheme'] ?? 'http'));
        if ($scheme !== 'http' && $scheme !== 'https') {
            $scheme = 'http';
        }
        $base = $scheme . '://' . $parts['host'];
        if (!empty($parts['port'])) {
            $base .= ':' . (int) $parts['port'];
        }
        return $base
            . '/get.php?username=' . rawurlencode($username)
            . '&password=' . rawurlencode($password)
            . '&type=m3u_plus&output=m3u8';
    }
}

if (!function_exists('apply_current_login_to_device')) {
    function apply_current_login_to_device(PDO $conn, string $deviceId, array $fields): void
    {
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return;
        }
        $customDomain = isset($fields['custom_domain']) ? trim((string) $fields['custom_domain']) : '';
        if ($customDomain !== '') {
            $stmt = $conn->prepare(
                'UPDATE activated_devices
                 SET code_server_host = ?, manual_login_username = ?, manual_login_password = ?,
                     account_key = ?, account_display_name = ?, custom_domain = ?
                 WHERE device_id = ?'
            );
            $stmt->execute([
                ($fields['code_server_host'] ?? '') !== '' ? $fields['code_server_host'] : null,
                ($fields['manual_login_username'] ?? '') !== '' ? $fields['manual_login_username'] : null,
                ($fields['manual_login_password'] ?? '') !== '' ? $fields['manual_login_password'] : null,
                ($fields['account_key'] ?? '') !== '' ? $fields['account_key'] : null,
                ($fields['account_display_name'] ?? '') !== '' ? $fields['account_display_name'] : null,
                $customDomain,
                $deviceId,
            ]);
            return;
        }
        $stmt = $conn->prepare(
            'UPDATE activated_devices
             SET code_server_host = ?, manual_login_username = ?, manual_login_password = ?,
                 account_key = ?, account_display_name = ?
             WHERE device_id = ?'
        );
        $stmt->execute([
            ($fields['code_server_host'] ?? '') !== '' ? $fields['code_server_host'] : null,
            ($fields['manual_login_username'] ?? '') !== '' ? $fields['manual_login_username'] : null,
            ($fields['manual_login_password'] ?? '') !== '' ? $fields['manual_login_password'] : null,
            ($fields['account_key'] ?? '') !== '' ? $fields['account_key'] : null,
            ($fields['account_display_name'] ?? '') !== '' ? $fields['account_display_name'] : null,
            $deviceId,
        ]);
    }
}

if (!function_exists('normalize_device_login_server_host')) {
    function normalize_device_login_server_host(string $host): string
    {
        $host = strtolower(trim($host));
        if ($host === '') {
            return '';
        }
        return rtrim($host, '/');
    }
}

if (!function_exists('find_existing_device_login_session')) {
    /**
     * Find a prior login row for the same device + server host.
     */
    function find_existing_device_login_session(
        PDO $conn,
        string $deviceId,
        string $serverHost,
        string $username = ''
    ): ?array {
        unset($username);
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return null;
        }
        $wantHost = normalize_device_login_server_host($serverHost);
        if ($wantHost === '') {
            return null;
        }
        try {
            $st = $conn->prepare(
                'SELECT id, code_server_host
                 FROM device_login_sessions
                 WHERE device_id = ?
                 ORDER BY COALESCE(last_login_at, created_at) DESC, id DESC'
            );
            $st->execute([$deviceId]);
            foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $rowHost = normalize_device_login_server_host((string) ($row['code_server_host'] ?? ''));
                if ($rowHost === $wantHost) {
                    return $row;
                }
            }
        } catch (PDOException $e) {
            return null;
        }
        return null;
    }
}

if (!function_exists('record_device_login_session')) {
    /**
     * Add a login snapshot for a device. When $setAsCurrent=true, it becomes the active login in the app/panel.
     *
     * @return int|null inserted session id
     */
    function record_device_login_session(
        PDO $conn,
        string $deviceId,
        string $serverHost,
        string $username,
        string $passwordPlain,
        string $accountKey = '',
        string $displayName = '',
        bool $setAsCurrent = false,
        string $source = 'app'
    ): ?int {
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return null;
        }
        if (strlen($serverHost) > 500) {
            $serverHost = substr($serverHost, 0, 500);
        }
        if (strlen($username) > 255) {
            $username = substr($username, 0, 255);
        }
        if (strlen($displayName) > 255) {
            $displayName = substr($displayName, 0, 255);
        }
        if ($source === '') {
            $source = 'app';
        }
        if (strlen($source) > 32) {
            $source = substr($source, 0, 32);
        }

        $passEnc = '';
        if ($passwordPlain !== '') {
            $passEnc = credential_encrypt_password_for_storage($conn, $passwordPlain);
            if ($passEnc === '' && $passwordPlain !== '') {
                return null;
            }
        }
        if ($accountKey === '' && $username !== '' && $passwordPlain !== '') {
            $accountKey = build_account_key($conn, $username, $passwordPlain);
        }

        $existing = find_existing_device_login_session($conn, $deviceId, $serverHost, $username);
        if ($existing !== null) {
            $sessionId = (int) ($existing['id'] ?? 0);
            if ($sessionId <= 0) {
                return null;
            }
            if ($setAsCurrent) {
                $clear = $conn->prepare('UPDATE device_login_sessions SET is_current = 0 WHERE device_id = ?');
                $clear->execute([$deviceId]);
            }
            $upd = $conn->prepare(
                'UPDATE device_login_sessions
                 SET manual_login_username = COALESCE(?, manual_login_username),
                     manual_login_password = COALESCE(?, manual_login_password),
                     account_key = COALESCE(?, account_key),
                     account_display_name = COALESCE(?, account_display_name),
                     is_current = ?,
                     source = ?,
                     last_login_at = NOW()
                 WHERE id = ? AND device_id = ?'
            );
            $upd->execute([
                $username !== '' ? $username : null,
                $passEnc !== '' ? $passEnc : null,
                $accountKey !== '' ? $accountKey : null,
                $displayName !== '' ? $displayName : null,
                $setAsCurrent ? 1 : 0,
                $source,
                $sessionId,
                $deviceId,
            ]);
            if ($setAsCurrent) {
                $playlistUrl = build_xtream_m3u_playlist_url($serverHost, $username, $passwordPlain);
                apply_current_login_to_device($conn, $deviceId, [
                    'code_server_host' => $serverHost,
                    'manual_login_username' => $username,
                    'manual_login_password' => $passEnc,
                    'account_key' => $accountKey,
                    'account_display_name' => $displayName,
                    'custom_domain' => $playlistUrl,
                ]);
            }
            return $sessionId;
        }

        if ($setAsCurrent) {
            $clear = $conn->prepare('UPDATE device_login_sessions SET is_current = 0 WHERE device_id = ?');
            $clear->execute([$deviceId]);
        }

        $ins = $conn->prepare(
            'INSERT INTO device_login_sessions
             (device_id, code_server_host, manual_login_username, manual_login_password, account_key, account_display_name, is_current, source, last_login_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())'
        );
        $ins->execute([
            $deviceId,
            $serverHost !== '' ? $serverHost : null,
            $username !== '' ? $username : null,
            $passEnc !== '' ? $passEnc : null,
            $accountKey !== '' ? $accountKey : null,
            $displayName !== '' ? $displayName : null,
            $setAsCurrent ? 1 : 0,
            $source,
        ]);
        $sessionId = (int) $conn->lastInsertId();

        if ($setAsCurrent) {
            $playlistUrl = build_xtream_m3u_playlist_url($serverHost, $username, $passwordPlain);
            apply_current_login_to_device($conn, $deviceId, [
                'code_server_host' => $serverHost,
                'manual_login_username' => $username,
                'manual_login_password' => $passEnc,
                'account_key' => $accountKey,
                'account_display_name' => $displayName,
                'custom_domain' => $playlistUrl,
            ]);
        }

        return $sessionId > 0 ? $sessionId : null;
    }
}

if (!function_exists('fetch_device_login_sessions')) {
    /** @return list<array<string,mixed>> */
    function fetch_device_login_sessions(PDO $conn, string $deviceId, int $limit = 15): array
    {
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return [];
        }
        if ($limit < 1) {
            $limit = 15;
        }
        if ($limit > 50) {
            $limit = 50;
        }
        try {
            $st = $conn->prepare(
                'SELECT id, code_server_host, manual_login_username, manual_login_password,
                        account_key, account_display_name, is_current, source, created_at, last_login_at
                 FROM device_login_sessions
                 WHERE device_id = ?
                 ORDER BY is_current DESC, COALESCE(last_login_at, created_at) DESC, id DESC
                 LIMIT ' . (int) $limit
            );
            $st->execute([$deviceId]);
            return $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
        } catch (PDOException $e) {
            return [];
        }
    }
}

if (!function_exists('delete_device_login_session')) {
    /** حذف جلسة دخول واحدة لهذا الجهاز. */
    function delete_device_login_session(PDO $conn, int $sessionId, string $deviceId): bool
    {
        $deviceId = trim($deviceId);
        if ($sessionId <= 0 || $deviceId === '') {
            return false;
        }
        try {
            $st = $conn->prepare(
                'DELETE FROM device_login_sessions WHERE id = ? AND device_id = ? LIMIT 1'
            );
            $st->execute([$sessionId, $deviceId]);
            return $st->rowCount() > 0;
        } catch (PDOException $e) {
            return false;
        }
    }
}

if (!function_exists('delete_all_device_login_sessions')) {
    /** حذف كل سجل الدخول لهذا الجهاز. */
    function delete_all_device_login_sessions(PDO $conn, string $deviceId): int
    {
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return 0;
        }
        try {
            $st = $conn->prepare('DELETE FROM device_login_sessions WHERE device_id = ?');
            $st->execute([$deviceId]);
            return (int) $st->rowCount();
        } catch (PDOException $e) {
            return 0;
        }
    }
}

if (!function_exists('device_presence_is_online')) {
    function device_presence_is_online(?string $lastSeenAt, int $thresholdSeconds = 60): bool
    {
        if ($lastSeenAt === null || trim($lastSeenAt) === '') {
            return false;
        }
        $ts = strtotime($lastSeenAt);
        if ($ts === false) {
            return false;
        }

        return (time() - $ts) <= $thresholdSeconds;
    }
}

if (!function_exists('sync_device_login_fields_from_url')) {
    /**
     * Parse playlist/server URL and store a login snapshot.
     * Full credentials → new session + current (replaces active login only).
     * Host-only → add pending session without touching the current active login.
     */
    function sync_device_login_fields_from_url(
        PDO $conn,
        string $deviceId,
        string $url,
        bool $setAsCurrent = true,
        string $source = 'admin'
    ): void {
        $deviceId = trim($deviceId);
        $url = trim($url);
        if ($deviceId === '' || $url === '') {
            return;
        }
        $creds = parse_xtream_credentials_from_url($url);
        if ($creds === null) {
            return;
        }
        $serverBase = trim((string) ($creds['server_base'] ?? ''));
        $username = trim((string) ($creds['username'] ?? ''));
        $password = (string) ($creds['password'] ?? '');

        if ($username !== '' && $password !== '') {
            record_device_login_session(
                $conn,
                $deviceId,
                $serverBase,
                $username,
                $password,
                '',
                '',
                $setAsCurrent,
                $source
            );
            return;
        }

        if (is_xtream_host_only_url($url) && $serverBase !== '') {
            record_device_login_session(
                $conn,
                $deviceId,
                $serverBase,
                '',
                '',
                '',
                '',
                false,
                $source
            );
        }
    }
}

if (!function_exists('account_key_tooltip_safe')) {
    /** Tooltip text without password material. */
    function account_key_tooltip_safe(string $accountKey, string $serverHost = ''): string
    {
        $label = account_key_display_label($accountKey);
        $parts = [];
        if ($label !== '') {
            $parts[] = $label;
        }
        $serverHost = trim($serverHost);
        if ($serverHost !== '') {
            $parts[] = $serverHost;
        }
        return implode(' | ', $parts);
    }
}

if (!function_exists('credential_migrate_plaintext_passwords')) {
    /**
     * One-shot: encrypt any legacy plaintext manual_login_password rows.
     */
    function credential_migrate_plaintext_passwords(PDO $conn): void
    {
        try {
            $stmt = $conn->query(
                "SELECT id, manual_login_password FROM activated_devices
                 WHERE manual_login_password IS NOT NULL
                   AND manual_login_password <> ''
                   AND manual_login_password NOT LIKE 'enc:v1:%'
                 LIMIT 200"
            );
            if (!$stmt) {
                return;
            }
            $upd = $conn->prepare('UPDATE activated_devices SET manual_login_password = ? WHERE id = ?');
            while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
                $plain = (string) ($row['manual_login_password'] ?? '');
                if ($plain === '' || credential_is_encrypted($plain)) {
                    continue;
                }
                $enc = credential_encrypt_password_for_storage($conn, $plain);
                if ($enc !== '') {
                    $upd->execute([$enc, (int) $row['id']]);
                }
            }
        } catch (Throwable $e) {
            // ignore — non-fatal
        }
    }
}
