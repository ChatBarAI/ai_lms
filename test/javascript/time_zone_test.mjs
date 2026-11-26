import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/time_zone_controller.js", import.meta.url), "utf8")

function controller(options = {}) {
  const listeners = new Map()
  const requests = []
  const visits = []
  const document = {
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    querySelector: selector => selector.includes("csrf-token") ? { content: "csrf" } : null
  }
  const window = {
    location: { href: "https://lms.example/profile" },
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name)
  }
  const Klass = vm.runInNewContext(source.replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.TimeZoneController = class"), {
    Controller: class {}, document, window,
    Intl: { DateTimeFormat: () => ({ resolvedOptions: () => ({ timeZone: options.zone ?? "Asia/Singapore" }) }) },
    Turbo: { visit: (...args) => visits.push(args) },
    fetch: async (...args) => {
      requests.push(args)
      return options.response ?? { ok: true, redirected: false }
    }
  })
  const instance = Object.assign(new Klass(), {
    urlValue: "/profile/browser_time_zone", savedValue: "", effectiveValue: "UTC", manualValue: false,
    refreshValue: true, ...options.values
  })
  return { instance, requests, visits, listeners }
}

test("sends timezone with CSRF and refreshes the initial automatic page once", async () => {
  const { instance, requests, visits } = controller()
  await instance.sync()
  assert.equal(requests.length, 1)
  assert.equal(requests[0][1].method, "PATCH")
  assert.equal(requests[0][1].headers["X-CSRF-Token"], "csrf")
  assert.deepEqual(JSON.parse(requests[0][1].body), { time_zone: "Asia/Singapore" })
  assert.equal(visits.length, 1)
  await instance.sync()
  assert.equal(requests.length, 1)
})

test("manual override preserves displayed timezone while saving the detected zone", async () => {
  const { instance, requests, visits } = controller({ values: { manualValue: true } })
  await instance.sync()
  assert.equal(requests.length, 1)
  assert.equal(visits.length, 0)
})

test("unchanged device timezone causes no request", async () => {
  const { instance, requests } = controller({ values: { savedValue: "Asia/Singapore" } })
  await instance.sync()
  assert.equal(requests.length, 0)
})

test("edited forms are neither refreshed nor resynchronized", async () => {
  const { instance, requests, visits } = controller()
  instance.dirty = true
  await instance.sync()
  assert.equal(requests.length, 0)
  assert.equal(visits.length, 0)
})

test("a non-GET page such as a rejected submission is not refreshed", async () => {
  const { instance, requests, visits } = controller({ values: { refreshValue: false } })
  await instance.sync()
  assert.equal(requests.length, 1)
  assert.equal(visits.length, 0)
})

test("failed or redirected responses leave the current page intact", async () => {
  for (const response of [{ ok: false }, { ok: true, redirected: true }]) {
    const { instance, visits } = controller({ response })
    await instance.sync()
    assert.equal(instance.savedValue, "")
    assert.equal(visits.length, 0)
  }
})

test("late response after disconnect does not navigate", async () => {
  const { instance, visits } = controller()
  const saving = instance.sync()
  instance.disconnected = true
  await saving
  assert.equal(visits.length, 0)
})

test("disconnect cleans up detection and dirty-form listeners", async () => {
  const { instance, listeners } = controller()
  instance.connect()
  assert.equal(listeners.size, 5)
  instance.disconnect()
  assert.equal(listeners.size, 0)
})


test("typing or submitting while detection is pending prevents a refresh", async () => {
  const { instance, visits } = controller()
  const saving = instance.sync()
  instance.dirty = true
  await saving
  assert.equal(visits.length, 0)
})
