// Cache only the generic, public offline document. Never persist authenticated
// HTML or files, regardless of destination or HTTP cache headers.
const STATIC_CACHE = "ai-lms-static-v3"
const OFFLINE_URL = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(STATIC_CACHE)
    .then((cache) => cache.add(OFFLINE_URL))
    .then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys()
    .then((names) => Promise.all(names
      .filter((name) => name.startsWith("ai-lms-") && name !== STATIC_CACHE)
      .map((name) => caches.delete(name))))
    .then(() => self.clients.claim()))
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return
  if (request.mode === "navigate") {
    event.respondWith(fetch(request, { cache: "no-store" }).catch(async () =>
      (await caches.match(OFFLINE_URL)) || new Response("Offline", { status: 503 })))
  }
})
