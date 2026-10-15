<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$isSuperAdmin = adminIsSuperAdmin();
$isSubAdmin = adminIsSubAdminRole();
$canCreateUsers = $isSuperAdmin || $isSubAdmin || adminCan('users_create');
$canManageUsers = $isSuperAdmin;

// السماح لمالك النظام الرئيسي (super_admin) أو الموظفين/المدراء الفرعيين (sub-admins) بفتح وإدارة حسابات الموزعين
if (!$canCreateUsers && !$canManageUsers) {
    header('Location: access_denied.php?perm=users_create');
    exit;
}

$current_page = 'admin_users';
$myId = (int) $_SESSION['admin_user_id'];

function adminCountActiveSuperAdmins(PDO $conn): int
{
    $stmt = $conn->query("SELECT COUNT(*) FROM admin_users WHERE role = 'super_admin' AND is_active = 1");
    return (int) $stmt->fetchColumn();
}

function adminPermGroupLabel(string $group, string $lang): string
{
    $map = [
        'users' => ['ar' => 'المستخدمون', 'en' => 'Users'],
        'devices' => ['ar' => 'الأجهزة', 'en' => 'Devices'],
        'settings' => ['ar' => 'الإعدادات', 'en' => 'Settings'],
        'licenses' => ['ar' => 'التراخيص', 'en' => 'Licenses'],
        'products' => ['ar' => 'المنتجات', 'en' => 'Products'],
        'dashboard' => ['ar' => 'لوحة التحكم', 'en' => 'Dashboard'],
        'logs' => ['ar' => 'السجلات', 'en' => 'Logs'],
        'reports' => ['ar' => 'التقارير', 'en' => 'Reports'],
        'ads' => ['ar' => 'الإعلانات', 'en' => 'Ads'],
        'servers' => ['ar' => 'السيرفرات', 'en' => 'Servers'],
        'general' => ['ar' => 'عام', 'en' => 'General'],
    ];

    if (isset($map[$group])) {
        return $map[$group][$lang === 'ar' ? 'ar' : 'en'];
    }

    return ucfirst(str_replace('_', ' ', $group));
}

/** هل يُسمح بحذف هذا الصف */
function adminUserRowCanDelete(PDO $conn, array $u, int $myId): bool
{
    if ((int) ($u['id'] ?? 0) === $myId) {
        return false;
    }
    $targetRole = (string) ($u['role'] ?? '');
    $isSuper = adminIsSuperAdmin();
    // أي مستخدم غير super_admin مسموح له فقط بحذف حسابات الموزعين (reseller) التي أنشأها بنفسه
    if (!$isSuper) {
        $myUsername = !empty($_SESSION['admin_username']) ? trim((string)$_SESSION['admin_username']) : '';
        $createdBy = (int) ($u['created_by'] ?? 0);
        $creatorName = trim((string)($u['creator_username'] ?? ''));
        if ($targetRole !== ADMIN_ROLE_RESELLER || ($createdBy !== $myId && ($myUsername === '' || $creatorName !== $myUsername))) {
            return false;
        }
    }
    if (adminRoleIsSuperAdmin($targetRole) && !$isSuper) {
        return false;
    }
    if (adminRoleIsSuperAdmin($targetRole) && (int) ($u['is_active'] ?? 0) === 1 && adminCountActiveSuperAdmins($conn) <= 1) {
        return false;
    }
    return true;
}

/** هل يُسمح بتعطيل/تفعيل */
function adminUserRowCanToggle(PDO $conn, array $u, int $myId): bool
{
    if ((int) ($u['id'] ?? 0) === $myId) {
        return false;
    }
    $targetRole = (string) ($u['role'] ?? '');
    $isSuper = adminIsSuperAdmin();
    if (!$isSuper) {
        $myUsername = !empty($_SESSION['admin_username']) ? trim((string)$_SESSION['admin_username']) : '';
        $createdBy = (int) ($u['created_by'] ?? 0);
        $creatorName = trim((string)($u['creator_username'] ?? ''));
        if ($targetRole !== ADMIN_ROLE_RESELLER || ($createdBy !== $myId && ($myUsername === '' || $creatorName !== $myUsername))) {
            return false;
        }
    }
    if ($targetRole === 'super_admin' && !$isSuper) {
        return false;
    }
    if ($targetRole === 'super_admin' && (int) ($u['is_active'] ?? 0) === 1 && adminCountActiveSuperAdmins($conn) <= 1) {
        return false;
    }
    return true;
}

$allowedRoles = adminAssignableRoles();
$msgOk = $msgErr = '';

if (isset($_GET['perm_saved']) && (string) $_GET['perm_saved'] === '1') {
    $msgOk = t('users.perm_matrix_saved');
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    $op = $_POST['admin_op'] ?? '';

    if ($op === 'save_role_perms') {
        if (!adminIsSuperAdmin()) {
            header('Location: access_denied.php?perm=users_manage');
            exit;
        }
        $assignable = adminAllAssignablePermissionKeys();
        try {
            $conn->beginTransaction();
            $del = $conn->prepare('DELETE FROM admin_role_permissions WHERE role = ?');
            $ins = $conn->prepare('INSERT INTO admin_role_permissions (role, permission_key) VALUES (?, ?)');
            $rp = $_POST['rp'] ?? [];
            if (!is_array($rp)) {
                $rp = [];
            }
            foreach (adminConfigurableRoles() as $role) {
                $del->execute([$role]);
                $row = (isset($rp[$role]) && is_array($rp[$role])) ? $rp[$role] : [];
                foreach ($assignable as $pk) {
                    if (adminPermissionPostGranted($row[$pk] ?? null)) {
                        $ins->execute([$role, $pk]);
                    }
                }
            }
            $conn->commit();
            $GLOBALS['_admin_role_perm_map_cached'] = null;
            adminWarmPermissionCache($conn);
            header('Location: admin_users.php?perm_saved=1');
            exit;
        } catch (Throwable $e) {
            if ($conn->inTransaction()) {
                $conn->rollBack();
            }
            $msgErr = t('msg.db_error');
        }
    } elseif ($op === 'add') {
        if (!$canCreateUsers) {
            header('Location: access_denied.php?perm=users_create');
            exit;
        }
    } elseif ($op === 'change_role') {
        if (!$isSuperAdmin) {
            header('Location: access_denied.php?perm=users_manage');
            exit;
        }
    } elseif (!$canManageUsers && !$isSubAdmin) {
        header('Location: access_denied.php?perm=users_manage');
        exit;
    }

    if ($op === 'add') {
        $username = trim((string) ($_POST['username'] ?? ''));
        $email = trim((string) ($_POST['email'] ?? ''));
        $password = (string) ($_POST['password'] ?? '');
        $role = (string) ($_POST['role'] ?? ADMIN_ROLE_RESELLER);

        // Sub-admins have strict authority to open and provision Resellers only
        if (!$isSuperAdmin) {
            $role = ADMIN_ROLE_RESELLER;
        }
        if (!preg_match('/^[a-zA-Z0-9_]{3,64}$/', $username)) {
            $msgErr = t('users.error_username');
        } elseif (!adminIsAssignableRole($role)) {
            $msgErr = t('users.cannot_super_here');
        } elseif (strlen($password) < 8) {
            $msgErr = t('profile.error_short');
        } elseif ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $msgErr = t('profile.error_email');
        } else {
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $emailVal = $email === '' ? null : $email;
            $createdBy = $myId;
            try {
                $ins = $conn->prepare('INSERT INTO admin_users (username, email, password_hash, role, is_active, created_by) VALUES (?, ?, ?, ?, 1, ?)');
                $ins->execute([$username, $emailVal, $hash, $role, $createdBy]);
                $msgOk = $isSuperAdmin 
                    ? t('users.success_added') 
                    : ($lang === 'ar' ? 'تم فتح وإنشاء حساب الموزع الجديد بنجاح!' : 'New Reseller account opened and created successfully!');
            } catch (PDOException $e) {
                if ((int) $e->getCode() === 23000) {
                    $msgErr = t('users.error_exists');
                } else {
                    $msgErr = t('msg.db_error');
                }
            }
        }
    }

    if ($op === 'toggle') {
        $tid = (int) ($_POST['user_id'] ?? 0);
        if ($tid <= 0) {
            $msgErr = t('msg.db_error');
        } elseif ($tid === $myId) {
            $msgErr = t('users.error_self_toggle');
        } else {
            $stmt = $conn->prepare('SELECT id, role, is_active, created_by FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$tid]);
            $u = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$u) {
                $msgErr = t('msg.db_error');
            } elseif (!adminUserRowCanToggle($conn, $u, $myId)) {
                $msgErr = t('users.error_last_super');
            } else {
                $new = (int) $u['is_active'] ? 0 : 1;
                $conn->prepare('UPDATE admin_users SET is_active = ? WHERE id = ?')->execute([$new, $tid]);
                $msgOk = t('users.success_updated');
            }
        }
    }

    if ($op === 'reset_password') {
        $tid = (int) ($_POST['user_id'] ?? 0);
        $newPw = (string) ($_POST['new_password'] ?? '');
        if ($tid <= 0 || strlen($newPw) < 8) {
            $msgErr = t('profile.error_short');
        } else {
            $stmt = $conn->prepare('SELECT id, role, created_by FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$tid]);
            $u = $stmt->fetch(PDO::FETCH_ASSOC);
            $targetRole = (string)($u['role'] ?? '');
            if (!$u) {
                $msgErr = t('msg.db_error');
            } elseif (!$isSuperAdmin && ($targetRole !== ADMIN_ROLE_RESELLER || (int)($u['created_by'] ?? 0) !== $myId)) {
                $msgErr = t('users.error_no_edit_super');
            } elseif ($targetRole === 'super_admin' && !$isSuperAdmin) {
                $msgErr = t('users.error_no_edit_super');
            } else {
                $hash = password_hash($newPw, PASSWORD_DEFAULT);
                $stmt = $conn->prepare('UPDATE admin_users SET password_hash = ? WHERE id = ?');
                $stmt->execute([$hash, $tid]);
                if ($stmt->rowCount() === 0) {
                    $msgErr = t('msg.db_error');
                } else {
                    $msgOk = t('users.success_updated');
                }
            }
        }
    }

    if ($op === 'change_role') {
        if (!$isSuperAdmin) {
            header('Location: access_denied.php?perm=users_manage');
            exit;
        }
        $tid = (int) ($_POST['user_id'] ?? 0);
        $newRole = (string) ($_POST['role'] ?? '');
        if ($tid <= 0 || !adminIsAssignableRole($newRole)) {
            $msgErr = t('msg.db_error');
        } else {
            $stmt = $conn->prepare('SELECT id, role FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$tid]);
            $u = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$u || $u['role'] === 'super_admin') {
                $msgErr = t('users.error_no_edit_super');
            } else {
                $conn->prepare('UPDATE admin_users SET role = ? WHERE id = ? AND role != ?')->execute([$newRole, $tid, 'super_admin']);
                $msgOk = t('users.success_updated');
            }
        }
    }

    if ($op === 'delete') {
        $tid = (int) ($_POST['user_id'] ?? 0);
        if ($tid <= 0) {
            $msgErr = t('msg.db_error');
        } elseif ($tid === $myId) {
            $msgErr = t('users.error_self_delete');
        } else {
            $stmt = $conn->prepare('SELECT id, username, role, is_active, created_by FROM admin_users WHERE id = ? LIMIT 1');
            $stmt->execute([$tid]);
            $delUser = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$delUser) {
                $msgErr = t('msg.db_error');
            } elseif (!adminUserRowCanDelete($conn, $delUser, $myId)) {
                $msgErr = t('users.error_last_super');
            } else {
                $stDel = $conn->prepare('DELETE FROM admin_users WHERE id = ?');
                $stDel->execute([$tid]);
                if ($stDel->rowCount() > 0) {
                    $msgOk = t('users.success_deleted');
                } else {
                    $msgErr = t('msg.db_error');
                }
            }
        }
    }
}

