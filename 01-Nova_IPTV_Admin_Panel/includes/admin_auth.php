<?php
/**
 * صلاحيات لوحة التحكم + مزامنة الجلسة مع قاعدة البيانات.
 * يُحمَّل بعد session_start و config/database.
 *
 * أدوار اللوحة كلها (المصدر الوحيد):
 * - super_admin = مسؤول أعلى (كل الصلاحيات، لا يُنشأ من الواجهة)
 * - admin       = مدير
 * - moderator   = مشرف
 * - viewer      = ضيف / عرض فقط
 */

if (!defined('ADMIN_ROLE_SUPER_ADMIN')) {
    define('ADMIN_ROLE_SUPER_ADMIN', 'super_admin');
    define('ADMIN_ROLE_ADMIN', 'admin');
    define('ADMIN_ROLE_MODERATOR', 'moderator');
    define('ADMIN_ROLE_RESELLER', 'reseller');
    define('ADMIN_ROLE_VIEWER', 'viewer');
}

if (!function_exists('adminAllRoles')) {
    /** كل أدوار اللوحة بالترتيب من الأعلى للأدنى. */
    function adminAllRoles(): array
    {
        return [
            ADMIN_ROLE_SUPER_ADMIN,
            ADMIN_ROLE_ADMIN,
            ADMIN_ROLE_MODERATOR,
            ADMIN_ROLE_RESELLER,
            ADMIN_ROLE_VIEWER,
        ];
    }

    /** أدوار يمكن تعيينها من صفحة المسؤولين (بدون super_admin). */
    function adminAssignableRoles(): array
    {
        return [
            ADMIN_ROLE_ADMIN,
            ADMIN_ROLE_MODERATOR,
            ADMIN_ROLE_RESELLER,
            ADMIN_ROLE_VIEWER,
        ];
    }

    function adminIsKnownRole(string $role): bool
    {
        return in_array($role, adminAllRoles(), true);
    }

    function adminIsAssignableRole(string $role): bool
    {
        return in_array($role, adminAssignableRoles(), true);
    }

    function adminRoleIsSuperAdmin(string $role): bool
    {
        return $role === ADMIN_ROLE_SUPER_ADMIN;
    }

    function adminRoleIsAdmin(string $role): bool
    {
        return $role === ADMIN_ROLE_ADMIN;
    }

    function adminRoleIsModerator(string $role): bool
    {
        return $role === ADMIN_ROLE_MODERATOR;
    }

    function adminRoleIsReseller(string $role): bool
    {
        return $role === ADMIN_ROLE_RESELLER;
    }

    function adminRoleIsGuest(string $role): bool
    {
        return $role === ADMIN_ROLE_VIEWER;
    }

    function adminRoleLabel(string $role): string
    {
        $keys = [
            ADMIN_ROLE_SUPER_ADMIN => 'role.super_admin',
            ADMIN_ROLE_ADMIN => 'role.admin',
            ADMIN_ROLE_MODERATOR => 'role.moderator',
            ADMIN_ROLE_RESELLER => 'role.reseller',
            ADMIN_ROLE_VIEWER => 'role.viewer',
        ];
        $key = $keys[$role] ?? $role;
        return function_exists('t') ? t($key) : $key;
    }
}

if (!function_exists('adminBuiltinDefaultRolePermissions')) {
    /** القيم الافتراضية عند أول تشغيل أو جدول فارغ بالكامل */
    function adminBuiltinDefaultRolePermissions(): array
    {
        return [
            ADMIN_ROLE_ADMIN => [
                'profile', 'dashboard', 'devices_view', 'devices_add', 'devices_edit', 'devices_delete',
                'settings', 'feedbacks', 'feedbacks_delete', 'manage_activations', 'expiring', 'activity_log_clear',
                'notifications_send',
            ],
            ADMIN_ROLE_MODERATOR => [
                'profile', 'dashboard', 'devices_view', 'devices_add', 'devices_edit',
                'feedbacks', 'feedbacks_delete', 'expiring',
            ],
            ADMIN_ROLE_RESELLER => [
                'profile', 'dashboard', 'devices_view', 'devices_add', 'devices_edit', 'expiring',
            ],
            ADMIN_ROLE_VIEWER => [
                'profile', 'dashboard', 'devices_view', 'feedbacks', 'expiring',
            ],
        ];
    }
}

if (!function_exists('adminConfigurableRoles')) {
    function adminConfigurableRoles(): array
    {
        return adminAssignableRoles();
    }
}

