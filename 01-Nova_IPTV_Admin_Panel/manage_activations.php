<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);
require_once __DIR__ . '/includes/credential_crypto.php';
require_once __DIR__ . '/includes/pagination.php';

$current_page = 'manage';

$devicesAll = getActivatedDevices($conn);
$devicesPager = admin_paginate_items($devicesAll);
$devices = $devicesPager['items'];
$isGuest = adminIsGuestRole();
?>

<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl':'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">

<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title><?php echo t('manage.title'); ?> - <?php echo t('app.title'); ?></title>

<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">

<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">

<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap" rel="stylesheet">

<style>

body{
font-family:'Cairo',sans-serif;
background:#020617;
color:#e5e7eb;
}

/* ================= CARD ================= */

.manage-card,.log-card{

border-radius:18px;

background:linear-gradient(145deg,#0f172a,#020617);

border:1px solid rgba(148,163,184,.25);

box-shadow:0 20px 40px rgba(0,0,0,.6);

}

/* ================= TABLE ================= */

.table{
color:#e5e7eb;
}

.table thead th{

background:#0f172a;
color:#f1f5f9;

font-weight:700;

border-bottom:2px solid #334155;

white-space:nowrap;

}

.table tbody tr:hover{
background:#1e293b;
}

/* ================= STATUS ================= */

.status-badge{

padding:5px 12px;

border-radius:999px;

font-size:.82rem;

font-weight:700;

display:inline-flex;

gap:6px;

align-items:center;

}

.active{
background:#16a34a;
color:white;
box-shadow:0 0 10px rgba(34,197,94,.8);
}

.expired{
background:#b91c1c;
color:white;
}

.blocked{
background:#475569;
color:white;
}

/* ================= DATE ================= */

.date-pill{

display:inline-flex;

align-items:center;

gap:6px;

padding:4px 10px;

border-radius:999px;

font-size:.82rem;

}

.date-pill--start{
background:#1d4ed8;
color:white;
}

.date-pill--end{
background:#b91c1c;
color:white;
}

/* ================= CONNECTION ================= */

.connection-badge{

display:inline-flex;

align-items:center;

gap:6px;

padding:5px 12px;

border-radius:999px;

font-size:.82rem;

font-weight:700;

}

.online{
background:#16a34a;
color:white;
}

.offline{
background:#b91c1c;
color:white;
}

/* ================= BUTTONS ================= */

.btn-action{

border-radius:999px;

padding:6px 12px;

border:none;

font-size:.85rem;

transition:.2s;

}

.btn-edit{

background:linear-gradient(135deg,#38bdf8,#6366f1);
color:white;

}

.btn-delete{

background:linear-gradient(135deg,#f97373,#ef4444);
color:white;

}

.btn-action:hover{

transform:scale(1.05);

box-shadow:0 10px 20px rgba(0,0,0,.6);

}

/* ================= ALERT ================= */

.alert-success{

background:rgba(22,163,74,.15);

border:1px solid rgba(34,197,94,.6);

color:#bbf7d0;

}

</style>

</head>

<body>

<?php require_once 'includes/header.php'; ?>

<div class="container admin-main mt-4">

<h4 class="mb-3">
<i class="fas fa-clipboard-list text-info"></i>
<?php echo t('manage.title'); ?>
</h4>

<!-- DEVICES TABLE -->

<div class="manage-card p-3 mb-4">

<div style="display:flex;justify-content:flex-end;margin-bottom:12px;">
<button id="sortByAccountBtn" data-sort="off" style="padding:6px 16px;border-radius:999px;border:1px solid #1e40af;background:#020617;color:white;cursor:pointer;display:flex;align-items:center;gap:6px;font-family:inherit;">
<i class="fas fa-layer-group"></i>
<?php echo t('filter.group_by_account'); ?>
</button>
</div>

<div class="table-responsive">

<table class="table table-hover">

<thead>

<tr>

<th><i class="fas fa-mobile-alt me-1"></i> <?php echo t('table.device_id'); ?></th>

<th><i class="fas fa-link me-1"></i> <?php echo t('table.bound_account'); ?></th>

<th><i class="fas fa-calendar-plus me-1"></i> <?php echo t('table.activation_date'); ?></th>

<th><i class="fas fa-calendar-times me-1"></i> <?php echo t('table.expiry_date'); ?></th>

<th><i class="fas fa-wifi me-1"></i> <?php echo t('table.connection_status'); ?></th>

<th><i class="fas fa-info-circle me-1"></i> <?php echo t('table.status'); ?></th>

<th><i class="fas fa-cogs me-1"></i> <?php echo t('table.actions'); ?></th>

</tr>

</thead>

<tbody>

<?php if(empty($devices)): ?>

<tr>
<td colspan="6" class="text-center py-4">
<?php echo $lang==='ar'?'لا توجد أجهزة مفعلة':'No active devices'; ?>
</td>
</tr>

<?php else: ?>

<?php foreach($devices as $device): ?>
<?php
$rawDeviceId = (string)($device['device_id'] ?? '');
$displayDeviceId = $isGuest ? adminMaskDeviceId($rawDeviceId) : $rawDeviceId;
?>

<tr data-account="<?php echo htmlspecialchars(account_key_display_label(isset($device['account_key']) ? (string)$device['account_key'] : '')); ?>">

<td><strong><?php echo htmlspecialchars($displayDeviceId); ?></strong></td>

<td>
<?php
$ak = isset($device['account_key']) ? trim((string)$device['account_key']) : '';
if ($ak !== '') {
    $display = htmlspecialchars(account_key_display_label($ak));
    echo '<span class="badge" style="background:#1e40af;font-size:.8rem;max-width:160px;overflow:hidden;text-overflow:ellipsis;display:inline-block;white-space:nowrap;" title="'.htmlspecialchars($display).'">'.$display.'</span>';
} else {
    echo '<span class="text-secondary" style="font-size:.8rem;">'.t('table.no_account').'</span>';
}
?>
</td>

<td>

<span class="date-pill date-pill--start">

<i class="fas fa-calendar-plus"></i>

<?php echo format_datetime_short($device['activation_date']); ?>

</span>

</td>

<td>

<span class="date-pill date-pill--end">

<i class="fas fa-calendar-times"></i>

<?php echo format_device_expiry($device['expiry_date']); ?>

</span>

</td>

<td>

<?php

$lastSeen=!empty($device['last_seen_at'])?strtotime($device['last_seen_at']):0;

$now=time();

// متصل = تواجد في التطبيق خلال 60 ثانية، بغض النظر عن حالة التفعيل
$isOnline=$lastSeen>0 && ($now-$lastSeen)<=60;

?>

<span class="connection-status connection-badge <?php echo $isOnline?'online':'offline'; ?>"
      data-device-pk="<?php echo (int)$device['id']; ?>"
      <?php if (!$isGuest): ?>data-device-id="<?php echo htmlspecialchars($rawDeviceId); ?>"<?php endif; ?>>

<i class="fas fa-circle"></i>

<?php echo $isOnline?t('presence.online'):t('presence.offline'); ?>

</span>

</td>

<td>

<span class="status-badge <?php echo $device['status']; ?>">

<?php echo t('status.'.$device['status']); ?>

</span>

</td>

<td>

<a href="edit-device.php?id=<?php echo $device['id']; ?>" class="btn btn-action btn-edit">

<i class="fas fa-edit"></i>

</a>

<a href="delete-device.php?id=<?php echo (int) $device['id']; ?>&confirm=yes"
   class="btn btn-action btn-delete"
   data-admin-perm="devices_delete"
   data-admin-confirm
   data-confirm-title="<?php echo htmlspecialchars(t('delete.title'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-message="<?php echo htmlspecialchars(t('delete.question'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-warning="<?php echo htmlspecialchars(t('delete.warning'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-ok="<?php echo htmlspecialchars(t('delete.confirm_button'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-details="<?php echo htmlspecialchars(json_encode([
       ['label' => t('table.device_id'), 'value' => $displayDeviceId, 'mono' => true],
   ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">

<i class="fas fa-trash"></i>

</a>

</td>

</tr>

<?php endforeach; ?>

<?php endif; ?>

</tbody>

</table>

</div>

<?php echo admin_render_pagination((int)$devicesPager['page'], (int)$devicesPager['pages']); ?>

</div>

</div>

<?php require_once 'includes/footer.php'; ?>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<?php require_once 'includes/admin_confirm_modal.php'; ?>

<script>
var txtOnline = <?php echo json_encode(t('presence.online')); ?>;
var txtOffline = <?php echo json_encode(t('presence.offline')); ?>;

function updateConnectionStatuses(){

fetch('api/device-status.php')

.then(r=>r.json())

.then(data=>{

data.devices.forEach(device=>{

let el = null
if (device.id != null && device.id !== '') {
  el = document.querySelector(`.connection-status[data-device-pk="${device.id}"]`)
}
if (!el && device.device_id) {
  el = document.querySelector(`.connection-status[data-device-id="${device.device_id}"]`)
}

if(!el) return

let online=device.online

el.classList.remove('online','offline')

el.classList.add(online?'online':'offline')

el.innerHTML='<i class="fas fa-circle"></i> '+(online?txtOnline:txtOffline)

})

})

}

updateConnectionStatuses()

setInterval(updateConnectionStatuses,5000)

/* group / sort by account */

const accountColors = [
  'rgba(37,99,235,0.18)',
  'rgba(5,150,105,0.18)',
  'rgba(217,119,6,0.18)',
  'rgba(124,58,237,0.18)',
  'rgba(220,38,38,0.18)',
  'rgba(6,182,212,0.18)',
  'rgba(236,72,153,0.18)',
  'rgba(16,185,129,0.18)',
];

const sortBtn = document.getElementById('sortByAccountBtn');
let sortActive = false;
let originalOrder = null;

sortBtn.addEventListener('click', function(){
  const tbody = document.querySelector('.table tbody');
  const rows = Array.from(tbody.querySelectorAll('tr'));

  if (!sortActive) {
    originalOrder = rows.slice();

    rows.sort((a, b) => {
      const acA = a.dataset.account || '';
      const acB = b.dataset.account || '';
      if (acA === acB) return 0;
      if (acA === '') return 1;
      if (acB === '') return -1;
      return acA.localeCompare(acB);
    });

    rows.forEach(r => tbody.appendChild(r));

    const colorMap = {};
    let colorIdx = 0;
    rows.forEach(row => {
      const ac = row.dataset.account || '';
      if (ac === '') { row.style.removeProperty('background-color'); return; }
      if (!(ac in colorMap)) { colorMap[ac] = accountColors[colorIdx % accountColors.length]; colorIdx++; }
      row.style.backgroundColor = colorMap[ac];
    });

    sortBtn.classList.add('active');
    sortBtn.style.background = '#1e40af';
    sortBtn.innerHTML = '<i class="fas fa-layer-group"></i> <?php echo t('filter.group_by_account'); ?> ✓';
    sortActive = true;

  } else {
    if (originalOrder) {
      originalOrder.forEach(r => { r.style.removeProperty('background-color'); tbody.appendChild(r); });
    }
    sortBtn.style.background = '#020617';
    sortBtn.innerHTML = '<i class="fas fa-layer-group"></i> <?php echo t('filter.group_by_account'); ?>';
    sortActive = false;
  }
});

</script>

</body>
</html>