<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

$current_page = 'index';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
require_once __DIR__ . '/includes/credential_crypto.php';
require_once __DIR__ . '/includes/pagination.php';
require_once __DIR__ . '/includes/devices_table_row.php';
$searchQuery = trim((string)($_GET['q'] ?? $_GET['search'] ?? ''));
$devices = getActivatedDevices($conn, $searchQuery);
$expiringSoonCount = getExpiringSoonDevicesCount($conn, 7);
$isGuest = adminIsGuestRole();
?>

<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">

<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title><?php echo t('app.title'); ?></title>

<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap" rel="stylesheet">

<style>

body{
font-family:'Cairo',sans-serif;
background:#020617;
color:#e5e7eb;
}

.admin-main{
min-height:calc(100vh - 160px);
}

/* cards */

.stats-card{
border-radius:18px;
padding:22px;
background:linear-gradient(145deg,#0f172a,#020617);
border:1px solid rgba(148,163,184,0.25);
text-align:center;
transition:.3s;
height:100%;
}

.stats-card:hover{
transform:translateY(-5px);
box-shadow:0 20px 40px rgba(0,0,0,.6);
}

.stats-number{
font-size:28px;
font-weight:700;
}

.quick-connected-btn{
display:inline-flex;
align-items:center;
justify-content:center;
gap:8px;
width:100%;
margin-top:12px;
padding:10px 14px;
border-radius:999px;
text-decoration:none;
font-weight:700;
font-size:.85rem;
color:#e2e8f0;
background:linear-gradient(135deg, rgba(14,165,233,.28), rgba(99,102,241,.24));
border:1px solid rgba(56,189,248,.45);
box-shadow:0 10px 24px rgba(2,6,23,.5);
transition:.2s;
cursor:pointer;
}

.quick-connected-btn:hover{
transform:translateY(-1px);
color:#ffffff;
border-color:rgba(56,189,248,.75);
box-shadow:0 14px 28px rgba(56,189,248,.22);
}

.quick-connected-btn.active{
color:#ffffff;
border-color:rgba(56,189,248,.95);
box-shadow:0 14px 28px rgba(56,189,248,.35);
}

#devicesLiveToast{
position:fixed;
bottom:22px;
right:22px;
z-index:1080;
max-width:min(92vw,360px);
padding:12px 16px;
border-radius:14px;
background:linear-gradient(135deg,rgba(14,165,233,.95),rgba(99,102,241,.92));
color:#fff;
font-weight:700;
box-shadow:0 16px 40px rgba(2,6,23,.45);
opacity:0;
transform:translateY(12px);
pointer-events:none;
transition:opacity .25s ease,transform .25s ease;
}
#devicesLiveToast.is-visible{
opacity:1;
transform:translateY(0);
}
[dir="rtl"] #devicesLiveToast{right:auto;left:22px;}
tr.device-row-new td{
animation:deviceRowFlash 2.4s ease;
}
@keyframes deviceRowFlash{
0%{background:rgba(56,189,248,.28);}
100%{background:transparent;}
}

