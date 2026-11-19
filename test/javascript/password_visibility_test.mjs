import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/password_visibility_controller.js", import.meta.url), "utf8")

function classList(initial = []) {
  const classes = new Set(initial)
  return {
    toggle: (name, force) => (force ? classes.add(name) : classes.delete(name)),
    contains: name => classes.has(name)
  }
}

function controller() {
  const PasswordVisibility = vm.runInNewContext(source
    .replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.PasswordVisibility = class"), { Controller: class {} })
  const attributes = {}
  let focused = 0
  const instance = Object.assign(new PasswordVisibility(), {
    inputTarget: { type: "password", focus: () => { focused += 1 } },
    buttonTarget: { title: "", setAttribute: (name, value) => { attributes[name] = value } },
    showIconTarget: { classList: classList() },
    hideIconTarget: { classList: classList(["hidden"]) },
    showLabelValue: "Show password",
    hideLabelValue: "Hide password"
  })
  return { instance, attributes, focusCount: () => focused }
}

test("starts hidden with a show label", () => {
  const { instance, attributes } = controller()
  instance.connect()
  assert.equal(instance.inputTarget.type, "password")
  assert.equal(attributes["aria-pressed"], "false")
  assert.equal(attributes["aria-label"], "Show password")
  assert.equal(instance.showIconTarget.classList.contains("hidden"), false)
  assert.equal(instance.hideIconTarget.classList.contains("hidden"), true)
})

test("toggle reveals then hides the password and keeps focus in the field", () => {
  const { instance, attributes, focusCount } = controller()
  instance.connect()

  instance.toggle()
  assert.equal(instance.inputTarget.type, "text")
  assert.equal(attributes["aria-pressed"], "true")
  assert.equal(attributes["aria-label"], "Hide password")
  assert.equal(instance.buttonTarget.title, "Hide password")
  assert.equal(instance.showIconTarget.classList.contains("hidden"), true)
  assert.equal(instance.hideIconTarget.classList.contains("hidden"), false)

  instance.toggle()
  assert.equal(instance.inputTarget.type, "password")
  assert.equal(attributes["aria-label"], "Show password")
  assert.equal(focusCount(), 2)
})
