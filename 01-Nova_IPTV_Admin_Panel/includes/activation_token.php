<?php

function app_act_panel_host(): string
{
    $host = (string) ($_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? '');
    $host = strtolower(trim((string) preg_replace('/:\d+$/', '', $host)));
    return $host;
}

function app_act_b64url_encode(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function app_act_b64url_decode(string $b64): string
{
    $pad = strlen($b64) % 4;
    if ($pad) {
        $b64 .= str_repeat('=', 4 - $pad);
    }
    $out = base64_decode(strtr($b64, '-_', '+/'), true);
    return is_string($out) ? $out : '';
}

function app_issue_activation_token(PDO $conn, string $deviceId, string $status, ?string $expiryDate, bool $lifetime = false): string
{
    $secret = app_api_get_secret($conn);
    if ($secret === '' || $deviceId === '') {
        return '';
    }
    $now = time();
    $claims = [
        'v' => 1,
        'did' => $deviceId,
        'st' => strtolower(trim($status)),
        'ph' => app_act_panel_host(),
        'ed' => $expiryDate ? (string) $expiryDate : '',
        'lt' => $lifetime ? 1 : 0,
        'iat' => $now,
        'exp' => $now + 172800,
    ];
    $json = json_encode($claims, JSON_UNESCAPED_UNICODE);
    if (!is_string($json)) {
        return '';
    }
    $payload = app_act_b64url_encode($json);
    $sig = hash_hmac('sha256', $payload, $secret);
    return 'stv1.' . $payload . '.' . $sig;
}

function app_with_activation_token(PDO $conn, string $deviceId, array $payload): array
{
    $status = strtolower(trim((string) ($payload['status'] ?? (!empty($payload['activated']) ? 'active' : 'inactive'))));
    $token = app_issue_activation_token(
        $conn,
        $deviceId,
        $status,
        isset($payload['expiry_date']) ? (string) $payload['expiry_date'] : null,
        !empty($payload['lifetime'])
    );
    if ($token !== '') {
        $payload['activation_token'] = $token;
    }
    return $payload;
}

function app_emit_activation_json(PDO $conn, string $deviceId, array $payload, int $http = 200): void
{
    if ($http !== 200) {
        http_response_code($http);
    }
    echo json_encode(app_with_activation_token($conn, $deviceId, $payload), JSON_UNESCAPED_UNICODE);
    exit();
}