if (!function_exists('adminAllAssignablePermissionKeys')) {
    /** كل المفاتيح القابلة للتخصيص (بدون *) */
    function adminAllAssignablePermissionKeys(): array
    {
        return [
            'profile', 'dashboard', 'devices_view', 'devices_add', 'devices_edit', 'devices_delete',
            'settings', 'feedbacks', 'feedbacks_delete', 'manage_activations', 'expiring', 'activity_log_clear',
            'users_manage',
            'users_create',
            'notifications_send',
        ];
    }
}

if (!function_exists('adminSeedRolePermissionsIfEmpty')) {
    function adminSeedRolePermissionsIfEmpty(PDO $conn): void
    {
        try {
            $total = (int) $conn->query('SELECT COUNT(*) FROM admin_role_permissions')->fetchColumn();
            if ($total > 0) {
                return;
            }
            $defaults = adminBuiltinDefaultRolePermissions();
            $ins = $conn->prepare('INSERT INTO admin_role_permissions (role, permission_key) VALUES (?, ?)');
            foreach (adminConfigurableRoles() as $role) {
                foreach ($defaults[$role] ?? [] as $pk) {
                    $ins->execute([$role, $pk]);
                }
            }
        } catch (Throwable $e) {
            // تجاهل إن لم يُنشأ الجدول بعد
        }
    }
}

if (!function_exists('adminPermissionPostGranted')) {
    /** هل خانة POST تعني تفعيل الصلاحية (يدعم 1 / on / مصفوفة من حقول مكررة). */
    function adminPermissionPostGranted($val): bool
    {
        if (is_array($val)) {
            foreach ($val as $item) {
                if (adminPermissionPostGranted($item)) {
                    return true;
                }
            }
            return false;
        }
        return $val === true || $val === 1 || $val === '1' || $val === 'on' || $val === 'true';
    }
}

if (!function_exists('adminEffectivePermissionKeysForRole')) {
    /** مفاتيح الصلاحيات الفعلية للعرض في المصفوفة (بدون *). */
    function adminEffectivePermissionKeysForRole(array $map, string $role): array
    {
        if (adminRoleIsSuperAdmin($role)) {
            return adminAllAssignablePermissionKeys();
        }
        $keys = $map[$role] ?? [];
        if (!is_array($keys)) {
            $keys = [];
        }
        if (in_array('*', $keys, true)) {
            return adminAllAssignablePermissionKeys();
        }
        $allow = array_flip(adminAllAssignablePermissionKeys());
        $out = [];
        foreach ($keys as $k) {
            $k = (string) $k;
            if (isset($allow[$k])) {
                $out[] = $k;
            }
        }
        return array_values(array_unique($out));
    }
}

if (!function_exists('adminWarmPermissionCache')) {
    /**
     * يبني خريطة الأدوار من الجدول لكل الأدوار القابلة للتخصيص (مدير / مشرف / زائر).
     * إن كان الجدول فارغاً بالكامل تُستخدم الافتراضيات.
     * إن وُجدت صفوف لأي دور لكن دوراً ما بلا صفوف → يُعتبر [] صريحاً (بعد حفظ المصفوفة).
     */
    function adminWarmPermissionCache(PDO $conn): void
    {
        $defaults = adminBuiltinDefaultRolePermissions();
        $map = [ADMIN_ROLE_SUPER_ADMIN => ['*']];
        try {
            $totalAll = (int) $conn->query('SELECT COUNT(*) FROM admin_role_permissions')->fetchColumn();
            $stmt = $conn->prepare('SELECT permission_key FROM admin_role_permissions WHERE role = ? ORDER BY permission_key');
            foreach (adminConfigurableRoles() as $role) {
                $stmt->execute([$role]);
                $keys = $stmt->fetchAll(PDO::FETCH_COLUMN);
                $keys = is_array($keys) ? array_values(array_filter(array_map('strval', $keys))) : [];
                $keys = array_values(array_filter($keys, static function ($k) {
                    return $k !== '' && $k !== '*';
                }));
                if (count($keys) === 0) {
                    $map[$role] = $totalAll === 0 ? ($defaults[$role] ?? []) : [];
                } else {
                    $map[$role] = $keys;
                }
            }
            $GLOBALS['_admin_role_perm_map_cached'] = $map;
        } catch (Throwable $e) {
            $GLOBALS['_admin_role_perm_map_cached'] = array_merge([ADMIN_ROLE_SUPER_ADMIN => ['*']], $defaults);
        }
    }
}

if (!function_exists('adminIsSuperAdmin')) {
    function adminIsSuperAdmin(): bool
    {
        return adminRoleIsSuperAdmin(adminSessionRole());
    }
}

