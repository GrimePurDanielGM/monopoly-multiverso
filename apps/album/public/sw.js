// Service worker del álbum familiar: permite instalar la web como app
// (Android/iPhone) y abrirla sin conexión con lo último que se vio.

const VERSION = 'album-v1';
const SHELL = [
  '/',
  '/styles.css',
  '/app.js',
  '/manifest.webmanifest',
  '/favicon.svg',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((claves) => Promise.all(claves.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  // El API y las fotos subidas van siempre a la red (datos en vivo)
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/uploads/')) return;

  event.respondWith(
    fetch(event.request)
      .then((res) => {
        const copia = res.clone();
        caches.open(VERSION).then((cache) => cache.put(event.request, copia)).catch(() => {});
        return res;
      })
      .catch(() =>
        caches
          .match(event.request, { ignoreSearch: true })
          .then((guardada) => guardada || caches.match('/')),
      ),
  );
});