$search = trim((string)($_GET['q'] ?? ''));

$users = $conn->query('SELECT u.id, u.username, u.email, u.role, u.is_active, u.created_by, u.last_login_at, creator.username AS creator_username 
    FROM admin_users u 
    LEFT JOIN admin_users creator ON u.created_by = creator.id 
    ORDER BY u.id ASC')->fetchAll(PDO::FETCH_ASSOC);

/**
 * إخفاء صفوف `super_admin` و`admin` عن موظفي الدعم الفرعيين.
 * الموظف يرى فقط الموزعين والزوار بالإضافة لحسابه الشخصي.
 */
$hidePrivilegedRows = !$isSuperAdmin;
if ($hidePrivilegedRows) {
    $myId = (int) $myId;
    $myUsername = !empty($_SESSION['admin_username']) ? trim((string)$_SESSION['admin_username']) : '';
    $users = array_values(array_filter($users, static function ($u) use ($myId, $myUsername) {
        $id = (int) ($u['id'] ?? 0);
        if ($id === $myId) {
            return true;
        }
        $role = (string) ($u['role'] ?? '');
        $createdBy = (int) ($u['created_by'] ?? 0);
        $creatorName = trim((string)($u['creator_username'] ?? ''));
        // Supervisor A can ONLY see/manage Resellers created by Supervisor A (matched by user id or username)
        return ($role === ADMIN_ROLE_RESELLER && ($createdBy === $myId || ($myUsername !== '' && $creatorName === $myUsername)));
    }));
}

if ($search !== '') {
    $users = array_values(array_filter($users, static function ($u) use ($search) {
        $uname = (string)($u['username'] ?? '');
        $email = (string)($u['email'] ?? '');
        $creator = (string)($u['creator_username'] ?? '');
        return (stripos($uname, $search) !== false || stripos($email, $search) !== false || stripos($creator, $search) !== false);
    }));
}

$permKeysForLabels = adminAllAssignablePermissionKeys();
$permLabelsForJs = [];
foreach ($permKeysForLabels as $pk) {
    $permLabelsForJs[$pk] = t('users.perm.' . $pk);
}
$rolesPermsForJs = [];
$allRolePerms = adminRolePermissions();
foreach ($allowedRoles as $r) {
    $rolesPermsForJs[$r] = adminEffectivePermissionKeysForRole($allRolePerms, $r);
}

$groupedPerms = [];
foreach ($permKeysForLabels as $pk) {
    $group = explode('_', $pk)[0] ?? 'general';
    $groupedPerms[$group][] = $pk;
}
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('users.title'); ?> — <?php echo t('app.title'); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Cairo', sans-serif;
            background: #020617;
            color: #e5e7eb;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        .admin-main {
            flex: 1 0 auto;
            padding-bottom: calc(32px + env(safe-area-inset-bottom, 0px));
        }
        .container.admin-main {
            padding-left: max(12px, env(safe-area-inset-left, 0px));
            padding-right: max(12px, env(safe-area-inset-right, 0px));
        }

        .staff-hero {
            margin-bottom: 18px;
        }
        .staff-hero h1 {
            margin: 0;
            font-size: clamp(1.15rem, 4vw, 1.4rem);
            font-weight: 800;
            color: #f8fafc;
            display: flex;
            align-items: center;
            gap: 10px;
            line-height: 1.25;
        }
        .staff-hero h1 i { color: #38bdf8; flex-shrink: 0; }
        .staff-hero p {
            margin: 8px 0 0;
            color: #94a3b8;
            font-size: 0.88rem;
            max-width: 640px;
            line-height: 1.55;
        }

        .staff-card {
            border-radius: 20px;
            background: linear-gradient(160deg, #0f172a 0%, #020617 100%);
            border: 1px solid rgba(148, 163, 184, 0.22);
            box-shadow: 0 18px 40px rgba(0, 0, 0, 0.35);
            overflow: hidden;
            margin-bottom: 16px;
        }
        .staff-card__body { padding: clamp(14px, 3vw, 22px); }
        .staff-card__head {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            gap: 10px;
            flex-wrap: wrap;
            margin-bottom: 14px;
        }
        .staff-card__title {
            margin: 0;
            font-size: 0.98rem;
            font-weight: 800;
            color: #e2e8f0;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .staff-card__title i { color: #38bdf8; }
        .staff-card__hint {
            margin: 4px 0 0;
            font-size: 0.78rem;
            color: #94a3b8;
            line-height: 1.45;
        }

        .form-label {
            font-size: 0.82rem;
            font-weight: 700;
            color: #cbd5e1;
            margin-bottom: 6px;
        }
        .form-control,
        .form-select {
            background: #020617;
            border: 1px solid #334155;
            color: #e5e7eb;
            border-radius: 12px;
            min-height: 44px;
        }
        .form-control:focus,
        .form-select:focus {
            background: #020617;
            color: #fff;
            border-color: #3b82f6;
            box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
        }
        .form-select option { background: #0f172a; color: #e5e7eb; }
        .form-control:disabled,
        .form-select:disabled {
            background: #0b1220;
            color: #64748b;
            opacity: 1;
        }

        .btn-primary {
            background: linear-gradient(135deg, #2563eb, #0ea5e9);
            border: none;
            font-weight: 700;
            border-radius: 12px;
            min-height: 44px;
        }
        .btn-primary:hover {
            background: linear-gradient(135deg, #1d4ed8, #0284c7);
        }
        .btn-outline-light {
            color: #cbd5e1 !important;
            border-color: #475569 !important;
            background: transparent;
        }
        .btn-outline-light:hover {
            background: rgba(148, 163, 184, 0.12) !important;
            color: #f8fafc !important;
        }
        .btn-outline-primary {
            color: #7dd3fc !important;
            border-color: rgba(56, 189, 248, 0.45) !important;
        }
        .btn-outline-primary:hover {
            background: rgba(56, 189, 248, 0.12) !important;
            color: #e0f2fe !important;
        }
        .btn-outline-secondary {
            color: #94a3b8 !important;
            border-color: #475569 !important;
        }
        .btn-outline-secondary:hover {
            background: rgba(148, 163, 184, 0.1) !important;
            color: #e2e8f0 !important;
        }

        .alert-success {
            background: rgba(16, 185, 129, 0.12);
            border: 1px solid rgba(52, 211, 153, 0.35);
            color: #a7f3d0;
            border-radius: 12px;
        }
        .alert-danger {
            background: rgba(239, 68, 68, 0.12);
            border: 1px solid rgba(248, 113, 113, 0.35);
            color: #fecaca;
            border-radius: 12px;
        }
        .staff-privacy-note {
            background: rgba(15, 23, 42, 0.7);
            border: 1px solid rgba(148, 163, 184, 0.22);
            color: #94a3b8;
            border-radius: 12px;
            padding: 0.7rem 0.9rem;
            font-size: 0.82rem;
            display: flex;
            align-items: flex-start;
            gap: 8px;
            margin-bottom: 14px;
        }
        .staff-privacy-note i { color: #38bdf8; margin-top: 2px; }

        .role-perm-preview-box {
            background: rgba(15, 23, 42, 0.65);
            border: 1px solid rgba(56, 189, 248, 0.28);
            border-radius: 14px;
            padding: 1rem 1.1rem;
        }
        .role-perm-preview-box .role-perm-title {
            color: #e0f2fe;
            font-weight: 700;
            font-size: 0.92rem;
        }
        .role-perm-preview-box .role-perm-title i { color: #38bdf8; }
        .role-perm-preview-box ul {
            color: #cbd5e1;
            font-size: 0.86rem;
            line-height: 1.55;
            padding-inline-start: 1.15rem;
            margin-top: 0.55rem;
            margin-bottom: 0;
        }
        .role-perm-preview-box li { margin-bottom: 0.2rem; }

        .table-staff {
            --bs-table-bg: transparent;
            --bs-table-color: #e5e7eb;
            --bs-table-hover-bg: rgba(56, 189, 248, 0.06);
            --bs-table-hover-color: #f8fafc;
            color: #e5e7eb;
            margin-bottom: 0;
        }
        .table-staff thead th {
            background: rgba(15, 23, 42, 0.9);
            color: #94a3b8;
            font-weight: 700;
            font-size: 0.78rem;
            border-bottom: 1px solid rgba(148, 163, 184, 0.22);
            white-space: nowrap;
            text-transform: none;
        }
        .table-staff tbody tr {
            background: transparent;
            transition: background 0.15s ease;
        }
        .table-staff tbody tr:nth-child(even) {
            background: rgba(15, 23, 42, 0.45);
        }
        .table-staff td,
        .table-staff th {
            border-color: rgba(148, 163, 184, 0.14);
            vertical-align: middle;
            padding: 0.75rem 0.65rem;
        }
        .badge.bg-info.text-dark {
            background: rgba(56, 189, 248, 0.18) !important;
            color: #7dd3fc !important;
        }
        .badge.bg-success {
            background: rgba(34, 197, 94, 0.2) !important;
            color: #86efac !important;
        }
        .badge.bg-secondary {
            background: rgba(100, 116, 139, 0.35) !important;
            color: #cbd5e1 !important;
        }

        .pill-btn {
            background: rgba(15, 23, 42, 0.7);
            border: 1px solid rgba(148, 163, 184, 0.25);
            color: #94a3b8;
            padding: 8px 18px;
            border-radius: 999px;
            font-size: 0.88rem;
            font-weight: 600;
            text-decoration: none;
            transition: all 0.2s ease;
            display: inline-flex;
            align-items: center;
        }
        .pill-btn:hover {
            color: #fff;
            border-color: rgba(56, 189, 248, 0.4);
            background: rgba(56, 189, 248, 0.08);
        }
        .pill-btn.active {
            background: #2563eb;
            border-color: #38bdf8;
            color: #fff;
            box-shadow: 0 0 14px rgba(37, 99, 235, 0.45);
        }
        .staff-col-symbol {
            width: 50px;
            text-align: center;
            font-weight: 800;
            font-size: 1.15rem;
            color: #38bdf8;
        }

        .staff-col-actions { min-width: 200px; }
        .staff-actions-cell { vertical-align: middle !important; }
        .staff-actions-rail {
            display: flex;
            flex-direction: column;
            align-items: flex-end;
            gap: 0.5rem;
            max-width: 360px;
            margin-inline-start: auto;
        }
        [dir="rtl"] .staff-actions-rail {
            align-items: flex-start;
            margin-inline-start: 0;
            margin-inline-end: auto;
        }
        .staff-actions-icon-row {
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            flex-wrap: wrap;
            padding: 0.35rem;
            border-radius: 14px;
            background: rgba(2, 6, 23, 0.65);
            border: 1px solid rgba(148, 163, 184, 0.2);
        }
        .staff-act-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 0.4rem;
            min-width: 40px;
            height: 40px;
            padding: 0 0.7rem;
            border-radius: 12px;
            border: none;
            transition: transform 0.16s ease, filter 0.16s ease;
            font-size: 0.82rem;
            font-weight: 700;
            cursor: pointer;
            line-height: 1;
            white-space: nowrap;
        }
        .staff-act-btn:hover {
            transform: translateY(-1px);
            filter: brightness(1.06);
        }
        .staff-act-btn:disabled { opacity: 0.45; cursor: not-allowed; transform: none; }
        .staff-act-label { display: none; }
        @media (min-width: 768px) {
            .staff-act-label { display: inline; }
            .staff-act-btn { height: 38px; }
        }
        .staff-act-toggle {
            background: rgba(245, 158, 11, 0.16);
            color: #fbbf24;
            border: 1px solid rgba(245, 158, 11, 0.35);
        }
        .staff-act-key {
            background: rgba(56, 189, 248, 0.14);
            color: #7dd3fc;
            border: 1px solid rgba(56, 189, 248, 0.35);
        }
        .staff-act-del {
            background: rgba(239, 68, 68, 0.14);
            color: #fca5a5;
            border: 1px solid rgba(239, 68, 68, 0.35);
        }
        .staff-pw-collapse {
            width: 100%;
            max-width: 300px;
        }
        .staff-pw-panel {
            padding: 0.75rem 0.85rem;
            border-radius: 14px;
            background: rgba(15, 23, 42, 0.9);
            border: 1px solid rgba(56, 189, 248, 0.28);
        }
        .staff-pw-panel .form-control { font-size: 0.8125rem; min-height: 38px; }
        .staff-your-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.35rem 0.75rem;
            border-radius: 999px;
            font-size: 0.8125rem;
            font-weight: 600;
            color: #7dd3fc;
            background: rgba(56, 189, 248, 0.12);
            border: 1px solid rgba(56, 189, 248, 0.3);
        }

        /* Advanced role permissions (collapsed by default) */
        .perm-matrix-card {
            border: 1px solid rgba(148, 163, 184, 0.22);
            background: linear-gradient(160deg, #0f172a 0%, #020617 100%);
        }
        .perm-matrix-topbar {
            padding: 1.05rem 1.15rem;
            background: rgba(15, 23, 42, 0.55);
            border-bottom: 1px solid rgba(148, 163, 184, 0.16);
            cursor: pointer;
        }
        .perm-matrix-topicon {
            width: 44px;
            height: 44px;
            border-radius: 12px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: #e0f2fe;
            background: rgba(56, 189, 248, 0.14);
            border: 1px solid rgba(56, 189, 248, 0.3);
            font-size: 1.05rem;
            flex-shrink: 0;
        }
        .perm-matrix-chip {
            display: inline-flex;
            align-items: center;
            padding: 0.4rem 0.75rem;
            border-radius: 999px;
            font-size: 0.78rem;
            font-weight: 700;
            color: #fde68a;
            background: rgba(245, 158, 11, 0.12);
            border: 1px solid rgba(245, 158, 11, 0.35);
        }
        .perm-matrix-chevron {
            width: 36px;
            height: 36px;
            border-radius: 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: rgba(2, 6, 23, 0.7);
            border: 1px solid rgba(148, 163, 184, 0.22);
            color: #94a3b8;
            transition: transform 0.25s ease;
        }
        .perm-matrix-toolbar { padding: 0.85rem 1.15rem 0; }
        .perm-role-grid {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 1rem;
            padding: 1rem 1.15rem 1.15rem;
        }
        .perm-role-card {
            background: rgba(2, 6, 23, 0.55);
            border: 1px solid rgba(148, 163, 184, 0.2);
            border-radius: 16px;
            overflow: hidden;
        }
        .perm-role-head {
            padding: 0.95rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 0.75rem;
            border-bottom: 1px solid rgba(148, 163, 184, 0.14);
            cursor: pointer;
        }
        .perm-role-badge {
            width: 38px;
            height: 38px;
            border-radius: 11px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: #7dd3fc;
            background: rgba(56, 189, 248, 0.12);
            border: 1px solid rgba(56, 189, 248, 0.28);
            font-size: 0.95rem;
            flex-shrink: 0;
        }
        .perm-role-title {
            font-size: 0.95rem;
            font-weight: 800;
            color: #f1f5f9;
        }
        .perm-role-sub {
            font-size: 0.78rem;
            color: #94a3b8;
        }
        .perm-role-count {
            font-weight: 800;
            color: #38bdf8;
        }
        .perm-role-chevron {
            width: 30px;
            height: 30px;
            border-radius: 9px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: rgba(15, 23, 42, 0.8);
            border: 1px solid rgba(148, 163, 184, 0.2);
            color: #94a3b8;
            transition: transform 0.25s ease;
            flex-shrink: 0;
        }
        .perm-role-body {
            padding: 0.95rem;
            display: flex;
            flex-direction: column;
            gap: 0.9rem;
        }
        .perm-group-block {
            background: rgba(15, 23, 42, 0.55);
            border: 1px solid rgba(148, 163, 184, 0.14);
            border-radius: 12px;
            padding: 0.8rem;
        }
        .perm-group-title {
            display: flex;
            align-items: center;
            gap: 0.45rem;
            font-size: 0.8rem;
            font-weight: 800;
            color: #cbd5e1;
            margin-bottom: 0.7rem;
            text-transform: capitalize;
        }
        .perm-group-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #38bdf8;
            box-shadow: 0 0 0 3px rgba(56, 189, 248, 0.18);
        }
        .perm-cards-grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 0.55rem;
        }
        .perm-check-card {
            position: relative;
            display: flex;
            align-items: flex-start;
            gap: 0.7rem;
            padding: 0.75rem 0.85rem;
            border-radius: 12px;
            border: 1px solid rgba(148, 163, 184, 0.2);
            background: rgba(2, 6, 23, 0.55);
            cursor: pointer;
            transition: border-color 0.18s ease, background 0.18s ease;
            min-height: 56px;
            user-select: none;
        }
        .perm-check-card:hover {
            border-color: rgba(56, 189, 248, 0.45);
        }
        .perm-check-card.is-checked {
            background: rgba(16, 185, 129, 0.1);
            border-color: rgba(52, 211, 153, 0.4);
        }
        .perm-check-input {
            position: absolute;
            opacity: 0;
            pointer-events: none;
        }
        .perm-check-mark {
            flex: 0 0 auto;
            width: 22px;
            height: 22px;
            margin-top: 2px;
            border-radius: 7px;
            border: 1.5px solid #475569;
            background: #020617;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: transparent;
            transition: all 0.2s ease;
        }
        .perm-check-card.is-checked .perm-check-mark {
            background: linear-gradient(135deg, #22c55e, #10b981);
            border-color: #10b981;
            color: #fff;
        }
        .perm-check-content {
            display: flex;
            flex-direction: column;
            gap: 0.2rem;
            min-width: 0;
        }
        .perm-check-title {
            font-size: 0.86rem;
            font-weight: 700;
            color: #e2e8f0;
            line-height: 1.45;
        }
        .perm-check-key { display: none !important; }
        .perm-bulk-btn {
            border-radius: 999px;
            font-weight: 700;
            padding-inline: 0.8rem;
        }
        .perm-matrix-savebar {
            display: flex;
            align-items: center;
            justify-content: flex-end;
            gap: 1rem;
            flex-wrap: wrap;
            padding: 0 1.15rem 1.15rem;
        }
        [dir="rtl"] .perm-check-card { text-align: right; }

        @media (max-width: 1199px) {
            .perm-role-grid { grid-template-columns: 1fr; }
        }
        @media (max-width: 767px) {
            .perm-matrix-topbar,
            .perm-role-head,
            .perm-matrix-savebar {
                padding-left: 1rem;
                padding-right: 1rem;
            }
            .perm-role-grid { padding: 1rem; }
            .perm-role-head {
                flex-direction: column;
                align-items: stretch;
            }
            .perm-role-head > div:last-child { justify-content: space-between; }
            .perm-check-card { min-height: unset; }
            .staff-actions-rail {
                align-items: stretch;
                max-width: none;
                margin-inline: 0;
            }
            .staff-actions-icon-row { justify-content: flex-start; }
            .staff-pw-collapse { max-width: none; }
            .table-staff thead { display: none; }
            .table-staff,
            .table-staff tbody,
            .table-staff tr,
            .table-staff td {
                display: block;
                width: 100%;
            }
            .table-staff tr {
                border: 1px solid rgba(148, 163, 184, 0.18);
                border-radius: 14px;
                margin-bottom: 0.75rem;
                padding: 0.65rem 0.75rem;
                background: rgba(15, 23, 42, 0.55) !important;
            }
            .table-staff td {
                border: 0;
                padding: 0.35rem 0;
            }
            .table-staff td::before {
                content: attr(data-label);
                display: block;
                font-size: 0.72rem;
                font-weight: 700;
                color: #64748b;
                margin-bottom: 0.15rem;
            }
            .staff-actions-cell.text-lg-end { text-align: start !important; }
        }
    </style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container admin-main mt-4">
    <div class="staff-hero">
        <h1>
            <i class="fas <?php echo $isSuperAdmin ? 'fa-user-shield' : 'fa-handshake'; ?>"></i>
            <span><?php echo $isSuperAdmin ? t('users.title') : ($lang === 'ar' ? 'إدارة وفتح حسابات الموزعين (Resellers)' : 'Reseller Account Management'); ?></span>
        </h1>
        <p><?php echo $isSuperAdmin ? t('users.subtitle') : ($lang === 'ar' ? 'يمكنك هنا فتح وإنشاء حسابات جديدة للموزعين، ضبط كلمات المرور وإدارة نشاطهم.' : 'Create and provision new reseller accounts, manage credentials, and oversee reseller activity.'); ?></p>
    </div>

    <?php if ($hidePrivilegedRows): ?>
    <div class="staff-privacy-note">
        <i class="fas fa-user-lock"></i>
        <span><?php echo $lang === 'ar' ? 'بيئة موظف معتمدة: مصرح لك بإنشاء وإدارة حسابات الموزعين فقط.' : 'Authorized Staff Scope: You are authorized to create and manage Reseller accounts only.'; ?></span>
    </div>
    <?php endif; ?>

    <?php if ($msgOk): ?><div class="alert alert-success"><?php echo htmlspecialchars($msgOk); ?></div><?php endif; ?>
    <?php if ($msgErr): ?><div class="alert alert-danger"><?php echo htmlspecialchars($msgErr); ?></div><?php endif; ?>

    <!-- Section 1: Add staff / reseller -->
    <div class="staff-card">
        <div class="staff-card__body">
            <div class="staff-card__head">
                <div>
                    <h2 class="staff-card__title">
                        <i class="fas <?php echo $isSuperAdmin ? 'fa-user-plus' : 'fa-handshake text-info'; ?>"></i>
                        <span><?php echo $isSuperAdmin ? t('users.section_add') : ($lang === 'ar' ? 'فتح حساب موزع جديد (Add New Reseller)' : 'Add New Reseller Account'); ?></span>
                    </h2>
                    <p class="staff-card__hint">
                        <?php echo $isSuperAdmin ? t('users.cannot_super_here') : ($lang === 'ar' ? 'إنشاء حساب موزع معزول (Reseller) لتقديم لوحة مخصصة لمشتركيه.' : 'Provision an isolated Reseller account with dedicated customer scope.'); ?>
                    </p>
                </div>
            </div>
            <?php if (!$canCreateUsers && adminIsGuestRole()): ?>
            <?php require_once __DIR__ . '/includes/view_only_banner.php'; ?>
            <?php endif; ?>
            <form method="post" class="mt-1" <?php echo !$canCreateUsers ? 'data-admin-perm="users_create"' : ''; ?>>
                <input type="hidden" name="admin_op" value="add">
                <fieldset <?php echo $canCreateUsers ? '' : 'disabled'; ?> style="border:0;padding:0;margin:0;min-width:0;">
                <div class="row g-3 align-items-end">
                    <div class="col-md-3">
                        <label class="form-label"><?php echo t('users.add_username'); ?></label>
                        <input type="text" name="username" class="form-control" required pattern="[a-zA-Z0-9_]{3,64}" autocomplete="off" placeholder="<?php echo $lang === 'ar' ? 'اسم المستخدم للموزع' : 'Reseller username'; ?>">
                    </div>
                    <div class="col-md-3">
                        <label class="form-label"><?php echo t('users.add_email'); ?></label>
                        <input type="email" name="email" class="form-control" autocomplete="off" placeholder="reseller@example.com">
                    </div>
                    <div class="col-md-2">
                        <label class="form-label"><?php echo t('users.add_password'); ?></label>
                        <input type="password" name="password" class="form-control" required minlength="8" autocomplete="new-password" placeholder="••••••••">
                    </div>
                    <div class="col-md-2">
                        <label class="form-label"><?php echo t('users.add_role'); ?></label>
                        <?php if ($isSuperAdmin): ?>
                            <select name="role" id="staffAddRoleSelect" class="form-select">
                                <?php foreach (adminAssignableRoles() as $r): ?>
                                    <option value="<?php echo htmlspecialchars($r); ?>" <?php echo $r === ADMIN_ROLE_RESELLER ? 'selected' : ''; ?>>
                                        <?php echo htmlspecialchars(adminRoleLabel($r)); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        <?php else: ?>
                            <select name="role" id="staffAddRoleSelect" class="form-select">
                                <option value="<?php echo ADMIN_ROLE_RESELLER; ?>" selected>
                                    <?php echo htmlspecialchars(adminRoleLabel(ADMIN_ROLE_RESELLER)); ?>
                                </option>
                            </select>
                        <?php endif; ?>
                    </div>
                    <div class="col-md-2">
                        <button type="submit" class="btn btn-primary w-100">
                            <i class="fas fa-plus me-1"></i>
                            <span><?php echo $isSuperAdmin ? t('users.btn_add') : ($lang === 'ar' ? 'فتح حساب موزع' : 'Add Reseller'); ?></span>
                        </button>
                    </div>
                </div>
                <?php if ($isSuperAdmin): ?>
                <div class="row mt-3">
                    <div class="col-12">
                        <div class="role-perm-preview-box" id="rolePermissionsPreview">
                            <div class="role-perm-title d-flex align-items-center gap-2">
                                <i class="fas fa-list-check"></i>
                                <span><?php echo t('users.role_permissions_title'); ?></span>
                            </div>
                            <ul id="rolePermissionsList"></ul>
                        </div>
                    </div>
                </div>
                <?php endif; ?>
                </fieldset>
            </form>
        </div>
    </div>

    <?php
    /**
     * Helper function to render a user table with a category-specific top header column symbol:
     * - '+' for the Supervisors Table
     * - '*' for the Resellers Table
     * - '#' remains strictly for the Customers Table in customers.php
     */
    function renderStaffCategoryTable(array $list, string $headerSymbol, bool $isSuperAdmin, bool $isSubAdmin, int $myId, PDO $conn, string $lang, array $allowedRoles, string $emptyMsg): void {
    ?>
        <div class="table-responsive">
            <table class="table table-staff table-hover mb-0">
                <thead>
                    <tr>
                        <th class="staff-col-symbol text-center" style="width:50px;"><?php echo htmlspecialchars($headerSymbol); ?></th>
                        <th><?php echo t('users.table_user'); ?></th>
                        <th><?php echo t('users.table_email'); ?></th>
                        <th><?php echo t('users.table_role'); ?></th>
                        <th><?php echo t('users.table_status'); ?></th>
                        <th><?php echo t('users.table_last_login'); ?></th>
                        <?php if ($isSuperAdmin): ?>
                        <th><?php echo $lang === 'ar' ? 'أنشئ بواسطة' : 'Created By'; ?></th>
                        <?php endif; ?>
                        <th class="staff-col-actions text-lg-end"><?php echo t('users.table_actions'); ?></th>
                    </tr>
                </thead>
                <tbody>
                <?php if (empty($list)): ?>
                    <tr>
                        <td colspan="<?php echo $isSuperAdmin ? 8 : 7; ?>" class="text-center py-4 text-muted">
                            <i class="fas fa-user-slash fa-2x mb-2 d-block opacity-50"></i>
                            <?php echo htmlspecialchars($emptyMsg); ?>
                        </td>
                    </tr>
                <?php else: ?>
                    <?php foreach ($list as $u): ?>
                        <?php 
                            $rowId = (int) $u['id']; 
                            $rowRole = (string) ($u['role'] ?? '');
                            $canManageRow = $isSuperAdmin || ($isSubAdmin && $rowRole === ADMIN_ROLE_RESELLER && (int)($u['created_by'] ?? 0) === $myId);
                            $collapseId = 'staffPw' . $rowId . '_' . ($headerSymbol === '+' ? 'sup' : 'res');
                            $uname = (string)($u['username'] ?? '');
                            $uemail = (string)($u['email'] ?? '');
                            $ucreator = (string)($u['creator_username'] ?? '');
                        ?>
                        <tr class="staff-user-row" data-username="<?php echo htmlspecialchars(strtolower($uname)); ?>" data-email="<?php echo htmlspecialchars(strtolower($uemail)); ?>" data-creator="<?php echo htmlspecialchars(strtolower($ucreator)); ?>">
                            <td class="text-muted fw-bold text-center staff-col-symbol" data-label="<?php echo htmlspecialchars($headerSymbol); ?>">#<?php echo $rowId; ?></td>
                            <td data-label="<?php echo htmlspecialchars(t('users.table_user')); ?>">
                                <div class="d-flex align-items-center flex-wrap gap-1">
                                    <strong><?php echo htmlspecialchars($uname); ?></strong>
                                    <?php if ($rowId === $myId): ?>
                                        <span class="badge bg-info text-dark"><?php echo t('users.badge_you'); ?></span>
                                    <?php endif; ?>
                                </div>
                            </td>
                            <td data-label="<?php echo htmlspecialchars(t('users.table_email')); ?>"><?php echo $u['email'] ? htmlspecialchars($u['email']) : '—'; ?></td>
                            <td data-label="<?php echo htmlspecialchars(t('users.table_role')); ?>">
                                <?php if ($u['role'] === 'super_admin'): ?>
                                    <?php echo htmlspecialchars(adminRoleLabel('super_admin')); ?>
                                <?php elseif ($isSuperAdmin): ?>
                                    <form method="post" class="d-flex gap-2 align-items-center flex-wrap" data-admin-perm="users_manage">
                                        <input type="hidden" name="admin_op" value="change_role">
                                        <input type="hidden" name="user_id" value="<?php echo $rowId; ?>">
                                        <select name="role" class="form-select form-select-sm" style="max-width:200px;">
                                            <?php foreach ($allowedRoles as $r): ?>
                                                <option value="<?php echo htmlspecialchars($r); ?>" <?php echo $u['role'] === $r ? 'selected' : ''; ?>>
                                                    <?php echo htmlspecialchars(adminRoleLabel($r)); ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                        <button type="submit" class="btn btn-sm btn-outline-light"><?php echo t('button.save_changes'); ?></button>
                                    </form>
                                <?php else: ?>
                                    <span class="badge bg-secondary-subtle text-info border border-info-subtle">
                                        <?php echo htmlspecialchars(adminRoleLabel($u['role'])); ?>
                                    </span>
                                <?php endif; ?>
                            </td>
                            <td data-label="<?php echo htmlspecialchars(t('users.table_status')); ?>">
                                <?php if ((int) $u['is_active']): ?>
                                    <span class="badge bg-success"><?php echo t('users.active'); ?></span>
                                <?php else: ?>
                                    <span class="badge bg-secondary"><?php echo t('users.inactive'); ?></span>
                                <?php endif; ?>
                            </td>
                            <td class="small" data-label="<?php echo htmlspecialchars(t('users.table_last_login')); ?>"><?php echo $u['last_login_at'] ? htmlspecialchars(format_datetime_short($u['last_login_at'])) : '—'; ?></td>
                            <?php if ($isSuperAdmin): ?>
                            <td data-label="<?php echo $lang === 'ar' ? 'أنشئ بواسطة' : 'Created By'; ?>">
                                <?php if (!empty($u['creator_username'])): ?>
                                    <span class="badge bg-primary-subtle text-primary border border-primary-subtle">
                                        <i class="fas fa-user-tie me-1"></i><?php echo htmlspecialchars($u['creator_username']); ?>
                                    </span>
                                <?php elseif ($rowRole === 'super_admin'): ?>
                                    <span class="badge bg-warning-subtle text-warning border border-warning-subtle">
                                        <i class="fas fa-crown me-1"></i><?php echo $lang === 'ar' ? 'المالك الرئيسي' : 'Master Owner'; ?>
                                    </span>
                                <?php else: ?>
                                    <span class="text-muted small">—</span>
                                <?php endif; ?>
                            </td>
                            <?php endif; ?>
                            <td class="staff-actions-cell text-lg-end" data-label="<?php echo htmlspecialchars(t('users.table_actions')); ?>">
                                <?php if ($rowId === $myId): ?>
                                    <span class="staff-your-badge"><i class="fas fa-user-check"></i> <?php echo t('users.actions_your_row'); ?></span>
                                <?php else: ?>
                                <div class="staff-actions-rail">
                                    <div class="staff-actions-icon-row">
                                        <?php if (adminUserRowCanToggle($conn, $u, $myId)): ?>
                                        <form method="post"
                                              class="d-inline m-0"
                                              <?php echo !$canManageRow ? 'data-admin-perm="users_manage"' : ''; ?>
                                              data-admin-confirm
                                              data-confirm-tone="warn"
                                              data-confirm-icon="fas fa-user-gear"
                                              data-confirm-ok-icon="fas fa-check"
                                              data-confirm-title="<?php echo htmlspecialchars(t('users.toggle_title'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-message="<?php echo htmlspecialchars(t('users.toggle_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-warning="<?php echo htmlspecialchars(t('users.toggle_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-ok="<?php echo htmlspecialchars(t('users.btn_toggle'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                                  ['label' => t('users.table_user'), 'value' => (string)($u['username'] ?? '')],
                                                  ['label' => t('users.table_status'), 'value' => (int)$u['is_active'] ? t('users.active') : t('users.inactive')],
                                              ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                            <input type="hidden" name="admin_op" value="toggle">
                                            <input type="hidden" name="user_id" value="<?php echo $rowId; ?>">
                                            <button type="submit" class="staff-act-btn staff-act-toggle" title="<?php echo htmlspecialchars(t('users.btn_toggle')); ?>" <?php echo $canManageRow ? '' : 'disabled'; ?>>
                                                <i class="fas fa-<?php echo (int) $u['is_active'] ? 'user-slash' : 'user-check'; ?>"></i>
                                                <span class="staff-act-label"><?php echo t('users.btn_toggle'); ?></span>
                                            </button>
                                        </form>
                                        <?php endif; ?>
                                        <button type="button" class="staff-act-btn staff-act-key"
                                                data-bs-toggle="collapse" data-bs-target="#<?php echo $collapseId; ?>"
                                                aria-expanded="false" aria-controls="<?php echo $collapseId; ?>"
                                                title="<?php echo htmlspecialchars(t('users.btn_reset_pass')); ?>"
                                                <?php echo $canManageRow ? '' : 'disabled'; ?>>
                                            <i class="fas fa-key"></i>
                                            <span class="staff-act-label"><?php echo t('users.btn_reset_pass'); ?></span>
                                        </button>
                                        <?php if (adminUserRowCanDelete($conn, $u, $myId)): ?>
                                        <form method="post"
                                              class="d-inline m-0"
                                              <?php echo !$canManageRow ? 'data-admin-perm="users_manage"' : ''; ?>
                                              data-admin-confirm
                                              data-confirm-title="<?php echo htmlspecialchars(t('users.delete_title'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-message="<?php echo htmlspecialchars(t('users.delete_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-warning="<?php echo htmlspecialchars(t('users.delete_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-ok="<?php echo htmlspecialchars(t('users.btn_delete'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                              data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                                  ['label' => t('users.table_user'), 'value' => (string)($u['username'] ?? '')],
                                                  ['label' => t('users.table_role'), 'value' => adminRoleLabel((string)($u['role'] ?? ''))],
                                              ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                            <input type="hidden" name="admin_op" value="delete">
                                            <input type="hidden" name="user_id" value="<?php echo $rowId; ?>">
                                            <button type="submit" class="staff-act-btn staff-act-del" title="<?php echo htmlspecialchars(t('users.btn_delete')); ?>" <?php echo $canManageRow ? '' : 'disabled'; ?>>
                                                <i class="fas fa-trash-alt"></i>
                                                <span class="staff-act-label"><?php echo t('users.btn_delete'); ?></span>
                                            </button>
                                        </form>
                                        <?php endif; ?>
                                    </div>
                                    <div class="collapse staff-pw-collapse" id="<?php echo $collapseId; ?>">
                                        <div class="staff-pw-panel">
                                            <div class="small fw-semibold mb-2" style="color:#94a3b8;"><?php echo t('users.pw_panel_title'); ?></div>
                                            <form method="post"
                                                  class="d-flex flex-column gap-2"
                                                  <?php echo !$canManageRow ? 'data-admin-perm="users_manage"' : ''; ?>
                                                  data-admin-confirm
                                                  data-confirm-tone="warn"
                                                  data-confirm-icon="fas fa-key"
                                                  data-confirm-ok-icon="fas fa-check"
                                                  data-confirm-title="<?php echo htmlspecialchars(t('users.reset_title'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-message="<?php echo htmlspecialchars(t('users.reset_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-warning="<?php echo htmlspecialchars(t('users.reset_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-ok="<?php echo htmlspecialchars(t('users.btn_reset_pass'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-minlength="8"
                                                  data-confirm-minlength-name="new_password"
                                                  data-confirm-minlength-msg="<?php echo htmlspecialchars(t('profile.error_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                                  data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                                      ['label' => t('users.table_user'), 'value' => (string)($u['username'] ?? '')],
                                                  ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                                <input type="hidden" name="admin_op" value="reset_password">
                                                <input type="hidden" name="user_id" value="<?php echo $rowId; ?>">
                                                <input type="password" name="new_password" class="form-control form-control-sm" placeholder="<?php echo htmlspecialchars(t('users.new_password_placeholder')); ?>" minlength="8" autocomplete="new-password" required <?php echo $canManageRow ? '' : 'disabled'; ?>>
                                                <button type="submit" class="btn btn-sm btn-primary" <?php echo $canManageRow ? '' : 'disabled'; ?>><?php echo t('users.pw_panel_submit'); ?></button>
                                            </form>
                                        </div>
                                    </div>
                                </div>
                                <?php endif; ?>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
                </tbody>
            </table>
        </div>
    <?php
    }
    ?>

    <!-- Section 2: Team list with category-based tables -->
    <?php if ($isSuperAdmin): ?>
        <?php
            $supervisorsUsers = array_values(array_filter($users, static function ($u) {
                return ($u['role'] ?? '') !== ADMIN_ROLE_RESELLER;
            }));
            $resellersUsers = array_values(array_filter($users, static function ($u) {
                return ($u['role'] ?? '') === ADMIN_ROLE_RESELLER;
            }));
        ?>
        <div class="staff-card mb-4">
            <div class="staff-card__body">
                <div class="staff-card__head mb-3">
                    <div>
                        <h2 class="staff-card__title"><i class="fas fa-people-group"></i><?php echo t('users.section_team'); ?></h2>
                        <p class="staff-card__hint"><?php echo t('users.section_team_hint'); ?></p>
                    </div>
                </div>

                <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
                    <ul class="nav nav-pills gap-2" id="categoryTabs" role="tablist">
                        <li class="nav-item" role="presentation">
                            <button class="pill-btn active d-inline-flex align-items-center gap-2" id="tab-supervisors" data-bs-toggle="pill" data-bs-target="#pane-supervisors" type="button" role="tab" style="cursor:pointer;">
                                <i class="fas fa-user-shield text-primary"></i>
                                <span><?php echo $lang === 'ar' ? 'جدول المشرفين (Supervisors)' : 'Supervisors Table'; ?></span>
                                <span class="badge rounded-pill bg-primary ms-1" style="font-size:0.75rem;">+ (<?php echo count($supervisorsUsers); ?>)</span>
                            </button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="pill-btn d-inline-flex align-items-center gap-2" id="tab-resellers" data-bs-toggle="pill" data-bs-target="#pane-resellers" type="button" role="tab" style="cursor:pointer;">
                                <i class="fas fa-handshake text-info"></i>
                                <span><?php echo $lang === 'ar' ? 'جدول الموزعين (Resellers)' : 'Resellers Table'; ?></span>
                                <span class="badge rounded-pill bg-info text-dark ms-1" style="font-size:0.75rem;">* (<?php echo count($resellersUsers); ?>)</span>
                            </button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="pill-btn d-inline-flex align-items-center gap-2" id="tab-all" data-bs-toggle="pill" data-bs-target="#pane-all" type="button" role="tab" style="cursor:pointer;">
                                <i class="fas fa-layer-group"></i>
                                <span><?php echo $lang === 'ar' ? 'عرض كلا الجدولين' : 'Show Both Tables'; ?></span>
                            </button>
                        </li>
                    </ul>

                    <div class="d-flex align-items-center gap-2">
                        <form method="GET" action="admin_users.php" class="d-flex align-items-center m-0 staff-search-form">
                            <div class="input-group input-group-sm" style="min-width: 220px;">
                                <span class="input-group-text bg-dark border-secondary text-muted" style="border-color: rgba(255,255,255,0.15) !important;">
                                    <i class="fas fa-search"></i>
                                </span>
                                <input type="text" name="q" class="form-control form-control-sm text-white staff-search-input" 
                                       style="background: rgba(15, 23, 42, 0.8); border-color: rgba(255,255,255,0.15); min-width: 180px;"
                                       placeholder="<?php echo $lang === 'ar' ? 'بحث باسم المستخدم...' : 'Search by Username...'; ?>" 
                                       value="<?php echo htmlspecialchars($search); ?>" 
                                       autocomplete="off">
                                <?php if ($search !== ''): ?>
                                <a href="admin_users.php" class="btn btn-sm btn-outline-secondary" style="border-color: rgba(255,255,255,0.15);" title="<?php echo $lang === 'ar' ? 'إلغاء البحث' : 'Clear Search'; ?>">
                                    <i class="fas fa-times"></i>
                                </a>
                                <?php endif; ?>
                            </div>
                        </form>
                    </div>
                </div>

                <div class="tab-content" id="categoryTabContent">
                    <!-- 1. Supervisors Table: Top header column symbol is '+' -->
                    <div class="tab-pane fade show active" id="pane-supervisors" role="tabpanel">
                        <div class="d-flex align-items-center justify-content-between mb-2">
                            <h3 class="fs-6 fw-bold text-white mb-0 d-flex align-items-center gap-2">
                                <i class="fas fa-user-shield text-primary"></i>
                                <span><?php echo $lang === 'ar' ? 'جدول المشرفين والمدراء' : 'Supervisors & Staff Table'; ?></span>
                                <span class="badge bg-primary-subtle text-primary border border-primary-subtle fs-6">+</span>
                            </h3>
                            <span class="small text-muted"><?php echo count($supervisorsUsers); ?> <?php echo $lang === 'ar' ? 'مشرف' : 'supervisors'; ?></span>
                        </div>
                        <?php renderStaffCategoryTable($supervisorsUsers, '+', true, $isSubAdmin, $myId, $conn, $lang, $allowedRoles, $lang === 'ar' ? 'لا يوجد مشرفون مسجلون حالياً.' : 'No supervisors found.'); ?>
                    </div>

                    <!-- 2. Resellers Table: Top header column symbol is '*' -->
                    <div class="tab-pane fade" id="pane-resellers" role="tabpanel">
                        <div class="d-flex align-items-center justify-content-between mb-2">
                            <h3 class="fs-6 fw-bold text-white mb-0 d-flex align-items-center gap-2">
                                <i class="fas fa-handshake text-info"></i>
                                <span><?php echo $lang === 'ar' ? 'جدول الموزعين المعزولين' : 'Isolated Resellers Table'; ?></span>
                                <span class="badge bg-info-subtle text-info border border-info-subtle fs-6">*</span>
                            </h3>
                            <span class="small text-muted"><?php echo count($resellersUsers); ?> <?php echo $lang === 'ar' ? 'موزع' : 'resellers'; ?></span>
                        </div>
                        <?php renderStaffCategoryTable($resellersUsers, '*', true, $isSubAdmin, $myId, $conn, $lang, $allowedRoles, $lang === 'ar' ? 'لا يوجد موزعون مسجلون حالياً.' : 'No resellers found.'); ?>
                    </div>

                    <!-- Both Tables View -->
                    <div class="tab-pane fade" id="pane-all" role="tabpanel">
                        <div class="mb-4">
                            <div class="d-flex align-items-center justify-content-between mb-2">
                                <h3 class="fs-6 fw-bold text-white mb-0 d-flex align-items-center gap-2">
                                    <i class="fas fa-user-shield text-primary"></i>
                                    <span><?php echo $lang === 'ar' ? 'جدول المشرفين والمدراء (رمز العمود الأول: +)' : 'Supervisors Table (Header Column: +)'; ?></span>
                                </h3>
                            </div>
                            <?php renderStaffCategoryTable($supervisorsUsers, '+', true, $isSubAdmin, $myId, $conn, $lang, $allowedRoles, $lang === 'ar' ? 'لا يوجد مشرفون مسجلون حالياً.' : 'No supervisors found.'); ?>
                        </div>
                        <div>
                            <div class="d-flex align-items-center justify-content-between mb-2">
                                <h3 class="fs-6 fw-bold text-white mb-0 d-flex align-items-center gap-2">
                                    <i class="fas fa-handshake text-info"></i>
                                    <span><?php echo $lang === 'ar' ? 'جدول الموزعين (رمز العمود الأول: *)' : 'Resellers Table (Header Column: *)'; ?></span>
                                </h3>
                            </div>
                            <?php renderStaffCategoryTable($resellersUsers, '*', true, $isSubAdmin, $myId, $conn, $lang, $allowedRoles, $lang === 'ar' ? 'لا يوجد موزعون مسجلون حالياً.' : 'No resellers found.'); ?>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    <?php else: ?>
        <!-- For Supervisors: They only manage Resellers, so this is strictly the Resellers Table -->
        <div class="staff-card mb-4">
            <div class="staff-card__body">
                <div class="staff-card__head mb-3 d-flex flex-wrap align-items-center justify-content-between gap-3">
                    <div>
                        <h2 class="staff-card__title">
                            <i class="fas fa-handshake text-info"></i>
                            <span><?php echo $lang === 'ar' ? 'جدول الموزعين التابعين لك (Resellers)' : 'Your Resellers Table'; ?></span>
                            <span class="badge bg-info-subtle text-info border border-info-subtle ms-2">*</span>
                        </h2>
                        <p class="staff-card__hint mb-0"><?php echo $lang === 'ar' ? 'قائمة حسابات الموزعين التي قمت بإنشائها والإشراف عليها.' : 'List of reseller accounts created and supervised by your account.'; ?></p>
                    </div>
                    <div class="d-flex align-items-center gap-2">
                        <form method="GET" action="admin_users.php" class="d-flex align-items-center m-0 staff-search-form">
                            <div class="input-group input-group-sm" style="min-width: 220px;">
                                <span class="input-group-text bg-dark border-secondary text-muted" style="border-color: rgba(255,255,255,0.15) !important;">
                                    <i class="fas fa-search"></i>
                                </span>
                                <input type="text" name="q" class="form-control form-control-sm text-white staff-search-input" 
                                       style="background: rgba(15, 23, 42, 0.8); border-color: rgba(255,255,255,0.15); min-width: 180px;"
                                       placeholder="<?php echo $lang === 'ar' ? 'بحث باسم المستخدم...' : 'Search by Username...'; ?>" 
                                       value="<?php echo htmlspecialchars($search); ?>" 
                                       autocomplete="off">
                                <?php if ($search !== ''): ?>
                                <a href="admin_users.php" class="btn btn-sm btn-outline-secondary" style="border-color: rgba(255,255,255,0.15);" title="<?php echo $lang === 'ar' ? 'إلغاء البحث' : 'Clear Search'; ?>">
                                    <i class="fas fa-times"></i>
                                </a>
                                <?php endif; ?>
                            </div>
                        </form>
                    </div>
                </div>
                <!-- Resellers Table: Top header column symbol is '*' -->
                <?php renderStaffCategoryTable($users, '*', false, $isSubAdmin, $myId, $conn, $lang, $allowedRoles, $lang === 'ar' ? 'لم تقم بإنشاء أي موزع حتى الآن.' : 'No resellers created yet under your account.'); ?>
            </div>
        </div>
    <?php endif; ?>

    <?php if (adminIsSuperAdmin()): ?>
    <!-- Section 3: Advanced role permissions (bottom, collapsed) -->
    <div class="staff-card perm-matrix-card p-0 mb-4 overflow-hidden">
        <div class="perm-matrix-topbar d-flex align-items-center justify-content-between flex-wrap gap-3"
             data-bs-toggle="collapse"
             data-bs-target="#permMatrixMainCollapse"
             aria-expanded="false"
             role="button">
            <div class="d-flex align-items-center gap-3">
                <span class="perm-matrix-topicon">
                    <i class="fas fa-sliders"></i>
                </span>
                <div>
                    <h2 class="h5 mb-1" style="color:#f1f5f9;font-weight:800;"><?php echo t('users.perm_matrix_title'); ?></h2>
                    <p class="small mb-0" style="color:#94a3b8;"><?php echo t('users.perm_matrix_subtitle'); ?></p>
                </div>
            </div>

            <div class="d-flex align-items-center gap-2 flex-wrap">
                <span class="perm-matrix-chip">
                    <i class="fas fa-lock me-1"></i>
                    <?php echo t('users.super_full_access_note'); ?>
                </span>
                <span class="perm-matrix-chevron" id="permMatrixChevron" style="transform: rotate(0deg);">
                    <i class="fas fa-chevron-down"></i>
                </span>
            </div>
        </div>

        <div id="permMatrixMainCollapse" class="collapse">
            <form method="post" class="perm-matrix-form" id="permMatrixForm">
                <input type="hidden" name="admin_op" value="save_role_perms">
                <input type="hidden" name="rp_sent" value="1">

                <div class="perm-matrix-toolbar">
                    <div class="small d-flex align-items-center gap-2 flex-wrap" style="color:#94a3b8;">
                        <span><i class="fas fa-circle-info" style="color:#38bdf8;"></i> <?php echo t('users.perm_matrix_hint'); ?></span>
                    </div>
                </div>

                <div class="perm-role-grid">
                    <?php foreach ($allowedRoles as $role): ?>
                        <?php
                        $rolePerms = adminEffectivePermissionKeysForRole($allRolePerms, $role);
                        $roleCount = count($rolePerms);
                        $roleCollapseId = 'rolePerms_' . $role;
                        ?>
                        <div class="perm-role-card">
                            <div class="perm-role-head"
                                 data-bs-toggle="collapse"
                                 data-bs-target="#<?php echo htmlspecialchars($roleCollapseId); ?>"
                                 aria-expanded="false"
                                 role="button">
                                <div class="d-flex align-items-center gap-2 flex-grow-1 min-w-0">
                                    <span class="perm-role-badge">
                                        <i class="fas fa-user-gear"></i>
                                    </span>
                                    <div>
                                        <div class="perm-role-title"><?php echo htmlspecialchars(adminRoleLabel($role)); ?></div>
                                        <div class="perm-role-sub">
                                            <span class="perm-role-count" data-role-count="<?php echo htmlspecialchars($role); ?>"><?php echo (int) $roleCount; ?></span>
                                            <?php echo t('users.perm_enabled_count'); ?>
                                        </div>
                                    </div>
                                </div>
                                <span class="perm-role-chevron" style="transform: rotate(0deg);"><i class="fas fa-chevron-down"></i></span>
                            </div>

                            <div class="collapse" id="<?php echo htmlspecialchars($roleCollapseId); ?>">
                                <div class="perm-role-body">
                                    <div class="perm-role-bulkbar d-flex flex-wrap align-items-center gap-2 pb-2 mb-2" style="border-bottom:1px solid rgba(148,163,184,0.18);">
                                        <button type="button"
                                                class="btn btn-sm btn-outline-primary perm-bulk-btn"
                                                data-role-toggle="all"
                                                data-role="<?php echo htmlspecialchars($role); ?>">
                                            <?php echo t('users.perm_select_all'); ?>
                                        </button>
                                        <button type="button"
                                                class="btn btn-sm btn-outline-secondary perm-bulk-btn"
                                                data-role-toggle="none"
                                                data-role="<?php echo htmlspecialchars($role); ?>">
                                            <?php echo t('users.perm_clear'); ?>
                                        </button>
                                        <span class="small ms-auto" style="color:#64748b;"><?php echo t('users.perm_bulk_hint'); ?></span>
                                    </div>
                                    <?php foreach ($groupedPerms as $groupName => $groupPerms): ?>
                                        <div class="perm-group-block">
                                            <div class="perm-group-title">
                                                <span class="perm-group-dot"></span>
                                                <?php echo htmlspecialchars(adminPermGroupLabel((string) $groupName, (string) $lang)); ?>
                                            </div>

                                            <div class="perm-cards-grid">
                                                <?php foreach ($groupPerms as $pk): ?>
                                                    <?php
                                                    $has = in_array($pk, $rolePerms, true);
                                                    $rid = 'rp_' . $role . '_' . preg_replace('/[^a-z0-9_]/i', '_', $pk);
                                                    ?>
                                                    <label class="perm-check-card <?php echo $has ? 'is-checked' : ''; ?>"
                                                           for="<?php echo htmlspecialchars($rid); ?>"
                                                           data-role-card="<?php echo htmlspecialchars($role); ?>">
                                                        <input
                                                            class="perm-check-input"
                                                            type="checkbox"
                                                            name="rp[<?php echo htmlspecialchars($role); ?>][<?php echo htmlspecialchars($pk); ?>]"
                                                            value="1"
                                                            id="<?php echo htmlspecialchars($rid); ?>"
                                                            data-role="<?php echo htmlspecialchars($role); ?>"
                                                            <?php echo $has ? 'checked' : ''; ?>>
                                                        <span class="perm-check-mark">
                                                            <i class="fas fa-check"></i>
                                                        </span>

                                                        <span class="perm-check-content">
                                                            <span class="perm-check-title"><?php echo htmlspecialchars(t('users.perm.' . $pk)); ?></span>
                                                        </span>
                                                    </label>
                                                <?php endforeach; ?>
                                            </div>
                                        </div>
                                    <?php endforeach; ?>
                                </div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>

                <div class="perm-matrix-savebar">
                    <button type="submit" class="btn btn-primary px-4">
                        <i class="fas fa-floppy-disk me-2"></i><?php echo t('users.perm_matrix_save'); ?>
                    </button>
                </div>
            </form>
        </div>
    </div>
    <?php endif; ?>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
<script>
(function () {
    var data = {
        roles: <?php echo json_encode($rolesPermsForJs, JSON_UNESCAPED_UNICODE); ?>,
        labels: <?php echo json_encode($permLabelsForJs, JSON_UNESCAPED_UNICODE); ?>,
        roleKeys: <?php echo json_encode($allowedRoles, JSON_UNESCAPED_UNICODE); ?>
    };

    var sel = document.getElementById('staffAddRoleSelect');
    var ul = document.getElementById('rolePermissionsList');

    function expandPerms(keys) {
        var out = [];
        (keys || []).forEach(function (p) {
            if (p === '*') {
                Object.keys(data.labels).forEach(function (k) {
                    if (out.indexOf(data.labels[k]) === -1) out.push(data.labels[k]);
                });
            } else if (data.labels[p]) {
                out.push(data.labels[p]);
            }
        });
        return out;
    }

    function renderRolePreview() {
        if (!sel || !ul) return;
        var role = sel.value;
        var keys = data.roles[role] || [];
        var lines = expandPerms(keys);
        ul.innerHTML = '';
        lines.forEach(function (text) {
            var li = document.createElement('li');
            li.textContent = text;
            ul.appendChild(li);
        });
    }

    if (sel && ul) {
        sel.addEventListener('change', renderRolePreview);
        renderRolePreview();
    }

    function refreshRoleCount(role) {
        var checked = document.querySelectorAll('.perm-check-input[data-role="' + role + '"]:checked').length;
        var target = document.querySelector('[data-role-count="' + role + '"]');
        if (target) target.textContent = checked;
    }

    function refreshCardState(input) {
        var card = input.closest('.perm-check-card');
        if (!card) return;
        if (input.checked) {
            card.classList.add('is-checked');
        } else {
            card.classList.remove('is-checked');
        }
    }

    document.querySelectorAll('.perm-check-input').forEach(function (input) {
        refreshCardState(input);
        input.addEventListener('change', function () {
            refreshCardState(input);
            refreshRoleCount(input.getAttribute('data-role'));
        });
    });

    document.querySelectorAll('[data-role-toggle]').forEach(function (btn) {
        btn.addEventListener('click', function (e) {
            e.stopPropagation();
            var role = btn.getAttribute('data-role');
            var mode = btn.getAttribute('data-role-toggle');
            document.querySelectorAll('.perm-check-input[data-role="' + role + '"]').forEach(function (input) {
                input.checked = (mode === 'all');
                refreshCardState(input);
            });
            refreshRoleCount(role);
        });
    });

    var mainCollapse = document.getElementById('permMatrixMainCollapse');
    var mainChevron = document.getElementById('permMatrixChevron');
    if (mainCollapse && mainChevron) {
        mainCollapse.addEventListener('show.bs.collapse', function () {
            mainChevron.style.transform = 'rotate(180deg)';
        });
        mainCollapse.addEventListener('hide.bs.collapse', function () {
            mainChevron.style.transform = 'rotate(0deg)';
        });
    }

    document.querySelectorAll('.perm-role-card').forEach(function (card) {
        var collapse = card.querySelector('.collapse');
        var chevron = card.querySelector('.perm-role-chevron');
        if (!collapse || !chevron) return;

        collapse.addEventListener('show.bs.collapse', function () {
            chevron.style.transform = 'rotate(180deg)';
        });

        collapse.addEventListener('hide.bs.collapse', function () {
            chevron.style.transform = 'rotate(0deg)';
        });
    });

    var permForm = document.getElementById('permMatrixForm');
    if (permForm) {
        permForm.addEventListener('submit', function () {
            permForm.querySelectorAll('input[data-rp-sync]').forEach(function (el) {
                el.remove();
            });
            document.querySelectorAll('.perm-check-input').forEach(function (input) {
                var h = document.createElement('input');
                h.type = 'hidden';
                h.name = input.name;
                h.value = input.checked ? '1' : '0';
                h.setAttribute('data-rp-sync', '1');
                permForm.appendChild(h);
                input.disabled = true;
            });
        });
    }

    (data.roleKeys || []).forEach(refreshRoleCount);
})();

// Live instant search for Staff & Resellers tables
(function () {
    var searchInputs = document.querySelectorAll('.staff-search-input');
    if (!searchInputs || searchInputs.length === 0) return;

    var isArabic = <?php echo json_encode($lang === 'ar'); ?>;

    function filterAllStaffTables(query) {
        var q = (query || '').trim().toLowerCase();
        var tables = document.querySelectorAll('.table-staff');

        tables.forEach(function (table) {
            var tbody = table.querySelector('tbody');
            if (!tbody) return;

            var rows = tbody.querySelectorAll('tr.staff-user-row');
            var matched = 0;

            rows.forEach(function (row) {
                var uname = (row.getAttribute('data-username') || '').toLowerCase();
                var email = (row.getAttribute('data-email') || '').toLowerCase();
                var creator = (row.getAttribute('data-creator') || '').toLowerCase();
                var fullText = row.textContent.toLowerCase();

                if (!q || uname.indexOf(q) !== -1 || email.indexOf(q) !== -1 || creator.indexOf(q) !== -1 || fullText.indexOf(q) !== -1) {
                    row.style.display = '';
                    matched++;
                } else {
                    row.style.display = 'none';
                }
            });

            // Handle "No results found" row
            var noRes = tbody.querySelector('.staff-no-search-results');
            if (rows.length > 0 && matched === 0 && q !== '') {
                if (!noRes) {
                    noRes = document.createElement('tr');
                    noRes.className = 'staff-no-search-results';
                    var colCount = table.querySelectorAll('thead th').length || 7;
                    var label = isArabic
                        ? 'لا توجد حسابات مطابقة لاسم المستخدم "' + q + '"'
                        : 'No accounts matching username "' + q + '"';
                    noRes.innerHTML = '<td colspan="' + colCount + '" class="text-center py-4 text-muted">' +
                        '<i class="fas fa-search fa-2x mb-2 d-block opacity-50"></i>' +
                        '<span>' + label + '</span>' +
                        '</td>';
                    tbody.appendChild(noRes);
                } else {
                    var span = noRes.querySelector('span');
                    if (span) {
                        span.textContent = isArabic
                            ? 'لا توجد حسابات مطابقة لاسم المستخدم "' + q + '"'
                            : 'No accounts matching username "' + q + '"';
                    }
                    noRes.style.display = '';
                }
            } else if (noRes) {
                noRes.style.display = 'none';
            }
        });
    }

    searchInputs.forEach(function (input) {
        input.addEventListener('input', function () {
            var val = this.value;
            searchInputs.forEach(function (other) {
                if (other !== input) other.value = val;
            });
            filterAllStaffTables(val);
        });
        input.addEventListener('keyup', function () {
            filterAllStaffTables(this.value);
        });
    });

    var firstVal = searchInputs[0].value;
    if (firstVal && firstVal.trim() !== '') {
        filterAllStaffTables(firstVal);
    }
})();
</script>
</body>
</html>