/* First-setup welcome toast */
.setup-welcome{
position:relative;
margin:18px auto 0;
max-width:920px;
border-radius:22px;
overflow:hidden;
background:
radial-gradient(circle at 0% 0%, rgba(34,197,94,.22), transparent 42%),
radial-gradient(circle at 100% 0%, rgba(56,189,248,.18), transparent 40%),
linear-gradient(145deg, rgba(15,23,42,.98), rgba(2,6,23,.99));
border:1px solid rgba(148,163,184,.28);
box-shadow:0 24px 60px rgba(2,6,23,.55), 0 0 0 1px rgba(34,197,94,.12);
animation:setupWelcomeIn .55s cubic-bezier(.22,1,.36,1) both;
}
.setup-welcome::before{
content:"";
position:absolute;
inset:0 auto 0 0;
width:4px;
background:linear-gradient(180deg,#22c55e,#38bdf8);
}
[dir="rtl"] .setup-welcome::before{
inset:0 0 0 auto;
}
.setup-welcome__inner{
display:flex;
align-items:flex-start;
gap:16px;
padding:18px 18px 16px 20px;
}
.setup-welcome__badge{
flex:0 0 auto;
width:54px;
height:54px;
border-radius:18px;
display:inline-flex;
align-items:center;
justify-content:center;
background:linear-gradient(145deg, rgba(34,197,94,.35), rgba(56,189,248,.22));
border:1px solid rgba(74,222,128,.45);
color:#bbf7d0;
font-size:1.35rem;
box-shadow:0 10px 24px rgba(34,197,94,.18);
}
.setup-welcome__content{flex:1 1 auto;min-width:0;}
.setup-welcome__title{
margin:0 0 6px;
font-size:1.15rem;
font-weight:800;
color:#f8fafc;
letter-spacing:.01em;
}
.setup-welcome__body{
margin:0 0 12px;
color:#cbd5e1;
font-size:.92rem;
line-height:1.55;
}
.setup-welcome__chips{
display:flex;
flex-wrap:wrap;
gap:8px;
margin-bottom:14px;
}
.setup-welcome__chip{
display:inline-flex;
align-items:center;
gap:7px;
padding:7px 12px;
border-radius:999px;
font-size:.78rem;
font-weight:700;
color:#e2e8f0;
background:rgba(15,23,42,.88);
border:1px solid rgba(148,163,184,.28);
}
.setup-welcome__chip i{color:#38bdf8;}
.setup-welcome__chip--ok i{color:#4ade80;}
.setup-welcome__actions{
display:flex;
flex-wrap:wrap;
gap:10px;
align-items:center;
}
.setup-welcome__btn{
display:inline-flex;
align-items:center;
gap:8px;
padding:9px 16px;
border-radius:999px;
font-weight:700;
font-size:.86rem;
text-decoration:none !important;
border:none;
cursor:pointer;
font-family:inherit;
transition:transform .15s ease, box-shadow .15s ease, filter .15s ease;
}
.setup-welcome__btn:hover{transform:translateY(-1px);}
.setup-welcome__btn--primary{
color:#04111f !important;
background:linear-gradient(135deg,#38bdf8,#6366f1);
box-shadow:0 10px 22px rgba(56,189,248,.28);
}
.setup-welcome__btn--ghost{
color:#e2e8f0 !important;
background:rgba(30,41,59,.85);
border:1px solid rgba(148,163,184,.35);
}
.setup-welcome__close{
position:absolute;
top:12px;
inset-inline-end:12px;
width:34px;
height:34px;
border-radius:999px;
border:1px solid rgba(148,163,184,.3);
background:rgba(15,23,42,.75);
color:#94a3b8;
display:inline-flex;
align-items:center;
justify-content:center;
cursor:pointer;
transition:.15s ease;
}
.setup-welcome__close:hover{
color:#fff;
border-color:rgba(248,250,252,.35);
background:rgba(51,65,85,.9);
}
@keyframes setupWelcomeIn{
from{opacity:0;transform:translateY(-14px) scale(.98);}
to{opacity:1;transform:translateY(0) scale(1);}
}
@media (max-width:575.98px){
.setup-welcome__inner{padding:16px 14px 14px;}
.setup-welcome__badge{width:46px;height:46px;border-radius:14px;font-size:1.15rem;}
.setup-welcome__title{font-size:1.02rem;}
}

/* filter */

.filter-bar{
display:flex;
align-items:center;
gap:12px;
flex-wrap:wrap;
margin-bottom:18px;
}

.filter-pills{
display:flex;
align-items:center;
gap:10px;
flex-wrap:wrap;
}

.filter-btn{
padding:6px 16px;
border-radius:999px;
border:1px solid #334155;
background:#020617;
color:white;
cursor:pointer;
transition: background .18s ease, border-color .18s ease, box-shadow .18s ease;
}

.filter-btn.active{
background:#2563eb;
}

.filter-btn-group{
margin-inline-start:auto;
border-color:#1e40af !important;
display:flex;
align-items:center;
gap:6px;
white-space:nowrap;
}

/* Device ID search */
.device-id-search{
flex:1 1 240px;
min-width:200px;
max-width:360px;
position:relative;
}

.device-id-search__field{
width:100%;
display:flex;
align-items:center;
gap:10px;
padding:7px 12px 7px 14px;
border-radius:14px;
background:linear-gradient(180deg, rgba(15,23,42,.95), rgba(2,6,23,.98));
border:1px solid rgba(148,163,184,.28);
box-shadow:
  0 0 0 1px rgba(15,23,42,.4) inset,
  0 8px 22px rgba(0,0,0,.22);
transition: border-color .2s ease, box-shadow .2s ease;
}

.device-id-search__field:focus-within{
border-color:rgba(56,189,248,.7);
box-shadow:
  0 0 0 1px rgba(56,189,248,.2) inset,
  0 0 0 3px rgba(56,189,248,.14),
  0 10px 26px rgba(14,165,233,.18);
}

.device-id-search__icon{
color:#38bdf8;
font-size:.95rem;
opacity:.9;
flex-shrink:0;
}

.device-id-search__input{
flex:1;
min-width:0;
border:0;
outline:none;
background:transparent;
color:#f1f5f9;
font-size:.9rem;
font-weight:600;
font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
letter-spacing:.02em;
}

.device-id-search__input::placeholder{
color:#64748b;
font-weight:500;
font-family:inherit;
letter-spacing:0;
}

.device-id-search__clear{
display:none;
width:28px;
height:28px;
border:0;
border-radius:9px;
background:rgba(148,163,184,.12);
color:#94a3b8;
cursor:pointer;
align-items:center;
justify-content:center;
flex-shrink:0;
transition: background .15s ease, color .15s ease;
}

.device-id-search__clear.is-visible{
display:inline-flex;
}

.device-id-search__clear:hover{
background:rgba(239,68,68,.18);
color:#fca5a5;
}

/* table */

.table{
color:#e5e7eb;
}

/* prevent horizontal scrollbar by forcing a fixed table layout */
#devicesTable{
    table-layout: fixed;
    width: 100%;
}
#devicesTable td, #devicesTable th{
    padding: 0.65rem 0.5rem !important;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
#devicesTable th:nth-child(3),
#devicesTable td:nth-child(3){
    width: 16%;
    max-width: 220px;
}
.device-id-pill{
    display: inline-block;
    max-width: 100%;
    width: auto;
    box-sizing: border-box;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    vertical-align: middle;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.78rem;
    line-height: 1.35;
    padding: 0.28rem 0.55rem;
    border-radius: 8px;
    background: rgba(15,23,42,0.92);
    color: #cbd5e1;
    border: 1px solid rgba(148,163,184,0.28);
}

.table thead th{
letter-spacing:0.5px;
background:#0f172a;
color:#ffffff;
font-weight:700;
font-size:15px;
border-bottom:2px solid #475569;
white-space:nowrap;
}

.table tbody tr:hover{
background:#1e293b;
}

/* online row */

.row-online{
background:rgba(34,197,94,.15)!important;
}

/* status */

.status-badge{
padding:5px 12px;
border-radius:999px;
font-size:.82rem;
font-weight:700;
}

.active{
background:#16a34a;
color:white;
}

.expired{
background:#b91c1c;
color:white;
}

.blocked{
background:#475569;
color:white;
}

/* buttons */

.btn-action{
border-radius:999px;
padding:6px 12px;
border:none;
font-size:.85rem;
}

.btn-edit{
background:linear-gradient(135deg,#38bdf8,#6366f1);
color:white;
}

.btn-delete{
background:linear-gradient(135deg,#f97373,#ef4444);
color:white;
}

/* Bulk delete modal — solid readable surface */
#bulkDeleteModal .modal-content{
background:#0b1220 !important;
background-image:linear-gradient(180deg,#111827 0%,#0b1220 100%) !important;
color:#f1f5f9 !important;
border:1px solid rgba(148,163,184,.3) !important;
}
#bulkDeleteModal .modal-body,
#bulkDeleteModal .modal-header,
#bulkDeleteModal .modal-footer{
background:transparent;
color:#f1f5f9;
}
#bulkDeleteModal .modal-body > div:first-child{
color:#e2e8f0;
opacity:1 !important;
}
#bulkDeleteModal .modal-body .mt-3.p-3{
background:#3f1212 !important;
border-color:rgba(248,113,113,.45) !important;
color:#fecaca !important;
}

/* responsive fixes */

@media (max-width:768px){

.stats-number{
font-size:22px;
}

.stats-card{
padding:16px;
}

}

</style>

</head>

<body>

<?php require_once 'includes/header.php'; ?>

<?php if (!empty($_GET['forbidden'])): ?>
<div class="container admin-main pt-0">
    <div class="alert alert-warning shadow-sm border-0"><?php echo t('admin.forbidden'); ?></div>
</div>
<?php endif; ?>

<?php if (isset($_GET['setup']) && $_GET['setup'] === '1'): ?>
<div class="container admin-main pt-0" id="setupWelcomeWrap">
  <div class="setup-welcome" role="status" aria-live="polite">
    <button type="button" class="setup-welcome__close" id="setupWelcomeClose" aria-label="<?php echo htmlspecialchars(t('msg.setup_welcome_dismiss'), ENT_QUOTES, 'UTF-8'); ?>">
      <i class="fas fa-times" aria-hidden="true"></i>
    </button>
    <div class="setup-welcome__inner">
      <div class="setup-welcome__badge" aria-hidden="true">
        <i class="fas fa-shield-alt"></i>
      </div>
      <div class="setup-welcome__content">
        <h3 class="setup-welcome__title"><?php echo htmlspecialchars(t('msg.setup_welcome_title'), ENT_QUOTES, 'UTF-8'); ?></h3>
        <p class="setup-welcome__body"><?php echo htmlspecialchars(t('msg.setup_welcome_body'), ENT_QUOTES, 'UTF-8'); ?></p>
        <div class="setup-welcome__chips">
          <span class="setup-welcome__chip setup-welcome__chip--ok">
            <i class="fas fa-user-shield" aria-hidden="true"></i>
            <?php echo htmlspecialchars(t('msg.setup_welcome_chip_admin'), ENT_QUOTES, 'UTF-8'); ?>
          </span>
          <span class="setup-welcome__chip setup-welcome__chip--ok">
            <i class="fas fa-key" aria-hidden="true"></i>
            <?php echo htmlspecialchars(t('msg.setup_welcome_chip_keys'), ENT_QUOTES, 'UTF-8'); ?>
          </span>
          <span class="setup-welcome__chip">
            <i class="fas fa-mobile-alt" aria-hidden="true"></i>
            <?php echo htmlspecialchars(t('msg.setup_welcome_tip'), ENT_QUOTES, 'UTF-8'); ?>
          </span>
        </div>
        <div class="setup-welcome__actions">
          <a href="settings.php" class="setup-welcome__btn setup-welcome__btn--primary">
            <i class="fas fa-cog" aria-hidden="true"></i>
            <?php echo htmlspecialchars(t('msg.setup_welcome_cta'), ENT_QUOTES, 'UTF-8'); ?>
          </a>
          <button type="button" class="setup-welcome__btn setup-welcome__btn--ghost" id="setupWelcomeDismiss">
            <i class="fas fa-check" aria-hidden="true"></i>
            <?php echo htmlspecialchars(t('msg.setup_welcome_dismiss'), ENT_QUOTES, 'UTF-8'); ?>
          </button>
        </div>
      </div>
    </div>
  </div>
</div>
<script>
(function(){
  function dismissSetupWelcome(){
    var wrap = document.getElementById('setupWelcomeWrap');
    if(!wrap) return;
    wrap.style.transition = 'opacity .28s ease, transform .28s ease';
    wrap.style.opacity = '0';
    wrap.style.transform = 'translateY(-10px)';
    setTimeout(function(){
      if(wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);
      try{
        var u = new URL(window.location.href);
        u.searchParams.delete('setup');
        window.history.replaceState({}, '', u.pathname + (u.search || '') + u.hash);
      }catch(e){}
    }, 280);
  }
  var closeBtn = document.getElementById('setupWelcomeClose');
  var dismissBtn = document.getElementById('setupWelcomeDismiss');
  if(closeBtn) closeBtn.addEventListener('click', dismissSetupWelcome);
  if(dismissBtn) dismissBtn.addEventListener('click', dismissSetupWelcome);
})();
</script>
<?php endif; ?>

<div class="container admin-main mt-4">

<!-- statistics -->

<div class="row g-3 mb-4">

<div class="col-xl-3 col-lg-6 col-md-6 col-12">
<div class="stats-card">
<i class="fas fa-mobile-alt text-info fa-2x mb-2"></i>
<div class="stats-number" id="statTotalDevices"><?php echo count($devices); ?></div>
<?php echo t('dashboard.total_devices'); ?>
</div>
</div>

<div class="col-xl-3 col-lg-6 col-md-6 col-12">
<div class="stats-card">
<i class="fas fa-check-circle text-success fa-2x mb-2"></i>
<div class="stats-number" id="statActiveDevices">

<?php
$active_devices=array_filter($devices,function($d){
return $d['status']=='active' && strtotime($d['expiry_date'])>time();
});
echo count($active_devices);
?>

</div>
<?php echo t('dashboard.active_devices'); ?>
</div>
</div>

<div class="col-xl-3 col-lg-6 col-md-6 col-12">
<div class="stats-card">
<i class="fas fa-times-circle text-danger fa-2x mb-2"></i>
<div class="stats-number" id="statExpiredDevices">

<?php
$expired_devices=array_filter($devices,function($d){
return strtotime($d['expiry_date'])<=time();
});
echo count($expired_devices);
?>

</div>
<?php echo t('dashboard.expired_devices'); ?>
</div>
</div>

<div class="col-xl-3 col-lg-6 col-md-6 col-12">
<div class="stats-card">
<i class="fas fa-signal text-info fa-2x mb-2"></i>
<div class="stats-number">
<span id="onlineCount">0</span> /
<span id="offlineCount">0</span>
</div>
<?php echo t('dashboard.presence_now'); ?>
<button type="button" id="filterOnlineNowBtn" class="quick-connected-btn">
<i class="fas fa-satellite-dish"></i>
<?php echo t('dashboard.connected_now_btn'); ?>
</button>
</div>
</div>

</div>

<?php if ($expiringSoonCount > 0): ?>
<a href="expiring-devices.php" id="expiring-soon" class="text-decoration-none d-block mb-4 rounded-3 p-3 p-md-4 admin-expiring-banner">
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-3">
        <div class="d-flex align-items-center gap-3">
            <div class="admin-expiring-banner-icon">
                <i class="fas fa-hourglass-half"></i>
            </div>
            <div>
                <div class="fw-bold text-white mb-0"><?php echo t('dashboard.expiring_banner_title'); ?></div>
                <div class="small text-white-50"><?php echo t('dashboard.expiring_banner_sub'); ?></div>
            </div>
        </div>
        <span class="badge rounded-pill admin-expiring-badge px-3 py-2">
            <?php echo (int)$expiringSoonCount; ?>
        </span>
    </div>
</a>
<style>
.admin-expiring-banner {
    background: linear-gradient(135deg, rgba(56,189,248,0.12), rgba(99,102,241,0.1));
    border: 1px solid rgba(56,189,248,0.35);
    box-shadow: 0 12px 40px rgba(2,6,23,0.45);
    transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.admin-expiring-banner:hover {
    transform: translateY(-2px);
    box-shadow: 0 16px 48px rgba(56,189,248,0.2);
    border-color: rgba(56,189,248,0.55);
}
.admin-expiring-banner-icon {
    width: 48px;
    height: 48px;
    border-radius: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #38bdf8, #6366f1);
    color: #0b1120;
    font-size: 1.25rem;
}
.admin-expiring-badge {
    background: linear-gradient(135deg, #f59e0b, #d97706) !important;
    color: #0b1120 !important;
    font-weight: 700;
    font-size: 0.95rem;
}
</style>
<?php endif; ?>

<!-- filter -->

<div class="filter-bar">

<div class="filter-pills">
<button class="filter-btn active" data-filter="">
<?php echo t('filter.all'); ?>
</button>

<button class="filter-btn" data-filter="active">
<?php echo t('status.active'); ?>
</button>

<button class="filter-btn" data-filter="expired">
<?php echo t('status.expired'); ?>
</button>

<button class="filter-btn" data-filter="blocked">
<?php echo t('status.blocked'); ?>
</button>
</div>

<div class="device-id-search" role="search">
  <label class="visually-hidden" for="deviceIdSearch"><?php echo htmlspecialchars(t('filter.search_username')); ?></label>
  <div class="device-id-search__field">
    <i class="fas fa-magnifying-glass device-id-search__icon" aria-hidden="true"></i>
    <input
      type="search"
      id="deviceIdSearch"
      class="device-id-search__input"
      placeholder="<?php echo htmlspecialchars(t('filter.search_username_placeholder'), ENT_QUOTES, 'UTF-8'); ?>"
      value="<?php echo htmlspecialchars($searchQuery, ENT_QUOTES, 'UTF-8'); ?>"
      autocomplete="off"
      spellcheck="false"
      inputmode="text"
    >
    <button type="button" class="device-id-search__clear" id="deviceIdSearchClear" aria-label="<?php echo htmlspecialchars(t('filter.search_clear'), ENT_QUOTES, 'UTF-8'); ?>">
      <i class="fas fa-xmark" aria-hidden="true"></i>
    </button>
  </div>
</div>

<button class="filter-btn filter-btn-group" id="sortByAccountBtn" data-sort="off">
<i class="fas fa-layer-group"></i>
<?php echo t('filter.group_by_account'); ?>
</button>

</div>

<!-- table -->

<div>

<div class="d-flex align-items-center gap-2 mb-2" style="flex-wrap:wrap;">
  <button id="bulkDeleteBtn" class="btn btn-action btn-delete" style="display:none;" data-admin-perm="devices_delete">
    <i class="fas fa-trash"></i>
    <?php echo t('bulk.delete_selected'); ?>
    <span class="badge bg-dark ms-1" id="bulkDeleteCount">0</span>
  </button>
</div>

<p class="admin-scroll-hint mb-2">
  <i class="fas fa-arrows-left-right" aria-hidden="true"></i>
  <span><?php echo $isRtl ? 'اسحب الجدول أفقياً لعرض كل الأعمدة' : 'Swipe the table sideways to see all columns'; ?></span>
</p>
<div class="table-responsive admin-table-scroll admin-table-hint">
<table class="table table-hover" id="devicesTable">

<thead>

<tr>
<th style="width:34px;">
  <input type="checkbox" id="chkAll" aria-label="<?php echo htmlspecialchars(t('bulk.select_all_aria'), ENT_QUOTES, 'UTF-8'); ?>">
</th>
<th><?php echo t('table.device_name'); ?></th>
<th><?php echo t('table.device_id'); ?></th>
<th><?php echo t('table.bound_account'); ?></th>
<th><?php echo t('table.login_method'); ?></th>
<th><?php echo t('table.activation_date'); ?></th>
<th><?php echo t('table.expiry_date'); ?></th>
<th><?php echo t('table.connection_status'); ?></th>
<th><?php echo t('table.status'); ?></th>
<th><?php echo t('table.actions'); ?></th>
</tr>

</thead>

<tbody>

<?php foreach ($devices as $device): ?>
<?php echo admin_render_device_dashboard_row($device, $isGuest, admin_request_list_page()); ?>
<?php endforeach; ?>

</tbody>

</table>
</div>

<?php echo admin_render_pagination_shell('devicesTablePager'); ?>

</div>

</div>

<?php require_once 'includes/footer.php'; ?>

<div id="devicesLiveToast" role="status" aria-live="polite"></div>

<!-- Bulk delete modal -->
<div class="modal fade" id="bulkDeleteModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content" style="border-radius:18px;">
      <div class="modal-header" style="border-bottom:1px solid rgba(148,163,184,0.18);">
        <h5 class="modal-title" style="font-weight:700;color:#f8fafc;">
          <i class="fas fa-trash me-2" style="color:#f87171;"></i>
          <?php echo t('bulk.delete_title'); ?>
        </h5>
        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <div>
          <?php echo t('bulk.delete_confirm'); ?>
        </div>
        <div class="mt-3 p-3" style="border-radius:14px;">
          <i class="fas fa-exclamation-triangle me-2" style="color:#f87171;"></i>
          <?php echo t('bulk.delete_warning'); ?>
        </div>
      </div>
      <div class="modal-footer" style="border-top:1px solid rgba(148,163,184,0.18);">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" style="border-radius:999px;background:#1f2937;border-color:rgba(148,163,184,.35);">
          <i class="fas fa-times me-1"></i> <?php echo t('delete.cancel_short'); ?>
        </button>
        <button type="button" class="btn btn-danger" id="bulkDeleteConfirmBtn" data-admin-perm="devices_delete" style="border-radius:999px;">
          <i class="fas fa-trash me-1"></i>
          <?php echo t('bulk.delete_now'); ?>
          <span class="badge bg-dark ms-1" id="bulkDeleteConfirmCount">0</span>
        </button>
      </div>
    </div>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>

<script>

/* filter + pagination (12 rows / page; filters stay on all devices) */

const onlineOnlyBtn = document.getElementById("filterOnlineNowBtn");
let onlineOnlyMode = false;
const DEVICES_PER_PAGE = <?php echo (int)admin_pagination_per_page(); ?>;
const DEVICES_PAGE_KEY = "adminDevicesPage";
const devicesPager = document.getElementById("devicesTablePager");
const devicesPagerInner = devicesPager ? devicesPager.querySelector(".admin-pager__inner") : null;
const isRtlPager = document.documentElement.getAttribute("dir") === "rtl";

function readDevicesPageParam(raw){
  const n = parseInt(raw || "", 10);
  return n > 0 ? n : 0;
}

function readInitialDevicesPage(){
  const fromUrl = readDevicesPageParam(new URLSearchParams(window.location.search).get("page"));
  if (fromUrl) return fromUrl;
  try {
    const fromStore = readDevicesPageParam(sessionStorage.getItem(DEVICES_PAGE_KEY));
    if (fromStore) return fromStore;
  } catch (e) {}
  return 1;
}

function persistDevicesPage(){
  try {
    sessionStorage.setItem(DEVICES_PAGE_KEY, String(devicesPage));
  } catch (e) {}
  const url = new URL(window.location.href);
  if (devicesPage > 1) {
    url.searchParams.set("page", String(devicesPage));
  } else {
    url.searchParams.delete("page");
  }
  const next = url.pathname + url.search + url.hash;
  const cur = window.location.pathname + window.location.search + window.location.hash;
  if (next !== cur) {
    history.replaceState(null, "", next);
  }
}

function withDevicesPage(href){
  try {
    const u = new URL(href, window.location.href);
    const path = u.pathname.split("/").pop() || "";
    if (path !== "add_device.php" && path !== "delete-device.php" && path !== "edit-device.php") {
      return href;
    }
    if (devicesPage > 1) {
      u.searchParams.set("page", String(devicesPage));
    } else {
      u.searchParams.delete("page");
    }
    return u.pathname + u.search + u.hash;
  } catch (e) {
    return href;
  }
}

let devicesPage = readInitialDevicesPage();

document.addEventListener("click", function(e){
  const a = e.target.closest("a[href]");
  if (!a) return;
  const href = a.getAttribute("href") || "";
  if (!/(add_device|delete-device|edit-device)\.php/.test(href)) return;
  a.setAttribute("href", withDevicesPage(href));
}, true);

function devicesPagerWindow(current, totalPages){
  if (totalPages <= 1) return [1];
  const keep = {};
  for (let i = 1; i <= totalPages; i++) {
    if (i <= 2 || i > totalPages - 2 || Math.abs(i - current) <= 1) keep[i] = true;
  }
  const out = [];
  let prev = 0;
  Object.keys(keep).map(Number).sort((a,b)=>a-b).forEach(i=>{
    if (prev && i - prev > 1) out.push("…");
    out.push(i);
    prev = i;
  });
  return out;
}

function renderDevicesPager(pages){
  if (!devicesPager || !devicesPagerInner) return;
  if (pages <= 1) {
    devicesPager.hidden = true;
    devicesPagerInner.innerHTML = "";
    return;
  }
  devicesPager.hidden = false;
  const prevLabel = isRtlPager ? "»" : "«";
  const nextLabel = isRtlPager ? "«" : "»";
  let html = "";
  const prevDisabled = devicesPage <= 1;
  html += prevDisabled
    ? `<span class="admin-pager__btn is-disabled" aria-disabled="true">${prevLabel}</span>`
    : `<button type="button" class="admin-pager__btn" data-page="${devicesPage - 1}" rel="prev">${prevLabel}</button>`;
  devicesPagerWindow(devicesPage, pages).forEach(token=>{
    if (token === "…") {
      html += `<span class="admin-pager__btn admin-pager__ellipsis" aria-hidden="true">…</span>`;
      return;
    }
    const n = Number(token);
    if (n === devicesPage) {
      html += `<span class="admin-pager__btn is-active" aria-current="page">${n}</span>`;
    } else {
      html += `<button type="button" class="admin-pager__btn" data-page="${n}">${n}</button>`;
    }
  });
  const nextDisabled = devicesPage >= pages;
  html += nextDisabled
    ? `<span class="admin-pager__btn is-disabled" aria-disabled="true">${nextLabel}</span>`
    : `<button type="button" class="admin-pager__btn" data-page="${devicesPage + 1}" rel="next">${nextLabel}</button>`;
  devicesPagerInner.innerHTML = html;
}

if (devicesPagerInner) {
  devicesPagerInner.addEventListener("click", function(e){
    const btn = e.target.closest("[data-page]");
    if (!btn) return;
    const p = parseInt(btn.getAttribute("data-page"), 10);
    if (!p || p === devicesPage) return;
    devicesPage = p;
    applyTableFilters({ keepPage: true });
    const tableEl = document.getElementById("devicesTable");
    if (tableEl) tableEl.scrollIntoView({ behavior: "smooth", block: "start" });
  });
}

function applyTableFilters(opts){
const keepPage = !!(opts && opts.keepPage);
if (!keepPage) devicesPage = 1;

const activeStatusBtn=document.querySelector(".filter-pills .filter-btn.active")
const status=activeStatusBtn ? (activeStatusBtn.dataset.filter || "") : ""
const searchEl=document.getElementById("deviceIdSearch")
const q=(searchEl && searchEl.value ? searchEl.value : "").trim().toLowerCase()

const rows = Array.from(document.querySelectorAll("#devicesTable tbody tr"));
const matching = [];
rows.forEach(row=>{
const statusMatch=!status || row.dataset.status===status
const onlineMatch=!onlineOnlyMode || row.dataset.online==="1"
const username=(row.dataset.username || row.dataset.account || "").toLowerCase()
const deviceId=(row.dataset.deviceId || "").toLowerCase()
const searchMatch=!q || username.indexOf(q)!==-1 || deviceId.indexOf(q)!==-1
const match = statusMatch && onlineMatch && searchMatch;
row.dataset.pagerMatch = match ? "1" : "0";
if (match) matching.push(row);
row.style.display = "none";
});

const pages = Math.max(1, Math.ceil(matching.length / DEVICES_PER_PAGE) || 1);
if (devicesPage > pages) devicesPage = pages;
const start = (devicesPage - 1) * DEVICES_PER_PAGE;
const end = start + DEVICES_PER_PAGE;
matching.forEach((row, i)=>{
  if (i >= start && i < end) row.style.display = "";
});
renderDevicesPager(matching.length === 0 ? 1 : pages);
persistDevicesPage();
}

document.querySelectorAll(".filter-pills .filter-btn").forEach(btn=>{
btn.addEventListener("click",function(){

document.querySelectorAll(".filter-pills .filter-btn").forEach(b=>b.classList.remove("active"))
this.classList.add("active")
applyTableFilters()

})
})

const deviceIdSearch=document.getElementById("deviceIdSearch")
const deviceIdSearchClear=document.getElementById("deviceIdSearchClear")
function syncDeviceSearchClear(){
  if(!deviceIdSearchClear || !deviceIdSearch) return
  deviceIdSearchClear.classList.toggle("is-visible", deviceIdSearch.value.trim().length>0)
}
if(deviceIdSearch){
  syncDeviceSearchClear()
  deviceIdSearch.addEventListener("input",function(){
    syncDeviceSearchClear()
    applyTableFilters()
  })
  deviceIdSearch.addEventListener("keydown",function(e){
    if(e.key==="Escape"){
      deviceIdSearch.value=""
      syncDeviceSearchClear()
      applyTableFilters()
      deviceIdSearch.blur()
    }
  })
}
if(deviceIdSearchClear){
  deviceIdSearchClear.addEventListener("click",function(){
    if(!deviceIdSearch) return
    deviceIdSearch.value=""
    syncDeviceSearchClear()
    applyTableFilters()
    deviceIdSearch.focus()
  })
}

if(onlineOnlyBtn){
onlineOnlyBtn.addEventListener("click",function(){
onlineOnlyMode=!onlineOnlyMode
this.classList.toggle("active",onlineOnlyMode)
applyTableFilters()
})
}

/* group / sort by account */

const accountColors = [
  'rgba(37,99,235,0.18)',   // blue
  'rgba(5,150,105,0.18)',   // green
  'rgba(217,119,6,0.18)',   // amber
  'rgba(124,58,237,0.18)',  // violet
  'rgba(220,38,38,0.18)',   // red
  'rgba(6,182,212,0.18)',   // cyan
  'rgba(236,72,153,0.18)',  // pink
  'rgba(16,185,129,0.18)',  // teal
];

const sortBtn = document.getElementById('sortByAccountBtn');
let sortActive = false;
let originalOrder = null;

sortBtn.addEventListener('click', function(){
  const tbody = document.querySelector('#devicesTable tbody');
  const rows = Array.from(tbody.querySelectorAll('tr'));

  if (!sortActive) {
    // save original order
    originalOrder = rows.map(r => r);

    // sort: rows with account first (grouped), then no-account
    rows.sort((a, b) => {
      const acA = a.dataset.account || '';
      const acB = b.dataset.account || '';
      if (acA === acB) return 0;
      if (acA === '') return 1;
      if (acB === '') return -1;
      return acA.localeCompare(acB);
    });

    rows.forEach(r => tbody.appendChild(r));

    // assign colors per unique account
    const colorMap = {};
    let colorIdx = 0;
    rows.forEach(row => {
      const ac = row.dataset.account || '';
      if (ac === '') {
        row.style.removeProperty('background-color');
        return;
      }
      if (!(ac in colorMap)) {
        colorMap[ac] = accountColors[colorIdx % accountColors.length];
        colorIdx++;
      }
      row.style.backgroundColor = colorMap[ac];
    });

    sortBtn.classList.add('active');
    sortBtn.style.background = '#1e40af';
    sortBtn.innerHTML = '<i class="fas fa-layer-group"></i> <?php echo t('filter.group_by_account'); ?> ✓';
    sortActive = true;
    applyTableFilters({ keepPage: true });

  } else {
    // restore original order
    if (originalOrder) {
      originalOrder.forEach(r => {
        r.style.removeProperty('background-color');
        tbody.appendChild(r);
      });
    }
    sortBtn.classList.remove('active');
    sortBtn.style.background = '';
    sortBtn.innerHTML = '<i class="fas fa-layer-group"></i> <?php echo t('filter.group_by_account'); ?>';
    sortActive = false;
    applyTableFilters({ keepPage: true });
  }
});

/* device presence */

let txtOnline = <?php echo json_encode(t('presence.online')); ?>;
let txtOffline = <?php echo json_encode(t('presence.offline')); ?>;
let txtNewDevice = <?php echo json_encode(t('dashboard.new_device_live')); ?>;

const knownDeviceIds = new Set(
  Array.from(document.querySelectorAll('#devicesTable tbody tr[data-device-row-id]'))
    .map(tr => parseInt(tr.getAttribute('data-device-row-id') || '0', 10))
    .filter(n => n > 0)
);
let deviceRowsFetchInFlight = false;
let deviceToastTimer = null;

function showDevicesLiveToast(message){
  const el = document.getElementById('devicesLiveToast');
  if (!el) return;
  el.textContent = message;
  el.classList.add('is-visible');
  if (deviceToastTimer) clearTimeout(deviceToastTimer);
  deviceToastTimer = setTimeout(function(){
    el.classList.remove('is-visible');
  }, 4200);
}

function updateDashboardStats(stats){
  if (!stats) return;
  const totalEl = document.getElementById('statTotalDevices');
  const activeEl = document.getElementById('statActiveDevices');
  const expiredEl = document.getElementById('statExpiredDevices');
  if (totalEl && typeof stats.total === 'number') totalEl.textContent = String(stats.total);
  if (activeEl && typeof stats.active === 'number') activeEl.textContent = String(stats.active);
  if (expiredEl && typeof stats.expired === 'number') expiredEl.textContent = String(stats.expired);
}

function removeMissingDeviceRows(apiIds){
  document.querySelectorAll('#devicesTable tbody tr[data-device-row-id]').forEach(function(tr){
    const id = parseInt(tr.getAttribute('data-device-row-id') || '0', 10);
    if (id > 0 && !apiIds.has(id)) {
      tr.remove();
      knownDeviceIds.delete(id);
    }
  });
}

function applyDeviceRows(rows){
  if (!rows || !rows.length) return;
  const tbody = document.querySelector('#devicesTable tbody');
  if (!tbody) return;
  const emptyRow = tbody.querySelector('tr[data-empty-row]');
  if (emptyRow) emptyRow.remove();
  let added = 0;
  rows.forEach(function(row){
    const id = parseInt(row.id || '0', 10);
    if (!id || !row.html) return;
    const temp = document.createElement('tbody');
    temp.innerHTML = row.html.trim();
    const tr = temp.firstElementChild;
    if (!tr) return;
    const existing = document.querySelector('#devicesTable tbody tr[data-device-row-id="' + id + '"]');
    if (existing) {
      const wasChecked = existing.querySelector('.rowChk') && existing.querySelector('.rowChk').checked;
      existing.replaceWith(tr);
      if (wasChecked) {
        const chk = tr.querySelector('.rowChk');
        if (chk) chk.checked = true;
      }
      knownDeviceIds.add(id);
      return;
    }
    if (knownDeviceIds.has(id)) return;
    tbody.insertBefore(tr, tbody.firstChild);
    tr.classList.add('device-row-new');
    knownDeviceIds.add(id);
    added++;
  });
  if (added > 0) {
    applyTableFilters({ keepPage: true });
    showDevicesLiveToast(added === 1 ? txtNewDevice : (txtNewDevice + ' (' + added + ')'));
  } else if (rows.length) {
    applyTableFilters({ keepPage: true });
  }
}

function syncDevicesList(data){
  if (!data || !data.success || !Array.isArray(data.devices)) return;
  updateDashboardStats(data.stats || null);
  const apiIds = new Set(data.devices.map(function(d){ return parseInt(d.id || '0', 10); }).filter(function(n){ return n > 0; }));
  removeMissingDeviceRows(apiIds);
  const refreshIds = [];
  data.devices.forEach(function(d){
    const id = parseInt(d.id || '0', 10);
    if (!id) return;
    const tr = document.querySelector('#devicesTable tbody tr[data-device-row-id="' + id + '"]');
    if (!tr) {
      if (!knownDeviceIds.has(id)) refreshIds.push(id);
      return;
    }
    const sig = tr.getAttribute('data-sync-sig') || '';
    if (d.sync_sig && d.sync_sig !== sig) refreshIds.push(id);
  });
  const uniqueRefresh = Array.from(new Set(refreshIds));
  if (!uniqueRefresh.length || deviceRowsFetchInFlight) return;
  deviceRowsFetchInFlight = true;
  fetch('api/device-rows.php?ids=' + encodeURIComponent(uniqueRefresh.join(',')))
    .then(function(res){ return res.json(); })
    .then(function(payload){
      if (payload && payload.success) applyDeviceRows(payload.rows || []);
    })
    .catch(function(){})
    .finally(function(){ deviceRowsFetchInFlight = false; });
}

function updatePresence(){

fetch("api/device-status.php")

.then(res=>res.json())

.then(data=>{

syncDevicesList(data);

let online=0
let offline=0

data.devices.forEach(d=>{

let el = null
if (d.id != null && d.id !== '') {
  el = document.querySelector(`[data-device-pk="${d.id}"]`)
}
if (!el && d.device_id) {
  el = document.querySelector(`[data-device="${d.device_id}"]`)
}

if(!el) return

if(d.online){

online++
el.innerHTML="🟢 "+txtOnline
el.closest("tr").classList.add("row-online")
el.closest("tr").dataset.online="1"

}else{

offline++
el.innerHTML="🔴 "+txtOffline
el.closest("tr").classList.remove("row-online")
el.closest("tr").dataset.online="0"

}

})

document.getElementById("onlineCount").textContent=online
document.getElementById("offlineCount").textContent=offline
applyTableFilters({ keepPage: true })

})

}

applyTableFilters({ keepPage: true })
updatePresence()
setInterval(updatePresence,5000)

// ===== Bulk selection + delete =====
const bulkBtn = document.getElementById('bulkDeleteBtn');
const bulkCount = document.getElementById('bulkDeleteCount');
const chkAll = document.getElementById('chkAll');
const bulkModalEl = document.getElementById('bulkDeleteModal');
const bulkConfirmCount = document.getElementById('bulkDeleteConfirmCount');
const bulkConfirmBtn = document.getElementById('bulkDeleteConfirmBtn');
const bulkModal = bulkModalEl ? new bootstrap.Modal(bulkModalEl) : null;

function visibleRowChecks() {
  return Array.from(document.querySelectorAll('#devicesTable tbody tr'))
    .filter(tr => tr.style.display !== 'none')
    .map(tr => tr.querySelector('.rowChk'))
    .filter(Boolean);
}

function selectedIds() {
  return Array.from(document.querySelectorAll('.rowChk:checked'))
    .map(x => parseInt(x.dataset.id || '0', 10))
    .filter(x => x > 0);
}

function refreshBulkUi() {
  const ids = selectedIds();
  const n = ids.length;
  if (bulkBtn) bulkBtn.style.display = n > 0 ? 'inline-flex' : 'none';
  if (bulkCount) bulkCount.textContent = String(n);
  if (bulkConfirmCount) bulkConfirmCount.textContent = String(n);
  if (chkAll) {
    const visible = visibleRowChecks();
    const all = visible.length;
    const checkedVisible = visible.filter(c => c.checked).length;
    chkAll.checked = all > 0 && checkedVisible === all;
    chkAll.indeterminate = checkedVisible > 0 && checkedVisible < all;
  }
}

document.addEventListener('change', (e) => {
  const t = e.target;
  if (!t) return;
  if (t === chkAll) {
    const on = chkAll.checked;
    visibleRowChecks().forEach(c => { c.checked = on; });
    refreshBulkUi();
  }
  if (t.classList && t.classList.contains('rowChk')) {
    refreshBulkUi();
  }
});

if (bulkBtn && bulkModal) {
  bulkBtn.addEventListener('click', () => {
    refreshBulkUi();
    bulkModal.show();
  });
}

if (bulkConfirmBtn) {
  bulkConfirmBtn.addEventListener('click', async () => {
    const ids = selectedIds();
    if (!ids.length) return;
    bulkConfirmBtn.disabled = true;
    try {
      const res = await fetch('api/bulk-delete-devices.php', {
        method: 'POST',
        headers: (typeof window.adminCsrfHeaders === 'function'
          ? window.adminCsrfHeaders({ 'Content-Type': 'application/json' })
          : { 'Content-Type': 'application/json' }),
        body: JSON.stringify({ ids, csrf_token: window.ADMIN_CSRF_TOKEN || '' }),
      });
      const data = await res.json().catch(() => ({}));
      if (!data || data.success !== true) {
        alert((data && data.message) ? data.message : 'Delete failed');
        return;
      }
      // remove rows from DOM
      ids.forEach(id => {
        const chk = document.querySelector(`.rowChk[data-id="${id}"]`);
        const tr = chk ? chk.closest('tr') : null;
        if (tr) tr.remove();
      });
      applyTableFilters({ keepPage: true });
      refreshBulkUi();
      if (bulkModal) bulkModal.hide();
    } catch (err) {
      alert('Network error');
    } finally {
      bulkConfirmBtn.disabled = false;
    }
  });
}

refreshBulkUi();

</script>

</body>
</html>