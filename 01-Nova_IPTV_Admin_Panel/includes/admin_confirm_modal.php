<?php
/**
 * نافذة تأكيد عصرية مشتركة — استدعِ بعد bootstrap.bundle.js
 * الاستخدام:
 *   adminConfirm({ title, message, warning, details:[{label,value,mono,icon}], confirmText, cancelText, tone:'danger'|'warn' })
 *     .then(ok => { if (ok) ... })
 */
if (!empty($GLOBALS['__admin_confirm_modal_rendered'])) {
    return;
}
$GLOBALS['__admin_confirm_modal_rendered'] = true;

$__acCancel = function_exists('t') ? t('delete.cancel_short') : 'Cancel';
$__acOk = function_exists('t') ? t('bulk.delete_now') : 'Confirm';
if ($__acCancel === 'delete.cancel_short') {
    $__acCancel = 'Cancel';
}
$__acDir = (!empty($isRtl) || (function_exists('t') && isset($lang) && $lang === 'ar')) ? 'rtl' : 'ltr';
if (isset($lang) && $lang === 'en') {
    $__acDir = 'ltr';
}
if (isset($lang) && $lang === 'ar') {
    $__acDir = 'rtl';
}
?>
<div class="modal fade" id="adminConfirmModal" tabindex="-1" aria-hidden="true" aria-labelledby="adminConfirmTitle" dir="<?php echo $__acDir; ?>">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-body admin-confirm-body">
        <div class="admin-confirm-accent" aria-hidden="true"></div>
        <button type="button" class="btn-close-confirm" data-bs-dismiss="modal" aria-label="Close">
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
        <div class="admin-confirm-inner">
          <div class="admin-confirm-top">
            <div class="admin-confirm-icon" id="adminConfirmIcon" aria-hidden="true">
              <i class="fas fa-trash-can" id="adminConfirmIconGlyph"></i>
            </div>
            <div class="admin-confirm-copy">
              <h5 class="admin-confirm-title" id="adminConfirmTitle">Confirm</h5>
              <p class="admin-confirm-message" id="adminConfirmMessage"></p>
            </div>
          </div>
          <div class="admin-confirm-details d-none" id="adminConfirmDetails"></div>
          <div class="admin-confirm-warning d-none" id="adminConfirmWarning">
            <i class="fas fa-shield-halved" aria-hidden="true"></i>
            <span id="adminConfirmWarningText"></span>
          </div>
          <div class="admin-confirm-actions">
            <button type="button" class="btn btn-admin-cancel" data-bs-dismiss="modal" id="adminConfirmCancelBtn">
              <i class="fas fa-arrow-rotate-left" aria-hidden="true"></i>
              <span><?php echo htmlspecialchars($__acCancel, ENT_QUOTES, 'UTF-8'); ?></span>
            </button>
            <button type="button" class="btn btn-admin-ok" id="adminConfirmOkBtn">
              <i class="fas fa-trash-can" id="adminConfirmOkIcon" aria-hidden="true"></i>
              <span id="adminConfirmOkLabel"><?php echo htmlspecialchars($__acOk, ENT_QUOTES, 'UTF-8'); ?></span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
