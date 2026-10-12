<?php
/**
 * بانر موحّد لوضع العرض فقط — تصميم واضح وعصري
 *
 * قبل التضمين (اختياري):
 *   $viewOnlyLangKey = 'view_only.page_hint'; // أو view_only.feedbacks_hint إلخ
 */
if (!function_exists('t')) {
    return;
}
$langKey = isset($viewOnlyLangKey) && is_string($viewOnlyLangKey) && $viewOnlyLangKey !== ''
    ? $viewOnlyLangKey
    : 'view_only.page_hint';
$bodyText = t($langKey);
$titleText = t('view_only.banner_title');
$badgeText = t('view_only.banner_badge');
if (!defined('ADMIN_VIEW_ONLY_BANNER_CSS')) {
    define('ADMIN_VIEW_ONLY_BANNER_CSS', true);
    ?>
<style>
.admin-view-only-banner {
    display: flex;
    align-items: flex-start;
    gap: 1rem;
    padding: 1rem 1.15rem;
    border-radius: 16px;
    margin-bottom: 1.25rem;
    position: relative;
    overflow: hidden;
    border: 1px solid rgba(56, 189, 248, 0.35);
    background:
        linear-gradient(135deg, rgba(15, 23, 42, 0.92) 0%, rgba(30, 41, 59, 0.88) 50%, rgba(15, 23, 42, 0.95) 100%);
    box-shadow:
        0 12px 40px rgba(2, 6, 23, 0.45),
        inset 0 1px 0 rgba(255, 255, 255, 0.06);
}
.admin-view-only-banner::before {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(ellipse 80% 120% at 0% 0%, rgba(56, 189, 248, 0.18), transparent 55%),
                radial-gradient(ellipse 70% 100% at 100% 100%, rgba(99, 102, 241, 0.14), transparent 50%);
    pointer-events: none;
}
.admin-view-only-banner__icon {
    flex-shrink: 0;
    width: 48px;
    height: 48px;
    border-radius: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.25rem;
    color: #0f172a;
    background: linear-gradient(145deg, #38bdf8, #6366f1);
    box-shadow: 0 8px 24px rgba(56, 189, 248, 0.35);
    position: relative;
    z-index: 1;
}
.admin-view-only-banner__body {
    position: relative;
    z-index: 1;
    min-width: 0;
    flex: 1;
}
.admin-view-only-banner__title {
    font-weight: 800;
    font-size: 1.02rem;
    letter-spacing: -0.02em;
    color: #f1f5f9;
    margin: 0 0 0.35rem 0;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
}
.admin-view-only-banner__badge {
    font-size: 0.65rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    padding: 0.2rem 0.5rem;
    border-radius: 999px;
    background: rgba(56, 189, 248, 0.2);
    color: #7dd3fc;
    border: 1px solid rgba(56, 189, 248, 0.35);
}
.admin-view-only-banner__text {
    margin: 0;
    font-size: 0.9rem;
    line-height: 1.65;
    color: #cbd5e1;
    font-weight: 500;
}
.staff-page-body .admin-view-only-banner {
    background: linear-gradient(135deg, #ffffff 0%, #f8fafc 45%, #f1f5f9 100%);
    border: 1px solid rgba(99, 102, 241, 0.22);
    box-shadow: 0 10px 36px rgba(79, 70, 229, 0.1);
}
.staff-page-body .admin-view-only-banner::before {
    background: radial-gradient(ellipse 90% 100% at 0% 0%, rgba(99, 102, 241, 0.12), transparent 55%),
                radial-gradient(ellipse 80% 100% at 100% 0%, rgba(56, 189, 248, 0.1), transparent 50%);
}
.staff-page-body .admin-view-only-banner__icon {
    background: linear-gradient(145deg, #6366f1, #4f46e5);
    color: #fff;
    box-shadow: 0 8px 22px rgba(79, 70, 229, 0.35);
}
.staff-page-body .admin-view-only-banner__title {
    color: #0f172a;
}
.staff-page-body .admin-view-only-banner__text {
    color: #475569;
}
.staff-page-body .admin-view-only-banner__badge {
    background: rgba(99, 102, 241, 0.12);
    color: #4338ca;
    border-color: rgba(99, 102, 241, 0.28);
}
</style>
<?php } ?>
<div class="admin-view-only-banner" role="status" aria-live="polite">
    <div class="admin-view-only-banner__icon" aria-hidden="true">
        <i class="fas fa-eye"></i>
    </div>
    <div class="admin-view-only-banner__body">
        <div class="admin-view-only-banner__title">
            <span><?php echo htmlspecialchars($titleText); ?></span>
            <span class="admin-view-only-banner__badge"><?php echo htmlspecialchars($badgeText); ?></span>
        </div>
        <p class="admin-view-only-banner__text"><?php echo htmlspecialchars($bodyText); ?></p>
    </div>
</div>
