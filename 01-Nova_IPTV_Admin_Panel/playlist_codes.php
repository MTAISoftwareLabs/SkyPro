<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
require_once __DIR__ . '/includes/pagination.php';
require_once __DIR__ . '/includes/playlist_code_helpers.php';

if (!function_exists('adminIsLoggedIn') || !adminIsLoggedIn()) {
    header('Location: login.php');
    exit;
}

$current_page = 'playlist_codes';
$canEdit = adminCan('devices_add');

$success = '';
$error = '';

function playlist_codes_validate_url(string $url): bool {
    $url = trim($url);
    if ($url === '' || strlen($url) < 8) {
        return false;
    }
    return (bool)preg_match('#^https?://#i', $url);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    if (isset($_POST['delete_id'])) {
        if (!$canEdit) {
            header('Location: access_denied.php?perm=devices_add');
            exit;
        }
        $id = (int)$_POST['delete_id'];
        if ($id > 0) {
            try {
                // تنظيف استخدامات الجهاز لنفس الرمز (حتى لو لم تكن الـ FK فعّالة في بعض البيئات القديمة).
                $d1 = $conn->prepare('DELETE FROM playlist_code_devices WHERE code_id = ?');
                $d1->execute([$id]);

                $d2 = $conn->prepare('DELETE FROM playlist_access_codes WHERE id = ?');
                $d2->execute([$id]);
                header('Location: playlist_codes.php?msg=deleted');
                exit;
            } catch (Throwable $e) {
                $error = t('msg.db_error');
            }
        }
    } elseif (isset($_POST['update_url_id'])) {
        if (!$canEdit) {
            header('Location: access_denied.php?perm=devices_add');
            exit;
        }
        $id = (int)($_POST['update_url_id'] ?? 0);
        $m3uUrl = trim((string)($_POST['m3u_url'] ?? ''));
        if ($id > 0) {
            if ($m3uUrl === '' || !playlist_codes_validate_url($m3uUrl)) {
                $error = t('playlist_codes.err_url');
            } else {
                try {
                    $u = $conn->prepare('UPDATE playlist_access_codes SET m3u_url = ? WHERE id = ?');
                    $u->execute([$m3uUrl, $id]);
                    header('Location: playlist_codes.php?msg=url_updated');
                    exit;
                } catch (Throwable $e) {
                    $error = t('msg.db_error');
                }
            }
        }
    } elseif (isset($_POST['update_max_id'])) {
        if (!$canEdit) {
            header('Location: access_denied.php?perm=devices_add');
            exit;
        }
        $id = (int)($_POST['update_max_id'] ?? 0);
        $maxDevices = isset($_POST['max_devices']) ? (int)$_POST['max_devices'] : 1;
        if ($maxDevices < 1) {
            $maxDevices = 1;
        }
        if ($maxDevices > 999) {
            $maxDevices = 999;
        }
        if ($id > 0) {
            try {
                $u = $conn->prepare('UPDATE playlist_access_codes SET max_devices = ? WHERE id = ?');
                $u->execute([$maxDevices, $id]);
                header('Location: playlist_codes.php?msg=max_updated');
                exit;
            } catch (Throwable $e) {
                $error = t('msg.db_error');
            }
        }
    } elseif (isset($_POST['replace_playlist_host'])) {
        if (!$canEdit) {
            header('Location: access_denied.php?perm=devices_add');
            exit;
        }
        $oldHost = trim((string) ($_POST['host_replace_old'] ?? ''));
        $newHost = trim((string) ($_POST['host_replace_new'] ?? ''));
        if ($oldHost === '' || $newHost === '') {
            $error = t('playlist_codes.host_replace_err_required');
        } else {
            $result = admin_bulk_replace_playlist_code_host($conn, $oldHost, $newHost);
            if (empty($result['ok'])) {
                $errKey = (string) ($result['error'] ?? 'db');
                $map = [
                    'invalid_host' => 'playlist_codes.host_replace_err_invalid',
                    'same_host' => 'playlist_codes.host_replace_err_same',
                    'db' => 'msg.db_error',
                ];
                $error = t($map[$errKey] ?? 'msg.db_error');
            } else {
                $qs = http_build_query([
                    'msg' => 'host_replaced',
                    'codes' => (int) ($result['codes_updated'] ?? 0),
                    'devices' => (int) ($result['devices_updated'] ?? 0),
                ]);
                header('Location: playlist_codes.php?' . $qs);
                exit;
            }
        }
    } elseif (isset($_POST['save_code'])) {
        if (!$canEdit) {
            header('Location: access_denied.php?perm=devices_add');
            exit;
        }
        $label = trim((string)($_POST['label'] ?? ''));
        $m3uUrl = trim((string)($_POST['m3u_url'] ?? ''));
        $code = preg_replace('/\D/', '', (string)($_POST['code'] ?? ''));
        $bindMode = strtolower(trim((string)($_POST['bind_mode'] ?? 'general')));
        if ($bindMode !== 'device') {
            $bindMode = 'general';
        }
        $boundDeviceId = trim((string)($_POST['bound_device_id'] ?? ''));
        $boundDeviceId = preg_replace('/[\x{200B}-\x{200D}\x{FEFF}]/u', '', $boundDeviceId) ?? $boundDeviceId;
        $boundDeviceId = preg_replace('/\s+/u', '', $boundDeviceId) ?? $boundDeviceId;
        if ($bindMode === 'general') {
            $boundDeviceId = '';
            $maxDevices = isset($_POST['max_devices']) ? (int)$_POST['max_devices'] : 999;
            if ($maxDevices < 1) {
                $maxDevices = 1;
            }
            if ($maxDevices > 9999) {
                $maxDevices = 9999;
            }
        } else {
            $maxDevices = 1;
        }

        $needsDevice = ($bindMode === 'device' && $boundDeviceId === '');
        if ($label === '' || $m3uUrl === '' || $code === '' || $needsDevice) {
            $error = $needsDevice
                ? t('playlist_codes.err_device_required')
                : t('playlist_codes.err_required');
        } elseif (strlen($code) < 5 || strlen($code) > 6) {
            $error = t('playlist_codes.err_code_format');
        } elseif ($code === '00000') {
            $error = t('playlist_codes.err_demo_reserved');
        } elseif (!playlist_codes_validate_url($m3uUrl)) {
            $error = t('playlist_codes.err_url');
        } else {
            try {
                if ($bindMode === 'device') {
                    $chk = $conn->prepare('SELECT id FROM playlist_access_codes WHERE code = ? AND bound_device_id = ? LIMIT 1');
                    $chk->execute([$code, $boundDeviceId]);
                } else {
                    // عام = فريد عالمياً (مثل النظام القديم قبل ربط الجهاز)
                    $chk = $conn->prepare('SELECT id FROM playlist_access_codes WHERE code = ? LIMIT 1');
                    $chk->execute([$code]);
                }
                if ($chk->fetch()) {
                    $error = $bindMode === 'device'
                        ? t('playlist_codes.err_duplicate_device')
                        : t('playlist_codes.err_duplicate_general');
                } else {
                    $ins = $conn->prepare('INSERT INTO playlist_access_codes (label, m3u_url, code, max_devices, bound_device_id) VALUES (?, ?, ?, ?, ?)');
                    $ins->execute([$label, $m3uUrl, $code, $maxDevices, $boundDeviceId !== '' ? $boundDeviceId : null]);
                    header('Location: playlist_codes.php?msg=saved');
                    exit;
                }
            } catch (PDOException $e) {
                if ((int)$e->getCode() === 23000) {
                    $error = $bindMode === 'device'
                        ? t('playlist_codes.err_duplicate_device')
                        : t('playlist_codes.err_duplicate_general');
                } else {
                    $error = t('msg.db_error');
                }
            }
        }
    }
}

if (isset($_GET['msg'])) {
    if ($_GET['msg'] === 'saved') {
        $success = t('playlist_codes.saved');
    } elseif ($_GET['msg'] === 'deleted') {
        $success = t('playlist_codes.deleted');
    } elseif ($_GET['msg'] === 'max_updated') {
        $success = t('playlist_codes.max_updated');
    } elseif ($_GET['msg'] === 'url_updated') {
        $success = t('playlist_codes.url_updated');
    } elseif ($_GET['msg'] === 'host_replaced') {
        $codesN = isset($_GET['codes']) ? (int) $_GET['codes'] : 0;
        $devicesN = isset($_GET['devices']) ? (int) $_GET['devices'] : 0;
        $success = str_replace(
            ['@codes', '@devices'],
            [(string) $codesN, (string) $devicesN],
            t('playlist_codes.host_replace_ok')
        );
    }
}

