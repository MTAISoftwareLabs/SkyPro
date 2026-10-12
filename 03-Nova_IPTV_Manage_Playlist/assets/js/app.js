(function () {
  var html = document.documentElement;

  function currentLang() {
    return html.getAttribute('lang') === 'ar' ? 'ar' : 'en';
  }

  function updateThemeLabels() {
    var theme = html.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
    var lang = currentLang();
    var title = document.querySelector('.theme-mode-title');
    var hint = document.querySelector('.theme-mode-hint');
    var btn = document.getElementById('themeToggle');
    if (lang === 'ar') {
      if (title) title.textContent = theme === 'light' ? 'الوضع الفاتح' : 'الوضع الداكن';
      if (hint) hint.textContent = theme === 'light' ? 'مظهر Nova النهاري' : 'مظهر Nova الليلي';
      if (btn) btn.setAttribute('aria-label', 'تبديل الوضع الفاتح والداكن');
    } else {
      if (title) title.textContent = theme === 'light' ? 'Light mode' : 'Dark mode';
      if (hint) hint.textContent = theme === 'light' ? 'Nova day look' : 'Nova night look';
      if (btn) btn.setAttribute('aria-label', 'Toggle light and dark theme');
    }
    if (btn) btn.setAttribute('aria-pressed', theme === 'light' ? 'true' : 'false');
  }

  function setTheme(theme) {
    theme = theme === 'light' ? 'light' : 'dark';
    html.setAttribute('data-theme', theme);
    try { localStorage.setItem('mp_theme', theme); } catch (e) {}
    updateThemeLabels();
  }

  var themeBtn = document.getElementById('themeToggle');
  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var current = html.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
      setTheme(current === 'light' ? 'dark' : 'light');
    });
  }
  updateThemeLabels();

  // Persist language choice in cookie when using ?lang=
  document.querySelectorAll('.lang-btn').forEach(function (a) {
    a.addEventListener('click', function () {
      var lang = a.getAttribute('href') || '';
      var m = lang.match(/lang=(en|ar)/);
      if (m) {
        try {
          document.cookie = 'mp_lang=' + m[1] + ';path=/;max-age=31536000;SameSite=Lax';
        } catch (e) {}
      }
    });
  });

  var scrollLockY = 0;

  function lockPageScroll() {
    if (html.classList.contains('modal-open')) return;
    scrollLockY = window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
    html.classList.add('modal-open');
    document.body.classList.add('modal-open');
    document.body.style.top = '-' + scrollLockY + 'px';
  }

  function unlockPageScroll() {
    html.classList.remove('modal-open');
    document.body.classList.remove('modal-open');
    document.body.style.top = '';
    window.scrollTo(0, scrollLockY);
  }

  window.mpOpenModal = function (id) {
    var el = document.getElementById(id);
    if (!el) return;
    if (el.parentElement !== document.body) {
      document.body.appendChild(el);
    }
    el.classList.add('is-open');
    lockPageScroll();
    syncModalKeyboardPad();
    window.setTimeout(function () {
      var pin = el.querySelector('input[name="pin"], input[type="password"]');
      var first = el.querySelector('input:not([type="hidden"])');
      var focusEl = ((id === 'deleteModal' || id === 'revealModal') && pin) ? pin : (first || pin);
      if (focusEl) focusEl.focus();
    }, 50);
  };
  window.mpCloseModal = function (id) {
    var el = document.getElementById(id);
    if (el) el.classList.remove('is-open');
    if (!document.querySelector('.modal-backdrop.is-open')) {
      unlockPageScroll();
    }
    syncModalKeyboardPad();
  };

  function isScrollInsideModal(target) {
    var modal = target && target.closest ? target.closest('.modal') : null;
    if (!modal) return false;
    return modal.scrollHeight > modal.clientHeight + 2;
  }

  document.addEventListener('touchmove', function (e) {
    if (!html.classList.contains('modal-open')) return;
    if (isScrollInsideModal(e.target)) return;
    e.preventDefault();
  }, { passive: false });

  document.addEventListener('wheel', function (e) {
    if (!html.classList.contains('modal-open')) return;
    if (isScrollInsideModal(e.target)) return;
    e.preventDefault();
  }, { passive: false });

  function syncModalKeyboardPad() {
    var modal = document.querySelector('.modal-backdrop.is-open .modal');
    if (!modal || !window.visualViewport) {
      document.querySelectorAll('.modal').forEach(function (m) {
        m.style.removeProperty('--kb-inset');
      });
      return;
    }
    var vv = window.visualViewport;
    var kb = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
    modal.style.setProperty('--kb-inset', kb + 'px');
  }
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', syncModalKeyboardPad);
    window.visualViewport.addEventListener('scroll', syncModalKeyboardPad);
  }

  document.querySelectorAll('[data-open-modal]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var id = btn.getAttribute('data-open-modal');
      var playlistId = btn.getAttribute('data-id') || '';
      var name = btn.getAttribute('data-name') || '';
      var url = btn.getAttribute('data-url') || '';
      if (id === 'editModal') {
        var eid = document.getElementById('editPlaylistId');
        var ename = document.getElementById('editName');
        var eurl = document.getElementById('editUrl');
        if (eid) eid.value = playlistId;
        if (ename) ename.value = name;
        if (eurl) eurl.value = '';
      }
      if (id === 'deleteModal') {
        var did = document.getElementById('deletePlaylistId');
        var dname = document.getElementById('deletePlaylistName');
        if (did) did.value = playlistId;
        if (dname) dname.textContent = name;
      }
      if (id === 'revealModal') {
        var rid = document.getElementById('revealPlaylistId');
        var rname = document.getElementById('revealPlaylistName');
        var rpin = document.getElementById('revealPin');
        var rerr = document.getElementById('revealError');
        var rres = document.getElementById('revealResult');
        var rbox = document.getElementById('revealUrlBox');
        var rsub = document.getElementById('revealSubmitBtn');
        var rcopy = document.getElementById('revealCopyBtn');
        var rpinField = document.getElementById('revealPinField');
        if (rid) rid.value = playlistId;
        if (rname) rname.textContent = name;
        if (rpin) rpin.value = '';
        if (rerr) {
          rerr.hidden = true;
          rerr.textContent = '';
        }
        if (rres) rres.hidden = true;
        if (rbox) {
          rbox.textContent = '';
          rbox.removeAttribute('data-url');
        }
        if (rsub) rsub.hidden = false;
        if (rcopy) rcopy.hidden = true;
        if (rpinField) rpinField.hidden = false;
        var rform = document.getElementById('revealForm');
        if (rform) rform.classList.remove('is-revealed');
      }
      window.mpOpenModal(id);
    });
  });

  document.querySelectorAll('[data-close-modal]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      window.mpCloseModal(btn.getAttribute('data-close-modal'));
    });
  });

  document.querySelectorAll('.modal-backdrop').forEach(function (backdrop) {
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop) window.mpCloseModal(backdrop.id);
    });
  });

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    var open = document.querySelector('.modal-backdrop.is-open');
    if (open) window.mpCloseModal(open.id);
  });

  (function () {
    var form = document.getElementById('revealForm');
    if (!form) return;
    var errEl = document.getElementById('revealError');
    var resEl = document.getElementById('revealResult');
    var boxEl = document.getElementById('revealUrlBox');
    var pinField = document.getElementById('revealPinField');
    var submitBtn = document.getElementById('revealSubmitBtn');
    var copyBtn = document.getElementById('revealCopyBtn');

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (errEl) {
        errEl.hidden = true;
        errEl.textContent = '';
      }
      var fd = new FormData(form);
      fetch('dashboard.php', {
        method: 'POST',
        body: fd,
        credentials: 'same-origin',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          Accept: 'application/json'
        }
      })
        .then(function (r) {
          return r.json().then(function (data) {
            return { ok: r.ok, data: data || {} };
          }).catch(function () {
            return { ok: false, data: {} };
          });
        })
        .then(function (result) {
          var data = result.data || {};
          if (result.ok && data.success && data.url) {
            if (boxEl) {
              boxEl.textContent = data.url;
              boxEl.setAttribute('data-url', data.url);
            }
            if (resEl) resEl.hidden = false;
            if (pinField) pinField.hidden = true;
            if (submitBtn) submitBtn.hidden = true;
            if (copyBtn) copyBtn.hidden = false;
            form.classList.add('is-revealed');
            return;
          }
          if (errEl) {
            errEl.hidden = false;
            errEl.textContent = data.message || '';
          }
        })
        .catch(function () {
          if (errEl) {
            errEl.hidden = false;
            errEl.textContent = currentLang() === 'ar'
              ? 'تعذر الاتصال. حاول مرة أخرى.'
              : 'Could not connect. Try again.';
          }
        });
    });

    if (copyBtn) {
      copyBtn.addEventListener('click', function () {
        var url = (boxEl && (boxEl.getAttribute('data-url') || boxEl.textContent)) || '';
        if (!url) return;
        var done = function () {
          var span = copyBtn.querySelector('span');
          if (!span) return;
          var prev = span.textContent;
          span.textContent = copyBtn.getAttribute('data-copied') || prev;
          setTimeout(function () {
            span.textContent = prev;
          }, 1600);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done).catch(function () {
            try {
              var ta = document.createElement('textarea');
              ta.value = url;
              document.body.appendChild(ta);
              ta.select();
              document.execCommand('copy');
              document.body.removeChild(ta);
              done();
            } catch (err) {}
          });
        }
      });
    }
  })();

  // عدّاد المدة المتبقية + مزامنة حيّة (أرقام + شريط بدون تحديث الصفحة)
  (function () {
    var el = document.getElementById('remainBig');
    var card = document.getElementById('remainCard');
    if (!el) return;

    var daysEl = document.getElementById('remainDays');
    var daysLabelEl = document.getElementById('remainDaysLabel');
    var subEl = document.getElementById('remainSub');
    var untilEl = document.getElementById('remainUntil');
    var bar = document.getElementById('remainBarFill') || document.querySelector('.remain-bar span');
    var deltaEl = document.getElementById('remainDelta');

    var daysL = el.getAttribute('data-days-label') || 'days';
    var hoursL = el.getAttribute('data-hours-label') || 'hours';
    var minsL = el.getAttribute('data-mins-label') || 'min';
    var expiredL = el.getAttribute('data-expired-label') || 'Expired';
    var lifetimeL = el.getAttribute('data-lifetime-label') || 'Lifetime';
    var untilLifeL = el.getAttribute('data-until-life-label') || 'Never expires';
    var extendL = el.getAttribute('data-extend-label') || 'Duration extended';
    var shrinkL = el.getAttribute('data-shrink-label') || 'Duration shortened';

    var expiryMs = parseInt(el.getAttribute('data-expiry') || '0', 10) * 1000;
    var currentPercent = Math.max(
      0,
      Math.min(100, parseInt(el.getAttribute('data-percent') || '0', 10) || 0)
    );
    var maxSeconds = parseInt(el.getAttribute('data-max-seconds') || '0', 10) || 0;
    if (maxSeconds <= 0) {
      // احتياط: سنتان تقريباً
      maxSeconds = Math.floor((Date.now() + 2 * 365.25 * 86400000 - Date.now()) / 1000);
    }
    var currentSeconds = Math.max(0, Math.floor((expiryMs - Date.now()) / 1000));
    var animToken = 0;
    var pollBusy = false;
    var animating = false;

    function syncRemainSupport(active, sec, isLifetime) {
      var support = document.getElementById('remainSupport');
      var card = document.getElementById('remainCard');
      if (!card) return;
      var renewWithin = parseInt(card.getAttribute('data-renew-within') || '5', 10);
      if (!isFinite(renewWithin) || renewWithin < 1) renewWithin = 5;
      var seconds = Math.max(0, parseInt(sec, 10) || 0);
      var daysLeft = Math.floor(seconds / 86400);
      var expired = !active || seconds <= 0;
      /* Lifetime or ≥ 5 full days left → hide. Renew only if daysLeft < 5. */
      var need = !isLifetime && (expired || daysLeft < renewWithin);
      if (!need) {
        if (support) {
          support.hidden = true;
          support.setAttribute('hidden', '');
          support.style.display = 'none';
        }
        card.classList.remove('is-expired-support', 'is-renew-support');
        return;
      }
      if (!support) return;
      var kind = expired ? 'expired' : 'renew';
      support.hidden = false;
      support.removeAttribute('hidden');
      support.style.display = '';
      support.setAttribute('data-kind', kind);
      card.classList.toggle('is-expired-support', expired);
      card.classList.toggle('is-renew-support', !expired);
      var hintEl = document.getElementById('remainSupportHint');
      var btnLabel = document.getElementById('remainSupportBtnLabel');
      var btnIco = document.getElementById('remainSupportBtnIco');
      var btn = document.getElementById('remainSupportBtn');
      if (hintEl) {
        hintEl.textContent = support.getAttribute(kind === 'expired' ? 'data-hint-expired' : 'data-hint-renew') || '';
      }
      if (btnLabel) {
        btnLabel.textContent = support.getAttribute(kind === 'expired' ? 'data-btn-expired' : 'data-btn-renew') || '';
      }
      if (btnIco) {
        btnIco.className = 'fa-solid ' + (kind === 'expired' ? 'fa-key' : 'fa-rotate-right');
      }
      if (btn) {
        var nextHref = support.getAttribute(kind === 'expired' ? 'data-href-expired' : 'data-href-renew') || '';
        if (nextHref) btn.setAttribute('href', nextHref);
      }
    }

    var lifetime = el.getAttribute('data-lifetime') === '1';

    function percentFromSeconds(sec) {
      if (maxSeconds <= 0) return 0;
      return Math.max(0, Math.min(100, Math.round((Math.max(0, sec) / maxSeconds) * 100)));
    }

    function easeOutCubic(t) {
      return 1 - Math.pow(1 - t, 3);
    }

    function splitSec(sec) {
      sec = Math.max(0, Math.floor(sec));
      return {
        days: Math.floor(sec / 86400),
        hours: Math.floor((sec % 86400) / 3600),
        mins: Math.floor((sec % 3600) / 60),
        sec: sec
      };
    }

    function readBarPercent() {
      if (!bar) return currentPercent;
      var w = bar.style.width || '';
      if (w.indexOf('%') >= 0) {
        var n = parseFloat(w);
        if (!isNaN(n)) return Math.max(0, Math.min(100, n));
      }
      return currentPercent;
    }

    function paintLifetime() {
      lifetime = true;
      el.setAttribute('data-lifetime', '1');
      if (!daysEl) return;
      daysEl.classList.remove('is-expired');
      daysEl.textContent = '∞';
      if (daysLabelEl) {
        daysLabelEl.hidden = false;
        daysLabelEl.textContent = lifetimeL;
      }
      if (subEl) {
        subEl.hidden = true;
        subEl.textContent = '';
      }
      if (untilEl) untilEl.textContent = '∞';
      setBarWidth(100);
      syncRemainSupport(true, currentSeconds, true);
    }

    function paintActive(parts) {
      if (!daysEl) return;
      daysEl.classList.remove('is-expired');
      daysEl.textContent = String(parts.days);
      if (daysLabelEl) {
        daysLabelEl.hidden = false;
        daysLabelEl.textContent = daysL;
      }
      if (subEl) {
        subEl.hidden = false;
        subEl.textContent = parts.hours + ' ' + hoursL + ' · ' + parts.mins + ' ' + minsL;
      }
      syncRemainSupport(true, currentSeconds, lifetime);
    }

    function paintExpired() {
      if (!daysEl) return;
      daysEl.textContent = expiredL;
      daysEl.classList.add('is-expired');
      daysEl.classList.remove('is-animating');
      if (daysLabelEl) daysLabelEl.hidden = true;
      if (subEl) {
        subEl.hidden = true;
        subEl.textContent = '';
      }
      syncRemainSupport(false, 0, lifetime);
    }

    function setBarWidth(pct) {
      if (!bar) return;
      currentPercent = Math.max(0, Math.min(100, pct));
      bar.style.width = currentPercent + '%';
    }

    function flashDelta(kind) {
      if (!deltaEl) return;
      deltaEl.hidden = false;
      deltaEl.classList.remove('is-extend', 'is-shrink');
      deltaEl.classList.add(kind === 'extend' ? 'is-extend' : 'is-shrink');
      deltaEl.innerHTML =
        '<i class="fa-solid ' +
        (kind === 'extend' ? 'fa-arrow-trend-up' : 'fa-arrow-trend-down') +
        '"></i> ' +
        (kind === 'extend' ? extendL : shrinkL);
      clearTimeout(flashDelta._t);
      flashDelta._t = setTimeout(function () {
        deltaEl.hidden = true;
      }, 3600);
    }

    function playCardMotion(kind) {
      if (!card) return;
      card.classList.remove('is-extend', 'is-shrink', 'is-updating');
      void card.offsetWidth;
      card.classList.add('is-updating', kind === 'extend' ? 'is-extend' : 'is-shrink');
      clearTimeout(playCardMotion._t);
      playCardMotion._t = setTimeout(function () {
        card.classList.remove('is-updating', 'is-extend', 'is-shrink');
      }, 1600);
    }

    /** انتقال سلس للأرقام والشريط بدون إعادة تحميل الصفحة */
    function animateTo(targetSec, targetPct, targetExpiryMs, expiryLabel, active) {
      var fromSec = currentSeconds;
      var toSec = Math.max(0, targetSec | 0);
      var fromPct = percentFromSeconds(fromSec);
      var toPct = active
        ? (typeof targetPct === 'number' ? targetPct : percentFromSeconds(toSec))
        : 0;
      toPct = Math.max(0, Math.min(100, toPct));
      var kind = toSec >= fromSec ? 'extend' : 'shrink';
      var duration = Math.min(1800, Math.max(900, Math.abs(toSec - fromSec) / 80));

      if (untilEl && expiryLabel) untilEl.textContent = expiryLabel;
      expiryMs = targetExpiryMs;
      el.setAttribute('data-expiry', String(Math.floor(targetExpiryMs / 1000)));
      el.setAttribute('data-percent', String(toPct));

      if (!active || toSec <= 0) {
        animating = false;
        currentSeconds = 0;
        setBarWidth(0);
        paintExpired();
        return;
      }

      // إن كان الفرق بسيطاً جداً لا حاجة لأنيميشن طويل
      if (Math.abs(toSec - fromSec) < 45 && Math.abs(toPct - fromPct) < 1) {
        currentSeconds = toSec;
        setBarWidth(toPct);
        paintActive(splitSec(toSec));
        return;
      }

      animating = true;
      playCardMotion(kind);
      flashDelta(kind);
      if (daysEl) {
        daysEl.classList.remove('is-animating');
        void daysEl.offsetWidth;
        daysEl.classList.add('is-animating');
      }

      // ثبّت نقطة بداية الشريط ثم حرّكه مع الأرقام (نسبةً لسنتين)
      if (bar) {
        bar.style.transition = 'none';
        setBarWidth(fromPct);
        void bar.offsetWidth;
        bar.style.transition = 'none';
      }

      var token = ++animToken;
      var start = null;
      function frame(ts) {
        if (token !== animToken) return;
        if (start === null) start = ts;
        var p = Math.min(1, (ts - start) / duration);
        var e = easeOutCubic(p);
        var secNow = Math.round(fromSec + (toSec - fromSec) * e);
        currentSeconds = secNow;
        paintActive(splitSec(secNow));
        var pctNow = percentFromSeconds(secNow);
        if (bar) bar.style.width = pctNow.toFixed(2) + '%';
        currentPercent = pctNow;
        if (p < 1) {
          requestAnimationFrame(frame);
        } else {
          currentSeconds = toSec;
          currentPercent = toPct;
          setBarWidth(toPct);
          paintActive(splitSec(toSec));
          animating = false;
          if (daysEl) {
            setTimeout(function () {
              daysEl.classList.remove('is-animating');
            }, 180);
          }
        }
      }
      requestAnimationFrame(frame);
    }

    function tickLocal() {
      if (lifetime || animating || !expiryMs) return;
      var sec = Math.max(0, Math.floor((expiryMs - Date.now()) / 1000));
      currentSeconds = sec;
      if (sec <= 0) {
        paintExpired();
        setBarWidth(0);
        return;
      }
      paintActive(splitSec(sec));
    }

    function pollRemain() {
      if (pollBusy || document.hidden || animating) return;
      pollBusy = true;
      fetch('remain-status.php?_=' + Date.now(), {
        credentials: 'same-origin',
        headers: { Accept: 'application/json' },
        cache: 'no-store'
      })
        .then(function (r) {
          if (!r.ok) throw new Error('bad');
          return r.json();
        })
        .then(function (data) {
          if (!data || !data.ok) return;
          var nextExpiry = (parseInt(data.expiry_ts || 0, 10) || 0) * 1000;
          var nextSec = parseInt(data.seconds || 0, 10);
          if (isNaN(nextSec)) {
            nextSec = Math.max(0, Math.floor((nextExpiry - Date.now()) / 1000));
          }
          var nextPct = Math.max(0, Math.min(100, parseInt(data.percent || 0, 10) || 0));
          if (data.max_seconds) {
            maxSeconds = parseInt(data.max_seconds, 10) || maxSeconds;
            el.setAttribute('data-max-seconds', String(maxSeconds));
          }
          // إن لم تأتِ نسبة من السيرفر احسبها نسبةً لسنتين
          if (!data.percent && data.percent !== 0) {
            nextPct = percentFromSeconds(nextSec);
          }
          var active = !!data.active;
          if (data.lifetime) {
            lifetime = true;
            el.setAttribute('data-lifetime', '1');
            if (untilEl) untilEl.textContent = data.expiry_label === '∞' ? '∞' : (untilLifeL || '∞');
            paintLifetime();
            return;
          }
          lifetime = false;
          el.setAttribute('data-lifetime', '0');

          // تغيّر واضح في الانتهاء أو الثواني المتبقية → أنيميشن حي
          var expiryChanged = Math.abs(nextExpiry - expiryMs) > 1500;
          var secChanged = Math.abs(nextSec - currentSeconds) > 90;
          if (expiryChanged || secChanged) {
            animateTo(nextSec, nextPct, nextExpiry, data.expiry_label || '', active);
          } else {
            expiryMs = nextExpiry;
            currentSeconds = nextSec;
            if (untilEl && data.expiry_label) untilEl.textContent = data.expiry_label;
            if (!animating) {
              if (active && nextSec > 0) paintActive(splitSec(nextSec));
              else paintExpired();
            }
          }
        })
        .catch(function () {})
        .finally(function () {
          pollBusy = false;
        });
    }

    // حالة ابتدائية
    if (lifetime) {
      paintLifetime();
    } else if (currentSeconds > 0) paintActive(splitSec(currentSeconds));
    else if (expiryMs > Date.now()) {
      currentSeconds = Math.max(0, Math.floor((expiryMs - Date.now()) / 1000));
      paintActive(splitSec(currentSeconds));
    } else {
      paintExpired();
    }
    setBarWidth(currentPercent);
    syncRemainSupport(currentSeconds > 0, currentSeconds, lifetime);

    setInterval(tickLocal, 20000);
    setInterval(pollRemain, 2000);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) pollRemain();
    });
    setTimeout(pollRemain, 600);
  })();
})();
