<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/playlist_code_helpers.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';
require_once 'includes/credential_crypto.php';
require_once __DIR__ . '/includes/pagination.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$id = admin_parse_positive_int_id($_GET['id'] ?? $_POST['id'] ?? '');
$current_page = 'edit_device';
$success = $error = '';
$loginToast = null;
$listPage = admin_request_list_page();
$homeUrl = admin_devices_home_url($listPage > 1 ? $listPage : null);

if ($id <= 0 || !adminCan('devices_view')) {
    header('Location: ' . ($id <= 0 ? $homeUrl : 'access_denied.php?perm=devices_view'));
    exit();
}

syncExpiredStatus($conn);

try {
    $device = admin_find_managed_device($conn, $id);
    if (!$device) {
        header('Location: ' . $homeUrl);
        exit();
    }
} catch (PDOException $e) {
    header('Location: ' . $homeUrl);
    exit();
}

$canEditDevice = adminCan('devices_edit');
$canDeleteDevice = adminCan('devices_delete');
$isGuest = adminIsGuestRole();

$devicePlaylistCodes = [];
if ($device && !empty($device['device_id']) && !$isGuest) {
    $devicePlaylistCodes = admin_list_device_bound_playlist_codes($conn, (string) $device['device_id']);
}

$displayDeviceId = $isGuest
    ? adminMaskDeviceId((string)($device['device_id'] ?? ''))
    : (string)($device['device_id'] ?? '');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
admin_require_csrf();
if (!adminCan('devices_edit')) {
    header('Location: access_denied.php?perm=devices_edit');
    exit;
}

$device = admin_find_managed_device($conn, $id);
if (!$device) {
    header('Location: ' . $homeUrl);
    exit();
}

