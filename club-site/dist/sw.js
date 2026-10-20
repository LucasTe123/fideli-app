const CACHE = "fideli-card-v41-standalone-card-guard";
const SHELL = ["/", "/manifest.webmanifest", "/storefront.css", "/storefront.js", "/icons/fideli-192.svg", "/icons/fideli-512.svg"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== location.origin) return;
  event.respondWith(fetch(event.request).then((response) => {
    const copy = response.clone();
    caches.open(CACHE).then((cache) => cache.put(event.request, copy));
    return response;
  }).catch(() => caches.match(event.request).then((cached) => cached || caches.match("/"))));
});

self.addEventListener("push", (event) => {
  const data = event.data?.json() || {};
  const title = String(data.title || "Fideli");
  const message = String(data.body || "Tu tarjeta tiene una novedad.");
  event.waitUntil(Promise.all([
    self.registration.showNotification(title, {
      body: message,
      lang: "es-BO",
      icon: data.icon || "/icons/fideli-192.svg",
      badge: data.icon || "/icons/fideli-192.svg",
      tag: data.tag || undefined,
      renotify: false,
      data: { url: data.url || "/" },
    }),
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) client.postMessage({ type: "FIDELI_CARD_UPDATED" });
    }),
  ]));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = event.notification.data?.url || "/";
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
    const open = clients.find((client) => "focus" in client);
    if (open) {
      open.navigate(target);
      return open.focus();
    }
    return self.clients.openWindow(target);
  }));
});
