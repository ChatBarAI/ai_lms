const CACHE_VERSION = "v2"
const STATIC_CACHE = `ai-lms-static-${CACHE_VERSION}`
const RUNTIME_CACHE = `ai-lms-runtime-${CACHE_VERSION}`
const OFFLINE_URL = "/offline.html"

const PRECACHE_URLS = [
	"/",
	"/courses",
	OFFLINE_URL
]

self.addEventListener("install", (event) => {
	event.waitUntil(
		caches.open(STATIC_CACHE).then((cache) => cache.addAll(PRECACHE_URLS)).then(() => self.skipWaiting())
	)
})

self.addEventListener("activate", (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((cacheNames) =>
				Promise.all(
					cacheNames
						.filter((name) => name !== STATIC_CACHE && name !== RUNTIME_CACHE)
						.map((name) => caches.delete(name))
				)
			)
			.then(() => self.clients.claim())
	)
})

self.addEventListener("fetch", (event) => {
	const request = event.request
	const url = new URL(request.url)

	if (url.origin !== self.location.origin) {
		return
	}

	if (url.pathname === "/manifest" || url.pathname.startsWith("/pwa/icons/")) {
		event.respondWith(fetch(request))
		return
	}

	if (request.mode === "navigate") {
		event.respondWith(networkFirstNavigation(request))
		return
	}

	if (request.destination === "script" || request.destination === "style" || request.destination === "image") {
		event.respondWith(cacheFirstAssets(request))
	}
})

async function networkFirstNavigation(request) {
	const cache = await caches.open(RUNTIME_CACHE)

	try {
		const response = await fetch(request)
		if (response && response.ok) {
			cache.put(request, response.clone())
		}
		return response
	} catch (_error) {
		const cachedPage = await cache.match(request)
		if (cachedPage) {
			return cachedPage
		}

		const offlineResponse = await caches.match(OFFLINE_URL)
		if (offlineResponse) {
			return offlineResponse
		}

		return new Response("Offline", { status: 503, statusText: "Offline" })
	}
}

async function cacheFirstAssets(request) {
	const cached = await caches.match(request)
	if (cached) {
		return cached
	}

	const cache = await caches.open(RUNTIME_CACHE)
	const response = await fetch(request)
	if (response && response.ok) {
		cache.put(request, response.clone())
	}
	return response
}
