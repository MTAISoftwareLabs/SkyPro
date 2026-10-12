<?php

function admin_playlist_code_valid_url(string $url): bool
{
    $url = trim($url);
    return $url !== '' && strlen($url) >= 8 && (bool) preg_match('#^https?://#i', $url);
}

function admin_random_playlist_code_for_device(PDO $conn, string $deviceId): string
{
    for ($i = 0; $i < 50; $i++) {
        $code = str_pad((string) random_int(10000, 999999), 6, '0', STR_PAD_LEFT);
        if ($code === '00000') {
            continue;
        }
        $st = $conn->prepare(
            'SELECT id FROM playlist_access_codes WHERE code = ? AND bound_device_id = ? LIMIT 1'
        );
        $st->execute([$code, $deviceId]);
        if (!$st->fetch()) {
            return $code;
        }
    }
    return (string) random_int(100000, 999999);
}

/**
 * @return array{ok:bool,error?:string,code?:string,id?:int}
 */
function admin_create_device_bound_playlist_code(
    PDO $conn,
    string $deviceId,
    string $label,
    string $m3uUrl
): array {
    $deviceId = trim($deviceId);
    $label = trim($label);
    $m3uUrl = trim($m3uUrl);
    if ($deviceId === '' || $label === '' || $m3uUrl === '') {
        return ['ok' => false, 'error' => 'required'];
    }
    if (!admin_playlist_code_valid_url($m3uUrl)) {
        return ['ok' => false, 'error' => 'url'];
    }
    $code = admin_random_playlist_code_for_device($conn, $deviceId);
    try {
        $ins = $conn->prepare(
            'INSERT INTO playlist_access_codes (label, m3u_url, code, max_devices, bound_device_id)
             VALUES (?, ?, ?, 1, ?)'
        );
        $ins->execute([$label, $m3uUrl, $code, $deviceId]);
        return ['ok' => true, 'code' => $code, 'id' => (int) $conn->lastInsertId()];
    } catch (PDOException $e) {
        return ['ok' => false, 'error' => 'db'];
    }
}

/**
 * Codes generated for this device only (bound_device_id).
 *
 * @return list<array<string,mixed>>
 */
function admin_list_device_bound_playlist_codes(PDO $conn, string $deviceId): array
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return [];
    }
    try {
        $st = $conn->prepare(
            'SELECT c.id, c.code, c.label, c.m3u_url, c.created_at,
                    (SELECT COUNT(*) FROM playlist_code_devices d
                     WHERE d.code_id = c.id AND d.device_id = ?) AS redeemed_on_device
             FROM playlist_access_codes c
             WHERE c.bound_device_id = ?
             ORDER BY c.id DESC'
        );
        $st->execute([$deviceId, $deviceId]);
        $out = [];
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $out[] = [
                'id' => (int) ($row['id'] ?? 0),
                'code' => (string) ($row['code'] ?? ''),
                'label' => (string) ($row['label'] ?? ''),
                'm3u_url' => (string) ($row['m3u_url'] ?? ''),
                'created_at' => (string) ($row['created_at'] ?? ''),
                'redeemed' => ((int) ($row['redeemed_on_device'] ?? 0)) > 0,
            ];
        }
        return $out;
    } catch (PDOException $e) {
        return [];
    }
}

/**
 * Codes bound to this device + codes redeemed on this device (deduped).
 *
 * @return list<array<string,mixed>>
 */