$rows = [];
$existingCodeList = [];
$codesPager = ['page' => 1, 'pages' => 1, 'total' => 0, 'items' => []];
// الضيف لا يرى الأكواد/الروابط أصلاً — لا تُحمَّل من قاعدة البيانات.
if ($canEdit) {
    try {
        $q = $conn->query('SELECT c.id, c.label, c.m3u_url, c.code, c.created_at, c.max_devices, c.bound_device_id,
            (SELECT COUNT(*) FROM playlist_code_devices d WHERE d.code_id = c.id) AS device_count
            FROM playlist_access_codes c ORDER BY c.id DESC');
        $rowsAll = $q->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $rowsAll = [];
    }

    foreach ($rowsAll as $_r) {
        if (isset($_r['code']) && $_r['code'] !== '') {
            $existingCodeList[] = [
                'code' => (string)$_r['code'],
                'device' => trim((string)($_r['bound_device_id'] ?? '')),
            ];
        }
    }

    $codesPager = admin_paginate_items($rowsAll);
    $rows = $codesPager['items'];
}

$panelDevices = [];
if ($canEdit) {
    try {
        $panelDevices = getActivatedDevices($conn);
    } catch (Throwable $e) {
        $panelDevices = [];
    }
}

function playlist_codes_normalize_status(string $status): string {
    $status = strtolower(trim($status));
    if (!in_array($status, ['active', 'expired', 'blocked'], true)) {
        return 'active';
    }
    return $status;
}

?>
<!DOCTYPE html>
<html dir="<?php echo isset($isRtl) && $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang ?? 'ar'); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo htmlspecialchars(t('playlist_codes.title')); ?> - <?php echo htmlspecialchars(t('app.title')); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap" rel="stylesheet">
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<style>
/* ===== Playlist Codes — Redesigned ===== */
/* لا نعيد تعريف body أو html — الهيدر يتولى ذلك */
.pc-wrap {
    max-width: 960px;
    margin: 0 auto;
    padding: 2rem 1rem 3rem;
}

/* Header */
.pc-header {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-bottom: 2rem;
}
.pc-header-icon {
    width: 48px;
    height: 48px;
    border-radius: 14px;
    background: linear-gradient(135deg, #38bdf8, #6366f1 55%, #7c3aed);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    font-size: 1.2rem;
    color: #ffffff;
}
.pc-header h1 {
    font-size: 1.25rem !important;
    font-weight: 700 !important;
    color: #f8fafc !important;
    margin: 0 0 4px 0 !important;
    line-height: 1.3;
}
.pc-header p {
    font-size: 0.875rem !important;
    color: #94a3b8 !important;
    margin: 0 !important;
    line-height: 1.5;
}

/* Cards */
.pc-card {
    background: rgba(15, 23, 42, 0.65);
    border: 1px solid rgba(148, 163, 184, 0.2);
    border-radius: 18px;
    margin-bottom: 1.25rem;
    overflow: hidden;
}
.pc-card--form {
    overflow: visible;
    position: relative;
    z-index: 20;
}
.pc-card--form .pc-card-body {
    overflow: visible;
}
.pc-card-head {
    padding: 12px 20px;
    border-bottom: 1px solid rgba(148, 163, 184, 0.15);
    background: linear-gradient(90deg, rgba(56,189,248,0.1), rgba(99,102,241,0.07));
    display: flex;
    align-items: center;
    gap: 8px;
}
.pc-card-head i {
    color: #38bdf8;
    font-size: 0.9rem;
}
.pc-card-head span {
    font-size: 0.9rem;
    font-weight: 700;
    color: #e2e8f0;
}
.pc-card-body {
    padding: 20px;
}

/* Form */
.pc-form-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
}
.pc-field-full { grid-column: 1 / -1; }

.pc-form .form-label {
    font-size: 0.75rem;
    font-weight: 600;
    color: #94a3b8;
    margin-bottom: 6px;
    display: block;
}
.pc-form input.form-control,
.pc-form select.form-control,
.pc-form textarea.form-control {
    background: #1e293b !important;
    border: 1px solid #334155 !important;
    border-radius: 12px !important;
    padding: 9px 13px !important;
    font-size: 0.875rem !important;
    color: #f8fafc !important;
    transition: border-color .15s, box-shadow .15s;
}
.pc-form input.form-control:focus,
.pc-form select.form-control:focus {
    border-color: #38bdf8 !important;
    box-shadow: 0 0 0 3px rgba(56, 189, 248, 0.18) !important;
    background: #1e293b !important;
    color: #f8fafc !important;
}
.pc-form input.form-control::placeholder { color: #475569; }

.pc-number-group{
    display:flex;
    align-items:center;
    width:100%;
    max-width:100%;
    background:#0f172a;
    border:1px solid #334155;
    border-radius:14px;
    overflow:hidden;
}
.pc-number-group button{
    flex: 1;
    height:40px;
    border:none;
    background:#111827;
    color:#38bdf8;
    font-size:18px;
    font-weight:800;
    cursor:pointer;
    transition:.15s;
}
.pc-number-group button:hover{
    background:#1f2937;
    color:#e2e8f0;
}
.pc-number-group input{
    flex:1;
    height:40px;
    border:none !important;
    background:transparent !important;
    color:#f8fafc !important;
    text-align:center;
    font-weight:800;
    border-radius:0 !important;
    box-shadow:none !important;
}
.pc-number-group input:focus{
    outline:none;
}
.pc-number-group input[type=number]::-webkit-outer-spin-button,
.pc-number-group input[type=number]::-webkit-inner-spin-button{
    -webkit-appearance:none;
    margin:0;
}
.pc-number-group input[type=number]{
    -moz-appearance:textfield;
    appearance:textfield;
}

/* Code input group */
.pc-code-group {
    display: flex;
    flex-wrap: nowrap;
    align-items: stretch;
    width: 100%;
    max-width: 100%;
}
.pc-code-group > .form-control {
    flex: 1 1 auto;
    min-width: 0;
    width: 1%; /* Bootstrap input-group trick — OK in row */
}
.pc-code-group input.form-control {
    border-radius: 12px 0 0 12px !important;
    font-family: ui-monospace, monospace;
    letter-spacing: 0.1em;
}
html[dir="rtl"] .pc-code-group input.form-control {
    border-radius: 0 12px 12px 0 !important;
}
.pc-code-group.pc-code-group--custom input.form-control {
    border-radius: 12px !important;
    width: 100% !important;
    flex: 1 1 100% !important;
}
.pc-code-group .btn-gen {
    flex: 0 0 auto;
    background: #0e7490;
    border: 1px solid #0e7490;
    border-radius: 0 12px 12px 0;
    padding: 9px 16px;
    font-size: 0.8rem;
    font-weight: 700;
    color: #fff;
    cursor: pointer;
    white-space: nowrap;
    transition: background .12s;
}
html[dir="rtl"] .pc-code-group .btn-gen {
    border-radius: 12px 0 0 12px;
}
.pc-code-group .btn-gen:hover { background: #0891b2; }

/* Code mode — مدمج بمستوى أزرار النموذج (زر التوليد ~40px) */
.pc-segment {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-bottom: 8px;
}
.pc-segment__item {
    position: relative;
    margin: 0;
    cursor: pointer;
    flex: 1 1 calc(50% - 4px);
    min-width: 120px;
}
.pc-segment__item input {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
    opacity: 0;
}
.pc-segment__card {
    display: flex;
    flex-direction: row;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 40px;
    padding: 8px 12px;
    border-radius: 12px;
    background: rgba(15, 23, 42, 0.72);
    border: 1px solid rgba(148, 163, 184, 0.22);
    transition: border-color .18s ease, background .18s ease, box-shadow .18s ease;
}
.pc-segment__item:hover .pc-segment__card {
    border-color: rgba(56, 189, 248, 0.4);
    background: rgba(30, 41, 59, 0.55);
}
.pc-segment__item input:checked + .pc-segment__card {
    border-color: rgba(56, 189, 248, 0.65);
    background: linear-gradient(
        148deg,
        rgba(14, 116, 144, 0.22),
        rgba(99, 102, 241, 0.1)
    );
    box-shadow: 0 0 0 1px rgba(56, 189, 248, 0.1) inset;
}
.pc-segment__item input:focus-visible + .pc-segment__card {
    outline: 2px solid #38bdf8;
    outline-offset: 2px;
}
.pc-segment__icon {
    width: 26px;
    height: 26px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.72rem;
    flex-shrink: 0;
    background: rgba(56, 189, 248, 0.12);
    color: #7dd3fc;
    transition: background .18s, color .18s;
}
.pc-segment__item input:checked + .pc-segment__card .pc-segment__icon {
    background: rgba(56, 189, 248, 0.26);
    color: #f0f9ff;
}
.pc-segment__title {
    font-size: 0.78rem;
    font-weight: 700;
    color: #f1f5f9;
    letter-spacing: 0.01em;
    line-height: 1.2;
    white-space: nowrap;
}
.pc-custom-hint {
    font-size: 0.72rem;
    color: #64748b;
    margin-top: 8px;
    line-height: 1.45;
    display: none;
}

/* In-page toast (no browser alert) */
@keyframes pcToastIn {
    from { opacity: 0; transform: translateY(-10px) scale(0.98); }
    to { opacity: 1; transform: translateY(0) scale(1); }
}
@keyframes pcToastOut {
    from { opacity: 1; transform: translateY(0) scale(1); }
    to { opacity: 0; transform: translateY(-6px) scale(0.98); }
}
.pc-toast-host {
    position: fixed;
    z-index: 10850;
    top: 1rem;
    right: 1rem;
    display: flex;
    flex-direction: column;
    gap: 10px;
    pointer-events: none;
    max-width: min(420px, calc(100vw - 1.5rem));
}
html[dir="rtl"] .pc-toast-host {
    right: auto;
    left: 1rem;
}
.pc-toast {
    pointer-events: auto;
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: start;
    gap: 12px 14px;
    padding: 15px 14px 15px 16px;
    border-radius: 16px;
    background: linear-gradient(
        135deg,
        rgba(15, 23, 42, 0.94) 0%,
        rgba(30, 41, 59, 0.9) 100%
    );
    border: 1px solid rgba(148, 163, 184, 0.28);
    box-shadow:
        0 22px 48px rgba(0, 0, 0, 0.45),
        0 0 0 1px rgba(255, 255, 255, 0.04) inset;
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    animation: pcToastIn 0.38s cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
.pc-toast.pc-toast--out {
    animation: pcToastOut 0.28s ease forwards;
}
.pc-toast__icon {
    width: 42px;
    height: 42px;
    border-radius: 13px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.05rem;
    flex-shrink: 0;
}
.pc-toast--error .pc-toast__icon {
    background: linear-gradient(145deg, rgba(239, 68, 68, 0.22), rgba(220, 38, 38, 0.12));
    color: #fecaca;
    border: 1px solid rgba(248, 113, 113, 0.35);
}
.pc-toast--warning .pc-toast__icon {
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.22), rgba(217, 119, 6, 0.12));
    color: #fde68a;
    border: 1px solid rgba(251, 191, 36, 0.35);
}
.pc-toast__body { min-width: 0; }
.pc-toast__text {
    margin: 0;
    font-size: 0.84rem;
    line-height: 1.55;
    color: #e2e8f0;
    font-weight: 500;
}
.pc-toast__close {
    flex-shrink: 0;
    width: 32px;
    height: 32px;
    border: none;
    border-radius: 10px;
    background: rgba(148, 163, 184, 0.12);
    color: #94a3b8;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s, color 0.15s;
}
.pc-toast__close:hover {
    background: rgba(148, 163, 184, 0.22);
    color: #f1f5f9;
}
.pc-toast--error {
    border-color: rgba(248, 113, 113, 0.32);
    box-shadow:
        0 22px 48px rgba(0, 0, 0, 0.45),
        0 0 32px rgba(239, 68, 68, 0.12),
        0 0 0 1px rgba(255, 255, 255, 0.04) inset;
}
.pc-toast--warning {
    border-color: rgba(251, 191, 36, 0.28);
    box-shadow:
        0 22px 48px rgba(0, 0, 0, 0.45),
        0 0 28px rgba(245, 158, 11, 0.1),
        0 0 0 1px rgba(255, 255, 255, 0.04) inset;
}

/* Save button */
.pc-btn-save {
    width: 100%;
    border-radius: 14px;
    padding: 11px 20px;
    font-size: 0.9rem;
    font-weight: 800;
    border: none;
    background: linear-gradient(135deg, #facc15, #eab308 50%, #ca8a04);
    color: #0f172a;
    cursor: pointer;
    transition: opacity .12s, transform .1s;
}
.pc-btn-save:hover {
    opacity: .9;
    transform: translateY(-1px);
    color: #0f172a;
}

/* Saved codes list — compact rows */
.pc-saved-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 12px 12px;
}
.pc-saved-item {
    border: 1px solid rgba(148, 163, 184, 0.16);
    border-radius: 12px;
    background: rgba(2, 6, 23, 0.45);
    padding: 10px 12px;
    transition: border-color .15s ease, background .15s ease;
}
.pc-saved-item:hover {
    border-color: rgba(56, 189, 248, 0.24);
    background: rgba(15, 23, 42, 0.62);
}
.pc-saved-row-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 10px;
    flex-wrap: wrap;
}
.pc-saved-info {
    flex: 1;
    min-width: 0;
}
.pc-saved-info-top {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    row-gap: 4px;
}
.pc-saved-info-meta {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 6px 10px;
    margin-top: 5px;
}
.pc-saved-meta-chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 0.68rem;
    color: #94a3b8;
    white-space: nowrap;
}
.pc-saved-meta-chip i {
    font-size: 0.62rem;
    opacity: 0.85;
    width: 12px;
    text-align: center;
}
.pc-saved-meta-chip strong {
    color: #e2e8f0;
    font-weight: 800;
}
.pc-saved-meta-chip--mono {
    font-family: ui-monospace, Menlo, Consolas, monospace;
    font-size: 0.66rem;
    color: #7dd3fc;
    max-width: 140px;
    overflow: hidden;
    text-overflow: ellipsis;
}
.pc-saved-url {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 7px;
    padding-top: 7px;
    border-top: 1px solid rgba(148, 163, 184, 0.1);
    font-size: 0.7rem;
    color: #64748b;
    min-width: 0;
}
.pc-saved-url i {
    flex-shrink: 0;
    font-size: 0.62rem;
    opacity: 0.8;
}
.pc-saved-url span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
}
.pc-saved-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}
.pc-saved-empty {
    padding: 24px 12px;
    text-align: center;
    color: #64748b;
    font-size: 0.85rem;
}

.pc-badge-code {
    font-family: ui-monospace, monospace;
    font-size: 0.78rem;
    font-weight: 800;
    background: #164e63;
    border-radius: 8px;
    padding: 3px 9px;
    color: #7dd3fc;
    white-space: nowrap;
    flex-shrink: 0;
    display: inline-block;
}
.pc-badge-general {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 0.66rem;
    font-weight: 800;
    background: rgba(34, 197, 94, 0.12);
    border: 1px solid rgba(34, 197, 94, 0.3);
    border-radius: 999px;
    padding: 2px 8px;
    color: #4ade80;
}
.pc-saved-name {
    font-size: 0.84rem;
    font-weight: 800;
    color: #f8fafc;
    line-height: 1.25;
}