<script>
(function () {
  if (window.adminConfirm) return;

  var defaults = {
    cancelText: <?php echo json_encode($__acCancel, JSON_UNESCAPED_UNICODE); ?>,
    confirmText: <?php echo json_encode($__acOk, JSON_UNESCAPED_UNICODE); ?>
  };

  function el(id) { return document.getElementById(id); }

  function pageDir() {
    return document.documentElement.getAttribute('dir') ||
      (document.body && document.body.getAttribute('dir')) ||
      'ltr';
  }

  function detailIconFor(row, index) {
    if (row && row.icon) return row.icon;
    if (row && row.mono) return 'fas fa-fingerprint';
    var icons = ['fas fa-tag', 'fas fa-hashtag', 'fas fa-mobile-screen-button', 'fas fa-link'];
    return icons[index % icons.length];
  }

  function ensureModal() {
    var modalEl = el('adminConfirmModal');
    if (!modalEl || typeof bootstrap === 'undefined') return null;
    if (!modalEl._adminConfirmInst) {
      modalEl._adminConfirmInst = new bootstrap.Modal(modalEl, { backdrop: true, keyboard: true });
    }
    return modalEl;
  }

  window.adminConfirm = function (opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var modalEl = ensureModal();
      if (!modalEl) {
        resolve(window.confirm(opts.message || opts.title || 'Confirm?'));
        return;
      }

      modalEl.setAttribute('dir', pageDir());

      var tone = opts.tone === 'warn' ? 'warn' : 'danger';
      modalEl.classList.toggle('tone-warn', tone === 'warn');
      modalEl.classList.toggle('tone-danger', tone !== 'warn');

      var iconWrap = el('adminConfirmIcon');
      var iconGlyph = el('adminConfirmIconGlyph');
      var warnBox = el('adminConfirmWarning');
      var details = el('adminConfirmDetails');
      var okBtn = el('adminConfirmOkBtn');
      var okIcon = el('adminConfirmOkIcon');
      var cancelBtn = el('adminConfirmCancelBtn');
      var msgEl = el('adminConfirmMessage');

      el('adminConfirmTitle').textContent = opts.title || 'Confirm';
      if (msgEl) {
        msgEl.textContent = opts.message || '';
        msgEl.style.display = opts.message ? '' : 'none';
      }

      if (iconWrap && iconGlyph) {
        iconWrap.classList.toggle('is-warn', tone === 'warn');
        iconGlyph.className = opts.icon || (tone === 'warn' ? 'fas fa-triangle-exclamation' : 'fas fa-trash-can');
      }

      if (warnBox) {
        var w = opts.warning || '';
        warnBox.classList.toggle('d-none', !w);
        warnBox.classList.toggle('is-warn', tone === 'warn');
        var warnIcon = warnBox.querySelector('i');
        if (warnIcon) {
          warnIcon.className = tone === 'warn' ? 'fas fa-triangle-exclamation' : 'fas fa-shield-halved';
        }
        el('adminConfirmWarningText').textContent = w;
      }

      if (details) {
        details.innerHTML = '';
        var rows = Array.isArray(opts.details) ? opts.details : [];
        if (!rows.length) {
          details.classList.add('d-none');
        } else {
          details.classList.remove('d-none');
          rows.forEach(function (row, index) {
            if (!row) return;
            var item = document.createElement('div');
            item.className = 'admin-confirm-detail-row';

            var ico = document.createElement('div');
            ico.className = 'admin-confirm-detail-ico';
            ico.setAttribute('aria-hidden', 'true');
            ico.innerHTML = '<i class="' + detailIconFor(row, index) + '"></i>';

            var text = document.createElement('div');
            text.className = 'admin-confirm-detail-text';

            var lbl = document.createElement('span');
            lbl.className = 'lbl';
            lbl.textContent = row.label || '';

            var val = document.createElement('span');
            val.className = 'val' + (row.mono ? ' val-mono' : '');
            val.textContent = row.value == null || row.value === '' ? '—' : String(row.value);

            text.appendChild(lbl);
            text.appendChild(val);
            item.appendChild(ico);
            item.appendChild(text);
            details.appendChild(item);
          });
        }
      }

      if (okBtn) {
        okBtn.classList.toggle('is-warn', tone === 'warn');
        el('adminConfirmOkLabel').textContent = opts.confirmText || defaults.confirmText;
        if (okIcon) {
          okIcon.className = opts.confirmIcon || (tone === 'warn' ? 'fas fa-check' : 'fas fa-trash-can');
        }
      }
      if (cancelBtn) {
        var cancelSpan = cancelBtn.querySelector('span');
        if (cancelSpan) cancelSpan.textContent = opts.cancelText || defaults.cancelText;
      }

      var settled = false;
      var confirmed = false;
      function finish(ok) {
        if (settled) return;
        settled = true;
        modalEl.removeEventListener('hidden.bs.modal', onHidden);
        if (okBtn) okBtn.removeEventListener('click', onOk);
        resolve(!!ok);
      }
      function onOk(ev) {
        if (ev) ev.preventDefault();
        confirmed = true;
        modalEl._adminConfirmInst.hide();
        finish(true);
      }
      function onHidden() {
        finish(confirmed);
      }

      if (okBtn) okBtn.addEventListener('click', onOk);
      modalEl.addEventListener('hidden.bs.modal', onHidden, { once: true });
      modalEl._adminConfirmInst.show();
    });
  };

  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[data-admin-confirm]') : null;
    if (!a) return;
    e.preventDefault();
    var href = a.getAttribute('href') || '';
    window.adminConfirm({
      title: a.getAttribute('data-confirm-title') || '',
      message: a.getAttribute('data-confirm-message') || a.getAttribute('data-admin-confirm') || '',
      warning: a.getAttribute('data-confirm-warning') || '',
      confirmText: a.getAttribute('data-confirm-ok') || defaults.confirmText,
      cancelText: a.getAttribute('data-confirm-cancel') || defaults.cancelText,
      tone: a.getAttribute('data-confirm-tone') || 'danger',
      icon: a.getAttribute('data-confirm-icon') || '',
      details: (function () {
        try {
          var raw = a.getAttribute('data-confirm-details');
          return raw ? JSON.parse(raw) : [];
        } catch (err) { return []; }
      })()
    }).then(function (ok) {
      if (!ok) return;
      if (a.getAttribute('data-confirm-post') === '1') {
        var action = a.getAttribute('data-confirm-action') || (href.split('?')[0] || '');
        if (!action) return;
        var form = document.createElement('form');
        form.method = 'POST';
        form.action = action;
        form.style.display = 'none';
        function add(name, value) {
          var input = document.createElement('input');
          input.type = 'hidden';
          input.name = name;
          input.value = value;
          form.appendChild(input);
        }
        add('csrf_token', window.ADMIN_CSRF_TOKEN || '');
        add('confirm', 'yes');
        var deviceId = a.getAttribute('data-device-id') || '';
        if (deviceId) add('id', deviceId);
        var page = a.getAttribute('data-list-page') || '';
        if (page) add('page', page);
        document.body.appendChild(form);
        form.submit();
        return;
      }
      if (href && href !== '#') window.location.href = href;
    });
  });

  document.addEventListener('submit', function (e) {
    var form = e.target;
    if (!form || !form.getAttribute || !form.hasAttribute('data-admin-confirm')) return;
    if (form.dataset.adminConfirmArmed === '1') return;
    e.preventDefault();

    var minLen = parseInt(form.getAttribute('data-confirm-minlength') || '0', 10);
    var minName = form.getAttribute('data-confirm-minlength-name') || '';
    var minMsg = form.getAttribute('data-confirm-minlength-msg') || '';
    if (minLen > 0 && minName) {
      var field = form.querySelector('[name="' + minName + '"]');
      var val = field ? String(field.value || '') : '';
      if (val.length < minLen) {
        window.adminConfirm({
          title: form.getAttribute('data-confirm-title') || '',
          message: minMsg || ('Min length: ' + minLen),
          tone: 'warn',
          icon: 'fas fa-key',
          confirmText: defaults.cancelText,
          cancelText: defaults.cancelText,
          confirmIcon: 'fas fa-check'
        });
        return;
      }
    }

    window.adminConfirm({
      title: form.getAttribute('data-confirm-title') || '',
      message: form.getAttribute('data-confirm-message') || form.getAttribute('data-admin-confirm') || '',
      warning: form.getAttribute('data-confirm-warning') || '',
      confirmText: form.getAttribute('data-confirm-ok') || defaults.confirmText,
      cancelText: form.getAttribute('data-confirm-cancel') || defaults.cancelText,
      tone: form.getAttribute('data-confirm-tone') || 'danger',
      icon: form.getAttribute('data-confirm-icon') || '',
      confirmIcon: form.getAttribute('data-confirm-ok-icon') || '',
      details: (function () {
        try {
          var raw = form.getAttribute('data-confirm-details');
          return raw ? JSON.parse(raw) : [];
        } catch (err) { return []; }
      })()
    }).then(function (ok) {
      if (!ok) return;
      form.dataset.adminConfirmArmed = '1';
      if (typeof form.requestSubmit === 'function') form.requestSubmit();
      else form.submit();
    });
  }, true);
})();
</script>
