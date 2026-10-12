<?php

function mp_playlist_code_valid_url(string $url): bool
{
    $url = trim($url);
    return $url !== '' && strlen($url) >= 8 && (bool) preg_match('#^https?://#i', $url);
}

function mp_ensure_playlist_access_schema(PDO $conn): void
{
    try {
        $conn->exec("CREATE TABLE IF NOT EXISTS playlist_access_codes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(255) NOT NULL,
            m3u_url TEXT NOT NULL,
            code VARCHAR(6) NOT NULL,
            max_devices INT NOT NULL DEFAULT 1,
            bound_device_id VARCHAR(255) NULL DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_playlist_code (code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    } catch (PDOException $e) {
    }
    try {
        $conn->exec('ALTER TABLE playlist_access_codes ADD COLUMN max_devices INT NOT NULL DEFAULT 1');
    } catch (PDOException $e) {
    }
    try {
        $conn->exec('ALTER TABLE playlist_access_codes ADD COLUMN bound_device_id VARCHAR(255) NULL DEFAULT NULL');
    } catch (PDOException $e) {
    }
    try {
        $conn->exec('ALTER TABLE playlist_access_codes DROP INDEX uq_playlist_code');
    } catch (PDOException $e) {
    }
    try {
        $conn->exec('ALTER TABLE playlist_access_codes DROP INDEX uq_playlist_code_device');
    } catch (PDOException $e) {
    }
    try {
        $conn->exec('ALTER TABLE playlist_access_codes ADD UNIQUE KEY uq_playlist_code_device (code, bound_device_id)');
    } catch (PDOException $e) {
    }
    try {
        $conn->exec("CREATE TABLE IF NOT EXISTS playlist_code_devices (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code_id INT NOT NULL,
            device_id VARCHAR(255) NOT NULL,
            device_label VARCHAR(255) DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_playlist_code_device (code_id, device_id),
            KEY idx_pcd_code_id (code_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    } catch (PDOException $e) {
    }
}

function mp_random_playlist_code_for_device(PDO $conn, string $deviceId): string
{
    for ($i = 0; $i < 50; $i++) {
        $code = str_pad((string) random_int(10000, 999999), 6, '0', STR_PAD_LEFT);
        if ($code === '00000') {
            continue;
        }
        try {
            $st = $conn->prepare(
                'SELECT id FROM playlist_access_codes WHERE code = ? AND bound_device_id = ? LIMIT 1'
            );
            $st->execute([$code, $deviceId]);
            if (!$st->fetch()) {
                return $code;
            }
        } catch (PDOException $e) {
            return $code;
        }
    }
    return (string) random_int(100000, 999999);
}

/** @return array{ok:bool,error?:string,code?:string,id?:int} */
function mp_create_device_bound_playlist_code(
    PDO $conn,
    string $deviceId,
    string $label,
    string $m3uUrl,
    string $customCode = ''
): array {
    $deviceId = trim($deviceId);
    $label = trim($label);
    $m3uUrl = trim($m3uUrl);
    if ($deviceId === '' || $label === '' || $m3uUrl === '') {
        return ['ok' => false, 'error' => 'required'];
    }
    if (!mp_playlist_code_valid_url($m3uUrl)) {
        return ['ok' => false, 'error' => 'url'];
    }

    $customCode = preg_replace('/\D/', '', $customCode);
    if ($customCode !== '') {
        if (strlen($customCode) < 5 || strlen($customCode) > 6) {
            return ['ok' => false, 'error' => 'format'];
        }
        if ($customCode === '00000') {
            return ['ok' => false, 'error' => 'demo'];
        }
        $code = $customCode;
    } else {
        $code = mp_random_playlist_code_for_device($conn, $deviceId);
    }

    try {
        $chk = $conn->prepare(
            'SELECT id FROM playlist_access_codes WHERE code = ? AND bound_device_id = ? LIMIT 1'
        );
        $chk->execute([$code, $deviceId]);
        if ($chk->fetch()) {
            return ['ok' => false, 'error' => 'duplicate'];
        }
        $ins = $conn->prepare(
            'INSERT INTO playlist_access_codes (label, m3u_url, code, max_devices, bound_device_id)
             VALUES (?, ?, ?, 1, ?)'
        );
        $ins->execute([$label, $m3uUrl, $code, $deviceId]);
        return ['ok' => true, 'code' => $code, 'id' => (int) $conn->lastInsertId()];
    } catch (PDOException $e) {
        if ((int) $e->getCode() === 23000) {
            return ['ok' => false, 'error' => 'duplicate'];
        }
        return ['ok' => false, 'error' => 'db'];
    }
}

/** @return list<array<string,mixed>> */
function mp_list_device_playlist_codes(PDO $conn, string $deviceId): array
{
    $deviceId = trim($deviceId);
    if ($deviceId === '') {
        return [];
    }
    $out = [];
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
    } catch (PDOException $e) {
        return [];
    }
    return $out;
}

function mp_delete_device_bound_playlist_code(PDO $conn, int $codeId, string $deviceId): bool
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
