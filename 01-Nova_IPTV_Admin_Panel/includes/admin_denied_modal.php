<?php
/** نافذة تنبيه عصرية عند محاولة إجراء بلا صلاحية — يُحمّل بعد Bootstrap CSS في الصفحة */
if (!function_exists('adminIsLoggedIn') || !adminIsLoggedIn()) {
    return;
}
?>
<style>
@keyframes adminDeniedShake {
    0%, 100% { transform: translateX(0); }
    20% { transform: translateX(-6px); }
    40% { transform: translateX(6px); }
    60% { transform: translateX(-4px); }
    80% { transform: translateX(4px); }
}
@keyframes adminDeniedPop {
    0% { transform: scale(0.88) translateY(12px); opacity: 0; }
    70% { transform: scale(1.02) translateY(-4px); opacity: 1; }
    100% { transform: scale(1) translateY(0); opacity: 1; }
}
@keyframes adminDeniedGlow {
    0%, 100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.35); }
    50% { box-shadow: 0 0 28px 4px rgba(239, 68, 68, 0.2); }
}
#adminDeniedModal .modal-content.admin-denied-surface {
    border-radius: 22px;
    border: 1px solid rgba(148, 163, 184, 0.35);
    background: radial-gradient(circle at 20% 0%, rgba(254, 226, 226, 0.95) 0%, rgba(255, 255, 255, 0.98) 42%, rgba(241, 245, 249, 0.98) 100%);
    overflow: hidden;
    animation: adminDeniedPop 0.5s cubic-bezier(0.34, 1.35, 0.64, 1) forwards;
}
#adminDeniedModal .admin-denied-icon-wrap {
    width: 72px;
    height: 72px;
    margin: 0 auto;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(145deg, #fecaca, #f87171);
    color: #7f1d1d;
    font-size: 1.85rem;
    animation: adminDeniedGlow 2.2s ease-in-out infinite;
}
#adminDeniedModal .admin-denied-icon-wrap i {
    animation: adminDeniedShake 0.55s ease-out 0.35s 1;
}
#adminDeniedModal .admin-denied-title {
    font-weight: 800;
    color: #0f172a;
    letter-spacing: -0.02em;
}
#adminDeniedModal .admin-denied-text {
    color: #475569;
    font-size: 0.95rem;
    line-height: 1.65;
}
#adminDeniedModal .btn-admin-denied-ok {
    border-radius: 999px;
    padding: 0.55rem 1.75rem;
    font-weight: 700;
    background: linear-gradient(135deg, #6366f1, #4f46e5);
    border: none;
    box-shadow: 0 10px 28px rgba(79, 70, 229, 0.35);
}
#adminDeniedModal .btn-admin-denied-ok:hover {
    filter: brightness(1.06);
    transform: translateY(-1px);
}
</style>
<div class="modal fade" id="adminDeniedModal" tabindex="-1" aria-hidden="true" data-bs-backdrop="true">
    <div class="modal-dialog modal-dialog-centered modal-md">
        <div class="modal-content admin-denied-surface shadow-lg">
            <div class="modal-body text-center px-4 py-4 py-md-5">
                <div class="admin-denied-icon-wrap mb-3">
                    <i class="fas fa-shield-halved" aria-hidden="true"></i>
                </div>
                <h5 class="admin-denied-title mb-2" id="adminDeniedModalTitle"></h5>
                <p class="admin-denied-text mb-4" id="adminDeniedModalBody"></p>
                <button type="button" class="btn btn-primary btn-admin-denied-ok" data-bs-dismiss="modal" id="adminDeniedModalBtn"></button>
            </div>
        </div>
    </div>
</div>
<script>
(function () {
    function deniedMsg(perm) {
        var m = (window.ADMIN_DENIED_MESSAGES && window.ADMIN_DENIED_MESSAGES[perm]) || '';
        return m || (window.ADMIN_DENIED_MESSAGES && window.ADMIN_DENIED_MESSAGES._generic) || '';
    }
    function showAdminDeniedModal(perm) {
        var titleEl = document.getElementById('adminDeniedModalTitle');
        var bodyEl = document.getElementById('adminDeniedModalBody');
        var btnEl = document.getElementById('adminDeniedModalBtn');
        var modalEl = document.getElementById('adminDeniedModal');
        if (!titleEl || !bodyEl || !modalEl) return;
        titleEl.textContent = window.ADMIN_DENIED_TITLE || '';
        bodyEl.textContent = deniedMsg(perm);
        if (btnEl) btnEl.textContent = window.ADMIN_DENIED_BTN || 'OK';
        if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
            bootstrap.Modal.getOrCreateInstance(modalEl).show();
        } else {
            alert(deniedMsg(perm));
        }
    }
    window.showAdminDeniedModal = showAdminDeniedModal;

    document.addEventListener('click', function (e) {
        var el = e.target.closest('[data-admin-perm]');
        if (!el) return;
        var tag = (el.tagName || '').toLowerCase();
        if (tag !== 'a') return;
        var perm = el.getAttribute('data-admin-perm');
        if (!perm || !window.ADMIN_PERMS || window.ADMIN_PERMS[perm]) return;
        e.preventDefault();
        e.stopPropagation();
        if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
        showAdminDeniedModal(perm);
        return;
    }, true);

    document.addEventListener('submit', function (e) {
        var form = e.target;
        if (!form || !form.getAttribute) return;
        var perm = form.getAttribute('data-admin-perm');
        if (!perm || !window.ADMIN_PERMS) return;
        if (!window.ADMIN_PERMS[perm]) {
            e.preventDefault();
            e.stopPropagation();
            if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
            showAdminDeniedModal(perm);
        }
    }, true);
})();
</script>
