import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/chatbar_material_controller.js", import.meta.url), "utf8")

function setup() {
  const listeners = new Map()
  const frames = new Map()
  const scrolls = []
  let observer
  let frameId = 0
  const context = vm.createContext({
    Controller: class {},
    ResizeObserver: class {
      constructor(callback) { this.callback = callback; observer = this }
      observe() {}
      disconnect() { this.disconnected = true }
    },
    window: {
      innerHeight: 800, innerWidth: 1200,
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: name => listeners.delete(name),
      requestAnimationFrame: callback => { frames.set(++frameId, callback); return frameId },
      cancelAnimationFrame: id => frames.delete(id),
      scrollBy: options => scrolls.push(options.top)
    }
  })
  const Chatbar = vm.runInContext(source.replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.Chatbar = class"), context)
  const controller = new Chatbar()
  const rect = { top: 500, bottom: 700, height: 200, left: 0, right: 800 }
  controller.mountTarget = { dataset: { initialised: "1" }, getBoundingClientRect: () => rect }
  controller.startViewportTracking()
  const flush = () => {
    const pending = [...frames.values()]
    frames.clear()
    pending.forEach(callback => callback())
  }
  return { controller, rect, scrolls, listeners, frames, observer, flush }
}

test("size changes reveal the bottom with minimal scrolling and no recurring frames", () => {
  const state = setup()
  state.flush()
  assert.deepEqual(state.scrolls, [])
  Object.assign(state.rect, { height: 500, bottom: 1000 })
  state.observer.callback()
  state.flush()
  assert.deepEqual(state.scrolls, [216])
  assert.equal(state.frames.size, 0)
})

test("a mount taller than the viewport aligns its top", () => {
  const state = setup()
  Object.assign(state.rect, { height: 1000, bottom: 1500 })
  state.flush()
  assert.deepEqual(state.scrolls, [484])
})

for (const interaction of ["wheel", "touchstart", "pointerdown", "keydown"]) {
  test(`${interaction} stops adjustment and cancels pending work`, () => {
    const state = setup()
    state.listeners.get(interaction)({ key: "PageDown" })
    state.flush()
    assert.deepEqual(state.scrolls, [])
    assert.equal(state.observer.disconnected, true)
    assert.equal(state.listeners.size, 0)
    assert.equal(state.frames.size, 0)
  })
}

test("disconnect releases viewport tracking", () => {
  const state = setup()
  state.controller.disconnect()
  assert.equal(state.observer.disconnected, true)
  assert.equal(state.listeners.size, 0)
  assert.equal(state.frames.size, 0)
})
