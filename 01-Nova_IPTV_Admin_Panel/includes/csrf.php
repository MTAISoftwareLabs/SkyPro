<?php
/**
 * CSRF protection for admin panel state-changing requests.
 */

if (!function_exists('admin_csrf_token')) {
    function admin_csrf_token(): string
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            return '';
        }
        if (empty($_SESSION['admin_csrf_token']) || !is_string($_SESSION['admin_csrf_token'])) {
            $_SESSION['admin_csrf_token'] = bin2hex(random_bytes(32));
        }
        return (string) $_SESSION['admin_csrf_token'];
    }

    function admin_csrf_field(): string
    {
        $token = htmlspecialchars(admin_csrf_token(), ENT_QUOTES, 'UTF-8');
        return '<input type="hidden" name="csrf_token" value="' . $token . '">';
    }

    function admin_csrf_meta_tag(): string
    {
        $token = htmlspecialchars(admin_csrf_token(), ENT_QUOTES, 'UTF-8');
        return '<meta name="csrf-token" content="' . $token . '">';
    }

    function admin_csrf_request_token(): string
    {
        $fromPost = isset($_POST['csrf_token']) ? trim((string) $_POST['csrf_token']) : '';
        if ($fromPost !== '') {
            return $fromPost;
        }
        $fromHeader = trim((string) ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? ''));
        if ($fromHeader !== '') {
            return $fromHeader;
        }
        // Do not read php://input here — it can only be consumed once (JSON admin APIs).
        return '';
    }

    function admin_csrf_validate(?string $token = null): bool
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            return false;
        }
        $expected = admin_csrf_token();
        if ($expected === '') {
            return false;
        }
        $got = $token !== null ? trim($token) : admin_csrf_request_token();
        if ($got === '' || strlen($got) < 32) {
            return false;
        }
        return hash_equals($expected, $got);
    }

    /**
     * Reject invalid CSRF on state-changing requests.
     * Call at the start of POST handlers (HTML forms and admin AJAX).
     */
    function admin_require_csrf(bool $asJson = false): void
    {
        if (admin_csrf_validate()) {
            return;
        }
        if ($asJson
            || (isset($_POST['settings_ajax']) && (string) $_POST['settings_ajax'] === '1')
            || (isset($_SERVER['HTTP_X_REQUESTED_WITH'])
                && strtolower((string) $_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest')
        ) {
            header('Content-Type: application/json; charset=utf-8');
            http_response_code(403);
            $msg = function_exists('t') ? t('msg.csrf_invalid') : 'Invalid security token. Please refresh and try again.';
            echo json_encode(['success' => false, 'message' => $msg], JSON_UNESCAPED_UNICODE);
            exit;
        }
        http_response_code(403);
        $msg = function_exists('t') ? t('msg.csrf_invalid') : 'Invalid security token. Please refresh and try again.';
        echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>CSRF</title></head><body>';
        echo '<p>' . htmlspecialchars($msg, ENT_QUOTES, 'UTF-8') . '</p>';
        echo '<p><a href="javascript:history.back()">Back</a></p></body></html>';
        exit;
    }
}

if (!function_exists('admin_parse_positive_int_id')) {
    /** Strict positive integer ID from query/body (blocks IDOR via non-numeric IDs). */
    function admin_parse_positive_int_id($raw): int
    {
        if (is_int($raw)) {
            return $raw > 0 ? $raw : 0;
        }
        $s = trim((string) $raw);
        if ($s === '' || !ctype_digit($s)) {
            return 0;
        }
        $n = (int) $s;
        return $n > 0 ? $n : 0;
    }
}

if (!function_exists('admin_find_managed_device')) {
    /**
     * Load a device the logged-in admin is allowed to manage.
     * Soft-deleted rows are out of scope for edit/delete UI actions.
     * For resellers, isolates devices to those matching customers created by that reseller.
     */
    function admin_find_managed_device(PDO $conn, int $id): ?array
    {
        if ($id <= 0) {
            return null;
        }
        try {
            $isIsolated = !empty($_SESSION['admin_user_id']) && (!function_exists('adminIsSuperAdmin') || !adminIsSuperAdmin());
            if ($isIsolated) {
                $stmt = $conn->prepare(
                    "SELECT a.* FROM activated_devices a
                     INNER JOIN iptv_customers c ON (
                         c.username = a.manual_login_username 
                         OR c.username = a.account_display_name 
                         OR a.account_key LIKE CONCAT(c.username, '#%') 
                         OR a.account_key = c.username
                     )
                     WHERE a.id = ?
                       AND (a.status IS NULL OR a.status <> 'deleted')
                       AND c.created_by = ?
                     LIMIT 1"
                );
                $stmt->execute([$id, (int)$_SESSION['admin_user_id']]);
            } else {
                $stmt = $conn->prepare(
                    "SELECT * FROM activated_devices
                     WHERE id = ?
                       AND (status IS NULL OR status <> 'deleted')
                     LIMIT 1"
                );
                $stmt->execute([$id]);
            }
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            return $row ?: null;
        } catch (PDOException $e) {
            return null;
        }
    }
}
