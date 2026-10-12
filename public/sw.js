// H3 Benin Life service worker: ONLY admin Web Push (docs/BILLBOARDS.md). No fetch handler, no caching,
// so it never changes how the game loads or updates. Registered from /admin when an admin taps "Notify me".
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try {
    d = event.data ? event.data.json() : {};
  } catch {
    d = { title: 'Benin Life admin', body: event.data ? event.data.text() : '' };
  }
  const title = d.title || 'Benin Life admin';
  event.waitUntil(
    self.registration.showNotification(title, {
      body: d.body || '',
      icon: '/icon-192.png',
      badge: '/badge-96.png',
      tag: d.tag || undefined,
      renotify: Boolean(d.tag),
      data: { url: d.url || '/admin/ads' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/admin/ads', self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.startsWith(self.location.origin) && 'focus' in c) {
          if ('navigate' in c) c.navigate(url).catch(() => {});
          return c.focus();
        }
      }
      return self.clients.openWindow(url);
    }),
  );
});
