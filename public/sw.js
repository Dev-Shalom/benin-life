// Benin Life service worker: Web Push only (docs/BILLBOARDS.md for the owner's alerts, docs/NOTIFICATIONS.md for
// players). No fetch handler, no caching, so it never changes how the game loads or updates. Registered when a player
// or admin turns notifications on.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

// Player pushes carry `cat` (messages, money, ...) and a deep link like /play?go=dm:12. Owner pushes have no `cat`.
self.addEventListener('push', (event) => {
  let d = {};
  try {
    d = event.data ? event.data.json() : {};
  } catch {
    d = { title: 'Benin Life', body: event.data ? event.data.text() : '' };
  }
  const isPlayer = Boolean(d.cat);
  const title = d.title || (isPlayer ? 'Benin Life' : 'Benin Life admin');
  event.waitUntil(
    (async () => {
      if (isPlayer) {
        // The game is open and in front: it already shows this live, so no system notification on top of it.
        const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
        const front = list.find((c) => c.visibilityState === 'visible' && c.focused);
        if (front) {
          front.postMessage({ type: 'bl-push', cat: d.cat, kind: d.kind, title: d.title, body: d.body });
          return;
        }
      }
      await self.registration.showNotification(title, {
        body: d.body || '',
        icon: '/icon-192.png',
        badge: '/badge-96.png',
        tag: d.tag || undefined,
        renotify: Boolean(d.tag),
        data: { url: d.url || (isPlayer ? '/play' : '/admin/ads') },
      });
    })(),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/admin/ads', self.location.origin);
  const go = url.searchParams.get('go');
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const mine = list.filter((c) => c.url.startsWith(self.location.origin));
      // The game is already open: tell it where to go (no reload, nothing is lost), then bring it forward.
      const game = mine.find((c) => new URL(c.url).pathname.startsWith('/play'));
      if (go && game) {
        game.postMessage({ type: 'bl-go', go });
        return game.focus();
      }
      for (const c of mine) {
        if ('focus' in c) {
          if ('navigate' in c) c.navigate(url.href).catch(() => {});
          return c.focus();
        }
      }
      return self.clients.openWindow(url.href);
    }),
  );
});
