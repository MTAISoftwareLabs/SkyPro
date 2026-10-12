<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
require_once __DIR__ . '/includes/pagination.php';

$current_page = 'add_device';
$success = $error = '';
$canAddDevice = adminCan('devices_add');
$listPage = admin_request_list_page();
$homeUrl = admin_devices_home_url($listPage);
$panelSettings = getSettings($conn);
$trialDays = isset($panelSettings['default_expiry_days']) ? (int) $panelSettings['default_expiry_days'] : 30;
if ($trialDays <= 0) {
    $trialDays = 30;
}

$formDeviceName = '';
$formDeviceId = '';
$formCustomDomain = '';
$formBlockVpn = false;
$selectedDuration = '1';
$selectedStatus = 'active';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_require_csrf();
    if (!$canAddDevice) {
        header('Location: access_denied.php?perm=devices_add');
        exit;
    }
    $formDeviceId = trim((string) ($_POST['device_id'] ?? ''));
    $formDeviceName = trim((string) ($_POST['device_name'] ?? ''));
    $formCustomDomain = trim((string) ($_POST['custom_domain'] ?? ''));
    $formBlockVpn = isset($_POST['block_vpn']);
    $duration = strtolower(trim((string) ($_POST['duration'] ?? '')));
    $selectedDuration = $duration !== '' ? $duration : '1';
    $selectedStatus = strtolower(trim((string) ($_POST['status'] ?? 'active')));
    if (!in_array($selectedStatus, ['active', 'expired', 'blocked'], true)) {
        $selectedStatus = 'active';
    }

    $durationInfo = adminExpiryFromDurationChoice($conn, $duration);

    if ($formDeviceId === '') {
        $error = t('msg.required_fields');
    } elseif ($durationInfo === null) {
        $error = t('msg.duration_required');
    } else {
        try {
            if (addDevice(
                $conn,
                $formDeviceId,
                $durationInfo['expiry'],
                $formCustomDomain,
                $formDeviceName,
                $formBlockVpn ? 1 : 0,
                !empty($durationInfo['is_trial']),
                $selectedStatus
            )) {
                $success = t('msg.device_added');
                try {
                    logActivity(
                        $conn,
                        'add_device',
                        $formDeviceId,
                        !empty($durationInfo['is_trial'])
                            ? 'Added from admin panel (trial)'
                            : 'Added from admin panel'
                    );
                } catch (Throwable $e) {
                    // ignore
                }
                $formDeviceName = '';
                $formDeviceId = '';
                $formCustomDomain = '';
                $formBlockVpn = false;
                $selectedDuration = '1';
                $selectedStatus = 'active';
            } else {
                $error = t('msg.device_add_error');
            }
        } catch (PDOException $e) {
            if ((string) $e->getCode() === '23000') {
                $error = t('msg.device_exists');
            } else {
                $error = t('msg.db_error');
            }
        }
    }
}

