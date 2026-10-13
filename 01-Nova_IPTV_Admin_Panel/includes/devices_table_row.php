<?php

/**
 * Render one dashboard devices table row (used by index.php + live sync API).
 */
function admin_device_dashboard_sync_sig(array $device): string
{
    $parts = [
        trim((string) ($device['device_id'] ?? '')),
        trim((string) ($device['device_name'] ?? '')),
        strtolower(trim((string) ($device['status'] ?? ''))),
        trim((string) ($device['activation_date'] ?? '')),
        trim((string) ($device['expiry_date'] ?? '')),
        trim((string) ($device['account_key'] ?? '')),
        trim((string) ($device['account_display_name'] ?? '')),
        trim((string) ($device['code_server_host'] ?? '')),
        (string) (int) ($device['code_usage_count'] ?? 0),
    ];

    return hash('crc32b', implode("\x1e", $parts));
}

function admin_render_device_dashboard_row(array $device, bool $isGuest, int $listPage = 0): string
{
    $rawDeviceId = (string) ($device['device_id'] ?? '');
    $displayDeviceId = $isGuest ? adminMaskDeviceId($rawDeviceId) : $rawDeviceId;
    $deviceIdAttr = htmlspecialchars($displayDeviceId, ENT_QUOTES, 'UTF-8');
    $rawIdAttr = htmlspecialchars($rawDeviceId, ENT_QUOTES, 'UTF-8');
    $status = (string) ($device['status'] ?? '');
    $devicePk = (int) ($device['id'] ?? 0);
    $deviceName = htmlspecialchars((string) ($device['device_name'] ?? ''), ENT_QUOTES, 'UTF-8');
    $ak = isset($device['account_key']) ? trim((string) $device['account_key']) : '';
    $displayName = isset($device['account_display_name']) ? trim((string) $device['account_display_name']) : '';
    $manualUser = isset($device['manual_login_username']) ? trim((string) $device['manual_login_username']) : '';
    $rawUsername = $displayName !== '' ? $displayName : ($manualUser !== '' ? $manualUser : account_key_display_label($ak));
    $accountLabel = htmlspecialchars($rawUsername, ENT_QUOTES, 'UTF-8');
    $serverHost = isset($device['code_server_host']) ? trim((string) $device['code_server_host']) : '';
    $codeUsageCount = (int) ($device['code_usage_count'] ?? 0);
    $syncSig = admin_device_dashboard_sync_sig($device);

    ob_start();
    ?>
<tr data-device-row-id="<?php echo $devicePk; ?>"
    data-sync-sig="<?php echo htmlspecialchars($syncSig, ENT_QUOTES, 'UTF-8'); ?>"
    data-status="<?php echo htmlspecialchars($status, ENT_QUOTES, 'UTF-8'); ?>"
    data-device-id="<?php echo $deviceIdAttr; ?>"
    data-account="<?php echo $accountLabel; ?>"
    data-username="<?php echo htmlspecialchars($rawUsername, ENT_QUOTES, 'UTF-8'); ?>"
    data-online="0"
    data-pager-match="1">

<td>
  <input type="checkbox"
         class="rowChk"
         data-id="<?php echo $devicePk; ?>"
         aria-label="<?php echo htmlspecialchars(t('bulk.select_row_aria'), ENT_QUOTES, 'UTF-8'); ?>">
</td>
<td><strong><?php echo $deviceName; ?></strong></td>

<td>
<span class="device-id-pill" title="<?php echo $deviceIdAttr; ?>">
<?php echo $deviceIdAttr; ?>
</span>
</td>

<td>
<?php
if ($rawUsername !== '') {
    $display = htmlspecialchars($rawUsername, ENT_QUOTES, 'UTF-8');
    $titleSafe = $isGuest
        ? $rawUsername
        : account_key_tooltip_safe($ak, $serverHost);
    echo '<span class="badge" style="background:#1e40af;font-size:.8rem;max-width:180px;overflow:hidden;text-overflow:ellipsis;display:inline-block;white-space:nowrap;" title="' . htmlspecialchars($titleSafe, ENT_QUOTES, 'UTF-8') . '">' . $display . '</span>';
    if (!$isGuest && $serverHost !== '') {
        echo '<br><small class="text-secondary" style="font-size:.72rem;max-width:180px;display:inline-block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="' . htmlspecialchars($serverHost, ENT_QUOTES, 'UTF-8') . '">' . htmlspecialchars($serverHost, ENT_QUOTES, 'UTF-8') . '</small>';
    }
} else {
    echo '<span class="text-secondary" style="font-size:.8rem;">' . htmlspecialchars(t('table.no_account'), ENT_QUOTES, 'UTF-8') . '</span>';
}
?>
</td>

<td>
<?php
if ($codeUsageCount > 0) {
    echo '<span class="badge" style="background:#0e7490;color:#e0f2fe;font-size:.8rem;">' . htmlspecialchars(t('login_method.playlist_code'), ENT_QUOTES, 'UTF-8') . '</span>';
} else {
    echo '<span class="badge" style="background:#1e40af;color:#dbeafe;font-size:.8rem;">' . htmlspecialchars(t('login_method.username_password'), ENT_QUOTES, 'UTF-8') . '</span>';
}
?>
</td>

<td><?php echo format_datetime_short($device['activation_date'] ?? ''); ?></td>
<td><?php echo format_device_expiry($device['expiry_date'] ?? null); ?></td>

<td class="connection" data-device-pk="<?php echo $devicePk; ?>"<?php if (!$isGuest): ?> data-device="<?php echo $rawIdAttr; ?>"<?php endif; ?>>
<?php echo htmlspecialchars(t('presence.offline'), ENT_QUOTES, 'UTF-8'); ?>
</td>

<td>
<span class="status-badge <?php echo htmlspecialchars($status, ENT_QUOTES, 'UTF-8'); ?>">
<?php echo htmlspecialchars(t('status.' . $status), ENT_QUOTES, 'UTF-8'); ?>
</span>
</td>

<td>
<a href="edit-device.php?id=<?php echo $devicePk; ?>" class="btn btn-action btn-edit">
<i class="fas fa-edit"></i>
</a>
<a href="delete-device.php?id=<?php echo $devicePk; ?>"
   class="btn btn-action btn-delete"
   data-admin-perm="devices_delete"
   data-admin-confirm
   data-confirm-post="1"
   data-confirm-action="delete-device.php"
   data-device-id="<?php echo $devicePk; ?>"
   <?php if ($listPage > 1): ?>data-list-page="<?php echo (int) $listPage; ?>"<?php endif; ?>
   data-confirm-title="<?php echo htmlspecialchars(t('delete.title'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-message="<?php echo htmlspecialchars(t('delete.question'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-warning="<?php echo htmlspecialchars(t('delete.warning'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-ok="<?php echo htmlspecialchars(t('delete.confirm_button'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-cancel="<?php echo htmlspecialchars(t('delete.cancel_short'), ENT_QUOTES, 'UTF-8'); ?>"
   data-confirm-details="<?php echo htmlspecialchars(json_encode([
       ['label' => t('table.device_name'), 'value' => (string) ($device['device_name'] ?? '')],
       ['label' => t('table.device_id'), 'value' => $displayDeviceId, 'mono' => true],
   ], JSON_UNESCAPED_UNICODE), ENT_QUOTES, 'UTF-8'); ?>">
<i class="fas fa-trash"></i>
</a>
</td>

</tr>
    <?php
    return (string) ob_get_clean();
}