if (!function_exists('adminRolePermissions')) {
    function adminRolePermissions(): array
    {
        if (!empty($GLOBALS['_admin_role_perm_map_cached']) && is_array($GLOBALS['_admin_role_perm_map_cached'])) {
            return $GLOBALS['_admin_role_perm_map_cached'];
        }
        return array_merge([ADMIN_ROLE_SUPER_ADMIN => ['*']], adminBuiltinDefaultRolePermissions());
    }

    function adminIsLoggedIn(): bool
    {
        return !empty($_SESSION['admin_logged_in']) && !empty($_SESSION['admin_user_id']);
    }

    function adminSessionRole(): string
    {
        return isset($_SESSION['admin_role']) ? (string) $_SESSION['admin_role'] : '';
    }

    /** دور المدير (admin). */
    function adminIsAdminRole(): bool
    {
        return adminRoleIsAdmin(adminSessionRole());
    }

    function adminIsModeratorRole(): bool
    {
        return adminRoleIsModerator(adminSessionRole());
    }

    /** دور الضيف (viewer) — عرض محدود بدون أسرار/روابط كاملة. */
    function adminIsGuestRole(): bool
    {
        return adminRoleIsGuest(adminSessionRole());
    }

    /** إظهار أول 3 أحرف فقط من Device ID للضيف. */
    function adminMaskDeviceId(string $deviceId): string
    {
        $deviceId = trim($deviceId);
        if ($deviceId === '') {
            return '';
        }
        $prefix = function_exists('mb_substr')
            ? mb_substr($deviceId, 0, 3)
            : substr($deviceId, 0, 3);
        return $prefix . '••••';
    }

    function adminCan(string $permission): bool
    {
        $role = adminSessionRole();
        if ($role === '') {
            return false;
        }
        $map = adminRolePermissions();
        $perms = $map[$role] ?? [];
        if (in_array('*', $perms, true)) {
            return true;
        }
        return in_array($permission, $perms, true);
    }

    /**
     * تحديث الدور والبريد من قاعدة البيانات؛ تعطيل الحساب أو حذفه يُنهي الجلسة.
     */
    function adminRefreshSessionFromDb(PDO $conn): void
    {
        if (empty($_SESSION['admin_user_id'])) {
            return;
        }
        try {
            $stmt = $conn->prepare('SELECT id, username, email, role, is_active FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([(int) $_SESSION['admin_user_id']]);
            $u = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$u || !(int) $u['is_active']) {
                $_SESSION = [];
                if (session_status() === PHP_SESSION_ACTIVE) {
                    session_destroy();
                }
                header('Location: login.php?inactive=1');
                exit;
            }
            $_SESSION['admin_role'] = $u['role'];
            $_SESSION['admin_username'] = $u['username'];
            $_SESSION['admin_email'] = $u['email'] ?? '';
        } catch (Throwable $e) {
            $_SESSION = [];
            if (session_status() === PHP_SESSION_ACTIVE) {
                session_destroy();
            }
            header('Location: login.php');
            exit;
        }
    }

    function adminRequirePermission(string $permission): void
    {
        if (!adminIsLoggedIn()) {
            header('Location: login.php');
            exit;
        }
        if (!adminCan($permission)) {
            header('Location: access_denied.php?perm=' . rawurlencode($permission));
            exit;
        }
    }

    /**
     * تسجيل الدخول + مزامنة الجلسة فقط — كل المسؤولين يمكنهم فتح الصفحات (القيود على الإجراءات والـ POST).
     * يُحوِّل مبكراً لإعدادات الأمان إن نقص مفتاح API أو تشفير الاعتمادات (قبل أي HTML).
     */
    function adminBootstrapLogin(PDO $conn): void
    {
        if (function_exists('adminNeedsInitialSetup') && adminNeedsInitialSetup($conn)) {
            header('Location: setup.php');
            exit;
        }
        if (!adminIsLoggedIn()) {
            header('Location: login.php');
            exit;
        }
        adminRefreshSessionFromDb($conn);
        adminWarmPermissionCache($conn);

        // مهم: قبل طباعة أي HTML — وإلا يظهر صفحة زرقاء فارغة بعد setup/login.
        $page = $GLOBALS['current_page'] ?? '';
        if ($page !== 'settings' && function_exists('adminRedirectIfSecurityKeysMissing')) {
            adminRedirectIfSecurityKeysMissing($conn);
        }
    }

    /**
     * @deprecated استخدم adminBootstrapLogin ثم تحقق من adminCan عند الإرسال أو عطّل النموذج
     */
    function adminBootstrap(PDO $conn, string $permission): void
    {
        adminBootstrapLogin($conn);
        adminRequirePermission($permission);
    }

    /** خريطة الصلاحيات للواجهة (أزرار + اعتراض JS) */
    function adminClientPermissionKeys(): array
    {
        return adminAllAssignablePermissionKeys();
    }

    function adminClientPermissionMap(): array
    {
        $out = [];
        foreach (adminClientPermissionKeys() as $k) {
            $out[$k] = adminCan($k);
        }
        return $out;
    }
}

