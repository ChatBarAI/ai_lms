import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/collapsible_controller.js", import.meta.url), "utf8")

function controller({ storage = new Map(), key = "material-expanded:1:10", expanded = true } = {}) {
  const Controller = vm.runInNewContext(source
    .replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.Collapsible = class"), {
    Controller: class {},
    window: { localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value)
    } }
  })
  const classes = new Set()
  return Object.assign(new Controller(), {
    element: { dataset: { expanded: String(expanded) } },
    hasStorageKeyValue: Boolean(key),
    storageKeyValue: key,
    contentTarget: { classList: {
      add: name => classes.add(name),
      remove: name => classes.delete(name),
      contains: name => classes.has(name)
    } },
    hasIconTarget: false,
    dispatch() {}
  })
}

const isOpen = instance => !instance.contentTarget.classList.contains("hidden")

for (const expanded of [true, false]) {
  test(`uses configured default ${expanded} without saving a user choice`, () => {
    const storage = new Map()
    const instance = controller({ storage, expanded })
    instance.connect()
    assert.equal(isOpen(instance), expanded)
    assert.equal(storage.size, 0)
  })

  test(`restores user choice over default ${expanded} after reconnect and return visit`, () => {
    const storage = new Map()
    const instance = controller({ storage, expanded })
    instance.connect()
    instance.toggle()
    instance.connect()
    assert.equal(isOpen(instance), !expanded)
    const returning = controller({ storage, expanded })
    returning.connect()
    assert.equal(isOpen(returning), !expanded)
    returning.toggle()
    assert.equal(isOpen(returning), expanded)
    assert.equal(storage.get(returning.storageKeyValue), String(expanded))
  })
}

test("keeps choices separate for different users, guests and materials", () => {
  const storage = new Map()
  const first = controller({ storage })
  first.connect()
  first.toggle()
  for (const key of ["material-expanded:2:10", "material-expanded:guest:10", "material-expanded:1:11"]) {
    const other = controller({ storage, key })
    other.connect()
    assert.equal(isOpen(other), true)
  }
})

test("other collapsibles do not read or write browser state", () => {
  const storage = new Map([["", "true"]])
  const instance = controller({ storage, key: "", expanded: false })
  instance.connect()
  assert.equal(isOpen(instance), false)
  instance.toggle()
  instance.toggle()
  assert.equal(storage.get(""), "true")
})

test("invalid saved values fall back to the material default", () => {
  const storage = new Map([["material-expanded:1:10", "invalid"]])
  const instance = controller({ storage })
  instance.connect()
  assert.equal(isOpen(instance), true)
})

test("blocked storage does not prevent opening or closing materials", () => {
  const storage = {
    get() { throw new Error("Storage blocked") },
    set() { throw new Error("Storage blocked") }
  }
  const instance = controller({ storage })
  instance.connect()
  assert.equal(isOpen(instance), true)
  instance.toggle()
  assert.equal(isOpen(instance), false)
  instance.toggle()
  assert.equal(isOpen(instance), true)
})