function admin_list_device_playlist_codes(PDO $conn, string $deviceId): array
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return [];
    }
    $out = [];
    $seen = [];
    try {
        $stBound = $conn->prepare(
            'SELECT c.id, c.code, c.label, c.m3u_url, c.created_at, c.bound_device_id,
                    (SELECT COUNT(*) FROM playlist_code_devices d
                     WHERE d.code_id = c.id AND d.device_id = ?) AS redeemed_on_device
             FROM playlist_access_codes c
             WHERE c.bound_device_id = ?
             ORDER BY c.id DESC'
        );
        $stBound->execute([$deviceId, $deviceId]);
        foreach ($stBound->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $id = (int) ($row['id'] ?? 0);
            if ($id <= 0 || isset($seen[$id])) {
                continue;
            }
            $seen[$id] = true;
            $out[] = [
                'id' => $id,
                'code' => (string) ($row['code'] ?? ''),
                'label' => (string) ($row['label'] ?? ''),
                'm3u_url' => (string) ($row['m3u_url'] ?? ''),
                'created_at' => (string) ($row['created_at'] ?? ''),
                'kind' => 'bound',
                'redeemed' => ((int) ($row['redeemed_on_device'] ?? 0)) > 0,
                'redeemed_at' => '',
            ];
        }

        $stUsed = $conn->prepare(
            'SELECT c.id, c.code, c.label, c.m3u_url, c.bound_device_id, d.created_at AS redeemed_at
             FROM playlist_code_devices d
             INNER JOIN playlist_access_codes c ON c.id = d.code_id
             WHERE d.device_id = ?
             ORDER BY d.created_at DESC, d.id DESC'
        );
        $stUsed->execute([$deviceId]);
        foreach ($stUsed->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $id = (int) ($row['id'] ?? 0);
            if ($id <= 0) {
                continue;
            }
            if (isset($seen[$id])) {
                foreach ($out as &$existing) {
                    if ((int) $existing['id'] === $id) {
                        $existing['redeemed'] = true;
                        $existing['redeemed_at'] = (string) ($row['redeemed_at'] ?? '');
                        if (trim((string) ($row['bound_device_id'] ?? '')) === '') {
                            $existing['kind'] = 'general';
                        }
                        break;
                    }
                }
                unset($existing);
                continue;
            }
            $seen[$id] = true;
            $bound = trim((string) ($row['bound_device_id'] ?? ''));
            $out[] = [
                'id' => $id,
                'code' => (string) ($row['code'] ?? ''),
                'label' => (string) ($row['label'] ?? ''),
                'm3u_url' => (string) ($row['m3u_url'] ?? ''),
                'created_at' => '',
                'kind' => $bound !== '' ? 'bound' : 'general',
                'redeemed' => true,
                'redeemed_at' => (string) ($row['redeemed_at'] ?? ''),
            ];
        }
    } catch (PDOException $e) {
        return [];
    }
    return $out;
}

function admin_delete_device_bound_playlist_code(PDO $conn, int $codeId, string $deviceId): bool
{
    if ($codeId <= 0 || trim($deviceId) === '') {
        return false;
    }
    try {
        $st = $conn->prepare(
            'DELETE FROM playlist_access_codes WHERE id = ? AND bound_device_id = ? LIMIT 1'
        );
        $st->execute([$codeId, $deviceId]);
        return $st->rowCount() > 0;
    } catch (PDOException $e) {
        return false;
    }
}

/**
 * Parse host input: str2.example.com:2082 or http://str2.example.com:2082/get.php
 *
 * @return array{host:string,port:?int}|null
 */
function admin_parse_playlist_host_input(string $input): ?array
{
    $input = trim($input);
    if ($input === '') {
        return null;
    }

    if (preg_match('#^https?://#i', $input)) {
        $parts = @parse_url($input);
        if (!is_array($parts) || empty($parts['host'])) {
            return null;
        }
        return [
            'host' => strtolower((string) $parts['host']),
            'port' => isset($parts['port']) ? (int) $parts['port'] : null,
        ];
    }

    $input = preg_replace('#/.*$#', '', $input) ?? $input;
    $input = strtolower(trim($input, '/'));
    if ($input === '' || !preg_match('/^[a-z0-9.\-:]+$/i', $input)) {
        return null;
    }

    if (preg_match('#^(.+):(\d{1,5})$#', $input, $m)) {
        $port = (int) $m[2];
        if ($port < 1 || $port > 65535) {
            return null;
        }
        return ['host' => strtolower($m[1]), 'port' => $port];
    }

    return ['host' => $input, 'port' => null];
}