/* Bind mode — قائمة منسدلة مخصّصة مع أيقونات (General / Specific device) */
.pc-bind-select-wrap {
    margin-bottom: 4px;
}
.pc-bind-dropdown {
    position: relative;
}
.pc-bind-select-trigger {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 14px;
    border-radius: 12px;
    background: rgba(15, 23, 42, 0.78);
    border: 1px solid rgba(148, 163, 184, 0.24);
    color: #f8fafc;
    font-size: 0.84rem;
    font-weight: 700;
    line-height: 1.35;
    cursor: pointer;
    text-align: start;
    transition: border-color .18s ease, background .18s ease, box-shadow .18s ease;
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.03) inset;
}
html[dir="rtl"] .pc-bind-select-trigger {
    text-align: right;
}
.pc-bind-select-trigger:hover {
    border-color: rgba(56, 189, 248, 0.42);
    background: rgba(30, 41, 59, 0.72);
}
.pc-bind-select-trigger:focus {
    outline: none;
    border-color: rgba(56, 189, 248, 0.72);
    box-shadow: 0 0 0 3px rgba(14, 165, 233, 0.16), 0 0 0 1px rgba(56, 189, 248, 0.2) inset;
}
.pc-bind-dropdown--device .pc-bind-select-trigger:hover {
    border-color: rgba(168, 85, 247, 0.45);
}
.pc-bind-dropdown--device .pc-bind-select-trigger:focus {
    border-color: rgba(168, 85, 247, 0.72);
    box-shadow: 0 0 0 3px rgba(168, 85, 247, 0.14), 0 0 0 1px rgba(168, 85, 247, 0.2) inset;
}
.pc-bind-dropdown--open .pc-bind-select-trigger {
    border-color: rgba(56, 189, 248, 0.72);
    background: rgba(30, 41, 59, 0.82);
    box-shadow: 0 0 0 3px rgba(14, 165, 233, 0.12);
}
.pc-bind-dropdown--open.pc-bind-dropdown--device .pc-bind-select-trigger {
    border-color: rgba(168, 85, 247, 0.72);
    box-shadow: 0 0 0 3px rgba(168, 85, 247, 0.12);
}
.pc-bind-select-icon {
    width: 36px;
    height: 36px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.92rem;
    flex-shrink: 0;
    background: rgba(56, 189, 248, 0.14);
    color: #7dd3fc;
    transition: background .18s ease, color .18s ease;
}
.pc-bind-dropdown--device .pc-bind-select-icon {
    background: rgba(168, 85, 247, 0.14);
    color: #d8b4fe;
}
.pc-bind-select-label {
    flex: 1;
    min-width: 0;
    text-align: start;
}
html[dir="rtl"] .pc-bind-select-label {
    text-align: right;
}
.pc-bind-select-chevron {
    flex-shrink: 0;
    font-size: 0.68rem;
    color: #64748b;
    transition: color .18s ease, transform .18s ease;
}
.pc-bind-dropdown--open .pc-bind-select-chevron {
    color: #38bdf8;
    transform: rotate(180deg);
}
.pc-bind-dropdown--open.pc-bind-dropdown--device .pc-bind-select-chevron {
    color: #c084fc;
}
.pc-bind-select-menu {
    position: absolute;
    top: calc(100% + 6px);
    left: 0;
    right: 0;
    z-index: 40;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 6px;
    border-radius: 12px;
    background: rgba(15, 23, 42, 0.98);
    border: 1px solid rgba(148, 163, 184, 0.28);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.04) inset;
    backdrop-filter: blur(10px);
}
.pc-bind-select-menu[hidden] {
    display: none !important;
}
.pc-bind-select-option {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border: 1px solid transparent;
    border-radius: 10px;
    background: transparent;
    color: #f8fafc;
    text-align: start;
    cursor: pointer;
    transition: border-color .15s ease, background .15s ease;
}
html[dir="rtl"] .pc-bind-select-option {
    text-align: right;
}
.pc-bind-select-option:hover {
    background: rgba(30, 41, 59, 0.72);
    border-color: rgba(148, 163, 184, 0.18);
}
.pc-bind-select-option--active {
    background: linear-gradient(160deg, rgba(14, 116, 144, 0.22), rgba(99, 102, 241, 0.1));
    border-color: rgba(56, 189, 248, 0.35);
}
.pc-bind-select-option--active.pc-bind-select-option--device {
    background: linear-gradient(160deg, rgba(88, 28, 135, 0.2), rgba(99, 102, 241, 0.08));
    border-color: rgba(168, 85, 247, 0.35);
}
.pc-bind-select-option__icon {
    width: 36px;
    height: 36px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.9rem;
    flex-shrink: 0;
    background: rgba(56, 189, 248, 0.14);
    color: #7dd3fc;
}
.pc-bind-select-option__icon--device {
    background: rgba(168, 85, 247, 0.14);
    color: #d8b4fe;
}
.pc-bind-select-option--active .pc-bind-select-option__icon {
    background: rgba(56, 189, 248, 0.28);
    color: #f0f9ff;
}
.pc-bind-select-option--active.pc-bind-select-option--device .pc-bind-select-option__icon--device {
    background: rgba(168, 85, 247, 0.28);
    color: #fff;
}
.pc-bind-select-option__body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.pc-bind-select-option__title {
    font-size: 0.82rem;
    font-weight: 800;
    color: #f8fafc;
    line-height: 1.25;
}
.pc-bind-select-option__desc {
    font-size: 0.66rem;
    color: #94a3b8;
    line-height: 1.35;
}
.pc-bind-select-option--active .pc-bind-select-option__desc {
    color: #cbd5e1;
}
.pc-bind-select-option__check {
    width: 20px;
    height: 20px;
    border-radius: 999px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.58rem;
    flex-shrink: 0;
    color: #fff;
    background: #0ea5e9;
    opacity: 0;
    transform: scale(0.75);
    transition: opacity .15s ease, transform .15s ease;
}
.pc-bind-select-option--active .pc-bind-select-option__check {
    opacity: 1;
    transform: scale(1);
}
.pc-bind-select-option--active.pc-bind-select-option--device .pc-bind-select-option__check {
    background: #a855f7;
}
.pc-bind-select-hint {
    display: block;
    margin: 8px 0 0;
    font-size: 0.68rem;
    color: #94a3b8;
    line-height: 1.45;
}

