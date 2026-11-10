import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/chatbar_name_controller.js", import.meta.url), "utf8")
function editor(fetch) {
  const context = vm.createContext({ Controller: class {}, AbortController, fetch,
    document: { querySelector: () => ({ content: "csrf" }) } })
  const Klass = vm.runInContext(source.replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.ChatbarName = class"), context)
  const controller = Object.assign(new Klass(), {
    keyTarget: { value: "" }, nameTarget: { textContent: "Saved tutor" }, urlValue: "/courses/algebra/chatbar_name"
  })
  controller.connect()
  return controller
}

test("looks up an unsaved key with a CSRF-protected POST", async () => {
  const controller = editor(async (url, options) => {
    assert.equal(url, "/courses/algebra/chatbar_name")
    assert.equal(options.method, "POST")
    assert.equal(options.headers["X-CSRF-Token"], "csrf")
    assert.deepEqual(JSON.parse(options.body), { api_key: "new-key" })
    return { ok: true, json: async () => ({ name: "New tutor" }) }
  })
  controller.keyTarget.value = " new-key "
  await controller.lookup()
  assert.equal(controller.nameTarget.textContent, "New tutor")
})

test("ignores a delayed result after the key changes", async () => {
  let resolve
  const controller = editor(() => new Promise(done => { resolve = done }))
  controller.keyTarget.value = "first-key"
  const pending = controller.lookup()
  controller.keyTarget.value = "second-key"
  controller.changed()
  resolve({ ok: true, json: async () => ({ name: "Wrong tutor" }) })
  await pending
  assert.notEqual(controller.nameTarget.textContent, "Wrong tutor")
})

test("clearing a replacement key restores the saved name without a request", async () => {
  const controller = editor(() => assert.fail("must not fetch"))
  controller.changed()
  await controller.lookup()
  assert.equal(controller.nameTarget.textContent, "Saved tutor")
})

test("shows lookup failures and allows retry", async () => {
  let attempts = 0
  const controller = editor(async () => {
    attempts++
    return { ok: attempts > 1, json: async () => ({ name: "Tutor" }) }
  })
  controller.keyTarget.value = "key"
  await controller.lookup()
  assert.match(controller.nameTarget.textContent, /Could not look up/)
  await controller.lookup()
  assert.equal(controller.nameTarget.textContent, "Tutor")
})