if (!function_exists('adminEnsureSecurityKeysOnFirstSetup')) {
    /**
     * عند أول تثبيت (setup): يولّد App API secret + مفتاح تشفير الاعتمادات إن كانا فارغين.
     * يبقى التوليد/إعادة التوليد متاحاً من الإعدادات لاحقاً.
     */
    function adminEnsureSecurityKeysOnFirstSetup(PDO $conn): bool
    {
        require_once __DIR__ . '/api_auth.php';
        require_once __DIR__ . '/credential_crypto.php';

        $ok = true;
        try {
            if (function_exists('app_api_get_secret') && app_api_get_secret($conn) === '') {
                $secret = function_exists('app_api_regenerate_secret')
                    ? app_api_regenerate_secret($conn)
                    : '';
                if ($secret === '') {
                    $ok = false;
                }
            }
            if (function_exists('credential_is_configured') && !credential_is_configured($conn)) {
                $key = function_exists('credential_generate_and_save_key')
                    ? credential_generate_and_save_key($conn)
                    : '';
                if ($key === '') {
                    $ok = false;
                }
            }
        } catch (Throwable $e) {
            $ok = false;
        }
        return $ok;
    }
}

if (!function_exists('adminRedirectIfSecurityKeysMissing')) {
    /**
     * إن نقصت مفاتيح الأمان يُحاول توليدها تلقائياً (خصوصاً تنصيبات قديمة).
     * فقط عند فشل التوليد يُحوَّل المستخدم للإعدادات.
     */
    function adminRedirectIfSecurityKeysMissing(PDO $conn): void
    {
        if (!function_exists('adminIsLoggedIn') || !adminIsLoggedIn()) {
            return;
        }
        $page = $GLOBALS['current_page'] ?? '';
        if ($page === 'settings') {
            return;
        }

        require_once __DIR__ . '/api_auth.php';
        require_once __DIR__ . '/credential_crypto.php';

        $apiSec = function_exists('app_api_get_secret') ? (string) app_api_get_secret($conn) : '';
        $credOk = function_exists('credential_is_configured') && credential_is_configured($conn);
        if ($apiSec !== '' && $credOk) {
            return;
        }

        // محاولة توليد تلقائي بدل إجبار المستخدم على خطوة يدوية.
        if (function_exists('adminEnsureSecurityKeysOnFirstSetup')) {
            adminEnsureSecurityKeysOnFirstSetup($conn);
            $apiSec = function_exists('app_api_get_secret') ? (string) app_api_get_secret($conn) : '';
            $credOk = function_exists('credential_is_configured') && credential_is_configured($conn);
            if ($apiSec !== '' && $credOk) {
                return;
            }
        }

        $target = 'settings.php?security_setup=1';
        if (!headers_sent()) {
            header('Location: ' . $target);
            exit;
        }
        echo '<!DOCTYPE html><html><head><meta charset="UTF-8">'
            . '<meta http-equiv="refresh" content="0;url=' . htmlspecialchars($target, ENT_QUOTES, 'UTF-8') . '">'
            . '<script>location.replace(' . json_encode($target) . ');</script>'
            . '</head><body style="background:#020617;color:#e5e7eb;font-family:sans-serif;padding:2rem;">'
            . 'Redirecting to security setup…'
            . ' <a href="' . htmlspecialchars($target, ENT_QUOTES, 'UTF-8') . '" style="color:#38bdf8;">Open settings</a>'
            . '</body></html>';
        exit;
    }
}

if (!function_exists('adminCountUsers')) {
    function adminCountUsers(PDO $conn): int
    {
        try {
            $stmt = $conn->query('SELECT COUNT(*) FROM admin_users');
            return (int) $stmt->fetchColumn();
        } catch (Throwable $e) {
            return 0;
        }
    }
}

if (!function_exists('adminNeedsInitialSetup')) {
    /**
     * True when no admin users exist — buyer must create the first super admin.
     */
    function adminNeedsInitialSetup(PDO $conn): bool
    {
        return adminCountUsers($conn) === 0;
    }
}

if (!function_exists('adminRedirectIfNeedsSetup')) {
    function adminRedirectIfNeedsSetup(PDO $conn): void
    {
        if (adminNeedsInitialSetup($conn)) {
            header('Location: setup.php');
            exit;
        }
    }
}

require_once __DIR__ . '/csrf.php';