$durationCards = [
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
$validDurationKeys = array_column($durationCards, 'key');
if (!in_array($selectedDuration, $validDurationKeys, true)) {
    $selectedDuration = '1';
}

$statusCards = [
    ['key' => 'active', 'icon' => 'fa-circle-check', 'label' => t('status.active'), 'tone' => 'ok'],
    ['key' => 'expired', 'icon' => 'fa-clock', 'label' => t('status.expired'), 'tone' => 'warn'],
    ['key' => 'blocked', 'icon' => 'fa-ban', 'label' => t('status.blocked'), 'tone' => 'bad'],
];
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?php echo t('add_device.title'); ?> - <?php echo t('app.title'); ?></title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap" rel="stylesheet">
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

.add-shell{
  max-width:920px;
  margin:0 auto;
  width:100%;
}
.add-hero{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:14px;
  margin-bottom:16px;
}
.add-hero__text{ min-width:0; flex:1; }
.add-hero h1{
  margin:0;
  font-size:clamp(1.15rem, 4vw, 1.4rem);
  font-weight:800;
  color:#f8fafc;
  display:flex;
  align-items:center;
  gap:10px;
  line-height:1.25;
}
.add-hero h1 i{
  color:#38bdf8;
  flex-shrink:0;
}
.add-hero p{
  margin:8px 0 0;
  color:#94a3b8;
  font-size:0.88rem;
  max-width:560px;
  line-height:1.55;
}
.add-card{
  border-radius:20px;
  background:linear-gradient(160deg,#0f172a 0%,#020617 100%);
  border:1px solid rgba(148,163,184,0.22);
  box-shadow:0 18px 40px rgba(0,0,0,.35);
  overflow:hidden;
}
.add-card__body{ padding:clamp(14px, 3vw, 24px); }

.form-section{
  border:1px solid rgba(148,163,184,0.16);
  background:rgba(15,23,42,.55);
  border-radius:16px;
  padding:16px;
  margin-bottom:16px;
}
.form-section:last-of-type{ margin-bottom:0; }
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
.form-select option{ background:#0f172a; color:#e5e7eb; }
.field-help{
  display:block;
  margin-top:6px;
  font-size:0.72rem;
  color:#64748b;
}

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
  border-color:rgba(59,130,246,.5);
  transform:translateY(-1px);
}
.duration-card.is-selected{
  border-color:#3b82f6;
  background:rgba(37,99,235,.12);
  box-shadow:0 0 0 1px rgba(59,130,246,.35);
}
.duration-card--trial{ border-color:rgba(34,197,94,.28); }
.duration-card--trial .duration-card__value{ color:#4ade80; }
.duration-card--trial.is-selected{
  border-color:#22c55e;
  background:rgba(34,197,94,.12);
  box-shadow:0 0 0 1px rgba(34,197,94,.35);
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
  width:18px;
  height:18px;
  border-radius:999px;
  display:flex;
  align-items:center;
  justify-content:center;
  font-size:10px;
  color:#fff;
  background:#3b82f6;
  opacity:0;
  transform:scale(.7);
  transition:opacity .15s ease, transform .15s ease;
}
.duration-card--trial.is-selected .duration-card__check{ background:#22c55e; }
.duration-card--life.is-selected .duration-card__check{ background:#f59e0b; }
.duration-card.is-selected .duration-card__check{ opacity:1; transform:scale(1); }
.duration-card__ico{
  width:28px;
  height:28px;
  border-radius:9px;
  display:flex;
  align-items:center;
  justify-content:center;
  background:rgba(59,130,246,.14);
  color:#93c5fd;
  font-size:13px;
}
.duration-card.is-selected .duration-card__ico{
  background:rgba(59,130,246,.28);
  color:#fff;
}
.duration-card--trial .duration-card__ico{
  background:rgba(34,197,94,.14);
  color:#86efac;
}
.duration-card__value{
  font-size:1.1rem;
  font-weight:800;
  color:#e2e8f0;
  line-height:1.1;
}
.duration-card__label{
  font-size:0.72rem;
  color:#94a3b8;
  text-align:center;
  line-height:1.25;
}
.trial-note{
  margin-top:12px;
  padding:10px 12px;
  border-radius:12px;
  background:rgba(34,197,94,.08);
  border:1px solid rgba(34,197,94,.22);
  color:#bbf7d0;
  font-size:0.78rem;
  display:none;
  align-items:flex-start;
  gap:8px;
  line-height:1.45;
}
.trial-note.is-visible{ display:flex; }
.trial-note i{ margin-top:2px; color:#4ade80; }

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
  display:flex;
  align-items:center;
  gap:12px;
  min-height:64px;
  padding:12px 14px;
  border-radius:14px;
  cursor:pointer;
  user-select:none;
  background:rgba(2,6,23,.75);
  border:1px solid rgba(148,163,184,0.24);
  transition:border-color .18s ease, background .18s ease, box-shadow .18s ease;
}
.status-card input{ position:absolute; opacity:0; pointer-events:none; }
.status-card__ico{
  width:36px;
  height:36px;
  border-radius:11px;
  display:flex;
  align-items:center;
  justify-content:center;
  flex-shrink:0;
}
.status-card__label{
  font-weight:800;
  font-size:0.92rem;
  color:#e2e8f0;
}
.status-card--ok .status-card__ico{ background:rgba(34,197,94,.14); color:#4ade80; }
.status-card--warn .status-card__ico{ background:rgba(251,191,36,.14); color:#fbbf24; }
.status-card--bad .status-card__ico{ background:rgba(239,68,68,.14); color:#f87171; }
.status-card.is-selected.status-card--ok{
  border-color:#22c55e;
  background:rgba(34,197,94,.1);
  box-shadow:0 0 0 1px rgba(34,197,94,.28);
}
.status-card.is-selected.status-card--warn{
  border-color:#f59e0b;
  background:rgba(245,158,11,.1);
  box-shadow:0 0 0 1px rgba(245,158,11,.28);
}
.status-card.is-selected.status-card--bad{
  border-color:#ef4444;
  background:rgba(239,68,68,.1);
  box-shadow:0 0 0 1px rgba(239,68,68,.28);
}
.status-card.is-disabled{ opacity:.55; pointer-events:none; }

.feature-toggle{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:14px;
  padding:14px 16px;
  border-radius:14px;
  background:rgba(2,6,23,.65);
  border:1px solid rgba(148,163,184,0.24);
}
.feature-toggle > div:first-child{ min-width:0; flex:1; }
.feature-title{
  display:flex;
  align-items:center;
  gap:8px;
  font-weight:800;
  color:#e2e8f0;
}
.feature-inline-icon{ color:#38bdf8; }
.feature-desc{
  margin-top:4px;
  font-size:0.78rem;
  color:#94a3b8;
  line-height:1.45;
}
.toggle-wrapper{
  display:flex;
  align-items:center;
  gap:8px;
  font-size:12px;
  font-weight:700;
  flex-shrink:0;
}
.toggle-label.off{ color:#ef4444; }
.toggle-label.on{ color:#22c55e; }
.toggle-switch{
  position:relative;
  display:inline-block;
  width:52px;
  height:26px;
}
.toggle-switch input{ display:none; }
.slider{
  position:absolute;
  inset:0;
  background:#ef4444;
  border-radius:40px;
  transition:all .3s ease;
  box-shadow:inset 0 0 6px rgba(0,0,0,.35);
}
.slider:before{
  content:"";
  position:absolute;
  height:20px;
  width:20px;
  left:3px;
  bottom:3px;
  background:#fff;
  border-radius:50%;
  transition:all .3s ease;
}
.toggle-switch input:checked + .slider{
  background:#22c55e;
}
.toggle-switch input:checked + .slider:before{
  transform:translateX(26px);
}
[dir="rtl"] .toggle-wrapper{ flex-direction:row-reverse; }

.form-actions{
  display:flex;
  align-items:center;
  justify-content:center;
  flex-wrap:wrap;
  gap:12px;
  margin-top:20px;
  padding-top:16px;
  border-top:1px solid rgba(148,163,184,0.14);
  direction:ltr;
}
.btn-add{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  gap:8px;
  min-height:48px;
  padding:0 22px;
  border-radius:999px;
  font-weight:800;
  font-size:0.92rem;
  letter-spacing:0.01em;
  text-decoration:none;
  border:1px solid transparent;
  transition:transform .18s ease, box-shadow .18s ease, filter .18s ease, background .18s ease, border-color .18s ease, color .18s ease;
  -webkit-tap-highlight-color:transparent;
  touch-action:manipulation;
}
.btn-add:focus-visible{
  outline:2px solid #38bdf8;
  outline-offset:2px;
}
.btn-add__ico{
  width:28px;
  height:28px;
  border-radius:999px;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  font-size:0.82rem;
  flex-shrink:0;
}
.btn-add-main{
  color:#fff !important;
  background:linear-gradient(135deg,#0ea5e9 0%,#2563eb 55%,#4f46e5 100%);
  box-shadow:0 12px 28px rgba(37,99,235,.32);
  min-width:180px;
}
.btn-add-main .btn-add__ico{
  background:rgba(255,255,255,.18);
  color:#fff;
}
.btn-add-main:hover{
  color:#fff !important;
  filter:brightness(1.06);
  transform:translateY(-1px);
  box-shadow:0 16px 32px rgba(37,99,235,.4);
}
.btn-add-main:active{
  transform:translateY(0);
  filter:brightness(.98);
}
.btn-add-back{
  color:#e2e8f0 !important;
  background:rgba(15,23,42,.9);
  border-color:rgba(148,163,184,0.28);
  box-shadow:0 6px 16px rgba(0,0,0,.22);
  min-width:132px;
}
.btn-add-back .btn-add__ico{
  background:rgba(148,163,184,.14);
  color:#93c5fd;
}
.btn-add-back:hover{
  color:#fff !important;
  background:#1e293b;
  border-color:rgba(148,163,184,0.45);
  transform:translateY(-1px);
}
.btn-add-back:active{
  transform:translateY(0);
}
.alert{
  border-radius:12px;
  border:0;
}

@media (max-width:640px){
  .add-hero{
    margin-bottom:12px;
  }
  .add-hero p{
    font-size:0.82rem;
  }
  .form-section{
    padding:14px;
    border-radius:14px;
  }
  .form-section__head{
    flex-direction:column;
    align-items:flex-start;
    gap:6px;
  }
  .feature-toggle{
    flex-direction:column;
    align-items:stretch;
  }
  .toggle-wrapper{
    justify-content:flex-end;
    align-self:flex-end;
  }
  .form-actions{
    display:grid;
    grid-template-columns:minmax(0,1fr) minmax(0,1.35fr);
    gap:10px;
    position:sticky;
    bottom:0;
    z-index:20;
    margin:18px -14px -14px;
    padding:12px 14px calc(12px + env(safe-area-inset-bottom, 0px));
    border-top:1px solid rgba(148,163,184,0.18);
    background:linear-gradient(180deg, rgba(2,6,23,.72), rgba(2,6,23,.96) 28%);
    backdrop-filter:blur(10px);
    -webkit-backdrop-filter:blur(10px);
  }
  .form-actions .btn-add-back{ order:1; }
  .form-actions .btn-add-main{ order:2; }
  .btn-add{
    width:100%;
    min-height:50px;
    padding:0 12px;
    font-size:0.86rem;
    white-space:nowrap;
  }
  .btn-add__ico{
    width:24px;
    height:24px;
    font-size:0.75rem;
  }
  .btn-add-main,
  .btn-add-back{
    min-width:0;
  }
  .duration-card{
    min-height:82px;
  }
  .status-card{
    min-height:58px;
  }
}
</style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container mt-4 admin-main">
  <div class="add-shell">
    <div class="add-hero">
      <div class="add-hero__text">
        <h1><i class="fas fa-mobile-alt"></i> <?php echo t('add_device.title'); ?></h1>
        <p><?php echo t('add_device.subtitle'); ?></p>
      </div>
    </div>

    <div class="add-card">
      <div class="add-card__body">
        <?php if ($success): ?>
        <div class="alert alert-success"><?php echo htmlspecialchars($success); ?></div>
        <?php endif; ?>
        <?php if ($error): ?>
        <div class="alert alert-danger"><?php echo htmlspecialchars($error); ?></div>
        <?php endif; ?>

        <form method="POST" data-admin-perm="devices_add">
          <?php if ($listPage > 1): ?>
          <input type="hidden" name="page" value="<?php echo (int) $listPage; ?>">
          <?php endif; ?>
          <?php if (!$canAddDevice): ?>
          <?php require_once __DIR__ . '/includes/view_only_banner.php'; ?>
          <?php endif; ?>

          <fieldset <?php echo $canAddDevice ? '' : 'disabled'; ?> style="border:0;padding:0;margin:0;min-width:0;">

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-id-card"></i>
                  <?php echo t('add_device.section_device'); ?>
                </h2>
              </div>
              <div class="row g-3">
                <div class="col-md-6">
                  <label class="form-label" for="deviceNameInput"><?php echo t('add_device.device_name'); ?></label>
                  <input type="text"
                         class="form-control"
                         id="deviceNameInput"
                         name="device_name"
                         value="<?php echo htmlspecialchars($formDeviceName); ?>"
                         placeholder="<?php echo $lang === 'ar' ? 'مثال: غرفة المعيشة' : 'e.g. Living room TV'; ?>">
                  <span class="field-help"><?php echo t('add_device.device_name_help'); ?></span>
                </div>
                <div class="col-md-6">
                  <label class="form-label" for="deviceIdInput"><?php echo t('add_device.device_id'); ?></label>
                  <input type="text"
                         class="form-control"
                         id="deviceIdInput"
                         name="device_id"
                         required
                         value="<?php echo htmlspecialchars($formDeviceId); ?>"
                         style="font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700;letter-spacing:.3px;">
                </div>
                <div class="col-12">
                  <label class="form-label" for="customDomainInput"><?php echo t('add_device.custom_domain'); ?></label>
                  <input type="text"
                         class="form-control"
                         id="customDomainInput"
                         name="custom_domain"
                         value="<?php echo htmlspecialchars($formCustomDomain); ?>"
                         placeholder="https://...">
                  <span class="field-help"><?php echo t('add_device.custom_domain_help'); ?></span>
                </div>
              </div>
            </section>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-hourglass-half"></i>
                  <?php echo t('add_device.duration'); ?>
                </h2>
                <p class="form-section__hint"><?php echo t('add_device.duration_hint'); ?></p>
              </div>
              <div class="duration-picker" id="addDeviceDurationPicker">
                <div class="duration-grid" role="radiogroup" aria-label="<?php echo htmlspecialchars(t('add_device.duration'), ENT_QUOTES, 'UTF-8'); ?>">
                  <?php foreach ($durationCards as $meta):
                    $key = (string) $meta['key'];
                    $isOn = ($selectedDuration === $key);
                    $extraClass = '';
                    if (!empty($meta['trial'])) {
                        $extraClass .= ' duration-card--trial';
                    }
                    if (!empty($meta['life'])) {
                        $extraClass .= ' duration-card--life';
                    }
                    if (!$canAddDevice) {
                        $extraClass .= ' is-disabled';
                    }
                  ?>
                  <label class="duration-card<?php echo $isOn ? ' is-selected' : ''; ?><?php echo $extraClass; ?>"
                         data-duration="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>">
                    <input type="radio"
                           name="duration"
                           value="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>"
                           <?php echo $isOn ? 'checked' : ''; ?>
                           <?php echo $canAddDevice ? '' : 'disabled'; ?>
                           required>
                    <span class="duration-card__check" aria-hidden="true"><i class="fas fa-check"></i></span>
                    <span class="duration-card__ico" aria-hidden="true"><i class="fas <?php echo $meta['icon']; ?>"></i></span>
                    <span class="duration-card__value"><?php echo htmlspecialchars($meta['value']); ?></span>
                    <span class="duration-card__label"><?php echo htmlspecialchars($meta['short']); ?></span>
                  </label>
                  <?php endforeach; ?>
                </div>
                <div class="trial-note<?php echo $selectedDuration === 'trial' ? ' is-visible' : ''; ?>" id="addDeviceTrialNote">
                  <i class="fas fa-info-circle"></i>
                  <span><?php echo htmlspecialchars(str_replace('@days', (string) $trialDays, t('add_device.duration_trial_hint'))); ?></span>
                </div>
              </div>
            </section>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-toggle-on"></i>
                  <?php echo t('add_device.status'); ?>
                </h2>
                <p class="form-section__hint"><?php echo t('add_device.status_hint'); ?></p>
              </div>
              <div class="status-grid" id="addDeviceStatusPicker" role="radiogroup" aria-label="<?php echo htmlspecialchars(t('add_device.status'), ENT_QUOTES, 'UTF-8'); ?>">
                <?php foreach ($statusCards as $meta):
                  $key = (string) $meta['key'];
                  $isOn = ($selectedStatus === $key);
                ?>
                <label class="status-card status-card--<?php echo htmlspecialchars($meta['tone']); ?><?php echo $isOn ? ' is-selected' : ''; ?><?php echo $canAddDevice ? '' : ' is-disabled'; ?>"
                       data-status="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>">
                  <input type="radio"
                         name="status"
                         value="<?php echo htmlspecialchars($key, ENT_QUOTES, 'UTF-8'); ?>"
                         <?php echo $isOn ? 'checked' : ''; ?>
                         <?php echo $canAddDevice ? '' : 'disabled'; ?>
                         required>
                  <span class="status-card__ico" aria-hidden="true"><i class="fas <?php echo $meta['icon']; ?>"></i></span>
                  <span class="status-card__label"><?php echo htmlspecialchars($meta['label']); ?></span>
                </label>
                <?php endforeach; ?>
              </div>
            </section>

            <section class="form-section">
              <div class="form-section__head">
                <h2 class="form-section__title">
                  <i class="fas fa-shield-alt"></i>
                  <?php echo t('add_device.section_options'); ?>
                </h2>
              </div>
              <div class="feature-toggle">
                <div>
                  <div class="feature-title">
                    <i class="fas fa-shield-alt feature-inline-icon"></i>
                    <?php echo t('add_device.block_vpn'); ?>
                  </div>
                  <div class="feature-desc"><?php echo t('add_device.block_vpn_help'); ?></div>
                </div>
                <div class="toggle-wrapper">
                  <span class="toggle-label off"><?php echo t('off'); ?></span>
                  <label class="toggle-switch">
                    <input type="checkbox" name="block_vpn" <?php echo $formBlockVpn ? 'checked' : ''; ?>>
                    <span class="slider"></span>
                  </label>
                  <span class="toggle-label on"><?php echo t('on'); ?></span>
                </div>
              </div>
            </section>

            <div class="form-actions">
              <button type="submit" class="btn-add btn-add-main">
                <span class="btn-add__ico"><i class="fas fa-plus"></i></span>
                <span><?php echo t('button.add_device'); ?></span>
              </button>
              <a href="<?php echo htmlspecialchars($homeUrl); ?>" class="btn-add btn-add-back">
                <span class="btn-add__ico"><i class="fas fa-arrow-<?php echo $isRtl ? 'right' : 'left'; ?>"></i></span>
                <span><?php echo t('button.back'); ?></span>
              </a>
            </div>
          </fieldset>
        </form>
      </div>
    </div>
  </div>
</div>

<?php require_once 'includes/footer.php'; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
(function () {
  function bindPicker(rootId, cardSel, onChange) {
    var root = document.getElementById(rootId);
    if (!root) return;
    root.querySelectorAll(cardSel).forEach(function (card) {
      card.addEventListener('click', function (e) {
        if (card.classList.contains('is-disabled')) return;
        e.preventDefault();
        root.querySelectorAll(cardSel).forEach(function (c) {
          var on = c === card;
          c.classList.toggle('is-selected', on);
          var input = c.querySelector('input[type="radio"]');
          if (input) input.checked = on;
        });
        if (typeof onChange === 'function') onChange(card);
      });
    });
  }

  var trialNote = document.getElementById('addDeviceTrialNote');
  function syncTrialNote(card) {
    if (!trialNote) return;
    var key = card ? (card.getAttribute('data-duration') || '') : '';
    if (!key) {
      var checked = document.querySelector('#addDeviceDurationPicker input[name="duration"]:checked');
      key = checked ? checked.value : '';
    }
    trialNote.classList.toggle('is-visible', key === 'trial');
  }

  bindPicker('addDeviceDurationPicker', '.duration-card', syncTrialNote);
  bindPicker('addDeviceStatusPicker', '.status-card');
  syncTrialNote();
})();
</script>
</body>
</html>