/* Device picker — قائمة أجهزة اللوحة + إدخال يدوي */
.pc-device-picker {
    position: relative;
    z-index: 25;
    --pc-device-row-h: 56px;
    --pc-device-row-gap: 4px;
    --pc-device-visible-rows: 4;
}
.pc-device-picker--open {
    z-index: 50;
}
.pc-device-select-trigger {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    border-radius: 12px;
    background: rgba(15, 23, 42, 0.78);
    border: 1px solid rgba(148, 163, 184, 0.24);
    color: #f8fafc;
    font-size: 0.82rem;
    font-weight: 700;
    line-height: 1.35;
    cursor: pointer;
    text-align: start;
    transition: border-color .18s ease, background .18s ease, box-shadow .18s ease;
}
html[dir="rtl"] .pc-device-select-trigger {
    text-align: right;
}
.pc-device-select-trigger:hover {
    border-color: rgba(168, 85, 247, 0.45);
    background: rgba(30, 41, 59, 0.72);
}
.pc-device-select-trigger:focus {
    outline: none;
    border-color: rgba(168, 85, 247, 0.72);
    box-shadow: 0 0 0 3px rgba(168, 85, 247, 0.14);
}
.pc-device-picker--open .pc-device-select-trigger {
    border-color: rgba(168, 85, 247, 0.72);
    background: rgba(30, 41, 59, 0.82);
}
.pc-device-select-trigger__icon {
    width: 34px;
    height: 34px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.88rem;
    flex-shrink: 0;
    background: rgba(168, 85, 247, 0.14);
    color: #d8b4fe;
}
.pc-device-select-trigger__body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.pc-device-select-trigger__title {
    font-size: 0.82rem;
    font-weight: 800;
    color: #f8fafc;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.pc-device-select-trigger__sub {
    font-size: 0.66rem;
    color: #94a3b8;
    font-family: ui-monospace, Menlo, Consolas, monospace;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.pc-device-select-trigger__placeholder {
    flex: 1;
    color: #94a3b8;
    font-weight: 600;
}
.pc-device-select-chevron {
    flex-shrink: 0;
    font-size: 0.68rem;
    color: #64748b;
    transition: transform .18s ease, color .18s ease;
}
.pc-device-picker--open .pc-device-select-chevron {
    color: #c084fc;
    transform: rotate(180deg);
}
.pc-device-select-menu {
    position: absolute;
    top: calc(100% + 6px);
    left: 0;
    right: 0;
    z-index: 60;
    display: flex;
    flex-direction: column;
    gap: 0;
    padding: 8px;
    border-radius: 12px;
    background: rgba(15, 23, 42, 0.98);
    border: 1px solid rgba(148, 163, 184, 0.28);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(10px);
    overflow: hidden;
}
.pc-device-select-menu[hidden] {
    display: none !important;
}
.pc-device-search-wrap {
    position: relative;
    padding: 0 0 8px;
    flex-shrink: 0;
}
.pc-device-search-icon {
    position: absolute;
    top: 50%;
    left: 12px;
    transform: translateY(calc(-50% - 4px));
    font-size: 0.72rem;
    color: #64748b;
    pointer-events: none;
}
html[dir="rtl"] .pc-device-search-icon {
    left: auto;
    right: 12px;
}
.pc-device-select-list {
    display: flex;
    flex-direction: column;
    gap: var(--pc-device-row-gap);
    flex: 0 0 auto;
    max-height: calc(
        (var(--pc-device-row-h) * var(--pc-device-visible-rows)) +
        (var(--pc-device-row-gap) * (var(--pc-device-visible-rows) - 1))
    );
    overflow-x: hidden;
    overflow-y: auto;
    overscroll-behavior: contain;
    scrollbar-gutter: stable;
    padding: 2px 4px 6px 2px;
    scroll-padding-bottom: 6px;
}
.pc-device-select-list::-webkit-scrollbar {
    width: 8px;
}
.pc-device-select-list::-webkit-scrollbar-thumb {
    background: rgba(148, 163, 184, 0.35);
    border-radius: 999px;
}
.pc-device-select-list::-webkit-scrollbar-track {
    background: rgba(15, 23, 42, 0.35);
    border-radius: 999px;
}
.pc-device-select-footer {
    flex-shrink: 0;
    padding-top: 8px;
    margin-top: 4px;
    border-top: 1px solid rgba(148, 163, 184, 0.18);
    background: linear-gradient(180deg, rgba(15, 23, 42, 0.35), rgba(15, 23, 42, 0.98));
}
.pc-device-select-footer .pc-device-option--custom {
    min-height: 68px;
    margin: 0;
}
.pc-device-search {
    width: 100%;
    padding: 8px 10px 8px 32px;
    border-radius: 9px;
    border: 1px solid rgba(148, 163, 184, 0.22);
    background: rgba(2, 6, 23, 0.65);
    color: #f8fafc;
    font-size: 0.74rem;
}
html[dir="rtl"] .pc-device-search {
    padding: 8px 32px 8px 10px;
}
.pc-device-search:focus {
    outline: none;
    border-color: rgba(168, 85, 247, 0.5);
}
.pc-device-select-empty {
    padding: 12px 10px;
    font-size: 0.72rem;
    color: #94a3b8;
    text-align: center;
}
.pc-device-option {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    min-height: var(--pc-device-row-h);
    height: var(--pc-device-row-h);
    box-sizing: border-box;
    border: 1px solid transparent;
    border-radius: 10px;
    background: transparent;
    color: #f8fafc;
    text-align: start;
    cursor: pointer;
    transition: border-color .15s ease, background .15s ease;
    flex-shrink: 0;
}
html[dir="rtl"] .pc-device-option {
    text-align: right;
}
.pc-device-option:hover {
    background: rgba(30, 41, 59, 0.72);
    border-color: rgba(148, 163, 184, 0.18);
}
.pc-device-option--active {
    background: linear-gradient(160deg, rgba(88, 28, 135, 0.2), rgba(99, 102, 241, 0.08));
    border-color: rgba(168, 85, 247, 0.35);
}
.pc-device-option__icon {
    width: 32px;
    height: 32px;
    border-radius: 9px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.82rem;
    flex-shrink: 0;
    background: rgba(148, 163, 184, 0.12);
    color: #cbd5e1;
}
.pc-device-option--custom .pc-device-option__icon {
    background: rgba(251, 191, 36, 0.14);
    color: #fcd34d;
}
.pc-device-option__body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.pc-device-option__title {
    font-size: 0.78rem;
    font-weight: 800;
    color: #f8fafc;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.pc-device-option__id {
    font-size: 0.64rem;
    color: #94a3b8;
    font-family: ui-monospace, Menlo, Consolas, monospace;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.pc-device-option__desc {
    font-size: 0.64rem;
    color: #94a3b8;
    line-height: 1.35;
}
.pc-device-status {
    flex-shrink: 0;
    padding: 3px 8px;
    border-radius: 999px;
    font-size: 0.62rem;
    font-weight: 800;
    white-space: nowrap;
}
.pc-device-status.active {
    background: #16a34a;
    color: #fff;
}
.pc-device-status.expired {
    background: #b91c1c;
    color: #fff;
}
.pc-device-status.blocked {
    background: #475569;
    color: #fff;
}
.pc-device-select-divider {
    display: none;
}
.pc-device-custom-wrap {
    margin-top: 10px;
}
.pc-device-custom-wrap[hidden] {
    display: none !important;
}
.pc-btn-del {
    background: transparent;
    border: 1px solid #475569;
    border-radius: 20px;
    padding: 5px 14px;
    font-size: 0.75rem;
    color: #94a3b8;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    transition: all .12s;
}
.pc-btn-del:hover {
    border-color: #ef4444;
    color: #fca5a5;
    background: rgba(239, 68, 68, .08);
}

.pc-btn-edit-max{
    background: linear-gradient(135deg, rgba(37,99,235,0.22), rgba(99,102,241,0.18));
    border: 1px solid rgba(59,130,246,0.45);
    border-radius: 999px;
    padding: 6px 14px;
    font-size: 0.75rem;
    font-weight: 700;
    color: #dbeafe;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    transition: all .18s;
    box-shadow: 0 8px 18px rgba(37,99,235,.22);
}
.pc-btn-edit-max:hover {
    transform: translateY(-1px);
    border-color: rgba(56,189,248,.7);
    color: #f0f9ff;
    box-shadow: 0 12px 24px rgba(56,189,248,.25);
}

.pc-modal .modal-content{
    border-radius: 18px;
    background: radial-gradient(circle at top left, rgba(15,23,42,.98), rgba(2,6,23,.98));
    border: 1px solid rgba(148,163,184,.28);
    color: #e2e8f0;
}
.pc-modal .modal-header{
    border-bottom: 1px solid rgba(148,163,184,.2);
}
.pc-modal .modal-footer{
    border-top: 1px solid rgba(148,163,184,.2);
}
.pc-modal .btn-close{
    filter: invert(1) grayscale(1) brightness(2);
    opacity: .8;
}
.pc-modal .form-control{
    background: #1e293b !important;
    border: 1px solid #334155 !important;
    color: #f8fafc !important;
    border-radius: 12px !important;
}
.pc-modal .pc-number-group{
    margin-top:4px;
}
.pc-modal .form-control:focus{
    border-color: #38bdf8 !important;
    box-shadow: 0 0 0 3px rgba(56,189,248,.18) !important;
}
.pc-modal-code{
    font-family: ui-monospace, monospace;
    color: #7dd3fc;
    background: rgba(8,47,73,.45);
    border: 1px solid rgba(14,116,144,.35);
    border-radius: 999px;
    padding: 4px 10px;
    font-size: .8rem;
    font-weight: 800;
}
.pc-btn-save-max{
    border: none;
    border-radius: 999px;
    padding: 8px 16px;
    font-size: .85rem;
    font-weight: 800;
    color: #0f172a;
    background: linear-gradient(135deg, #38bdf8, #6366f1);
}
.pc-empty {
    text-align: center;
    padding: 48px 16px;
    color: #475569;
    font-size: 0.875rem;
}

/* Alerts */
.pc-alert-success {
    border-radius: 14px;
    background: rgba(34, 197, 94, .14);
    color: #bbf7d0;
    border: 1px solid rgba(34, 197, 94, .35);
    padding: 10px 16px;
    margin-bottom: 1rem;
    font-size: 0.875rem;
}
.pc-alert-danger {
    border-radius: 14px;
    background: rgba(239, 68, 68, .14);
    color: #fecaca;
    border: 1px solid rgba(239, 68, 68, .35);
    padding: 10px 16px;
    margin-bottom: 1rem;
    font-size: 0.875rem;
}
.pc-alert-secondary {
    border-radius: 14px;
    background: rgba(100, 116, 139, .18);
    color: #94a3b8;
    border: 1px solid rgba(100, 116, 139, .3);
    padding: 10px 16px;
    margin-bottom: 1rem;
    font-size: 0.875rem;
}

/* Responsive */
@media (max-width: 600px) {
    .pc-wrap {
        padding: 1rem 0.65rem 2rem;
    }
    .pc-header {
        margin-bottom: 1.25rem;
        gap: 10px;
    }
    .pc-header h1 {
        font-size: 1.05rem !important;
    }
    .pc-card-body {
        padding: 14px;
    }
    .pc-card-head {
        padding: 10px 14px;
    }
    .pc-saved-list {
        padding: 8px 8px 10px;
        gap: 5px;
    }
    .pc-saved-item {
        padding: 8px 10px;
    }
    .pc-saved-row-head {
        flex-direction: column;
        align-items: stretch;
    }
    .pc-saved-actions {
        width: 100%;
        justify-content: center;
        padding-top: 4px;
    }
    .pc-saved-actions .pc-btn,
    .pc-saved-actions form .pc-btn {
        min-width: 0;
        flex: 1 1 auto;
        max-width: 100%;
    }
    .pc-saved-actions form {
        width: auto;
        flex: 1 1 auto;
        display: flex;
    }
    .pc-saved-actions form .pc-btn {
        width: 100%;
    }
    .pc-btn-manage {
        width: 100%;
        justify-content: center;
        min-height: 36px;
    }
    .pc-form-grid { grid-template-columns: 1fr; }
    .pc-field-full { grid-column: 1; }
    .pc-code-group {
        flex-direction: column;
        flex-wrap: nowrap;
        align-items: stretch;
    }
    /* Bootstrap input-group sets width:1% — collapses in column layout on phones */
    .pc-code-group > .form-control,
    .pc-code-group input.form-control {
        width: 100% !important;
        max-width: 100% !important;
        flex: 0 0 auto !important;
        min-width: 0 !important;
        border-radius: 12px !important;
        margin-bottom: 8px;
    }
    .pc-code-group .btn-gen {
        border-radius: 12px !important;
        width: 100% !important;
        flex: 0 0 auto;
        align-self: stretch;
    }
    .pc-code-group.pc-code-group--custom .btn-gen {
        display: none !important;
    }
    .pc-code-group.pc-code-group--custom > .form-control {
        margin-bottom: 0;
    }
}
/* ===== FINAL PRO BUTTONS ===== */
.pc-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
}
.pc-actions form {
    margin: 0;
    width: auto;
}

/* base */
.pc-btn {
    height: 28px;
    padding: 0 10px;
    border-radius: 999px;
    font-size: 0.68rem;
    font-weight: 700;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    cursor: pointer;
    border: 1px solid transparent;
    transition: all .2s ease;
    white-space: nowrap;
    width: auto;
    box-sizing: border-box;
}

/* EDIT (clean blue) */
.pc-btn-edit {
    background: rgba(59,130,246,0.12);
    border: 1px solid rgba(59,130,246,0.35);
    color: #93c5fd;
}

.pc-btn-edit:hover {
    background: rgba(59,130,246,0.2);
    border-color: #3b82f6;
    color: #fff;
    transform: translateY(-1px);
}

/* DELETE (soft red) */
.pc-btn-delete {
    background: rgba(239,68,68,0.12);
    border: 1px solid rgba(239,68,68,0.35);
    color: #fca5a5;
}

.pc-btn-delete:hover {
    background: rgba(239,68,68,0.2);
    border-color: #ef4444;
    color: #fff;
    transform: translateY(-1px);
}

/* icon size */
.pc-btn i {
    font-size: 0.7rem;
    opacity: 0.9;
}

/* ===== Manage Devices Button ===== */
.pc-btn-manage {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 2px 8px;
    font-size: 0.66rem;
    font-weight: 700;
    border-radius: 999px;
    text-decoration: none;
    cursor: pointer;

    color: #22d3ee;
    background: rgba(6,182,212,0.12);
    border: 1px solid rgba(6,182,212,0.35);

    transition: all .2s ease;
}

.pc-btn-manage:hover {
    background: rgba(6,182,212,0.2);
    border-color: #22d3ee;
    color: #fff;
    transform: translateY(-1px);
}
.pc-host-replace-intro {
    font-size: 0.84rem;
    color: #94a3b8;
    margin: 0 0 14px;
    line-height: 1.55;
}
.pc-host-replace-hint {
    font-size: 0.72rem;
    color: #64748b;
    margin: 6px 0 0;
    line-height: 1.45;
}
.field-mono {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.82rem;
}
</style>

<div class="container-fluid px-2 px-md-3 admin-main">
    <div id="pc-toast-host" class="pc-toast-host" aria-live="polite" aria-relevant="additions"></div>
    <div class="pc-wrap">

        <!-- Page Header -->
        <div class="pc-header">
            <div class="pc-header-icon">
                <i class="fas fa-key"></i>
            </div>
            <div>
                <h1><?php echo htmlspecialchars(t('playlist_codes.title')); ?></h1>
                <p><?php echo htmlspecialchars(t('playlist_codes.subtitle')); ?></p>
            </div>
        </div>

        <!-- Alerts -->
        <?php if ($success !== ''): ?>
            <div class="pc-alert-success">
                <i class="fas fa-check-circle me-2"></i><?php echo htmlspecialchars($success); ?>
            </div>
        <?php endif; ?>
        <?php if ($error !== ''): ?>
            <div class="pc-alert-danger">
                <i class="fas fa-exclamation-circle me-2"></i><?php echo htmlspecialchars($error); ?>
            </div>
        <?php endif; ?>

        <!-- Add Form (مرئي للضيف أيضاً كمعاينة؛ الحفظ محظور من الخادم) -->
        <?php if (!$canEdit): ?>
            <div class="pc-alert-secondary">
                <i class="fas fa-eye me-2"></i><?php echo htmlspecialchars(t('playlist_codes.guest_preview_hint')); ?>
            </div>
        <?php endif; ?>
        <div class="pc-card pc-card--form">
            <div class="pc-card-head">
                <i class="fas fa-plus-circle"></i>
                <span><?php echo htmlspecialchars(t('playlist_codes.save_btn')); ?></span>
            </div>
            <div class="pc-card-body">
                <form method="post" id="pcForm" class="pc-form"
                      data-can-edit="<?php echo $canEdit ? '1' : '0'; ?>"
                      data-guest-msg="<?php echo htmlspecialchars(t('playlist_codes.guest_cannot_save'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-dup-msg="<?php echo htmlspecialchars(t('playlist_codes.err_duplicate'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-dup-general-msg="<?php echo htmlspecialchars(t('playlist_codes.err_duplicate_general'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-dup-device-msg="<?php echo htmlspecialchars(t('playlist_codes.err_duplicate_device'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-device-msg="<?php echo htmlspecialchars(t('playlist_codes.err_device_required'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-format-msg="<?php echo htmlspecialchars(t('playlist_codes.err_code_format'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-demo-msg="<?php echo htmlspecialchars(t('playlist_codes.err_demo_reserved'), ENT_QUOTES, 'UTF-8'); ?>">
                    <?php if ($canEdit): ?>
                    <input type="hidden" name="save_code" value="1">
                    <?php endif; ?>
                    <div class="pc-form-grid">

                        <div>
                            <label class="form-label"><?php echo htmlspecialchars(t('playlist_codes.name_label')); ?></label>
                            <input type="text" name="label" class="form-control" <?php echo $canEdit ? 'required' : ''; ?> maxlength="255" placeholder="Premium EU">
                        </div>

                        <div>
                            <span class="form-label d-block mb-1"><?php echo htmlspecialchars(t('playlist_codes.code_mode_label')); ?></span>
                            <div class="pc-segment" role="radiogroup" aria-label="<?php echo htmlspecialchars(t('playlist_codes.code_mode_label')); ?>">
                                <label class="pc-segment__item" title="<?php echo htmlspecialchars(t('playlist_codes.segment_random_desc'), ENT_QUOTES, 'UTF-8'); ?>">
                                    <input type="radio" name="pc_code_mode" id="pc_mode_random" value="random" checked>
                                    <span class="pc-segment__card">
                                        <span class="pc-segment__icon" aria-hidden="true"><i class="fas fa-dice"></i></span>
                                        <span class="pc-segment__title"><?php echo htmlspecialchars(t('playlist_codes.segment_random_title')); ?></span>
                                        <span class="visually-hidden pc-segment__desc"><?php echo htmlspecialchars(t('playlist_codes.segment_random_desc')); ?></span>
                                    </span>
                                </label>
                                <label class="pc-segment__item" title="<?php echo htmlspecialchars(t('playlist_codes.segment_custom_desc'), ENT_QUOTES, 'UTF-8'); ?>">
                                    <input type="radio" name="pc_code_mode" id="pc_mode_custom" value="custom">
                                    <span class="pc-segment__card">
                                        <span class="pc-segment__icon" aria-hidden="true"><i class="fas fa-keyboard"></i></span>
                                        <span class="pc-segment__title"><?php echo htmlspecialchars(t('playlist_codes.segment_custom_title')); ?></span>
                                        <span class="visually-hidden pc-segment__desc"><?php echo htmlspecialchars(t('playlist_codes.segment_custom_desc')); ?></span>
                                    </span>
                                </label>
                            </div>
                            <label class="form-label" for="pc_code"><?php echo htmlspecialchars(t('playlist_codes.code_label')); ?></label>
                            <div class="input-group pc-code-group" id="pc_code_group">
                                <input type="text" name="code" id="pc_code"
                                       class="form-control"
                                       <?php echo $canEdit ? 'required' : ''; ?> pattern="\d{5,6}" maxlength="6"
                                       inputmode="numeric" readonly placeholder="••••••" autocomplete="off">
                                <button type="button" class="btn-gen" id="pc_gen">
                                    <i class="fas fa-dice me-1"></i><?php echo htmlspecialchars(t('playlist_codes.generate_btn')); ?>
                                </button>
                            </div>
                            <p class="pc-custom-hint" id="pc_custom_hint"><?php echo htmlspecialchars(t('playlist_codes.custom_hint')); ?></p>
                        </div>

                        <div class="pc-field-full pc-bind-select-wrap">
                            <label class="form-label" for="pc_bind_mode_btn"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_label')); ?></label>
                            <div class="pc-bind-dropdown" id="pc_bind_dropdown">
                                <input type="hidden" name="bind_mode" id="pc_bind_mode" value="general">
                                <button type="button"
                                        class="pc-bind-select-trigger"
                                        id="pc_bind_mode_btn"
                                        aria-haspopup="listbox"
                                        aria-expanded="false"
                                        aria-controls="pc_bind_select_menu"
                                        aria-describedby="pc_bind_hint">
                                    <span class="pc-bind-select-icon" id="pc_bind_select_icon" aria-hidden="true"><i class="fas fa-globe"></i></span>
                                    <span class="pc-bind-select-label" id="pc_bind_select_label"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_general_title')); ?></span>
                                    <span class="pc-bind-select-chevron" aria-hidden="true"><i class="fas fa-chevron-down"></i></span>
                                </button>
                                <div class="pc-bind-select-menu" id="pc_bind_select_menu" role="listbox" hidden>
                                    <button type="button"
                                            class="pc-bind-select-option pc-bind-select-option--active"
                                            role="option"
                                            data-value="general"
                                            aria-selected="true">
                                        <span class="pc-bind-select-option__icon" aria-hidden="true"><i class="fas fa-globe"></i></span>
                                        <span class="pc-bind-select-option__body">
                                            <span class="pc-bind-select-option__title"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_general_title')); ?></span>
                                            <span class="pc-bind-select-option__desc"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_general_desc')); ?></span>
                                        </span>
                                        <span class="pc-bind-select-option__check" aria-hidden="true"><i class="fas fa-check"></i></span>
                                    </button>
                                    <button type="button"
                                            class="pc-bind-select-option pc-bind-select-option--device"
                                            role="option"
                                            data-value="device"
                                            aria-selected="false">
                                        <span class="pc-bind-select-option__icon pc-bind-select-option__icon--device" aria-hidden="true"><i class="fas fa-mobile-screen-button"></i></span>
                                        <span class="pc-bind-select-option__body">
                                            <span class="pc-bind-select-option__title"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_device_title')); ?></span>
                                            <span class="pc-bind-select-option__desc"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_device_desc')); ?></span>
                                        </span>
                                        <span class="pc-bind-select-option__check" aria-hidden="true"><i class="fas fa-check"></i></span>
                                    </button>
                                </div>
                            </div>
                            <p class="pc-bind-select-hint" id="pc_bind_hint"><?php echo htmlspecialchars(t('playlist_codes.bind_mode_general_desc')); ?></p>
                        </div>

                        <div class="pc-field-full" id="pc_max_devices_wrap">
                            <label class="form-label" for="pc_max_devices"><?php echo htmlspecialchars(t('playlist_codes.max_devices_create_label')); ?></label>
                            <div class="pc-number-group">
                                <button type="button" onclick="pcStepDown('pc_max_devices', 1, 9999)">−</button>
                                <input type="number"
                                       name="max_devices"
                                       id="pc_max_devices"
                                       min="1"
                                       max="9999"
                                       value="999"
                                       inputmode="numeric"
                                       required>
                                <button type="button" onclick="pcStepUp('pc_max_devices', 1, 9999)">+</button>
                            </div>
                            <p class="pc-custom-hint" style="display:block;margin-top:8px;"><?php echo htmlspecialchars(t('playlist_codes.max_devices_create_help')); ?></p>
                        </div>

                        <div class="pc-field-full" id="pc_device_wrap" hidden>
                            <label class="form-label" for="pc_device_btn"><?php echo htmlspecialchars(t('playlist_codes.device_pick_label')); ?></label>
                            <input type="hidden" name="bound_device_id" id="pc_bound_device" value="">
                            <div class="pc-device-picker" id="pc_device_picker">
                                <button type="button"
                                        class="pc-device-select-trigger"
                                        id="pc_device_btn"
                                        aria-haspopup="listbox"
                                        aria-expanded="false"
                                        aria-controls="pc_device_menu">
                                    <span class="pc-device-select-trigger__icon" id="pc_device_trigger_icon" aria-hidden="true"><i class="fas fa-mobile-screen-button"></i></span>
                                    <span class="pc-device-select-trigger__placeholder" id="pc_device_trigger_placeholder"><?php echo htmlspecialchars(t('playlist_codes.device_pick_placeholder')); ?></span>
                                    <span class="pc-device-select-trigger__body" id="pc_device_trigger_body" hidden>
                                        <span class="pc-device-select-trigger__title" id="pc_device_trigger_title"></span>
                                        <span class="pc-device-select-trigger__sub" id="pc_device_trigger_sub"></span>
                                    </span>
                                    <span class="pc-device-status" id="pc_device_trigger_status" hidden></span>
                                    <span class="pc-device-select-chevron" aria-hidden="true"><i class="fas fa-chevron-down"></i></span>
                                </button>
                                <div class="pc-device-select-menu" id="pc_device_menu" role="listbox" hidden>
                                    <div class="pc-device-search-wrap">
                                        <i class="fas fa-search pc-device-search-icon" aria-hidden="true"></i>
                                        <input type="search"
                                               class="pc-device-search"
                                               id="pc_device_search"
                                               placeholder="<?php echo htmlspecialchars(t('playlist_codes.device_pick_search')); ?>"
                                               autocomplete="off"
                                               spellcheck="false">
                                    </div>
                                    <div class="pc-device-select-list" id="pc_device_list">
                                        <?php if (count($panelDevices) === 0): ?>
                                            <div class="pc-device-select-empty" id="pc_device_empty"><?php echo htmlspecialchars(t('playlist_codes.device_pick_empty')); ?></div>
                                        <?php else: ?>
                                            <?php foreach ($panelDevices as $pd):
                                                $pdId = trim((string)($pd['device_id'] ?? ''));
                                                if ($pdId === '') continue;
                                                $pdName = trim((string)($pd['device_name'] ?? ''));
                                                $pdStatus = playlist_codes_normalize_status((string)($pd['status'] ?? 'active'));
                                                $pdTitle = $pdName !== '' ? $pdName : $pdId;
                                            ?>
                                            <button type="button"
                                                    class="pc-device-option"
                                                    role="option"
                                                    data-device-id="<?php echo htmlspecialchars($pdId, ENT_QUOTES, 'UTF-8'); ?>"
                                                    data-device-title="<?php echo htmlspecialchars($pdTitle, ENT_QUOTES, 'UTF-8'); ?>"
                                                    data-device-name="<?php echo htmlspecialchars($pdName, ENT_QUOTES, 'UTF-8'); ?>"
                                                    data-device-status="<?php echo htmlspecialchars($pdStatus, ENT_QUOTES, 'UTF-8'); ?>"
                                                    aria-selected="false">
                                                <span class="pc-device-option__icon" aria-hidden="true"><i class="fas fa-tablet-screen-button"></i></span>
                                                <span class="pc-device-option__body">
                                                    <span class="pc-device-option__title"><?php echo htmlspecialchars($pdTitle); ?></span>
                                                    <?php if ($pdName !== ''): ?>
                                                    <span class="pc-device-option__id"><?php echo htmlspecialchars($pdId); ?></span>
                                                    <?php endif; ?>
                                                </span>
                                                <span class="pc-device-status <?php echo htmlspecialchars($pdStatus); ?>"><?php echo htmlspecialchars(t('status.' . $pdStatus)); ?></span>
                                            </button>
                                            <?php endforeach; ?>
                                        <?php endif; ?>
                                    </div>
                                    <div class="pc-device-select-footer">
                                    <button type="button"
                                            class="pc-device-option pc-device-option--custom"
                                            id="pc_device_custom_option"
                                            role="option"
                                            data-value="custom"
                                            aria-selected="false">
                                        <span class="pc-device-option__icon" aria-hidden="true"><i class="fas fa-keyboard"></i></span>
                                        <span class="pc-device-option__body">
                                            <span class="pc-device-option__title"><?php echo htmlspecialchars(t('playlist_codes.device_pick_custom')); ?></span>
                                            <span class="pc-device-option__desc"><?php echo htmlspecialchars(t('playlist_codes.device_pick_custom_desc')); ?></span>
                                        </span>
                                    </button>
                                    </div>
                                </div>
                            </div>
                            <div class="pc-device-custom-wrap" id="pc_device_custom_wrap" hidden>
                                <label class="form-label" for="pc_bound_device_custom" style="margin-top:10px;font-size:.78rem;"><?php echo htmlspecialchars(t('playlist_codes.device_id_label')); ?></label>
                                <input type="text"
                                       id="pc_bound_device_custom"
                                       class="form-control"
                                       placeholder="<?php echo htmlspecialchars(t('playlist_codes.device_id_placeholder')); ?>"
                                       autocomplete="off"
                                       spellcheck="false"
                                       style="font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700;">
                            </div>
                            <p class="pc-custom-hint" style="display:block;margin-top:8px;"><?php echo htmlspecialchars(t('playlist_codes.device_id_help')); ?></p>
                        </div>

                        <div class="pc-field-full">
                            <label class="form-label"><?php echo htmlspecialchars(t('playlist_codes.url_label')); ?></label>
                            <input type="url" name="m3u_url" class="form-control" <?php echo $canEdit ? 'required' : ''; ?>
                                   placeholder="https://...">
                        </div>

                        <div class="pc-field-full" style="margin-top:4px">
                            <button type="submit" class="pc-btn-save">
                                <i class="fas fa-save me-2"></i><?php echo htmlspecialchars(t('playlist_codes.save_btn')); ?>
                            </button>
                        </div>

                    </div>
                </form>
            </div>
        </div>

        <script>
        window.__pcExistingCodes = <?php echo json_encode(array_values($existingCodeList), JSON_UNESCAPED_UNICODE); ?>;
        window.__pcToastClose = <?php echo json_encode(t('playlist_codes.toast_close')); ?>;
        (function () {
            var host = document.getElementById('pc-toast-host');
            var existing = window.__pcExistingCodes || [];
            var modeRandom = document.getElementById('pc_mode_random');
            var modeCustom = document.getElementById('pc_mode_custom');
            var genBtn = document.getElementById('pc_gen');
            var codeEl = document.getElementById('pc_code');
            var hintEl = document.getElementById('pc_custom_hint');
            var grpEl = document.getElementById('pc_code_group');
            var formEl = document.getElementById('pcForm');
            var canEdit = formEl ? formEl.getAttribute('data-can-edit') === '1' : false;
            var guestMsg = formEl ? (formEl.getAttribute('data-guest-msg') || '') : '';
            var dupMsg = formEl ? (formEl.getAttribute('data-dup-msg') || '') : '';
            var dupGeneralMsg = formEl ? (formEl.getAttribute('data-dup-general-msg') || dupMsg) : dupMsg;
            var dupDeviceMsg = formEl ? (formEl.getAttribute('data-dup-device-msg') || dupMsg) : dupMsg;
            var formatMsg = formEl ? (formEl.getAttribute('data-format-msg') || '') : '';
            var demoMsg = formEl ? (formEl.getAttribute('data-demo-msg') || '') : '';
            var closeLabel = window.__pcToastClose || 'Close';
            var demoReservedCode = '00000';

            var deviceEl = document.getElementById('pc_bound_device');
            var deviceCustomEl = document.getElementById('pc_bound_device_custom');
            var devicePickerEl = document.getElementById('pc_device_picker');
            var deviceBtnEl = document.getElementById('pc_device_btn');
            var deviceMenuEl = document.getElementById('pc_device_menu');
            var deviceSearchEl = document.getElementById('pc_device_search');
            var deviceListEl = document.getElementById('pc_device_list');
            var deviceCustomWrapEl = document.getElementById('pc_device_custom_wrap');
            var deviceCustomOptionEl = document.getElementById('pc_device_custom_option');
            var deviceTriggerPlaceholderEl = document.getElementById('pc_device_trigger_placeholder');
            var deviceTriggerBodyEl = document.getElementById('pc_device_trigger_body');
            var deviceTriggerTitleEl = document.getElementById('pc_device_trigger_title');
            var deviceTriggerSubEl = document.getElementById('pc_device_trigger_sub');
            var deviceTriggerStatusEl = document.getElementById('pc_device_trigger_status');
            var deviceOptionEls = deviceListEl ? deviceListEl.querySelectorAll('.pc-device-option[data-device-id]') : [];
            var devicePickMode = '';
            var deviceStatusLabels = {
                active: <?php echo json_encode(t('status.active'), JSON_UNESCAPED_UNICODE); ?>,
                expired: <?php echo json_encode(t('status.expired'), JSON_UNESCAPED_UNICODE); ?>,
                blocked: <?php echo json_encode(t('status.blocked'), JSON_UNESCAPED_UNICODE); ?>
            };
            var devicePickCustomTitle = <?php echo json_encode(t('playlist_codes.device_pick_custom'), JSON_UNESCAPED_UNICODE); ?>;
            var bindModeEl = document.getElementById('pc_bind_mode');
            var bindDropdownEl = document.getElementById('pc_bind_dropdown');
            var bindTriggerEl = document.getElementById('pc_bind_mode_btn');
            var bindMenuEl = document.getElementById('pc_bind_select_menu');
            var bindSelectIconEl = document.getElementById('pc_bind_select_icon');
            var bindSelectLabelEl = document.getElementById('pc_bind_select_label');
            var bindOptionEls = bindMenuEl ? bindMenuEl.querySelectorAll('.pc-bind-select-option') : [];
            var bindHintEl = document.getElementById('pc_bind_hint');
            var bindHintGeneral = <?php echo json_encode(t('playlist_codes.bind_mode_general_desc'), JSON_UNESCAPED_UNICODE); ?>;
            var bindHintDevice = <?php echo json_encode(t('playlist_codes.bind_mode_device_desc'), JSON_UNESCAPED_UNICODE); ?>;
            var bindTitleGeneral = <?php echo json_encode(t('playlist_codes.bind_mode_general_title'), JSON_UNESCAPED_UNICODE); ?>;
            var bindTitleDevice = <?php echo json_encode(t('playlist_codes.bind_mode_device_title'), JSON_UNESCAPED_UNICODE); ?>;
            var deviceWrapEl = document.getElementById('pc_device_wrap');
            var maxDevicesWrapEl = document.getElementById('pc_max_devices_wrap');

            function pcNormDevice(v) {
                return String(v || '').replace(/\s+/g, '').trim();
            }

            function pcSyncBoundDevice() {
                if (!deviceEl) return '';
                if (devicePickMode === 'custom' && deviceCustomEl) {
                    deviceEl.value = pcNormDevice(deviceCustomEl.value);
                }
                return pcNormDevice(deviceEl.value);
            }

            function pcCloseDeviceMenu() {
                if (!deviceMenuEl || !deviceBtnEl) return;
                deviceMenuEl.hidden = true;
                deviceBtnEl.setAttribute('aria-expanded', 'false');
                if (devicePickerEl) {
                    devicePickerEl.classList.remove('pc-device-picker--open');
                }
            }

            function pcOpenDeviceMenu() {
                if (!deviceMenuEl || !deviceBtnEl) return;
                deviceMenuEl.hidden = false;
                deviceBtnEl.setAttribute('aria-expanded', 'true');
                if (devicePickerEl) devicePickerEl.classList.add('pc-device-picker--open');
                if (deviceSearchEl) {
                    deviceSearchEl.value = '';
                    pcFilterDeviceList('');
                    setTimeout(function () { deviceSearchEl.focus(); }, 30);
                }
            }

            function pcToggleDeviceMenu() {
                if (!deviceMenuEl) return;
                if (deviceMenuEl.hidden) pcOpenDeviceMenu();
                else pcCloseDeviceMenu();
            }

            function pcFilterDeviceList(query) {
                var q = String(query || '').toLowerCase().trim();
                for (var i = 0; i < deviceOptionEls.length; i++) {
                    var opt = deviceOptionEls[i];
                    var id = (opt.getAttribute('data-device-id') || '').toLowerCase();
                    var title = (opt.getAttribute('data-device-title') || '').toLowerCase();
                    var name = (opt.getAttribute('data-device-name') || '').toLowerCase();
                    var show = !q || id.indexOf(q) !== -1 || title.indexOf(q) !== -1 || name.indexOf(q) !== -1;
                    opt.hidden = !show;
                }
            }

            function pcRenderDeviceTrigger() {
                if (!deviceTriggerPlaceholderEl || !deviceTriggerBodyEl) return;
                var id = pcSyncBoundDevice();
                if (devicePickMode === 'list' && id) {
                    deviceTriggerPlaceholderEl.hidden = true;
                    deviceTriggerBodyEl.hidden = false;
                    if (deviceTriggerTitleEl) {
                        var activeOpt = null;
                        for (var i = 0; i < deviceOptionEls.length; i++) {
                            if (deviceOptionEls[i].getAttribute('data-device-id') === id) {
                                activeOpt = deviceOptionEls[i];
                                break;
                            }
                        }
                        deviceTriggerTitleEl.textContent = activeOpt
                            ? (activeOpt.getAttribute('data-device-title') || id)
                            : id;
                    }
                    if (deviceTriggerSubEl) {
                        deviceTriggerSubEl.textContent = id;
                        deviceTriggerSubEl.hidden = false;
                    }
                    if (deviceTriggerStatusEl) {
                        var st = 'active';
                        for (var j = 0; j < deviceOptionEls.length; j++) {
                            if (deviceOptionEls[j].getAttribute('data-device-id') === id) {
                                st = deviceOptionEls[j].getAttribute('data-device-status') || 'active';
                                break;
                            }
                        }
                        deviceTriggerStatusEl.textContent = deviceStatusLabels[st] || st;
                        deviceTriggerStatusEl.className = 'pc-device-status ' + st;
                        deviceTriggerStatusEl.hidden = false;
                    }
                } else if (devicePickMode === 'custom') {
                    deviceTriggerPlaceholderEl.hidden = true;
                    deviceTriggerBodyEl.hidden = false;
                    if (deviceTriggerTitleEl) deviceTriggerTitleEl.textContent = devicePickCustomTitle;
                    if (deviceTriggerSubEl) {
                        deviceTriggerSubEl.textContent = id || '';
                        deviceTriggerSubEl.hidden = !id;
                    }
                    if (deviceTriggerStatusEl) deviceTriggerStatusEl.hidden = true;
                } else {
                    deviceTriggerPlaceholderEl.hidden = false;
                    deviceTriggerBodyEl.hidden = true;
                    if (deviceTriggerStatusEl) deviceTriggerStatusEl.hidden = true;
                }
            }

            function pcMarkDeviceOptions() {
                var current = pcSyncBoundDevice();
                for (var i = 0; i < deviceOptionEls.length; i++) {
                    var opt = deviceOptionEls[i];
                    var active = devicePickMode === 'list' && opt.getAttribute('data-device-id') === current;
                    opt.classList.toggle('pc-device-option--active', active);
                    opt.setAttribute('aria-selected', active ? 'true' : 'false');
                }
                if (deviceCustomOptionEl) {
                    var customActive = devicePickMode === 'custom';
                    deviceCustomOptionEl.classList.toggle('pc-device-option--active', customActive);
                    deviceCustomOptionEl.setAttribute('aria-selected', customActive ? 'true' : 'false');
                }
            }

            function pcSelectDeviceFromList(deviceId) {
                devicePickMode = 'list';
                if (deviceEl) deviceEl.value = pcNormDevice(deviceId);
                if (deviceCustomWrapEl) deviceCustomWrapEl.hidden = true;
                if (deviceCustomEl) {
                    deviceCustomEl.removeAttribute('required');
                    deviceCustomEl.value = '';
                }
                pcMarkDeviceOptions();
                pcRenderDeviceTrigger();
                pcCloseDeviceMenu();
            }

            function pcSelectDeviceCustom() {
                devicePickMode = 'custom';
                if (deviceEl) deviceEl.value = pcNormDevice(deviceCustomEl ? deviceCustomEl.value : '');
                if (deviceCustomWrapEl) deviceCustomWrapEl.hidden = false;
                if (deviceCustomEl) {
                    deviceCustomEl.setAttribute('required', 'required');
                    setTimeout(function () { deviceCustomEl.focus(); }, 30);
                }
                pcMarkDeviceOptions();
                pcRenderDeviceTrigger();
                pcCloseDeviceMenu();
            }

            function pcResetDevicePicker() {
                devicePickMode = '';
                if (deviceEl) deviceEl.value = '';
                if (deviceCustomEl) {
                    deviceCustomEl.value = '';
                    deviceCustomEl.removeAttribute('required');
                }
                if (deviceCustomWrapEl) deviceCustomWrapEl.hidden = true;
                if (deviceSearchEl) deviceSearchEl.value = '';
                pcFilterDeviceList('');
                pcMarkDeviceOptions();
                pcRenderDeviceTrigger();
                pcCloseDeviceMenu();
            }

            function pcBindMode() {
                return (bindModeEl && bindModeEl.value === 'device') ? 'device' : 'general';
            }

            function pcCloseBindMenu() {
                if (!bindMenuEl || !bindTriggerEl) return;
                bindMenuEl.hidden = true;
                bindTriggerEl.setAttribute('aria-expanded', 'false');
                if (bindDropdownEl) bindDropdownEl.classList.remove('pc-bind-dropdown--open');
            }

            function pcOpenBindMenu() {
                if (!bindMenuEl || !bindTriggerEl) return;
                bindMenuEl.hidden = false;
                bindTriggerEl.setAttribute('aria-expanded', 'true');
                if (bindDropdownEl) bindDropdownEl.classList.add('pc-bind-dropdown--open');
            }

            function pcToggleBindMenu() {
                if (!bindMenuEl) return;
                if (bindMenuEl.hidden) pcOpenBindMenu();
                else pcCloseBindMenu();
            }

            function pcSetBindMode(value, closeMenu) {
                var mode = value === 'device' ? 'device' : 'general';
                if (bindModeEl) bindModeEl.value = mode;
                for (var i = 0; i < bindOptionEls.length; i++) {
                    var opt = bindOptionEls[i];
                    var active = opt.getAttribute('data-value') === mode;
                    opt.classList.toggle('pc-bind-select-option--active', active);
                    opt.setAttribute('aria-selected', active ? 'true' : 'false');
                }
                applyBindMode();
                if (closeMenu !== false) pcCloseBindMenu();
            }

            function pcEffectiveDevice() {
                return pcSyncBoundDevice();
            }

            function pcPairExists(code, device) {
                var c = String(code || '');
                if (!c) return false;
                if (pcBindMode() === 'general') {
                    for (var i = 0; i < existing.length; i++) {
                        var rowG = existing[i];
                        if (typeof rowG === 'string') {
                            if (rowG === c) return true;
                            continue;
                        }
                        if (rowG && rowG.code === c) return true;
                    }
                    return false;
                }
                var d = pcNormDevice(device);
                for (var i = 0; i < existing.length; i++) {
                    var row = existing[i];
                    if (typeof row === 'string') {
                        continue;
                    }
                    if (row && row.code === c && pcNormDevice(row.device) === d) return true;
                }
                return false;
            }

            function applyBindMode() {
                var isDevice = pcBindMode() === 'device';
                if (bindDropdownEl) {
                    bindDropdownEl.classList.toggle('pc-bind-dropdown--device', isDevice);
                }
                if (bindSelectIconEl) {
                    bindSelectIconEl.innerHTML = isDevice
                        ? '<i class="fas fa-mobile-screen-button"></i>'
                        : '<i class="fas fa-globe"></i>';
                }
                if (bindSelectLabelEl) {
                    bindSelectLabelEl.textContent = isDevice ? bindTitleDevice : bindTitleGeneral;
                }
                if (bindHintEl) {
                    bindHintEl.textContent = isDevice ? bindHintDevice : bindHintGeneral;
                }
                if (deviceWrapEl) deviceWrapEl.hidden = !isDevice;
                if (maxDevicesWrapEl) maxDevicesWrapEl.hidden = isDevice;
                if (!isDevice) {
                    pcResetDevicePicker();
                } else if (devicePickMode === 'custom' && deviceCustomEl) {
                    deviceCustomEl.setAttribute('required', 'required');
                }
                if (!isDevice && modeRandom && modeRandom.checked && codeEl) {
                    genCode();
                }
            }

            function pcShowToast(message, variant) {
                if (!host || !message) return;
                var v = variant || 'warning';
                var wrap = document.createElement('div');
                wrap.className = 'pc-toast pc-toast--' + v;
                wrap.setAttribute('role', v === 'error' ? 'alert' : 'status');

                var icon = document.createElement('div');
                icon.className = 'pc-toast__icon';
                var iconClass = v === 'error' ? 'fa-circle-exclamation' : 'fa-triangle-exclamation';
                icon.innerHTML = '<i class="fas ' + iconClass + '"></i>';

                var body = document.createElement('div');
                body.className = 'pc-toast__body';
                var p = document.createElement('p');
                p.className = 'pc-toast__text';
                p.textContent = message;
                body.appendChild(p);

                var btn = document.createElement('button');
                btn.type = 'button';
                btn.className = 'pc-toast__close';
                btn.setAttribute('aria-label', closeLabel);
                btn.innerHTML = '<i class="fas fa-times" aria-hidden="true"></i>';

                wrap.appendChild(icon);
                wrap.appendChild(body);
                wrap.appendChild(btn);

                host.appendChild(wrap);

                var t = null;
                var remove = function () {
                    if (t) clearTimeout(t);
                    wrap.classList.add('pc-toast--out');
                    setTimeout(function () {
                        if (wrap.parentNode) wrap.parentNode.removeChild(wrap);
                    }, 280);
                };
                btn.addEventListener('click', remove);
                t = setTimeout(remove, 6400);
            }

            function genCode() {
                if (!codeEl) return;
                var device = pcEffectiveDevice();
                if (pcBindMode() === 'device' && !device) {
                    if (formEl && formEl.getAttribute('data-device-msg')) {
                        pcShowToast(formEl.getAttribute('data-device-msg'), 'error');
                    }
                    if (devicePickMode === 'custom' && deviceCustomEl) deviceCustomEl.focus();
                    else if (deviceBtnEl) deviceBtnEl.focus();
                    return;
                }
                var s = '';
                var tries = 0;
                do {
                    var len = 5 + Math.floor(Math.random() * 2);
                    s = '';
                    for (var i = 0; i < len; i++) s += Math.floor(Math.random() * 10);
                    tries++;
                } while ((pcPairExists(s, device) || s === demoReservedCode) && tries < 100);
                if (pcPairExists(s, device) || s === demoReservedCode) {
                    var dm = pcBindMode() === 'device' ? dupDeviceMsg : dupGeneralMsg;
                    if (dm) pcShowToast(dm, 'error');
                    return;
                }
                codeEl.removeAttribute('readonly');
                codeEl.value = s;
                codeEl.readOnly = true;
            }

            function applyMode() {
                var custom = modeCustom && modeCustom.checked;
                if (genBtn) genBtn.style.display = custom ? 'none' : '';
                if (hintEl) hintEl.style.display = custom ? 'block' : 'none';
                if (grpEl) grpEl.classList.toggle('pc-code-group--custom', custom);
                if (!codeEl) return;
                if (custom) {
                    codeEl.removeAttribute('readonly');
                    codeEl.placeholder = '12345';
                    codeEl.value = '';
                    codeEl.focus();
                } else {
                    codeEl.placeholder = '••••••';
                    genCode();
                }
            }

            if (codeEl) {
                codeEl.addEventListener('input', function () {
                    if (modeCustom && modeCustom.checked) {
                        codeEl.value = codeEl.value.replace(/\D/g, '').slice(0, 6);
                    }
                });
            }
            modeRandom && modeRandom.addEventListener('change', applyMode);
            modeCustom && modeCustom.addEventListener('change', applyMode);
            bindTriggerEl && bindTriggerEl.addEventListener('click', function () {
                pcToggleBindMenu();
            });
            for (var bo = 0; bo < bindOptionEls.length; bo++) {
                bindOptionEls[bo].addEventListener('click', function () {
                    pcSetBindMode(this.getAttribute('data-value') || 'general', true);
                });
            }
            document.addEventListener('click', function (e) {
                if (!bindDropdownEl || bindMenuEl.hidden) return;
                if (!bindDropdownEl.contains(e.target)) pcCloseBindMenu();
            });
            document.addEventListener('keydown', function (e) {
                if (e.key === 'Escape') {
                    pcCloseBindMenu();
                    pcCloseDeviceMenu();
                }
            });
            deviceBtnEl && deviceBtnEl.addEventListener('click', function () {
                pcToggleDeviceMenu();
            });
            deviceSearchEl && deviceSearchEl.addEventListener('input', function () {
                pcFilterDeviceList(deviceSearchEl.value);
            });
            deviceSearchEl && deviceSearchEl.addEventListener('click', function (e) {
                e.stopPropagation();
            });
            for (var di = 0; di < deviceOptionEls.length; di++) {
                deviceOptionEls[di].addEventListener('click', function () {
                    pcSelectDeviceFromList(this.getAttribute('data-device-id') || '');
                });
            }
            deviceCustomOptionEl && deviceCustomOptionEl.addEventListener('click', function () {
                pcSelectDeviceCustom();
            });
            deviceCustomEl && deviceCustomEl.addEventListener('input', function () {
                if (devicePickMode === 'custom' && deviceEl) {
                    deviceEl.value = pcNormDevice(deviceCustomEl.value);
                    pcRenderDeviceTrigger();
                }
            });
            document.addEventListener('click', function (e) {
                if (devicePickerEl && deviceMenuEl && !deviceMenuEl.hidden && !devicePickerEl.contains(e.target)) {
                    pcCloseDeviceMenu();
                }
            });
            genBtn && genBtn.addEventListener('click', genCode);
            formEl && formEl.addEventListener('submit', function (e) {
                if (!canEdit) {
                    e.preventDefault();
                    if (guestMsg) pcShowToast(guestMsg, 'warning');
                    return false;
                }
                var v = (codeEl && codeEl.value) ? codeEl.value.replace(/\D/g, '') : '';
                if (v.length < 5 || v.length > 6) {
                    e.preventDefault();
                    if (formatMsg) pcShowToast(formatMsg, 'warning');
                    return false;
                }
                if (v === demoReservedCode) {
                    e.preventDefault();
                    if (demoMsg) pcShowToast(demoMsg, 'error');
                    return false;
                }
                var device = pcEffectiveDevice();
                if (pcBindMode() === 'device' && !device) {
                    e.preventDefault();
                    if (formEl && formEl.getAttribute('data-device-msg')) {
                        pcShowToast(formEl.getAttribute('data-device-msg'), 'error');
                    }
                    if (devicePickMode === 'custom' && deviceCustomEl) deviceCustomEl.focus();
                    else if (deviceBtnEl) deviceBtnEl.focus();
                    return false;
                }
                if (pcPairExists(v, device)) {
                    e.preventDefault();
                    var dm = pcBindMode() === 'device' ? dupDeviceMsg : dupGeneralMsg;
                    if (dm) pcShowToast(dm, 'error');
                    return false;
                }
                if (codeEl) {
                    codeEl.readOnly = false;
                    codeEl.value = v;
                }
            });
            applyBindMode();
            applyMode();
            pcRenderDeviceTrigger();
        })();
        </script>

        <?php if ($canEdit): ?>
        <div class="pc-card" id="pc-host-replace">
            <div class="pc-card-head">
                <i class="fas fa-right-left"></i>
                <span><?php echo htmlspecialchars(t('playlist_codes.host_replace_title')); ?></span>
            </div>
            <div class="pc-card-body">
                <p class="pc-host-replace-intro"><?php echo htmlspecialchars(t('playlist_codes.host_replace_intro')); ?></p>
                <form method="post"
                      class="pc-form"
                      data-admin-confirm
                      data-confirm-title="<?php echo htmlspecialchars(t('playlist_codes.host_replace_confirm_title'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-confirm-message="<?php echo htmlspecialchars(t('playlist_codes.host_replace_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-confirm-warning="<?php echo htmlspecialchars(t('playlist_codes.host_replace_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-confirm-ok="<?php echo htmlspecialchars(t('playlist_codes.host_replace_btn'), ENT_QUOTES, 'UTF-8'); ?>"
                      data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>">
                    <input type="hidden" name="replace_playlist_host" value="1">
                    <div class="pc-form-grid">
                        <div>
                            <label class="form-label" for="host_replace_old"><?php echo htmlspecialchars(t('playlist_codes.host_replace_old_label')); ?></label>
                            <input type="text"
                                   class="form-control field-mono"
                                   id="host_replace_old"
                                   name="host_replace_old"
                                   required
                                   autocomplete="off"
                                   placeholder="<?php echo htmlspecialchars(t('playlist_codes.host_replace_old_placeholder')); ?>">
                            <p class="pc-host-replace-hint"><?php echo htmlspecialchars(t('playlist_codes.host_replace_old_help')); ?></p>
                        </div>
                        <div>
                            <label class="form-label" for="host_replace_new"><?php echo htmlspecialchars(t('playlist_codes.host_replace_new_label')); ?></label>
                            <input type="text"
                                   class="form-control field-mono"
                                   id="host_replace_new"
                                   name="host_replace_new"
                                   required
                                   autocomplete="off"
                                   placeholder="<?php echo htmlspecialchars(t('playlist_codes.host_replace_new_placeholder')); ?>">
                            <p class="pc-host-replace-hint"><?php echo htmlspecialchars(t('playlist_codes.host_replace_new_help')); ?></p>
                        </div>
                    </div>
                    <div class="mt-3">
                        <button type="submit" class="pc-btn-save">
                            <i class="fas fa-floppy-disk me-1"></i>
                            <?php echo htmlspecialchars(t('playlist_codes.host_replace_btn')); ?>
                        </button>
                    </div>
                </form>
            </div>
        </div>
        <?php endif; ?>

        <!-- Table: مخفية بالكامل عن الضيف -->
        <?php if ($canEdit): ?>
        <div class="pc-card">
            <div class="pc-card-head">
                <i class="fas fa-list-ul"></i>
                <span><?php echo htmlspecialchars(t('playlist_codes.table_title')); ?></span>
            </div>
            <div class="pc-saved-list">
                    <?php if (count($rows) === 0): ?>
                        <div class="pc-saved-empty">
                            <i class="fas fa-inbox me-2" style="font-size:1.25rem;display:block;margin-bottom:8px;color:#334155"></i>
                            <?php echo htmlspecialchars(t('playlist_codes.empty')); ?>
                        </div>
                    <?php else: foreach ($rows as $r):
                        $dc = (int)($r['device_count'] ?? 0);
                        $md = isset($r['max_devices']) ? (int)$r['max_devices'] : 1;
                        if ($md < 1) {
                            $md = 1;
                        }
                        $boundDev = trim((string)($r['bound_device_id'] ?? ''));
                        $m3uUrl = (string)($r['m3u_url']);
                    ?>
                        <article class="pc-saved-item">
                            <div class="pc-saved-row-head">
                                <div class="pc-saved-info">
                                    <div class="pc-saved-info-top">
                                        <span class="pc-saved-name"><?php echo htmlspecialchars((string)$r['label']); ?></span>
                                        <span class="pc-badge-code"><?php echo htmlspecialchars((string)$r['code']); ?></span>
                                    </div>
                                    <div class="pc-saved-info-meta">
                                        <?php if ($boundDev !== ''): ?>
                                        <span class="pc-saved-meta-chip pc-saved-meta-chip--mono" title="<?php echo htmlspecialchars($boundDev); ?>">
                                            <i class="fas fa-mobile-screen"></i>
                                            <?php echo htmlspecialchars($boundDev); ?>
                                        </span>
                                        <?php else: ?>
                                        <span class="pc-badge-general"><?php echo htmlspecialchars(t('playlist_codes.bind_general_badge')); ?></span>
                                        <?php endif; ?>
                                        <span class="pc-saved-meta-chip">
                                            <i class="fas fa-tv"></i>
                                            <strong><?php echo $dc; ?></strong> / <?php echo $md; ?>
                                        </span>
                                        <a class="pc-btn-manage" href="playlist_code_devices.php?id=<?php echo (int)$r['id']; ?>">
                                            <i class="fas fa-list"></i>
                                            <?php echo htmlspecialchars(t('playlist_codes.manage_devices')); ?>
                                        </a>
                                        <span class="pc-saved-meta-chip">
                                            <i class="fas fa-calendar"></i>
                                            <?php echo htmlspecialchars((string)$r['created_at']); ?>
                                        </span>
                                    </div>
                                </div>
                                <div class="pc-saved-actions pc-actions">
                                <button type="button"
                                        class="pc-btn pc-btn-edit"
                                        data-bs-toggle="modal"
                                        data-bs-target="#editMaxModal"
                                        data-id="<?php echo (int)$r['id']; ?>"
                                        data-max="<?php echo (int)$md; ?>"
                                        data-code="<?php echo htmlspecialchars((string)$r['code'], ENT_QUOTES, 'UTF-8'); ?>"
                                        data-label="<?php echo htmlspecialchars((string)$r['label'], ENT_QUOTES, 'UTF-8'); ?>">
                                    <i class="fas fa-sliders-h"></i>
                                    <?php echo htmlspecialchars(t('playlist_codes.edit_max')); ?>
                                </button>
                                <button type="button"
                                        class="pc-btn pc-btn-edit"
                                        data-bs-toggle="modal"
                                        data-bs-target="#editUrlModal"
                                        data-id="<?php echo (int)$r['id']; ?>"
                                        data-url="<?php echo htmlspecialchars($m3uUrl, ENT_QUOTES, 'UTF-8'); ?>"
                                        data-code="<?php echo htmlspecialchars((string)$r['code'], ENT_QUOTES, 'UTF-8'); ?>"
                                        data-label="<?php echo htmlspecialchars((string)$r['label'], ENT_QUOTES, 'UTF-8'); ?>">
                                    <i class="fas fa-link"></i>
                                    <?php echo htmlspecialchars(t('playlist_codes.edit_url')); ?>
                                </button>
                                <form method="post"
                                      data-admin-confirm
                                      data-confirm-title="<?php echo htmlspecialchars(t('playlist_codes.delete_title'), ENT_QUOTES, 'UTF-8'); ?>"
                                      data-confirm-message="<?php echo htmlspecialchars(t('playlist_codes.delete_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                                      data-confirm-warning="<?php echo htmlspecialchars(t('playlist_codes.delete_warning'), ENT_QUOTES, 'UTF-8'); ?>"
                                      data-confirm-ok="<?php echo htmlspecialchars(t('playlist_codes.delete'), ENT_QUOTES, 'UTF-8'); ?>"
                                      data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
                                      data-confirm-details="<?php echo htmlspecialchars(json_encode([
                                          ['label' => t('playlist_codes.col_name'), 'value' => (string)($r['label'] ?? '')],
                                          ['label' => t('playlist_codes.col_code'), 'value' => (string)($r['code'] ?? ''), 'mono' => true],
                                      ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
                                    <input type="hidden" name="delete_id" value="<?php echo (int)$r['id']; ?>">
                                    <button type="submit" class="pc-btn pc-btn-delete">
                                        <i class="fas fa-trash"></i>
                                        <?php echo htmlspecialchars(t('playlist_codes.delete')); ?>
                                    </button>
                                </form>
                                </div>
                            </div>
                            <div class="pc-saved-url" title="<?php echo htmlspecialchars($m3uUrl); ?>">
                                <i class="fas fa-link"></i>
                                <span><?php echo htmlspecialchars($m3uUrl); ?></span>
                            </div>
                        </article>
                    <?php endforeach; endif; ?>
            </div>
            <?php
            if ($canEdit && (int)($codesPager['total'] ?? 0) > 0) {
                $pq = $_GET;
                unset($pq['msg']);
                echo admin_render_pagination((int)$codesPager['page'], (int)$codesPager['pages'], ['query' => $pq]);
            }
            ?>
        </div>
        <?php else: ?>
        <div class="pc-card">
            <div class="pc-card-head">
                <i class="fas fa-lock"></i>
                <span><?php echo htmlspecialchars(t('playlist_codes.table_title')); ?></span>
            </div>
            <div class="pc-card-body">
                <div class="pc-empty" style="padding:28px 16px">
                    <i class="fas fa-shield-halved me-2" style="font-size:1.35rem;display:block;margin-bottom:10px;color:#64748b"></i>
                    <?php echo htmlspecialchars(t('playlist_codes.guest_codes_hidden')); ?>
                </div>
            </div>
        </div>
        <?php endif; ?>

    </div>
</div>

<?php if ($canEdit): ?>
<div class="modal fade pc-modal" id="editMaxModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <form method="post">
        <div class="modal-header">
          <h5 class="modal-title">
            <i class="fas fa-sliders-h me-2"></i><?php echo htmlspecialchars(t('playlist_codes.edit_max')); ?>
          </h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div class="small text-secondary mb-2" id="pcEditMaxLabel"></div>
          <div class="mb-3">
            <span class="pc-modal-code" id="pcEditMaxCode"></span>
          </div>
          <label class="form-label"><?php echo htmlspecialchars(t('playlist_codes.max_devices_label')); ?></label>
          <input type="hidden" name="update_max_id" id="pcEditMaxId" value="">
          <div class="pc-number-group">
            <button type="button" onclick="pcStepDown('pcEditMaxInput')">−</button>
            <input type="number" name="max_devices" id="pcEditMaxInput" min="1" max="999" required>
            <button type="button" onclick="pcStepUp('pcEditMaxInput')">+</button>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal"><?php echo htmlspecialchars(t('back')); ?></button>
          <button type="submit" class="pc-btn-save-max">
            <i class="fas fa-save me-1"></i><?php echo htmlspecialchars(t('button.save_changes')); ?>
          </button>
        </div>
      </form>
    </div>
  </div>
</div>
<?php endif; ?>

<?php if ($canEdit): ?>
<div class="modal fade pc-modal" id="editUrlModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <form method="post">
        <div class="modal-header">
          <h5 class="modal-title">
            <i class="fas fa-link me-2"></i><?php echo htmlspecialchars(t('playlist_codes.edit_url_title')); ?>
          </h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div class="small text-secondary mb-2" id="pcEditUrlLabel"></div>
          <div class="mb-3">
            <span class="pc-modal-code" id="pcEditUrlCode"></span>
          </div>
          <label class="form-label" for="pcEditUrlInput"><?php echo htmlspecialchars(t('playlist_codes.url_label')); ?></label>
          <input type="hidden" name="update_url_id" id="pcEditUrlId" value="">
          <input type="url" name="m3u_url" id="pcEditUrlInput" class="form-control" required
                 placeholder="https://...">
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal"><?php echo htmlspecialchars(t('back')); ?></button>
          <button type="submit" class="pc-btn-save-max">
            <i class="fas fa-save me-1"></i><?php echo htmlspecialchars(t('button.save_changes')); ?>
          </button>
        </div>
      </form>
    </div>
  </div>
</div>
<?php endif; ?>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
<script>
function pcStepUp(id, minVal, maxVal){
    var el=document.getElementById(id);
    if(!el) return;
    var minN = (minVal !== undefined && minVal !== null) ? parseInt(minVal, 10) : 1;
    var maxN = (maxVal !== undefined && maxVal !== null) ? parseInt(maxVal, 10) : 999;
    if(!Number.isFinite(minN)) minN = 1;
    if(!Number.isFinite(maxN)) maxN = 999;
    var n=parseInt(el.value || String(minN), 10);
    if(!Number.isFinite(n)) n=minN;
    n=Math.min(maxN, n+1);
    el.value=String(n);
}
function pcStepDown(id, minVal, maxVal){
    var el=document.getElementById(id);
    if(!el) return;
    var minN = (minVal !== undefined && minVal !== null) ? parseInt(minVal, 10) : 1;
    var maxN = (maxVal !== undefined && maxVal !== null) ? parseInt(maxVal, 10) : 999;
    if(!Number.isFinite(minN)) minN = 1;
    if(!Number.isFinite(maxN)) maxN = 999;
    var n=parseInt(el.value || String(minN), 10);
    if(!Number.isFinite(n)) n=minN;
    n=Math.max(minN, n-1);
    el.value=String(n);
}
<?php if ($canEdit): ?>
(function(){
    var modal = document.getElementById('editMaxModal');
    if(modal) {
    modal.addEventListener('show.bs.modal', function (event) {
        var btn = event.relatedTarget;
        if(!btn) return;
        var id = btn.getAttribute('data-id') || '';
        var max = btn.getAttribute('data-max') || '1';
        var code = btn.getAttribute('data-code') || '';
        var label = btn.getAttribute('data-label') || '';
        document.getElementById('pcEditMaxId').value = id;
        document.getElementById('pcEditMaxInput').value = max;
        document.getElementById('pcEditMaxCode').textContent = code;
        document.getElementById('pcEditMaxLabel').textContent = label;
    });
    }
    var urlModal = document.getElementById('editUrlModal');
    if(urlModal) {
    urlModal.addEventListener('show.bs.modal', function (event) {
        var btn = event.relatedTarget;
        if(!btn) return;
        var id = btn.getAttribute('data-id') || '';
        var url = btn.getAttribute('data-url') || '';
        var code = btn.getAttribute('data-code') || '';
        var label = btn.getAttribute('data-label') || '';
        document.getElementById('pcEditUrlId').value = id;
        document.getElementById('pcEditUrlInput').value = url;
        document.getElementById('pcEditUrlCode').textContent = code;
        document.getElementById('pcEditUrlLabel').textContent = label;
    });
    }
})();
<?php endif; ?>
</script>
</body>
</html>