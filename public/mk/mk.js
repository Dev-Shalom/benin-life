/* Benin Life marketing kit, behaviour for the static pages (/about/, /faq/, /sponsor/).
 * The React marketing screens do the same in src/screens/mk/ (ThemeToggle.tsx, useMk.ts, src/lib/theme.ts).
 * Needs the inline head script that sets data-theme before first paint. Plain JS, no libraries.
 */
(function () {
  var doc = document.documentElement;
  var KEY = 'bl.prefs.v1';
  doc.classList.add('mk-js');
  var reduceMq = window.matchMedia('(prefers-reduced-motion: reduce)');

  /* ---- Theme: same stored choice as the game (light | dark | system). ---- */
  function current() { return doc.getAttribute('data-theme') === 'light' ? 'light' : 'dark'; }
  function save(t) {
    try {
      var p = JSON.parse(localStorage.getItem(KEY) || '{}') || {};
      p.theme = t;
      localStorage.setItem(KEY, JSON.stringify(p));
    } catch (e) { /* storage blocked: the choice lasts for this page only */ }
  }
  function paint() {
    var t = current();
    var m = document.querySelector('meta[name="theme-color"]');
    if (m) m.setAttribute('content', t === 'light' ? '#f6f5f2' : '#0e0f11');
    var label = t === 'dark' ? 'Switch to light theme' : 'Switch to dark theme';
    [].forEach.call(document.querySelectorAll('[data-theme-toggle]'), function (b) { b.setAttribute('aria-label', label); b.title = label; });
  }
  function setTheme(next, btn) {
    function apply() { doc.setAttribute('data-theme', next); save(next); paint(); }
    if (next === current()) return;
    if (reduceMq.matches) { apply(); return; }
    if (!document.startViewTransition || !btn) {
      doc.classList.add('theme-fade');
      apply();
      setTimeout(function () { doc.classList.remove('theme-fade'); }, 320);
      return;
    }
    var r = btn.getBoundingClientRect();
    var x = r.left + r.width / 2, y = r.top + r.height / 2;
    var end = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
    doc.classList.add('mk-vt');
    var vt = document.startViewTransition(apply);
    vt.ready.then(function () {
      doc.animate(
        { clipPath: ['circle(0px at ' + x + 'px ' + y + 'px)', 'circle(' + end + 'px at ' + x + 'px ' + y + 'px)'] },
        { duration: 520, easing: 'cubic-bezier(0.23, 1, 0.32, 1)', pseudoElement: '::view-transition-new(root)' }
      );
    }, function () {});
    vt.finished.then(function () { doc.classList.remove('mk-vt'); }, function () { doc.classList.remove('mk-vt'); });
  }
  [].forEach.call(document.querySelectorAll('[data-theme-toggle]'), function (b) {
    b.addEventListener('click', function () { setTheme(current() === 'dark' ? 'light' : 'dark', b); });
  });
  paint();
  // No saved choice yet: keep following the phone setting live.
  try {
    var dark = window.matchMedia('(prefers-color-scheme: dark)');
    dark.addEventListener('change', function () {
      var c = (JSON.parse(localStorage.getItem(KEY) || '{}') || {}).theme;
      if (c === 'light' || c === 'dark') return;
      doc.setAttribute('data-theme', dark.matches ? 'dark' : 'light');
      paint();
    });
  } catch (e) { /* old browser */ }

  /* ---- Frosted nav once the page has moved (observer, not a scroll listener). ---- */
  var nav = document.querySelector('.mk-nav');
  if (nav && 'IntersectionObserver' in window) {
    var s = document.createElement('div');
    s.className = 'mk-sentinel';
    document.body.prepend(s);
    new IntersectionObserver(function (e) { nav.classList.toggle('is-stuck', !e[0].isIntersecting); }).observe(s);
  }

  /* ---- Reveal on enter, once. ---- */
  function countUp(el) {
    var to = +el.dataset.count, suf = el.dataset.suffix || '';
    if (reduceMq.matches) { el.textContent = to.toLocaleString('en-NG') + suf; return; }
    var t0 = performance.now(), dur = 1400;
    function tick(t) {
      var k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 4);
      el.textContent = Math.round(to * e).toLocaleString('en-NG') + suf;
      if (k < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }
  var items = document.querySelectorAll('.mk-rise, .mk-reveal-media');
  if (!('IntersectionObserver' in window)) {
    [].forEach.call(items, function (el) { el.classList.add('in'); });
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (!en.isIntersecting) return;
      en.target.classList.add('in');
      io.unobserve(en.target);
      var c = en.target.querySelector('[data-count]');
      if (c) countUp(c);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
  [].forEach.call(items, function (el) { io.observe(el); });
  // The first screen is visible at load: reveal it on the next frame so the transition plays.
  requestAnimationFrame(function () {
    [].forEach.call(document.querySelectorAll('[data-hero] .mk-rise, [data-hero] .mk-reveal-media, [data-hero].mk-rise'), function (el) { el.classList.add('in'); });
  });
})();
