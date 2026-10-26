// Smart HR staff portal service worker.
//
// Deliberately minimal: attendance data is live, legally significant, and
// geofenced, so nothing under /api or /mobile is ever served from cache. The
// worker exists to make the app installable and to show an honest offline
// screen instead of the browser's error page.
const VERSION = 'smarthr-v1';
const OFFLINE_URL = '/offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll([OFFLINE_URL, '/manifest.webmanifest'])),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key)))),
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Only page navigations get a fallback; everything else goes to the network.
  if (request.mode !== 'navigate') return;

  event.respondWith(
    fetch(request).catch(async () => {
      const cache = await caches.open(VERSION);
      return (await cache.match(OFFLINE_URL)) ?? Response.error();
    }),
  );
});
