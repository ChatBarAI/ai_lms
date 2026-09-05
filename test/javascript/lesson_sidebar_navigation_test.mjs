import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const controllerSource = readFileSync(new URL("../../app/javascript/controllers/lesson_sidebar_controller.js", import.meta.url), "utf8")
const scrollLockSource = readFileSync(new URL("../../app/javascript/controllers/scroll_lock.js", import.meta.url), "utf8")

function body() {
  const classes = new Set()
  return {
    classList: {
      toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) },
      remove(name) { classes.delete(name) },
      contains(name) { return classes.has(name) }
    }
  }
}

for (const desktop of [true, false]) {
  for (const newConnectsFirst of [true, false]) {
    test(`${desktop ? "desktop column" : "mobile drawer"}: outgoing cleanup ${newConnectsFirst ? "after" : "before"} incoming presentation`, () => {
      const oldBody = body()
      const newBody = body()
      const document = { body: oldBody, removeEventListener() {} }
      const context = vm.createContext({
        document,
        window: { matchMedia: () => ({ matches: desktop }), removeEventListener() {} },
        Controller: class {}
      })
      vm.runInContext(scrollLockSource.replaceAll("export function", "function"), context)
      const Sidebar = vm.runInContext(controllerSource
        .replace(/^import .*\n/gm, "")
        .replace("export default class", "globalThis.Sidebar = class"), context)
      const instance = element => Object.assign(new Sidebar(), {
        element,
        hasOverlayTarget: true,
        overlayTarget: { getAttribute: () => "false", setAttribute() {} }
      })
      const outgoing = instance(oldBody)
      const incoming = instance(newBody)
      outgoing.applyPresentation()
      document.body = newBody
      if (newConnectsFirst) incoming.applyPresentation()
      outgoing.disconnect()
      if (!newConnectsFirst) incoming.applyPresentation()

      assert.equal(newBody.classList.contains("lesson-sidebar-inline-active"), desktop)
      assert.equal(newBody.classList.contains("overflow-hidden"), !desktop)
      assert.equal(oldBody.classList.contains("lesson-sidebar-inline-active"), false)
      incoming.unlockPage()
      assert.equal(newBody.classList.contains("lesson-sidebar-inline-active"), false)
      assert.equal(newBody.classList.contains("overflow-hidden"), false)
    })
  }
}