function admin_playlist_hosts_equivalent(array $a, array $b): bool
{
    return strtolower($a['host']) === strtolower($b['host'])
        && (int) ($a['port'] ?? 0) === (int) ($b['port'] ?? 0);
}

function admin_url_matches_playlist_host(string $url, array $searchHost): bool
{
    $url = trim($url);
    if ($url === '') {
        return false;
    }
    $parts = @parse_url($url);
    if (!is_array($parts) || empty($parts['host'])) {
        return false;
    }
    $urlHost = strtolower((string) $parts['host']);
    $search = strtolower((string) $searchHost['host']);
    if ($urlHost !== $search) {
        return false;
    }
    if ($searchHost['port'] !== null) {
        return isset($parts['port']) && (int) $parts['port'] === (int) $searchHost['port'];
    }
    return true;
}

function admin_rebuild_url_from_parts(array $parts): string
{
    $scheme = !empty($parts['scheme']) ? strtolower((string) $parts['scheme']) . '://' : '';
    $host = (string) ($parts['host'] ?? '');
    $port = isset($parts['port']) ? ':' . (int) $parts['port'] : '';
    $path = (string) ($parts['path'] ?? '');
    $query = isset($parts['query']) && (string) $parts['query'] !== '' ? '?' . (string) $parts['query'] : '';
    $fragment = isset($parts['fragment']) && (string) $parts['fragment'] !== '' ? '#' . (string) $parts['fragment'] : '';

    return $scheme . $host . $port . $path . $query . $fragment;
}

function admin_replace_url_playlist_host(string $url, array $newHost): ?string
{
    $url = trim($url);
    if ($url === '') {
        return null;
    }
    $parts = @parse_url($url);
    if (!is_array($parts) || empty($parts['host'])) {
        return null;
    }

    $parts['host'] = strtolower((string) $newHost['host']);
    if ($newHost['port'] !== null) {
        $parts['port'] = (int) $newHost['port'];
    } else {
        unset($parts['port']);
    }

    $out = admin_rebuild_url_from_parts($parts);

    return $out !== '' ? $out : null;
}

/**
 * Replace old host with new host across playlist codes and linked device URLs.
 *
 * @return array{ok:bool,error?:string,codes_updated?:int,devices_updated?:int,web_playlists_updated?:int,sessions_updated?:int}
 */
