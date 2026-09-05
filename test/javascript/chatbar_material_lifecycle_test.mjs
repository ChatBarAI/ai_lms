import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

function loadController(name, context) {
  const source = readFileSync(new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url), "utf8")
  return vm.runInContext(source.replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.LoadedController = class"), context)
}

function setup() {
  const context = vm.createContext({
    Controller: class {},
    CustomEvent: class extends Event {},
    window: Object.assign(new EventTarget(), { cancelAnimationFrame() {}, requestAnimationFrame() {} })
  })
  const Chatbar = loadController("chatbar_material", context)
  const Scroller = loadController("material_scroller", context)
  const section = new EventTarget()
  const slide = new EventTarget()
  const chatbar = new Chatbar()
  let paused = false
  let stopped = false
  const media = { pause() { paused = true }, srcObject: { getTracks: () => [{ stop() { stopped = true } }] } }
  const classes = () => ({ add() {}, remove() {}, toggle() {} })
  chatbar.element = { closest: selector => selector.includes("collapsible") ? section : slide }
  chatbar.hasMountTarget = true
  chatbar.hasStartButtonTarget = true
  chatbar.mountTarget = {
    dataset: { initialised: "1" }, classList: classes(),
    querySelectorAll: () => [media],
    replaceChildren() { this.emptied = true }
  }
  chatbar.introTarget = { classList: classes() }
  chatbar.startButtonTarget = { disabled: true }
  chatbar.statusTarget = { classList: classes() }
  chatbar.connect()
  const scroller = new Scroller()
  scroller.currentIndex = 0
  scroller.slideTargets = [slide, new EventTarget()]
  scroller.updateControls = () => {}
  scroller.observeCurrentSlide = () => {}
  scroller.updateTrackHeight = () => {}
  scroller.trackTarget = { scrollLeft: 0, getBoundingClientRect: () => ({ left: 0 }), scrollTo() {} }
  scroller.slideTargets[1].getBoundingClientRect = () => ({ left: 800 })
  const assertUnloaded = () => {
    assert.equal(chatbar.active, false)
    assert.equal(chatbar.mountTarget.emptied, true)
    assert.equal(paused, true)
    assert.equal(stopped, true)
    assert.equal(media.srcObject, null)
  }
  return { chatbar, scroller, section, assertUnloaded }
}

test("collapsing a material unloads its avatar and restores the start button", () => {
  const state = setup()
  state.section.dispatchEvent(new Event("collapsible:collapsed"))
  state.assertUnloaded()
})

test("Next unloads immediately, before acknowledgement completes", async () => {
  const state = setup()
  let complete
  state.scroller.completeCurrentMaterial = () => new Promise(resolve => { complete = resolve })
  state.scroller.nextTarget = {}
  const next = state.scroller.next()
  state.assertUnloaded()
  complete(false)
  await next
  assert.equal(state.scroller.currentIndex, 1)
})

test("changing slides unloads the outgoing avatar", () => {
  const state = setup()
  state.scroller.goTo(1)
  state.assertUnloaded()
})

test("collapse cancels a pending script load", () => {
  const state = setup()
  delete state.chatbar.mountTarget.dataset.initialised
  const activationId = state.chatbar.activationId
  state.section.dispatchEvent(new Event("collapsible:collapsed"))
  assert.ok(state.chatbar.activationId > activationId)
  assert.equal(state.chatbar.startButtonTarget.disabled, false)
})
