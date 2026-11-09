// Runs without Rails: node --test test/security/service_worker_test.js
const { test } = require("node:test")
const assert = require("node:assert/strict")
const vm = require("node:vm")
const fs = require("node:fs")

test("upgrade removes private caches and offline navigation returns only generic content", async () => {
  const listeners = {}
  const removed = []
  const offline = { body: "generic offline" }
  const matches = []
  const context = {
    URL, Response,
    self: { location: { origin: "https://lms.test" }, addEventListener: (name, fn) => listeners[name] = fn,
      clients: { claim: async () => {} } },
    caches: {
      keys: async () => ["ai-lms-static-v2", "ai-lms-runtime-v2", "ai-lms-static-v3", "other-app"],
      delete: async (key) => removed.push(key),
      match: async (key) => { matches.push(key); return offline }
    },
    fetch: async () => { throw new Error("offline") }
  }
  vm.runInNewContext(fs.readFileSync("app/views/pwa/service-worker.js", "utf8"), context)
  await new Promise((resolve, reject) => listeners.activate({ waitUntil: (promise) => promise.then(resolve, reject) }))
  assert.deepEqual(removed, ["ai-lms-static-v2", "ai-lms-runtime-v2"])
  let result
  listeners.fetch({ request: { url: "https://lms.test/profile", mode: "navigate", method: "GET" },
    respondWith: (promise) => result = promise })
  assert.equal(await result, offline)
  assert.deepEqual(matches, ["/offline.html"])
  listeners.fetch({ request: { url: "https://lms.test/rails/active_storage/blobs/private", destination: "image", method: "GET" },
    respondWith: () => assert.fail("protected image must not use service worker cache") })
})