function admin_bulk_replace_playlist_code_host(PDO $conn, string $oldHostInput, string $newHostInput): array
{
    $old = admin_parse_playlist_host_input($oldHostInput);
    $new = admin_parse_playlist_host_input($newHostInput);
    if (!$old || !$new) {
        return ['ok' => false, 'error' => 'invalid_host'];
    }
    if (admin_playlist_hosts_equivalent($old, $new)) {
        return ['ok' => false, 'error' => 'same_host'];
    }

    $codesUpdated = 0;
    $devicesUpdated = 0;
    $webPlaylistsUpdated = 0;
    $sessionsUpdated = 0;

    try {
        $codeRows = $conn->query('SELECT id, m3u_url FROM playlist_access_codes')->fetchAll(PDO::FETCH_ASSOC);
        $updCode = $conn->prepare('UPDATE playlist_access_codes SET m3u_url = ? WHERE id = ?');
        foreach ($codeRows as $row) {
            $url = (string) ($row['m3u_url'] ?? '');
            if (!admin_url_matches_playlist_host($url, $old)) {
                continue;
            }
            $newUrl = admin_replace_url_playlist_host($url, $new);
            if ($newUrl === null || $newUrl === '') {
                continue;
            }
            $updCode->execute([$newUrl, (int) ($row['id'] ?? 0)]);
            $codesUpdated += $updCode->rowCount();
        }

        if (!function_exists('build_account_key_from_playlist_url')) {
            require_once __DIR__ . '/credential_crypto.php';
        }

        $devRows = $conn->query(
            "SELECT id, custom_domain FROM activated_devices
             WHERE custom_domain IS NOT NULL AND TRIM(custom_domain) <> ''"
        )->fetchAll(PDO::FETCH_ASSOC);
        $updDev = $conn->prepare('UPDATE activated_devices SET custom_domain = ?, account_key = ? WHERE id = ?');
        foreach ($devRows as $row) {
            $url = (string) ($row['custom_domain'] ?? '');
            if (!admin_url_matches_playlist_host($url, $old)) {
                continue;
            }
            $newUrl = admin_replace_url_playlist_host($url, $new);
            if ($newUrl === null || $newUrl === '') {
                continue;
            }
            $accountKey = build_account_key_from_playlist_url($conn, $newUrl);
            $updDev->execute([
                $newUrl,
                $accountKey !== '' ? $accountKey : null,
                (int) ($row['id'] ?? 0),
            ]);
            $devicesUpdated += $updDev->rowCount();
        }

        $hostRows = $conn->query(
            "SELECT id, code_server_host FROM activated_devices
             WHERE code_server_host IS NOT NULL AND TRIM(code_server_host) <> ''"
        )->fetchAll(PDO::FETCH_ASSOC);
        $updDevHost = $conn->prepare('UPDATE activated_devices SET code_server_host = ? WHERE id = ?');
        foreach ($hostRows as $row) {
            $url = (string) ($row['code_server_host'] ?? '');
            if (!admin_url_matches_playlist_host($url, $old)) {
                continue;
            }
            $newUrl = admin_replace_url_playlist_host($url, $new);
            if ($newUrl === null || $newUrl === '') {
                continue;
            }
            $updDevHost->execute([$newUrl, (int) ($row['id'] ?? 0)]);
        }

        try {
            $webRows = $conn->query('SELECT id, m3u_url FROM device_web_playlists')->fetchAll(PDO::FETCH_ASSOC);
            $updWeb = $conn->prepare('UPDATE device_web_playlists SET m3u_url = ? WHERE id = ?');
            foreach ($webRows as $row) {
                $url = (string) ($row['m3u_url'] ?? '');
                if (!admin_url_matches_playlist_host($url, $old)) {
                    continue;
                }
                $newUrl = admin_replace_url_playlist_host($url, $new);
                if ($newUrl === null || $newUrl === '') {
                    continue;
                }
                $updWeb->execute([$newUrl, (int) ($row['id'] ?? 0)]);
                $webPlaylistsUpdated += $updWeb->rowCount();
            }
        } catch (PDOException $e) {
            // optional table
        }

        try {
            $sessRows = $conn->query(
                "SELECT id, code_server_host FROM device_login_sessions
                 WHERE code_server_host IS NOT NULL AND TRIM(code_server_host) <> ''"
            )->fetchAll(PDO::FETCH_ASSOC);
            $updSess = $conn->prepare('UPDATE device_login_sessions SET code_server_host = ? WHERE id = ?');
            foreach ($sessRows as $row) {
                $url = (string) ($row['code_server_host'] ?? '');
                if (!admin_url_matches_playlist_host($url, $old)) {
                    continue;
                }
                $newUrl = admin_replace_url_playlist_host($url, $new);
                if ($newUrl === null || $newUrl === '') {
                    continue;
                }
                $updSess->execute([$newUrl, (int) ($row['id'] ?? 0)]);
                $sessionsUpdated += $updSess->rowCount();
            }
        } catch (PDOException $e) {
            // optional table
        }
    } catch (PDOException $e) {
        return ['ok' => false, 'error' => 'db'];
    }

    return [
        'ok' => true,
        'codes_updated' => $codesUpdated,
        'devices_updated' => $devicesUpdated,
        'web_playlists_updated' => $webPlaylistsUpdated,
        'sessions_updated' => $sessionsUpdated,
    ];
}
