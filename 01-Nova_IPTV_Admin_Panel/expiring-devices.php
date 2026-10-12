<?php
session_start();
require_once 'config/database.php';
require_once 'includes/functions.php';
require_once 'includes/lang.php';
require_once 'includes/admin_auth.php';

createDatabaseTable($conn);
adminBootstrapLogin($conn);

$current_page = 'expiring';

$withinDays = 7;
$expiringList = getExpiringSoonDevices($conn, $withinDays, 200);
$expiringCount = count($expiringList);
$isGuest = adminIsGuestRole();
?>
<!DOCTYPE html>
<html dir="<?php echo $isRtl ? 'rtl' : 'ltr'; ?>" lang="<?php echo htmlspecialchars($lang); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo t('expiring.page_title'); ?> - <?php echo t('app.title'); ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Cairo', system-ui, sans-serif; }
        .exp-page-hero {
            border-radius: 20px;
            padding: 1.75rem 1.5rem;
            background: radial-gradient(circle at 0% 0%, rgba(56,189,248,0.22), transparent 45%),
                        radial-gradient(circle at 100% 100%, rgba(99,102,241,0.18), transparent 40%),
                        linear-gradient(145deg, rgba(15,23,42,0.98), rgba(3,7,18,0.99));
            border: 1px solid rgba(56,189,248,0.28);
            box-shadow: 0 24px 60px rgba(2,6,23,0.55);
            margin-bottom: 1.75rem;
        }
        .exp-page-hero h1 {
            font-size: clamp(1.35rem, 2.5vw, 1.75rem);
            font-weight: 800;
            color: #f8fafc;
            letter-spacing: 0.02em;
        }
        .exp-page-hero p { color: #94a3b8; max-width: 42rem; }
        .exp-stat-pill {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem 1rem;
            border-radius: 999px;
            background: rgba(56,189,248,0.12);
            border: 1px solid rgba(56,189,248,0.35);
            color: #e0f2fe;
            font-weight: 700;
        }
        .exp-card-shell {
            border-radius: 18px;
            background: radial-gradient(circle at top left, rgba(30,41,59,0.95), rgba(3,7,18,0.98));
            border: 1px solid rgba(148,163,184,0.2);
            box-shadow: 0 20px 50px rgba(2,6,23,0.5);
            overflow: hidden;
        }
        .exp-table thead th {
            font-size: 0.78rem;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            color: #94a3b8 !important;
            border-bottom: 1px solid rgba(148,163,184,0.2) !important;
            background: rgba(15,23,42,0.9) !important;
            padding: 0.85rem 1rem;
            white-space: nowrap;
        }
        .exp-table tbody td {
            padding: 1rem;
            vertical-align: middle;
            border-color: rgba(148,163,184,0.12) !important;
            color: #e2e8f0;
        }
        .exp-table tbody tr:hover {
            background: rgba(56,189,248,0.06);
        }
        .exp-device-title { font-weight: 700; color: #f1f5f9; }
        .exp-device-id {
            font-family: ui-monospace, monospace;
            font-size: 0.82rem;
            color: #38bdf8;
            word-break: break-all;
        }
        .exp-date-cell { font-weight: 600; color: #fcd34d; }
        .exp-days-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.35rem 0.65rem;
            border-radius: 999px;
            font-size: 0.78rem;
            font-weight: 700;
            background: rgba(245,158,11,0.15);
            border: 1px solid rgba(251,191,36,0.4);
            color: #fde68a;
        }
        .exp-days-badge.urgent {
            background: rgba(239,68,68,0.18);
            border-color: rgba(248,113,113,0.5);
            color: #fecaca;
        }
        .exp-btn-edit {
            border-radius: 999px;
            padding: 0.4rem 1rem;
            font-size: 0.85rem;
            font-weight: 600;
            border: none;
            background: linear-gradient(135deg, #38bdf8, #6366f1);
            color: #0b1120;
        }
        .exp-btn-edit:hover { filter: brightness(1.08); color: #0b1120; }
        .exp-empty {
            border-radius: 18px;
            padding: 3rem 1.5rem;
            text-align: center;
            background: rgba(15,23,42,0.5);
            border: 1px dashed rgba(148,163,184,0.25);
            color: #94a3b8;
        }
        .exp-empty i {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            opacity: 0.7;
            color: #38bdf8;
        }
    </style>
</head>
<body>
<?php require_once 'includes/header.php'; ?>

<div class="container admin-main" id="expiring-soon">
    <div class="exp-page-hero">
        <div class="d-flex flex-wrap align-items-start justify-content-between gap-3">
            <div>
                <h1 class="mb-2">
                    <i class="fas fa-hourglass-half text-info me-2"></i>
                    <?php echo t('expiring.page_title'); ?>
                </h1>
                <p class="mb-0"><?php echo t('expiring.page_sub'); ?></p>
            </div>
            <div class="exp-stat-pill">
                <i class="fas fa-mobile-screen-button"></i>
                <span><?php echo (int)$expiringCount; ?></span>
                <span class="d-none d-sm-inline"><?php echo t('expiring.devices_in_window'); ?></span>
            </div>
        </div>
    </div>

    <?php if ($expiringCount === 0): ?>
        <div class="exp-empty">
            <i class="fas fa-circle-check"></i>
            <p class="mb-0 fs-5 fw-semibold text-white"><?php echo t('expiring.empty'); ?></p>
            <p class="small mt-2 mb-0"><?php echo t('expiring.empty_hint'); ?></p>
            <a href="index.php" class="btn btn-outline-light btn-sm mt-3 rounded-pill px-4"><?php echo t('expiring.back_home'); ?></a>
        </div>
    <?php else: ?>
        <div class="exp-card-shell">
            <div class="table-responsive">
                <table class="table table-dark table-hover exp-table mb-0 align-middle">
                    <thead>
                        <tr>
                            <th><?php echo t('table.device_name'); ?></th>
                            <th><?php echo t('table.device_id'); ?></th>
                            <th><?php echo t('table.expiry_date'); ?></th>
                            <th><?php echo t('expiring.days_left'); ?></th>
                            <th><?php echo t('table.connection_status'); ?></th>
                            <th class="text-end"><?php echo t('table.actions'); ?></th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($expiringList as $row):
                            $expTs = strtotime($row['expiry_date'] ?? '');
                            $daysLeft = ($expTs !== false) ? (int)ceil(($expTs - time()) / 86400) : 0;
                            if ($daysLeft < 0) {
                                $daysLeft = 0;
                            }
                            $urgent = $daysLeft <= 2;
                            $lastSeen = $row['last_seen_at'] ?? null;
                            $online = false;
                            if ($lastSeen) {
                                $ls = strtotime($lastSeen);
                                if ($ls !== false && (time() - $ls) <= 120) {
                                    $online = true;
                                }
                            }
                            $rawDeviceId = (string)($row['device_id'] ?? '');
                            $displayDeviceId = $isGuest
                                ? adminMaskDeviceId($rawDeviceId)
                                : $rawDeviceId;
                            ?>
                            <tr>
                                <td>
                                    <div class="exp-device-title"><?php echo htmlspecialchars($row['device_name'] ?: '—'); ?></div>
                                </td>
                                <td><span class="exp-device-id" title="<?php echo htmlspecialchars($displayDeviceId); ?>"><?php echo htmlspecialchars($displayDeviceId); ?></span></td>
                                <td class="exp-date-cell"><?php echo htmlspecialchars($row['expiry_date']); ?></td>
                                <td>
                                    <span class="exp-days-badge<?php echo $urgent ? ' urgent' : ''; ?>">
                                        <i class="fas fa-calendar-day"></i>
                                        <?php echo $daysLeft; ?> <?php echo t('expiring.days_unit'); ?>
                                    </span>
                                </td>
                                <td>
                                    <?php if ($online): ?>
                                        <span class="badge rounded-pill bg-success bg-opacity-25 text-success border border-success border-opacity-50">
                                            <i class="fas fa-circle text-success me-1" style="font-size:0.5rem;vertical-align:middle;"></i>
                                            <?php echo t('presence.online'); ?>
                                        </span>
                                    <?php else: ?>
                                        <span class="badge rounded-pill bg-secondary bg-opacity-25 text-secondary border border-secondary border-opacity-50">
                                            <?php echo t('presence.offline'); ?>
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td class="text-end">
                                    <a class="btn exp-btn-edit btn-sm" href="edit-device.php?id=<?php echo (int)$row['id']; ?>">
                                        <i class="fas fa-pen-to-square me-1"></i><?php echo t('expiring.manage'); ?>
                                    </a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <div class="mt-3 text-center">
            <a href="index.php" class="text-decoration-none small" style="color:#38bdf8;">
                <i class="fas fa-arrow-<?php echo $isRtl ? 'right' : 'left'; ?> me-1"></i><?php echo t('expiring.back_home'); ?>
            </a>
        </div>
    <?php endif; ?>
</div>

<?php require_once 'includes/footer.php'; ?>
</body>
</html>