// حذف سجل الدخول (جلسة واحدة أو الكل) — بدون تعديل باقي بيانات الجهاز.
$deleteSessionId = (int)($_POST['delete_login_session_id'] ?? 0);
$clearLoginHistory = isset($_POST['clear_login_history']) && (string)$_POST['clear_login_history'] === '1';
$loginHistoryAjax = isset($_POST['login_history_ajax']) && (string)$_POST['login_history_ajax'] === '1';
if ($deleteSessionId > 0 || $clearLoginHistory) {
    $deviceKey = trim((string)($device['device_id'] ?? ''));
    $toastOk = false;
    $toastMsg = t('msg.device_update_error');
    if ($deviceKey !== '' && !adminIsGuestRole()) {
        if ($clearLoginHistory) {
            $n = delete_all_device_login_sessions($conn, $deviceKey);
            $toastOk = $n > 0;
            $toastMsg = $toastOk
                ? t('edit_device.login_history_cleared')
                : t('edit_device.login_history_empty');
            if ($toastOk) {
                try {
                    logActivity($conn, 'clear_login_history', $deviceKey, 'Cleared login history (' . $n . ')');
                } catch (Throwable $e) {}
            }
        } else {
            $toastOk = delete_device_login_session($conn, $deleteSessionId, $deviceKey);
            $toastMsg = $toastOk
                ? t('edit_device.login_session_deleted')
                : t('edit_device.login_session_delete_failed');
            if ($toastOk) {
                try {
                    logActivity($conn, 'delete_login_session', $deviceKey, 'Deleted login session #' . $deleteSessionId);
                } catch (Throwable $e) {}
            }
        }
        $device = admin_find_managed_device($conn, $id) ?: $device;
    }
    if ($loginHistoryAjax) {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode([
            'success' => $toastOk,
            'message' => $toastMsg,
            'cleared' => $clearLoginHistory,
            'session_id' => $clearLoginHistory ? 0 : $deleteSessionId,
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    $loginToast = [
        'message' => $toastMsg,
        'ok' => $toastOk,
    ];
} else {

$expiry_date = trim((string)($device['expiry_date'] ?? ''));
if ($expiry_date === '') {
    $expiry_date = date('Y-m-d H:i:s');
}
$status = $_POST['status'] ?? 'active';
$notes = $_POST['notes'] ?? '';
$custom_domain = $_POST['custom_domain'] ?? '';
$device_name = $_POST['device_name'] ?? '';
$block_vpn = isset($_POST['block_vpn']) ? 1 : 0;
$device_ads_enabled = isset($_POST['device_ads_enabled']) ? 1 : 0;
$durationChoice = strtolower(trim((string)($_POST['duration'] ?? 'keep')));

if ($durationChoice !== 'keep' && $durationChoice !== '' && $status !== 'blocked') {
    $durationInfo = adminExpiryFromDurationChoice($conn, $durationChoice);
    if ($durationInfo !== null) {
        $expiry_date = $durationInfo['expiry'];
        $status = 'active';
    }
}

if ($status !== 'blocked') {
        $expiryTs = strtotime($expiry_date);
        $status = ($expiryTs !== false && $expiryTs > time()) ? 'active' : 'expired';
}

if (updateDevice($conn,$id,$expiry_date,$status,$notes,$custom_domain,$device_name,$block_vpn,$device_ads_enabled)) {
$success = t('msg.device_updated');

$device = admin_find_managed_device($conn, $id);
if (!$device) {
    header('Location: ' . $homeUrl);
    exit();
}

$syncDomain = trim((string)$custom_domain);
if ($syncDomain !== '' && !empty($device['device_id'])) {
    sync_device_login_fields_from_url($conn, (string)$device['device_id'], $syncDomain, true, 'admin');
    $device = admin_find_managed_device($conn, $id) ?: $device;
}

} else {

$error = t('msg.device_update_error');

}

} // end else (normal device update)

}

$codeHostStored = trim((string)($device['code_server_host'] ?? ''));
$manUserStored = trim((string)($device['manual_login_username'] ?? ''));
$manPassStoredRaw = trim((string)($device['manual_login_password'] ?? ''));
$manPassStored = '';
if ($manPassStoredRaw !== '') {
    $manPassStored = credential_decrypt_password_from_storage($conn, $manPassStoredRaw);
    if ($manPassStored !== '' && !credential_is_encrypted($manPassStoredRaw)) {
        $enc = credential_encrypt_password_for_storage($conn, $manPassStored);
        if ($enc !== '') {
            try {
                $mig = $conn->prepare('UPDATE activated_devices SET manual_login_password = ? WHERE id = ?');
                $mig->execute([$enc, (int)$device['id']]);
                $device['manual_login_password'] = $enc;
            } catch (PDOException $e) {
                // ignore migration failure; display still works
            }
        }
    }
}
// إذا كان الدخول Xtream (سيرفر+يوزر+باس) بدون رابط playlist → ابنِ get.php في custom_domain
$customDomainStored = trim((string)($device['custom_domain'] ?? ''));
if ($customDomainStored === '' && $codeHostStored !== '' && $manUserStored !== '' && $manPassStored !== '') {
    $builtPlaylist = build_xtream_m3u_playlist_url($codeHostStored, $manUserStored, $manPassStored);
    if ($builtPlaylist !== '') {
        try {
            $updUrl = $conn->prepare('UPDATE activated_devices SET custom_domain = ? WHERE id = ?');
            $updUrl->execute([$builtPlaylist, (int)$device['id']]);
            $device['custom_domain'] = $builtPlaylist;
            $customDomainStored = $builtPlaylist;
        } catch (PDOException $e) {
            // ignore; UI can still show host/user/pass
        }
    }
}
$accountDisplayName = trim((string)($device['account_display_name'] ?? ''));
$lastSeenAt = trim((string)($device['last_seen_at'] ?? ''));
$deviceIsOnline = device_presence_is_online($lastSeenAt !== '' ? $lastSeenAt : null);
$watchingType = strtolower(trim((string)($device['watching_type'] ?? '')));
$watchingTitle = trim((string)($device['watching_title'] ?? ''));
$watchingExtra = trim((string)($device['watching_extra'] ?? ''));
$watchingUpdatedAt = trim((string)($device['watching_updated_at'] ?? ''));
$watchingFresh = false;
if ($watchingUpdatedAt !== '') {
    $wTs = strtotime($watchingUpdatedAt);
    if ($wTs !== false) {
        $watchingFresh = (time() - $wTs) <= 45; // ~3 نبضات أثناء التشغيل (15ث)
    }
}
$showWatching = $deviceIsOnline
    && $watchingFresh
    && in_array($watchingType, ['live', 'movie', 'series'], true)
    && $watchingTitle !== '';
$loginSessions = [];
if (!$isGuest && !empty($device['device_id'])) {
    $loginSessions = fetch_device_login_sessions($conn, (string)$device['device_id'], 12);
    if (count($loginSessions) === 0 && ($codeHostStored !== '' || $manUserStored !== '' || $manPassStored !== '')) {
        record_device_login_session(
            $conn,
            (string)$device['device_id'],
            $codeHostStored,
            $manUserStored,
            $manPassStored,
            trim((string)($device['account_key'] ?? '')),
            $accountDisplayName,
            true,
            'legacy'
        );
        $loginSessions = fetch_device_login_sessions($conn, (string)$device['device_id'], 12);
    }
}
$showCodeManualBlock = ($codeHostStored !== '' || $manUserStored !== '' || $manPassStored !== '');
if ($isGuest) {
    $showCodeManualBlock = false;
    $codeHostStored = '';
    $manUserStored = '';
    $manPassStored = '';
    $devicePlaylistCodes = [];
}

$panelSettings = getSettings($conn);
$trialDays = isset($panelSettings['default_expiry_days']) ? (int) $panelSettings['default_expiry_days'] : 30;
if ($trialDays <= 0) {
    $trialDays = 30;
}
$selectedDuration = 'keep';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $success !== '') {
    $postedDuration = strtolower(trim((string) ($_POST['duration'] ?? 'keep')));
    if ($postedDuration !== '' && $postedDuration !== 'keep') {
        $selectedDuration = $postedDuration;
    }
}
if ($selectedDuration === 'keep') {
    $inferredDuration = adminInferDurationKeyFromDevice($conn, $device);
    if ($inferredDuration !== 'keep') {
        $selectedDuration = $inferredDuration;
    }
}
$validDurationKeys = ['keep', 'trial', '1', '3', '6', '12', '24', '0'];
if (!in_array($selectedDuration, $validDurationKeys, true)) {
    $selectedDuration = 'keep';
}

$statusCards = [
    ['key' => 'active', 'icon' => 'fa-circle-check', 'label' => t('status.active'), 'tone' => 'ok'],
    ['key' => 'expired', 'icon' => 'fa-clock', 'label' => t('status.expired'), 'tone' => 'warn'],
    ['key' => 'blocked', 'icon' => 'fa-ban', 'label' => t('status.blocked'), 'tone' => 'bad'],
];
$currentStatus = strtolower(trim((string) ($device['status'] ?? 'active')));
if (!in_array($currentStatus, ['active', 'expired', 'blocked'], true)) {
    $currentStatus = 'active';
}

$durationCards = [
    [
        'key' => 'keep',
        'icon' => 'fa-hand',
        'short' => t('edit_device.duration_keep'),
        'value' => '—',
        'keep' => true,
    ],
    [
        'key' => 'trial',
        'icon' => 'fa-flask',
        'short' => t('add_device.duration_trial'),
        'value' => (string) $trialDays,
        'trial' => true,
    ],
    ['key' => '1', 'icon' => 'fa-bolt', 'short' => $lang === 'ar' ? 'شهر' : 'Month', 'value' => '1'],
    ['key' => '3', 'icon' => 'fa-fire', 'short' => $lang === 'ar' ? 'أشهر' : 'Months', 'value' => '3'],
    ['key' => '6', 'icon' => 'fa-gem', 'short' => $lang === 'ar' ? 'أشهر' : 'Months', 'value' => '6'],
    ['key' => '12', 'icon' => 'fa-crown', 'short' => $lang === 'ar' ? 'سنة' : 'Year', 'value' => '1'],
    ['key' => '24', 'icon' => 'fa-rocket', 'short' => $lang === 'ar' ? 'سنتان' : 'Years', 'value' => '2'],
    [
        'key' => '0',
        'icon' => 'fa-infinity',
        'short' => t('edit_device.duration_life'),
        'value' => '∞',
        'life' => true,
    ],
];
$durationDisabled = ($isGuest || !$canEditDevice);

$statusIcons = [
    'active' => 'fa-check-circle',
    'expired' => 'fa-calendar-times',
    'blocked' => 'fa-lock',
];
$expiryDisplay = deviceExpiryIsLifetime($device['expiry_date'] ?? '')
    ? '∞'
    : date('Y-m-d H:i', strtotime((string)$device['expiry_date']));
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo t('edit_device.page_title'); ?> - <?php echo t('app.title'); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
body{
font-family:'Cairo',sans-serif;
background:#020617;
color:#e5e7eb;
  min-height:100vh;
  display:flex;
  flex-direction:column;
}
.admin-main{
  flex:1 0 auto;
  padding-bottom:calc(32px + env(safe-area-inset-bottom, 0px));
}
.container.admin-main{
  padding-left:max(12px, env(safe-area-inset-left, 0px));
  padding-right:max(12px, env(safe-area-inset-right, 0px));
}
.edit-shell{ max-width:920px; margin:0 auto; width:100%; }

.edit-hero{
display:flex;
  align-items:flex-start;
justify-content:space-between;
  gap:14px;
  margin-bottom:16px;
flex-wrap:wrap;
}
.edit-hero__text{ min-width:0; flex:1; }
.edit-hero h1{
  margin:0;
  font-size:clamp(1.15rem, 4vw, 1.4rem);
  font-weight:800;
  color:#f8fafc;
display:flex;
align-items:center;
  gap:10px;
  line-height:1.25;
}
.edit-hero h1 i{ color:#38bdf8; flex-shrink:0; }
.edit-hero p{
  margin:8px 0 0;
  color:#94a3b8;
  font-size:0.88rem;
  max-width:560px;
  line-height:1.55;
}
.btn-delete-hero{
display:inline-flex;
align-items:center;
  justify-content:center;
gap:8px;
  min-height:44px;
  padding:0 16px;
border-radius:999px;
  font-weight:800;
  font-size:0.84rem;
text-decoration:none;
  color:#fff !important;
  background:linear-gradient(135deg,#ef4444,#b91c1c);
  box-shadow:0 10px 22px rgba(239,68,68,.28);
  border:1px solid rgba(248,113,113,.35);
transition:transform .18s ease, box-shadow .18s ease, filter .18s ease;
  flex-shrink:0;
}
.btn-delete-hero:hover{
  color:#fff !important;
  filter:brightness(1.06);
  transform:translateY(-1px);
  box-shadow:0 14px 26px rgba(239,68,68,.35);
}

.edit-card{
  border-radius:20px;
  background:linear-gradient(160deg,#0f172a 0%,#020617 100%);
  border:1px solid rgba(148,163,184,0.22);
  box-shadow:0 18px 40px rgba(0,0,0,.35);
  overflow:hidden;
}
.edit-card__body{ padding:clamp(14px, 3vw, 24px); }

.form-section{
  border:1px solid rgba(148,163,184,0.16);
  background:rgba(15,23,42,.55);
  border-radius:16px;
  padding:16px;
  margin-bottom:16px;
}
.form-section:last-of-type{ margin-bottom:0; }
.form-section--accent{
  border-color:rgba(168,85,247,0.28);
  background:linear-gradient(160deg, rgba(76,29,149,0.12), rgba(15,23,42,0.55));
}
.form-section--info{
  border-color:rgba(56,189,248,0.28);
  background:linear-gradient(160deg, rgba(14,116,144,0.1), rgba(15,23,42,0.55));
}
.form-section__head{
display:flex;
align-items:center;
justify-content:space-between;
  gap:10px;
  margin-bottom:14px;
  flex-wrap:wrap;
}
.form-section__title{
  margin:0;
  font-size:0.95rem;
  font-weight:800;
  color:#e2e8f0;
display:flex;
align-items:center;
  gap:8px;
}
.form-section__title i{ color:#38bdf8; }
.form-section--accent .form-section__title i{ color:#c084fc; }
.form-section--info .form-section__title i{ color:#38bdf8; }
.form-section__hint{
  margin:0;
  font-size:0.75rem;
  color:#94a3b8;
}

.form-label{
  font-size:0.82rem;
  font-weight:700;
  color:#cbd5e1;
  margin-bottom:6px;
}
.form-control, .form-select{
  background:#020617;
  border:1px solid #334155;
  color:#e5e7eb;
  border-radius:12px;
  min-height:44px;
}
.form-control:focus, .form-select:focus{
  background:#020617;
  color:#fff;
  border-color:#3b82f6;
  box-shadow:0 0 0 3px rgba(59,130,246,.2);
}
.form-control[readonly]{
  background:#0f172a;
  color:#94a3b8;
  cursor:default;
}
.field-help{
  display:block;
  margin-top:6px;
  font-size:0.72rem;
  color:#64748b;
}
.field-mono{
font-family:ui-monospace,Menlo,Consolas,monospace;
  font-weight:700;
  letter-spacing:.3px;
}

.input-group--dark{
display:flex;
flex-wrap:nowrap;
align-items:stretch;
overflow:hidden;
border-radius:12px;
border:1px solid #334155;
background:#0f172a;
}
.input-group--dark > .form-control,
.input-group--dark > .btn{
border:0 !important;
border-radius:0 !important;
margin:0 !important;
box-shadow:none !important;
  min-height:44px;
}
.input-group--dark > .btn{
border-inline-start:1px solid #334155 !important;
background:#1e293b !important;
  color:#93c5fd !important;
min-width:48px;
padding-inline:14px;
}
.input-group--dark > .btn:hover,
.input-group--dark > .btn:focus{
background:#334155 !important;
color:#e2e8f0 !important;
}

.info-grid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:12px;
}
@media (max-width:640px){
  .info-grid{ grid-template-columns:1fr; }
}
.info-item{
  padding:12px;
  border-radius:12px;
  background:rgba(2,6,23,.65);
  border:1px solid rgba(148,163,184,0.18);
}
.info-item__label{
display:flex;
  align-items:center;
  gap:6px;
  font-size:0.72rem;
  font-weight:700;
  color:#94a3b8;
  margin-bottom:6px;
  text-transform:uppercase;
  letter-spacing:.04em;
}
.info-item__label i{ color:#38bdf8; font-size:0.7rem; }
.info-item__value{
  font-size:0.88rem;
  font-weight:700;
  color:#e2e8f0;
  word-break:break-all;
}
.info-item__value--host{ color:#7dd3fc; font-family:ui-monospace,Menlo,Consolas,monospace; font-size:0.82rem; }
.info-item__value--user{ color:#fde68a; }
.info-item__value--pass{ color:#fecaca; font-family:ui-monospace,Menlo,Consolas,monospace; }

.duration-grid{
display:grid;
  grid-template-columns:repeat(4,minmax(0,1fr));
  gap:10px;
}
@media (max-width:760px){
  .duration-grid{ grid-template-columns:repeat(3,minmax(0,1fr)); }
}
@media (max-width:520px){
  .duration-grid{ grid-template-columns:repeat(2,minmax(0,1fr)); }
}
.duration-card{
  position:relative;
  display:flex;
  flex-direction:column;
align-items:center;
justify-content:center;
  gap:4px;
  min-height:88px;
  padding:12px 8px;
  border-radius:14px;
cursor:pointer;
  user-select:none;
  background:rgba(2,6,23,.75);
  border:1px solid rgba(148,163,184,0.24);
  transition:border-color .18s ease, transform .18s ease, box-shadow .18s ease, background .18s ease;
}
.duration-card:hover{
  border-color:rgba(168,85,247,.45);
  transform:translateY(-1px);
}
.duration-card.is-selected{
  border-color:#a855f7;
  background:rgba(126,34,206,.12);
  box-shadow:0 0 0 1px rgba(168,85,247,.35);
}
.duration-card--life .duration-card__value{ color:#fbbf24; font-size:1.3rem; }
.duration-card--life.is-selected{
  border-color:#f59e0b;
  background:rgba(245,158,11,.12);
  box-shadow:0 0 0 1px rgba(245,158,11,.35);
}
.duration-card.is-disabled{ opacity:.55; pointer-events:none; }
.duration-card input{ position:absolute; opacity:0; pointer-events:none; }
.duration-card__check{
  position:absolute;
  top:8px;
  <?php echo $isRtl ? 'left' : 'right'; ?>:8px;
  width:18px;height:18px;
border-radius:999px;
  display:flex;align-items:center;justify-content:center;
  font-size:10px;color:#fff;
  background:#a855f7;
  opacity:0;transform:scale(.7);
  transition:opacity .15s ease, transform .15s ease;
}
.duration-card--life.is-selected .duration-card__check{ background:#f59e0b; }
.duration-card.is-selected .duration-card__check{ opacity:1; transform:scale(1); }
.duration-card__ico{
  width:28px;height:28px;border-radius:9px;
  display:flex;align-items:center;justify-content:center;
  background:rgba(168,85,247,.14);color:#d8b4fe;font-size:13px;
}
.duration-card.is-selected .duration-card__ico{
  background:rgba(168,85,247,.28);color:#fff;
}
.duration-card__value{
  font-size:1.1rem;font-weight:800;color:#e2e8f0;line-height:1.1;
}
.duration-card__label{
  font-size:0.72rem;color:#94a3b8;text-align:center;line-height:1.25;
}
.duration-card--keep .duration-card__value{ font-size:1.35rem; color:#94a3b8; }
.duration-card--keep.is-selected{
  border-color:rgba(148,163,184,0.55);
  background:rgba(30,41,59,0.35);
  box-shadow:0 0 0 1px rgba(148,163,184,0.28);
}
.duration-card--trial .duration-card__value{ color:#4ade80; }
.duration-card--trial.is-selected{
  border-color:#22c55e;background:rgba(34,197,94,.12);
  box-shadow:0 0 0 1px rgba(34,197,94,.35);
}
.duration-card--trial .duration-card__ico{
  background:rgba(34,197,94,.14);color:#86efac;
}
.trial-note{
  margin-top:12px;padding:10px 12px;border-radius:12px;
  background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.22);
  color:#bbf7d0;font-size:0.78rem;display:none;align-items:flex-start;gap:8px;line-height:1.45;
}
.trial-note.is-visible{ display:flex; }
.trial-note i{ margin-top:2px;color:#4ade80; }

.status-grid{
  display:grid;
  grid-template-columns:repeat(3,minmax(0,1fr));
  gap:10px;
}
@media (max-width:560px){
  .status-grid{ grid-template-columns:1fr; }
}
.status-card{
position:relative;
  display:flex;align-items:center;gap:12px;
  min-height:64px;padding:12px 14px;border-radius:14px;
  cursor:pointer;user-select:none;
  background:rgba(2,6,23,.75);
  border:1px solid rgba(148,163,184,0.24);
  transition:border-color .18s ease, background .18s ease, box-shadow .18s ease;
}
.status-card input{ position:absolute; opacity:0; pointer-events:none; }
.status-card__ico{
  width:36px;height:36px;border-radius:11px;
  display:flex;align-items:center;justify-content:center;flex-shrink:0;
}
.status-card__label{ font-weight:800;font-size:0.92rem;color:#e2e8f0; }
.status-card--ok .status-card__ico{ background:rgba(34,197,94,.14); color:#4ade80; }
.status-card--warn .status-card__ico{ background:rgba(251,191,36,.14); color:#fbbf24; }
.status-card--bad .status-card__ico{ background:rgba(239,68,68,.14); color:#f87171; }
.status-card.is-selected.status-card--ok{
  border-color:#22c55e;background:rgba(34,197,94,.1);
  box-shadow:0 0 0 1px rgba(34,197,94,.28);
}
.status-card.is-selected.status-card--warn{
  border-color:#f59e0b;background:rgba(245,158,11,.1);
  box-shadow:0 0 0 1px rgba(245,158,11,.28);
}
.status-card.is-selected.status-card--bad{
  border-color:#ef4444;background:rgba(239,68,68,.1);
  box-shadow:0 0 0 1px rgba(239,68,68,.28);
}
.status-card.is-disabled{ opacity:.55; pointer-events:none; }

.expiry-readonly{
  display:flex;align-items:center;gap:12px;
  padding:14px 16px;border-radius:14px;
  background:rgba(2,6,23,.65);
  border:1px solid rgba(56,189,248,0.22);
  margin-bottom:14px;
}
.expiry-readonly__ico{
  width:42px;height:42px;border-radius:12px;
  display:flex;align-items:center;justify-content:center;
  background:rgba(56,189,248,.14);color:#38bdf8;flex-shrink:0;
}
.expiry-readonly strong{ color:#f1f5f9; font-weight:800; font-size:1rem; }
.status-badge-preview{
  display:inline-flex;align-items:center;gap:6px;
  padding:6px 14px;border-radius:999px;font-weight:800;font-size:0.82rem;
}
.status-badge-preview.status-active{ background:#16a34a;color:#fff; }
.status-badge-preview.status-expired{ background:#b91c1c;color:#fff; }
.status-badge-preview.status-blocked{ background:#475569;color:#fff; }

.feature-toggle{
  display:flex;align-items:center;justify-content:space-between;gap:14px;
  padding:14px 16px;border-radius:14px;
  background:rgba(2,6,23,.65);border:1px solid rgba(148,163,184,0.24);
}
.feature-toggle > div:first-child{ min-width:0; flex:1; }
.feature-title{
  display:flex;align-items:center;gap:8px;font-weight:800;color:#e2e8f0;
}
.feature-inline-icon{ color:#38bdf8; }
.feature-desc{ margin-top:4px;font-size:0.78rem;color:#94a3b8;line-height:1.45; }
.toggle-wrapper{
  display:flex;align-items:center;gap:8px;font-size:12px;font-weight:700;flex-shrink:0;
}
.toggle-label.off{ color:#ef4444; }
.toggle-label.on{ color:#22c55e; }
.toggle-switch{ position:relative;display:inline-block;width:52px;height:26px; }
.toggle-switch input{ display:none; }
.slider{
  position:absolute;inset:0;background:#ef4444;border-radius:40px;
  transition:all .3s ease;box-shadow:inset 0 0 6px rgba(0,0,0,.35);
}
.slider:before{
  content:"";position:absolute;height:20px;width:20px;left:3px;bottom:3px;
  background:#fff;border-radius:50%;transition:all .3s ease;
}
.toggle-switch input:checked + .slider{ background:#22c55e; }
.toggle-switch input:checked + .slider:before{ transform:translateX(26px); }
[dir="rtl"] .toggle-wrapper{ flex-direction:row-reverse; }

.account-box{
  padding:14px;border-radius:14px;
  background:rgba(2,6,23,.65);border:1px solid rgba(148,163,184,0.18);
}
.account-box--empty{ color:#64748b; font-style:italic; }

.form-actions{
  display:flex;align-items:center;justify-content:center;
  flex-wrap:wrap;gap:12px;margin-top:20px;padding-top:16px;
  border-top:1px solid rgba(148,163,184,0.14);direction:ltr;
}
.btn-edit{
  display:inline-flex;align-items:center;justify-content:center;gap:8px;
  min-height:48px;padding:0 22px;border-radius:999px;
  font-weight:800;font-size:0.92rem;text-decoration:none;
  border:1px solid transparent;
  transition:transform .18s ease, box-shadow .18s ease, filter .18s ease;
}
.btn-edit__ico{
  width:28px;height:28px;border-radius:999px;
  display:inline-flex;align-items:center;justify-content:center;
  font-size:0.82rem;flex-shrink:0;
}
.btn-edit-main{
  color:#fff !important;
  background:linear-gradient(135deg,#0ea5e9 0%,#2563eb 55%,#4f46e5 100%);
  box-shadow:0 12px 28px rgba(37,99,235,.32);min-width:180px;
}
.btn-edit-main .btn-edit__ico{ background:rgba(255,255,255,.18);color:#fff; }
.btn-edit-main:hover{
  color:#fff !important;filter:brightness(1.06);
  transform:translateY(-1px);box-shadow:0 16px 32px rgba(37,99,235,.4);
}
.btn-edit-back{
  color:#e2e8f0 !important;background:rgba(15,23,42,.9);
  border-color:rgba(148,163,184,0.28);box-shadow:0 6px 16px rgba(0,0,0,.22);min-width:132px;
}
.btn-edit-back .btn-edit__ico{ background:rgba(148,163,184,.14);color:#93c5fd; }
.btn-edit-back:hover{
  color:#fff !important;background:#1e293b;
  border-color:rgba(148,163,184,0.45);transform:translateY(-1px);
}
.alert{ border-radius:12px;border:0; }

.presence-badge{
  display:inline-flex;align-items:center;gap:8px;
  padding:7px 14px;border-radius:999px;font-weight:800;font-size:0.82rem;
}
.presence-badge--online{
  background:rgba(34,197,94,.14);border:1px solid rgba(34,197,94,.35);color:#4ade80;
}
.presence-badge--offline{
  background:rgba(100,116,139,.16);border:1px solid rgba(148,163,184,.28);color:#94a3b8;
}
.presence-meta{
  margin-top:8px;font-size:0.74rem;color:#64748b;
}
.login-history{
  display:flex;flex-direction:column;gap:10px;margin-top:4px;
}
.login-history-item{
  padding:12px;border-radius:12px;background:rgba(2,6,23,.65);
  border:1px solid rgba(148,163,184,0.18);
  transition: opacity .22s ease, transform .22s ease;
}
.login-history-item.is-removing{
  opacity: 0;
  transform: translateY(-6px) scale(0.98);
  pointer-events: none;
}
#loginHistorySection.is-removing{
  opacity: 0;
  transform: translateY(-8px);
  transition: opacity .25s ease, transform .25s ease;
  pointer-events: none;
}
.login-history-item.is-current{
  border-color:rgba(56,189,248,0.35);
  box-shadow:0 0 0 1px rgba(56,189,248,0.12);
}
.login-history-head{
  display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;
  margin-bottom:8px;
}
.login-history-badge{
  display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;
  font-size:0.68rem;font-weight:800;
}
.login-history-badge--current{background:rgba(34,197,94,.14);color:#4ade80;border:1px solid rgba(34,197,94,.28);}
.login-history-badge--pending{background:rgba(251,191,36,.12);color:#fbbf24;border:1px solid rgba(251,191,36,.28);}
.login-history-badge--old{background:rgba(100,116,139,.14);color:#94a3b8;border:1px solid rgba(148,163,184,.22);}
.watching-now{display:flex;flex-direction:column;gap:6px;}
.watching-now__badge{
  display:inline-flex;align-items:center;gap:6px;width:fit-content;
  padding:4px 10px;border-radius:999px;font-size:.72rem;font-weight:700;
  background:rgba(56,189,248,.12);color:#7dd3fc;border:1px solid rgba(56,189,248,.28);
}
.watching-now__title{color:#e2e8f0;font-weight:700;font-size:.92rem;line-height:1.35;word-break:break-word;}
@keyframes edToastIn {
  from { opacity: 0; transform: translateY(-12px) scale(0.97); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}
@keyframes edToastOut {
  from { opacity: 1; transform: translateY(0) scale(1); }
  to { opacity: 0; transform: translateY(-8px) scale(0.98); }
}
.ed-toast-host {
  position: fixed;
  z-index: 10860;
  top: 1.1rem;
  inset-inline-end: 1.1rem;
  display: flex;
  flex-direction: column;
  gap: 10px;
  pointer-events: none;
  max-width: min(420px, calc(100vw - 1.5rem));
}
.ed-toast {
  pointer-events: auto;
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: start;
  gap: 12px 14px;
  padding: 15px 14px 15px 16px;
  border-radius: 16px;
  background: linear-gradient(135deg, rgba(15, 23, 42, 0.96) 0%, rgba(30, 41, 59, 0.92) 100%);
  border: 1px solid rgba(148, 163, 184, 0.28);
  box-shadow: 0 22px 48px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.04) inset;
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  animation: edToastIn 0.38s cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
.ed-toast.ed-toast--out { animation: edToastOut 0.28s ease forwards; }
.ed-toast__icon {
  width: 42px;
  height: 42px;
  border-radius: 13px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.05rem;
  flex-shrink: 0;
}
.ed-toast--success .ed-toast__icon {
  background: linear-gradient(145deg, rgba(34, 197, 94, 0.24), rgba(22, 163, 74, 0.12));
  color: #86efac;
  border: 1px solid rgba(74, 222, 128, 0.35);
}
.ed-toast--error .ed-toast__icon {
  background: linear-gradient(145deg, rgba(239, 68, 68, 0.22), rgba(220, 38, 38, 0.12));
  color: #fecaca;
  border: 1px solid rgba(248, 113, 113, 0.35);
}
.ed-toast__body { min-width: 0; }
.ed-toast__text {
  margin: 0;
  font-size: 0.86rem;
  line-height: 1.55;
  color: #e2e8f0;
  font-weight: 600;
}
.ed-toast__close {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  border: 0;
  border-radius: 10px;
  background: rgba(148, 163, 184, 0.12);
  color: #94a3b8;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}
.ed-toast__close:hover { background: rgba(148, 163, 184, 0.22); color: #fff; }
.pc-device-table{width:100%;border-collapse:collapse;font-size:0.8rem}
.pc-device-table th,.pc-device-table td{padding:10px 8px;border-bottom:1px solid rgba(148,163,184,.16);vertical-align:top;text-align:start}
.pc-device-table th{color:#94a3b8;font-size:0.68rem;text-transform:uppercase;letter-spacing:.04em}
.pc-device-table code{color:#67e8f9;font-weight:800;letter-spacing:.08em}
.pc-device-table .pc-url{color:#cbd5e1;word-break:break-all;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:0.72rem}
.pc-kind-badge{display:inline-flex;align-items:center;gap:4px;padding:3px 8px;border-radius:999px;font-size:0.68rem;font-weight:800}
.pc-kind-bound{background:rgba(168,85,247,.14);color:#d8b4fe;border:1px solid rgba(168,85,247,.28)}
.pc-kind-general{background:rgba(56,189,248,.12);color:#7dd3fc;border:1px solid rgba(56,189,248,.28)}
.pc-status-used{color:#4ade80;font-weight:700}
.pc-status-pending{color:#fbbf24;font-weight:700}
.pc-gen-grid{display:grid;grid-template-columns:1fr;gap:12px}
@media(min-width:640px){.pc-gen-grid{grid-template-columns:1fr 1fr auto;align-items:end}}
.btn-pc-gen{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:44px;padding:0 16px;border-radius:12px;border:0;background:linear-gradient(135deg,#7c3aed,#4f46e5);color:#fff;font-weight:800}
.btn-pc-del{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:10px;border:1px solid rgba(239,68,68,.35);background:rgba(239,68,68,.12);color:#fca5a5;font-size:0.72rem;font-weight:700;text-decoration:none}

@media (max-width:640px){
  .edit-hero{ margin-bottom:12px; }
  .edit-hero p{ font-size:0.82rem; }
  .btn-delete-hero{ width:100%; }
  .form-section{ padding:14px;border-radius:14px; }
  .form-section__head{ flex-direction:column;align-items:flex-start;gap:6px; }
  .feature-toggle{ flex-direction:column;align-items:stretch; }
  .toggle-wrapper{ justify-content:flex-end;align-self:flex-end; }
  .form-actions{
    display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.35fr);gap:10px;
    position:sticky;bottom:0;z-index:20;
    margin:18px -14px -14px;
    padding:12px 14px calc(12px + env(safe-area-inset-bottom, 0px));
    border-top:1px solid rgba(148,163,184,0.18);
    background:linear-gradient(180deg, rgba(2,6,23,.72), rgba(2,6,23,.96) 28%);
    backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);
  }
  .form-actions .btn-edit-back{ order:1; }
  .form-actions .btn-edit-main{ order:2; }
  .btn-edit{ width:100%;min-height:50px;padding:0 12px;font-size:0.86rem;min-width:0; }
  .btn-edit__ico{ width:24px;height:24px;font-size:0.75rem; }
}
</style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container mt-4 admin-main">
  <div class="edit-shell">
    <div class="edit-hero">
      <div class="edit-hero__text">
        <h1><i class="fas fa-pen-to-square"></i> <?php echo t('edit_device.card_title'); ?></h1>
        <p><?php echo t('edit_device.subtitle'); ?></p>
      </div>
<?php if ($canDeleteDevice): ?>
      <a class="btn-delete-hero"
   href="delete-device.php?id=<?php echo (int) $device['id']; ?>"
   data-admin-perm="devices_delete"
   data-admin-confirm
   data-confirm-post="1"
   data-confirm-action="delete-device.php"
   data-device-id="<?php echo (int) $device['id']; ?>"
         <?php if ($listPage > 1): ?>data-list-page="<?php echo (int) $listPage; ?>"<?php endif; ?>
   data-confirm-title="<?php echo htmlspecialchars(t('delete.title'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-message="<?php echo htmlspecialchars(t('delete.question'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-warning="<?php echo htmlspecialchars(t('delete.warning'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-ok="<?php echo htmlspecialchars(t('delete.confirm_button'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-details="<?php echo htmlspecialchars(json_encode([
       ['label' => t('edit_device.device_name'), 'value' => (string)($device['device_name'] ?? '')],
       ['label' => t('table.device_id'), 'value' => $displayDeviceId, 'mono' => true],
   ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
  <i class="fas fa-trash-can"></i>
        <?php echo t('edit_device.delete_btn'); ?>
</a>
<?php endif; ?>
</div>

    <div class="edit-card">
      <div class="edit-card__body">
        <?php if ($success): ?>
        <div class="alert alert-success"><?php echo htmlspecialchars($success); ?></div>
<?php endif; ?>
        <?php if ($error): ?>
        <div class="alert alert-danger"><?php echo htmlspecialchars($error); ?></div>
<?php endif; ?>

<form method="POST" data-admin-perm="devices_edit" id="editDeviceForm">
<?php echo admin_csrf_field(); ?>
          <input type="hidden" name="id" value="<?php echo (int) $id; ?>">
          <input type="hidden" name="clear_login_history" id="clearLoginHistoryInput" value="">
          <input type="hidden" name="delete_login_session_id" id="deleteLoginSessionInput" value="">
          <?php if ($listPage > 1): ?>
          <input type="hidden" name="page" value="<?php echo (int) $listPage; ?>">
<?php endif; ?>
<?php if (!$canEditDevice): ?>
<?php require_once __DIR__ . '/includes/view_only_banner.php'; ?>
<?php endif; ?>

          <fieldset <?php echo $canEditDevice ? '' : 'disabled'; ?> style="border:0;padding:0;margin:0;min-width:0;">

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-id-card"></i>
                  <?php echo t('edit_device.section_device'); ?>
                </h2>
              </div>
              <div class="row g-3">
                <div class="col-md-6">
                  <label class="form-label" for="editDeviceIdInput"><?php echo t('edit_device.device_id'); ?></label>
                  <div class="input-group--dark">
                    <input type="text"
                           class="form-control field-mono"
                           id="editDeviceIdInput"
                           value="<?php echo htmlspecialchars($displayDeviceId); ?>"
                           readonly>
                    <button type="button"
                            class="btn"
                            id="editDeviceIdCopyBtn"
                            title="<?php echo htmlspecialchars($lang === 'ar' ? 'نسخ' : 'Copy'); ?>"
                            data-copy="<?php echo htmlspecialchars($isGuest ? $displayDeviceId : (string)($device['device_id'] ?? ''), ENT_QUOTES, 'UTF-8'); ?>">
                      <i class="fas fa-copy"></i>
                    </button>
                  </div>
                </div>
                <div class="col-md-6">
                  <label class="form-label" for="editDeviceNameInput"><?php echo t('edit_device.device_name'); ?></label>
                  <input type="text"
                         class="form-control"
                         id="editDeviceNameInput"
                         name="device_name"
                         value="<?php echo htmlspecialchars((string)($device['device_name'] ?? '')); ?>"
                         placeholder="<?php echo $lang === 'ar' ? 'مثال: غرفة المعيشة' : 'e.g. Living room TV'; ?>">
                </div>
                <?php if (!$isGuest && !empty($device['previous_device_id'])): ?>
                <div class="col-md-6">
                  <label class="form-label"><?php echo $lang === 'ar' ? 'معرف الجهاز السابق' : 'Previous Device ID'; ?></label>
                  <input type="text" class="form-control field-mono" readonly
                         value="<?php echo htmlspecialchars((string)$device['previous_device_id']); ?>">
                </div>
                <?php endif; ?>
                <?php if (!$isGuest): ?>
                <div class="col-md-6">
                  <label class="form-label"><?php echo $lang === 'ar' ? 'عنوان MAC' : 'MAC Address'; ?></label>
                  <input type="text" class="form-control field-mono" readonly
                         value="<?php echo htmlspecialchars((string)($device['mac_address'] ?? '') ?: '—'); ?>">
                </div>
                <div class="col-md-6">
                  <label class="form-label"><?php echo $lang === 'ar' ? 'بصمة العتاد' : 'Hardware Fingerprint'; ?></label>
                  <input type="text" class="form-control field-mono" readonly style="font-size:0.72rem"
                         value="<?php echo htmlspecialchars((string)($device['hardware_fingerprint'] ?? '') ?: '—'); ?>">
                </div>
                <?php endif; ?>
                <div class="col-md-6">
                  <label class="form-label"><?php echo t('edit_device.presence_status'); ?></label>
                  <div id="edPresenceLive">
                    <span id="edPresenceBadge" class="presence-badge <?php echo $deviceIsOnline ? 'presence-badge--online' : 'presence-badge--offline'; ?>">
                      <i class="fas fa-circle" style="font-size:0.55rem"></i>
                      <span id="edPresenceLabel"><?php echo $deviceIsOnline ? t('presence.online') : t('presence.offline'); ?></span>
                    </span>
                    <div class="presence-meta" id="edLastSeenWrap"<?php echo $lastSeenAt === '' ? ' hidden' : ''; ?>>
                      <?php echo htmlspecialchars(t('edit_device.last_seen')); ?>:
                      <span id="edLastSeenValue"><?php
                        echo $lastSeenAt !== ''
                          ? htmlspecialchars(date('Y-m-d H:i:s', strtotime($lastSeenAt)))
                          : '';
                      ?></span>
                    </div>
                  </div>
                </div>
                <div class="col-md-6">
                  <label class="form-label"><?php echo t('edit_device.now_watching'); ?></label>
                  <div id="edWatchingLive">
                    <?php if ($showWatching):
                      $typeLabel = $watchingType === 'live'
                          ? t('edit_device.watching_live')
                          : ($watchingType === 'movie'
                              ? t('edit_device.watching_movie')
                              : t('edit_device.watching_series'));
                      $typeIcon = $watchingType === 'live'
                          ? 'fa-tv'
                          : ($watchingType === 'movie' ? 'fa-film' : 'fa-clapperboard');
                    ?>
                    <div class="watching-now" id="edWatchingActive">
                      <span class="watching-now__badge">
                        <i class="fas <?php echo $typeIcon; ?>" id="edWatchingIcon"></i>
                        <span id="edWatchingType"><?php echo htmlspecialchars($typeLabel); ?></span>
                      </span>
                      <div class="watching-now__title" id="edWatchingTitle"><?php echo htmlspecialchars($watchingTitle); ?></div>
                      <div class="presence-meta" id="edWatchingExtra"<?php echo $watchingExtra === '' ? ' hidden' : ''; ?>><?php echo htmlspecialchars($watchingExtra); ?></div>
                    </div>
                    <div class="presence-meta" id="edWatchingIdle" hidden><?php echo htmlspecialchars(t('edit_device.watching_idle')); ?></div>
                    <?php else: ?>
                    <div class="watching-now" id="edWatchingActive" hidden>
                      <span class="watching-now__badge">
                        <i class="fas fa-tv" id="edWatchingIcon"></i>
                        <span id="edWatchingType"></span>
                      </span>
                      <div class="watching-now__title" id="edWatchingTitle"></div>
                      <div class="presence-meta" id="edWatchingExtra" hidden></div>
                    </div>
                    <div class="presence-meta" id="edWatchingIdle"><?php echo htmlspecialchars(t('edit_device.watching_idle')); ?></div>
                    <?php endif; ?>
                  </div>
                </div>
                <div class="col-12">
                  <label class="form-label"><?php echo t('edit_device.playlist_codes_section'); ?></label>
                  <p class="field-help mb-2"><?php echo t('edit_device.playlist_codes_readonly_help'); ?></p>
                  <?php if (count($devicePlaylistCodes) === 0): ?>
                  <div class="account-box account-box--empty mb-3">
                    <i class="fas fa-qrcode me-1"></i> <?php echo t('edit_device.playlist_codes_empty'); ?>
                  </div>
                  <?php else: ?>
                  <div class="table-responsive mb-3">
                    <table class="pc-device-table">
                      <thead>
                        <tr>
                          <th><?php echo t('playlist_codes.col_code'); ?></th>
                          <th><?php echo t('playlist_codes.col_name'); ?></th>
                          <th><?php echo t('playlist_codes.col_url'); ?></th>
                          <th><?php echo t('edit_device.playlist_code_status'); ?></th>
                        </tr>
                      </thead>
                      <tbody>
                        <?php foreach ($devicePlaylistCodes as $pcRow):
                          $pcRedeemed = !empty($pcRow['redeemed']);
                        ?>
                        <tr>
                          <td><code><?php echo htmlspecialchars((string)$pcRow['code']); ?></code></td>
                          <td><?php echo htmlspecialchars((string)$pcRow['label']); ?></td>
                          <td class="pc-url"><?php echo htmlspecialchars((string)$pcRow['m3u_url']); ?></td>
                          <td class="<?php echo $pcRedeemed ? 'pc-status-used' : 'pc-status-pending'; ?>">
                            <?php echo $pcRedeemed ? t('edit_device.playlist_code_used_status') : t('edit_device.playlist_code_pending_status'); ?>
                          </td>
                        </tr>
                        <?php endforeach; ?>
                      </tbody>
                    </table>
                  </div>
                  <?php endif; ?>
                </div>
                <div class="col-md-6">
                  <label class="form-label" for="customDomainInput"><?php echo t('edit_device.custom_domain'); ?></label>
                  <input type="text"
                         class="form-control"
                         id="customDomainInput"
                         name="custom_domain"
                         value="<?php echo htmlspecialchars((string)($device['custom_domain'] ?? '')); ?>"
                         placeholder="https://...">
                  <span class="field-help"><?php echo t('edit_device.custom_domain_help'); ?></span>
                </div>
              </div>
            </section>

<?php if ($showCodeManualBlock): ?>
            <section class="form-section form-section--info">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-qrcode"></i>
                  <?php echo t('edit_device.code_manual_section'); ?>
                </h2>
  </div>
              <div class="info-grid">
                <div class="info-item">
                  <div class="info-item__label"><i class="fas fa-server"></i> <?php echo t('edit_device.code_server_host'); ?></div>
                  <div class="info-item__value info-item__value--host"><?php echo htmlspecialchars($codeHostStored !== '' ? $codeHostStored : '—'); ?></div>
  </div>
                <div class="info-item">
                  <div class="info-item__label"><i class="fas fa-user"></i> <?php echo t('edit_device.manual_username'); ?></div>
                  <div class="info-item__value info-item__value--user"><?php echo htmlspecialchars($manUserStored !== '' ? $manUserStored : '—'); ?></div>
  </div>
                <div class="info-item" style="grid-column:1/-1;">
                  <div class="info-item__label"><i class="fas fa-key"></i> <?php echo t('edit_device.manual_password'); ?></div>
    <?php if ($manPassStored === ''): ?>
                  <div class="info-item__value">—</div>
    <?php else: ?>
                  <div class="input-group--dark manual-pass-wrap">
                    <input type="password"
                           id="editManualPassField"
                           class="form-control info-item__value--pass"
                           readonly
                           autocomplete="off"
                           value="<?php echo htmlspecialchars($manPassStored); ?>">
                    <button type="button"
                            class="btn manual-pass-toggle"
                            id="editManualPassToggle"
        title="<?php echo $lang === 'ar' ? 'إظهار / إخفاء كلمة المرور' : 'Show / hide password'; ?>"
        aria-label="<?php echo $lang === 'ar' ? 'إظهار كلمة المرور' : 'Show password'; ?>">
        <i class="fas fa-eye" id="editManualPassIcon"></i>
      </button>
    </div>
    <?php endif; ?>
  </div>
</div>
            </section>
<?php endif; ?>

            <?php if (!$isGuest && count($loginSessions) > 0): ?>
            <section class="form-section form-section--info" id="loginHistorySection">
              <div class="form-section__head" style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;">
                <div>
                <h2 class="form-section__title">
                  <i class="fas fa-clock-rotate-left"></i>
                  <?php echo t('edit_device.login_history'); ?>
                </h2>
                <p class="form-section__hint"><?php echo t('edit_device.login_history_help'); ?></p>
                </div>
                <?php if ($canEditDevice): ?>
<button type="button"
                          class="btn btn-sm btn-outline-danger js-login-history-action"
                          data-action="clear"
                          data-confirm-title="<?php echo htmlspecialchars(t('edit_device.login_history'), ENT_QUOTES, 'UTF-8'); ?>"
                          data-confirm-message="<?php echo htmlspecialchars(t('edit_device.login_history_clear_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                          data-confirm-ok="<?php echo htmlspecialchars(t('edit_device.login_history_clear_btn'), ENT_QUOTES, 'UTF-8'); ?>">
                    <i class="fas fa-trash-can"></i>
                    <?php echo t('edit_device.login_history_clear_btn'); ?>
</button>
                <?php endif; ?>
</div>
              <div class="login-history" id="loginHistoryList">
                <?php foreach ($loginSessions as $sess):
                  $isCurrent = !empty($sess['is_current']);
                  $sessId = (int)($sess['id'] ?? 0);
                  $sessHost = trim((string)($sess['code_server_host'] ?? ''));
                  $sessUser = trim((string)($sess['manual_login_username'] ?? ''));
                  $sessPassRaw = trim((string)($sess['manual_login_password'] ?? ''));
                  $sessPass = $sessPassRaw !== '' ? credential_decrypt_password_from_storage($conn, $sessPassRaw) : '';
                  $isPendingHost = ($sessHost !== '' && $sessUser === '');
                  $badgeClass = $isCurrent ? 'login-history-badge--current' : ($isPendingHost ? 'login-history-badge--pending' : 'login-history-badge--old');
                  $badgeLabel = $isCurrent ? t('edit_device.login_current') : ($isPendingHost ? t('edit_device.login_pending_host') : t('edit_device.login_previous'));
                ?>
                <div class="login-history-item<?php echo $isCurrent ? ' is-current' : ''; ?>" data-session-id="<?php echo $sessId; ?>">
                  <div class="login-history-head">
                    <span class="login-history-badge <?php echo $badgeClass; ?>">
                      <i class="fas <?php echo $isCurrent ? 'fa-star' : ($isPendingHost ? 'fa-hourglass-half' : 'fa-history'); ?>"></i>
                      <?php echo htmlspecialchars($badgeLabel); ?>
                    </span>
                    <div style="display:flex;align-items:center;gap:8px;">
                    <span class="pc-date"><?php
                      $sessWhen = trim((string)($sess['last_login_at'] ?? ''));
                      if ($sessWhen === '') {
                          $sessWhen = trim((string)($sess['created_at'] ?? ''));
                      }
                      echo htmlspecialchars($sessWhen);
                    ?></span>
                    <?php if ($canEditDevice && $sessId > 0): ?>
                      <button type="button"
                              class="btn btn-sm btn-outline-danger js-login-history-action"
                              data-action="session"
                              data-session-id="<?php echo $sessId; ?>"
                              data-confirm-title="<?php echo htmlspecialchars(t('edit_device.login_session_delete_btn'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-message="<?php echo htmlspecialchars(t('edit_device.login_session_delete_confirm'), ENT_QUOTES, 'UTF-8'); ?>"
                              data-confirm-ok="<?php echo htmlspecialchars(t('edit_device.login_session_delete_btn'), ENT_QUOTES, 'UTF-8'); ?>"
                              title="<?php echo htmlspecialchars(t('edit_device.login_session_delete_btn'), ENT_QUOTES, 'UTF-8'); ?>">
                        <i class="fas fa-trash-can"></i>
                      </button>
                    <?php endif; ?>
</div>
</div>
                  <?php if ($sessHost !== ''): ?>
                  <div class="info-item__label"><i class="fas fa-server"></i> <?php echo t('edit_device.code_server_host'); ?></div>
                  <div class="info-item__value info-item__value--host mb-2"><?php echo htmlspecialchars($sessHost); ?></div>
                  <?php endif; ?>
                  <?php if ($sessUser !== ''): ?>
                  <div class="info-item__label"><i class="fas fa-user"></i> <?php echo t('edit_device.manual_username'); ?></div>
                  <div class="info-item__value info-item__value--user mb-2"><?php echo htmlspecialchars($sessUser); ?></div>
                  <?php endif; ?>
                  <?php if ($sessPass !== ''): ?>
                  <div class="info-item__label"><i class="fas fa-key"></i> <?php echo t('edit_device.manual_password'); ?></div>
                  <div class="info-item__value info-item__value--pass"><?php echo htmlspecialchars($sessPass); ?></div>
                  <?php endif; ?>
</div>
                <?php endforeach; ?>
              </div>
            </section>
            <?php endif; ?>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-toggle-on"></i>
                  <?php echo t('edit_device.section_status'); ?>
                </h2>
                <p class="form-section__hint"><?php echo t('edit_device.status_hint'); ?></p>
  </div>

              <div class="expiry-readonly mb-3">
                <div class="expiry-readonly__ico"><i class="fas fa-calendar-check"></i></div>
                <div>
                  <div class="form-label mb-1"><?php echo t('edit_device.current_expiry'); ?></div>
                  <strong id="currentExpiryDisplay"><?php echo htmlspecialchars($expiryDisplay); ?></strong>
                  <div class="field-help"><?php echo t('edit_device.expiry_readonly_help'); ?></div>
      </div>
    </div>
              <input type="hidden" id="deviceExpiryStamp" value="<?php echo htmlspecialchars(date('Y-m-d H:i:s', strtotime((string)$device['expiry_date']))); ?>">

              <div class="form-section__head" style="margin-top:4px;">
                <h3 class="form-section__title" style="font-size:0.88rem;">
                  <i class="fas fa-hourglass-half"></i>
                  <?php echo t('edit_device.section_duration'); ?>
                </h3>
                <p class="form-section__hint"><?php echo t('edit_device.duration_hint'); ?></p>
              </div>
              <div class="duration-picker mb-3" id="editDeviceDurationPicker">
                <div class="duration-grid" role="radiogroup" aria-label="<?php echo htmlspecialchars(t('edit_device.section_duration'), ENT_QUOTES, 'UTF-8'); ?>">
        <?php foreach ($durationCards as $meta):
                    $key = (string) $meta['key'];
                    $isOn = ($selectedDuration === $key);
                    $extraClass = '';
                    if (!empty($meta['keep'])) {
                        $extraClass .= ' duration-card--keep';
                    }
                    if (!empty($meta['trial'])) {
                        $extraClass .= ' duration-card--trial';
                    }
                    if (!empty($meta['life'])) {
                        $extraClass .= ' duration-card--life';
                    }
                    if ($durationDisabled) {
                        $extraClass .= ' is-disabled';
                    }
                  ?>
                  <label class="duration-card<?php echo $isOn ? ' is-selected' : ''; ?><?php echo $extraClass; ?>"
                         data-duration="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>">
          <input type="radio"
                           name="duration"
                           value="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>"
                 <?php echo $isOn ? 'checked' : ''; ?>
                 <?php echo $durationDisabled ? 'disabled' : ''; ?>>
          <span class="duration-card__check" aria-hidden="true"><i class="fas fa-check"></i></span>
          <span class="duration-card__ico" aria-hidden="true"><i class="fas <?php echo $meta['icon']; ?>"></i></span>
          <span class="duration-card__value"><?php echo htmlspecialchars($meta['value']); ?></span>
          <span class="duration-card__label"><?php echo htmlspecialchars($meta['short']); ?></span>
        </label>
        <?php endforeach; ?>
      </div>
                <div class="trial-note<?php echo $selectedDuration === 'trial' ? ' is-visible' : ''; ?>" id="editDeviceTrialNote">
                  <i class="fas fa-info-circle"></i>
                  <span><?php echo htmlspecialchars(str_replace('@days', (string) $trialDays, t('add_device.duration_trial_hint'))); ?></span>
    </div>
  </div>

              <div class="status-grid mb-3" id="editDeviceStatusPicker" role="radiogroup" aria-label="<?php echo htmlspecialchars(t('edit_device.status'), ENT_QUOTES, 'UTF-8'); ?>">
                <?php foreach ($statusCards as $meta):
                  $key = (string) $meta['key'];
                  $isOn = ($currentStatus === $key);
                ?>
                <label class="status-card status-card--<?php echo htmlspecialchars($meta['tone']); ?><?php echo $isOn ? ' is-selected' : ''; ?><?php echo $canEditDevice ? '' : ' is-disabled'; ?>"
                       data-status="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>">
                  <input type="radio"
                         name="status"
                         value="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>"
                         <?php echo $isOn ? 'checked' : ''; ?>
                         <?php echo $canEditDevice ? '' : 'disabled'; ?>>
                  <span class="status-card__ico" aria-hidden="true"><i class="fas <?php echo $meta['icon']; ?>"></i></span>
                  <span class="status-card__label"><?php echo htmlspecialchars($meta['label']); ?></span>
                </label>
                <?php endforeach; ?>
      </div>

  <div>
                <span class="form-label d-block mb-1"><?php echo t('edit_device.status_preview'); ?></span>
                <span id="liveStatusBadge" class="status-badge-preview status-<?php echo htmlspecialchars($currentStatus); ?>">
                  <i class="fas <?php echo $statusIcons[$currentStatus] ?? 'fa-circle'; ?>"></i>
                  <?php echo t('status.' . $currentStatus); ?>
                </span>
    </div>
            </section>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-link"></i>
                  <?php echo t('edit_device.section_account'); ?>
                </h2>
      </div>
    <?php
              $ak = isset($device['account_key']) ? trim((string) $device['account_key']) : '';
              if ($ak !== ''):
              ?>
              <div class="account-box">
                <?php if ($accountDisplayName !== ''): ?>
                <div class="mb-2">
                  <div class="info-item__label"><i class="fas fa-tag"></i> <?php echo $lang === 'ar' ? 'اسم الحساب في التطبيق' : 'App account label'; ?></div>
                  <div class="info-item__value" style="color:#a5f3fc;"><?php echo htmlspecialchars($accountDisplayName); ?></div>
</div>
      <?php endif; ?>
                <div class="mb-2">
                  <div class="info-item__label"><i class="fas fa-user-circle"></i> <?php echo t('table.bound_account'); ?></div>
                  <div class="info-item__value field-mono" style="color:#38bdf8;"><?php echo htmlspecialchars(account_key_display_label($ak)); ?></div>
    </div>
                <?php if (!$isGuest && $codeHostStored !== ''): ?>
                <div class="mb-2">
                  <div class="info-item__label"><i class="fas fa-globe"></i> <?php echo $lang === 'ar' ? 'سيرفر مخصص من التطبيق' : 'Custom server from app'; ?></div>
                  <div class="info-item__value info-item__value--host"><?php echo htmlspecialchars($codeHostStored); ?></div>
  </div>
  <?php endif; ?>
                <span class="field-help"><?php echo t('table.account_bound_info'); ?></span>
</div>
              <?php else: ?>
              <div class="account-box account-box--empty">
                <i class="fas fa-unlink me-1"></i> <?php echo t('table.no_account'); ?>
              </div>
              <?php endif; ?>
            </section>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-sliders"></i>
                  <?php echo t('edit_device.section_options'); ?>
                </h2>
              </div>
              <div class="feature-toggle mb-3">
  <div>
                  <div class="feature-title">
                    <i class="fas fa-shield-halved feature-inline-icon"></i>
<?php echo t('add_device.block_vpn'); ?>
    </div>
                  <div class="feature-desc"><?php echo t('add_device.block_vpn_help'); ?></div>
  </div>
<div class="toggle-wrapper">
                  <span class="toggle-label off"><?php echo t('off'); ?></span>
<label class="toggle-switch">
                    <input type="checkbox" id="block_vpn" name="block_vpn" <?php echo !empty($device['block_vpn']) ? 'checked' : ''; ?>>
<span class="slider"></span>
</label>
                  <span class="toggle-label on"><?php echo t('on'); ?></span>
</div>
</div>
              <div class="feature-toggle mb-3">
                <div>
                  <div class="feature-title">
                    <i class="fas fa-ad feature-inline-icon"></i>
                    <?php echo t('edit_device.ads_enabled'); ?>
</div>
                  <div class="feature-desc"><?php echo t('edit_device.ads_enabled_help'); ?></div>
</div>
<div class="toggle-wrapper">
                  <span class="toggle-label off"><?php echo t('off'); ?></span>
<label class="toggle-switch">
                    <input type="checkbox" id="device_ads_enabled" name="device_ads_enabled"
                      <?php echo (!isset($device['ads_enabled']) || (int)$device['ads_enabled'] === 1) ? 'checked' : ''; ?>>
<span class="slider"></span>
</label>
                  <span class="toggle-label on"><?php echo t('on'); ?></span>
</div>
</div>
              <div>
                <label class="form-label" for="deviceNotesInput"><?php echo t('edit_device.notes'); ?></label>
                <textarea class="form-control"
                          id="deviceNotesInput"
                          name="notes"
                          rows="3"
                          placeholder="<?php echo $lang === 'ar' ? 'ملاحظات داخلية...' : 'Internal notes...'; ?>"><?php echo htmlspecialchars((string)($device['notes'] ?? '')); ?></textarea>
                <span class="field-help"><?php echo t('edit_device.notes_help'); ?></span>
</div>
            </section>

            <div class="form-actions">
              <button type="submit" class="btn-edit btn-edit-main">
                <span class="btn-edit__ico"><i class="fas fa-save"></i></span>
                <span><?php echo t('button.save_changes'); ?></span>
</button>
              <a href="<?php echo htmlspecialchars($homeUrl); ?>" class="btn-edit btn-edit-back">
                <span class="btn-edit__ico"><i class="fas fa-arrow-<?php echo $isRtl ? 'right' : 'left'; ?>"></i></span>
                <span><?php echo t('button.back'); ?></span>
              </a>
            </div>
</fieldset>
</form>
</div>
</div>
</div>
</div>

<div id="ed-toast-host" class="ed-toast-host" aria-live="polite" aria-relevant="additions"></div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>
<script>
const statusLabels = {
  active: <?php echo json_encode(t('status.active'), JSON_UNESCAPED_UNICODE); ?>,
  expired: <?php echo json_encode(t('status.expired'), JSON_UNESCAPED_UNICODE); ?>,
  blocked: <?php echo json_encode(t('status.blocked'), JSON_UNESCAPED_UNICODE); ?>
};
const statusIcons = {
  active: 'fa-check-circle',
  expired: 'fa-calendar-times',
  blocked: 'fa-lock'
};
const edToastCloseLabel = <?php echo json_encode(t('playlist_codes.toast_close'), JSON_UNESCAPED_UNICODE); ?>;
const edCancelLabel = <?php echo json_encode(t('delete.cancel_short'), JSON_UNESCAPED_UNICODE); ?>;
const edLoginToast = <?php echo json_encode($loginToast, JSON_UNESCAPED_UNICODE); ?>;

function edShowToast(message, ok) {
  var host = document.getElementById('ed-toast-host');
  if (!host || !message) return;
  var wrap = document.createElement('div');
  wrap.className = 'ed-toast ed-toast--' + (ok ? 'success' : 'error');
  wrap.setAttribute('role', ok ? 'status' : 'alert');

  var icon = document.createElement('div');
  icon.className = 'ed-toast__icon';
  icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-circle-exclamation') + '"></i>';

  var body = document.createElement('div');
  body.className = 'ed-toast__body';
  var p = document.createElement('p');
  p.className = 'ed-toast__text';
  p.textContent = message;
  body.appendChild(p);

  var btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'ed-toast__close';
  btn.setAttribute('aria-label', edToastCloseLabel || 'Close');
  btn.innerHTML = '<i class="fas fa-times" aria-hidden="true"></i>';

  wrap.appendChild(icon);
  wrap.appendChild(body);
  wrap.appendChild(btn);
  host.appendChild(wrap);

  var timer = null;
  var remove = function () {
    if (timer) clearTimeout(timer);
    wrap.classList.add('ed-toast--out');
    setTimeout(function () {
      if (wrap.parentNode) wrap.parentNode.removeChild(wrap);
    }, 280);
  };
  btn.addEventListener('click', remove);
  timer = setTimeout(remove, 4200);
}

(function () {
  if (edLoginToast && edLoginToast.message) {
    edShowToast(edLoginToast.message, !!edLoginToast.ok);
  }
})();

(function () {
  var form = document.getElementById('editDeviceForm');
  if (!form) return;
  var busy = false;

  function csrfToken() {
    var el = form.querySelector('input[name="csrf_token"], input[name="_csrf"], input[name="admin_csrf"]');
    return el ? el.value : '';
  }

  function removeLoginHistorySection() {
    var section = document.getElementById('loginHistorySection');
    if (!section) return;
    section.classList.add('is-removing');
    setTimeout(function () {
      if (section.parentNode) section.parentNode.removeChild(section);
    }, 260);
  }

  function removeSessionCard(sessionId) {
    var list = document.getElementById('loginHistoryList');
    var item = list
      ? list.querySelector('.login-history-item[data-session-id="' + String(sessionId) + '"]')
      : null;
    if (!item) {
      if (list && !list.querySelector('.login-history-item')) removeLoginHistorySection();
      return;
    }
    item.classList.add('is-removing');
    setTimeout(function () {
      if (item.parentNode) item.parentNode.removeChild(item);
      if (list && !list.querySelector('.login-history-item')) removeLoginHistorySection();
    }, 220);
  }

  function postLoginHistoryDelete(payload) {
    var body = new FormData();
    body.append('id', form.querySelector('input[name="id"]') ? form.querySelector('input[name="id"]').value : '');
    body.append('csrf_token', csrfToken());
    // Support alternate CSRF field names used by admin_csrf_field().
    var csrfEl = form.querySelector('input[name="csrf_token"], input[name="_csrf"], input[name="admin_csrf"]');
    if (csrfEl && csrfEl.name !== 'csrf_token') {
      body.append(csrfEl.name, csrfEl.value);
    }
    body.append('login_history_ajax', '1');
    if (payload.clear) {
      body.append('clear_login_history', '1');
    } else {
      body.append('delete_login_session_id', String(payload.sessionId || ''));
    }
    return fetch(window.location.href, {
      method: 'POST',
      body: body,
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' }
    }).then(function (res) {
      return res.json().then(function (data) {
        return { okHttp: res.ok, data: data || {} };
      }).catch(function () {
        return { okHttp: false, data: { success: false, message: 'Request failed' } };
      });
    });
  }

  document.querySelectorAll('.js-login-history-action').forEach(function (btn) {
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      if (busy) return;
      var action = btn.getAttribute('data-action') || '';
      var title = btn.getAttribute('data-confirm-title') || '';
      var message = btn.getAttribute('data-confirm-message') || '';
      var okText = btn.getAttribute('data-confirm-ok') || '';
      var sessionId = btn.getAttribute('data-session-id') || '';
      var run = function () {
        busy = true;
        btn.disabled = true;
        postLoginHistoryDelete({
          clear: action === 'clear',
          sessionId: sessionId
        }).then(function (result) {
          var data = result.data || {};
          var ok = !!(data.success);
          if (typeof edShowToast === 'function') {
            edShowToast(data.message || (ok ? 'OK' : 'Error'), ok);
          }
          if (ok) {
            if (data.cleared) {
              removeLoginHistorySection();
            } else {
              removeSessionCard(data.session_id || sessionId);
            }
          }
        }).catch(function () {
          if (typeof edShowToast === 'function') edShowToast('Request failed', false);
        }).finally(function () {
          busy = false;
          btn.disabled = false;
        });
      };

      if (typeof window.adminConfirm === 'function') {
        window.adminConfirm({
          title: title,
          message: message,
          confirmText: okText,
          cancelText: edCancelLabel,
          tone: 'danger',
          icon: 'fas fa-trash-can'
        }).then(function (ok) {
          if (ok) run();
        });
      } else if (window.confirm(message || title)) {
        run();
      }
    });
  });
})();

function syncStatusUI(status) {
  var picker = document.getElementById('editDeviceStatusPicker');
  if (!picker) return;
  picker.querySelectorAll('.status-card').forEach(function (card) {
    var on = card.getAttribute('data-status') === status;
    card.classList.toggle('is-selected', on);
    var input = card.querySelector('input[type="radio"]');
    if (input) input.checked = on;
  });
}

function updateLiveStatus() {
  var expiryStamp = document.getElementById('deviceExpiryStamp');
  var picker = document.getElementById('editDeviceStatusPicker');
  var badge = document.getElementById('liveStatusBadge');
  if (!picker || !badge) return;

  var selected = picker.querySelector('input[name="status"]:checked');
  var selectedVal = selected ? selected.value : 'active';
  var effective = selectedVal;

  if (selectedVal !== 'blocked') {
    var expiryVal = expiryStamp ? String(expiryStamp.value || '').trim() : '';
    var expiry = null;
    if (expiryVal) {
      expiry = new Date(expiryVal.indexOf('T') >= 0 ? expiryVal : expiryVal.replace(' ', 'T'));
    }
    var validExpiry = expiry && !isNaN(expiry.getTime());
    effective = (validExpiry && expiry.getTime() > Date.now()) ? 'active' : 'expired';
    syncStatusUI(effective);
  }

  badge.className = 'status-badge-preview status-' + effective;
  badge.innerHTML = '<i class="fas ' + statusIcons[effective] + '"></i> ' + statusLabels[effective];
}

(function () {
  var picker = document.getElementById('editDeviceStatusPicker');
  if (!picker) return;
  picker.querySelectorAll('.status-card').forEach(function (card) {
    card.addEventListener('click', function (e) {
      if (card.classList.contains('is-disabled')) return;
      e.preventDefault();
      picker.querySelectorAll('.status-card').forEach(function (c) {
        var on = c === card;
        c.classList.toggle('is-selected', on);
        var input = c.querySelector('input[type="radio"]');
        if (input) input.checked = on;
      });
  updateLiveStatus();
    });
  });
  updateLiveStatus();
})();

(function () {
  var deviceId = <?php echo (int) $id; ?>;
  if (!deviceId) return;
  var labels = {
    online: <?php echo json_encode(t('presence.online'), JSON_UNESCAPED_UNICODE); ?>,
    offline: <?php echo json_encode(t('presence.offline'), JSON_UNESCAPED_UNICODE); ?>,
    live: <?php echo json_encode(t('edit_device.watching_live'), JSON_UNESCAPED_UNICODE); ?>,
    movie: <?php echo json_encode(t('edit_device.watching_movie'), JSON_UNESCAPED_UNICODE); ?>,
    series: <?php echo json_encode(t('edit_device.watching_series'), JSON_UNESCAPED_UNICODE); ?>
  };
  var icons = { live: 'fa-tv', movie: 'fa-film', series: 'fa-clapperboard' };
  var url = 'api/device-live.php?id=' + encodeURIComponent(String(deviceId));
  var timer = null;
  var inFlight = false;

  function setHidden(el, hidden) {
    if (!el) return;
    if (hidden) el.setAttribute('hidden', '');
    else el.removeAttribute('hidden');
  }

  function applyLive(data) {
    if (!data || !data.success) return;
    var badge = document.getElementById('edPresenceBadge');
    var label = document.getElementById('edPresenceLabel');
    var lastWrap = document.getElementById('edLastSeenWrap');
    var lastVal = document.getElementById('edLastSeenValue');
    var active = document.getElementById('edWatchingActive');
    var idle = document.getElementById('edWatchingIdle');
    var wType = document.getElementById('edWatchingType');
    var wIcon = document.getElementById('edWatchingIcon');
    var wTitle = document.getElementById('edWatchingTitle');
    var wExtra = document.getElementById('edWatchingExtra');

    var online = !!data.online;
    if (badge) {
      badge.classList.toggle('presence-badge--online', online);
      badge.classList.toggle('presence-badge--offline', !online);
    }
    if (label) label.textContent = online ? labels.online : labels.offline;

    var fmt = (data.last_seen_fmt || '').trim();
    if (lastVal) lastVal.textContent = fmt;
    setHidden(lastWrap, fmt === '');

    var watching = data.watching;
    if (watching && watching.title) {
      var type = String(watching.type || '').toLowerCase();
      if (wType) wType.textContent = labels[type] || type;
      if (wIcon) wIcon.className = 'fas ' + (icons[type] || 'fa-tv');
      if (wTitle) wTitle.textContent = watching.title || '';
      var extra = (watching.extra || '').trim();
      if (wExtra) {
        wExtra.textContent = extra;
        setHidden(wExtra, extra === '');
      }
      setHidden(active, false);
      setHidden(idle, true);
    } else {
      setHidden(active, true);
      setHidden(idle, false);
    }
  }

  function tick() {
    if (inFlight) return;
    if (document.visibilityState === 'hidden') return;
    inFlight = true;
    fetch(url, {
      method: 'GET',
      credentials: 'same-origin',
      headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      cache: 'no-store'
    }).then(function (res) {
      return res.json();
    }).then(applyLive).catch(function () {
      // keep previous UI on network blips
    }).finally(function () {
      inFlight = false;
    });
  }

  function start() {
    if (timer) clearInterval(timer);
    timer = setInterval(tick, 15000);
  }

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') tick();
  });

  start();
})();

(function () {
  var btn = document.getElementById('editManualPassToggle');
  var inp = document.getElementById('editManualPassField');
  var icon = document.getElementById('editManualPassIcon');
  if (!btn || !inp || !icon) return;
  var labelShow = <?php echo json_encode($lang === 'ar' ? 'إظهار كلمة المرور' : 'Show password', JSON_UNESCAPED_UNICODE); ?>;
  var labelHide = <?php echo json_encode($lang === 'ar' ? 'إخفاء كلمة المرور' : 'Hide password', JSON_UNESCAPED_UNICODE); ?>;
  btn.addEventListener('click', function () {
    var show = inp.type === 'password';
    inp.type = show ? 'text' : 'password';
    icon.className = show ? 'fas fa-eye-slash' : 'fas fa-eye';
    btn.setAttribute('aria-label', show ? labelHide : labelShow);
  });
})();

(function () {
  var btn = document.getElementById('editDeviceIdCopyBtn');
  var input = document.getElementById('editDeviceIdInput');
  if (!btn) return;
  btn.addEventListener('click', function () {
    var v = (btn.getAttribute('data-copy') || (input ? input.value : '') || '').trim();
    if (!v) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(v);
    } else if (input) {
      input.select();
      document.execCommand('copy');
    }
  });
})();

(function () {
  var root = document.getElementById('editDeviceDurationPicker');
  var trialNote = document.getElementById('editDeviceTrialNote');
  if (!root) return;

  function syncTrialNote(card) {
    if (!trialNote) return;
    var key = card ? (card.getAttribute('data-duration') || '') : '';
    if (!key) {
      var checked = root.querySelector('input[name="duration"]:checked');
      key = checked ? checked.value : 'keep';
    }
    trialNote.classList.toggle('is-visible', key === 'trial');
  }

  root.querySelectorAll('.duration-card').forEach(function (card) {
    card.addEventListener('click', function (e) {
      if (card.classList.contains('is-disabled')) return;
          e.preventDefault();
      root.querySelectorAll('.duration-card').forEach(function (c) {
        var on = c === card;
        c.classList.toggle('is-selected', on);
        var input = c.querySelector('input[type="radio"]');
        if (input) input.checked = on;
      });
      syncTrialNote(card);
    });
  });
  syncTrialNote();
})();
</script>
</body>
</html>
