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

function eventTarget() {
  const listeners = {}
  return {
    addEventListener: (type, fn) => { (listeners[type] ||= new Set()).add(fn) },
    removeEventListener: (type, fn) => { listeners[type]?.delete(fn) },
    dispatch: type => { for (const fn of listeners[type] || []) fn() },
    count: type => listeners[type]?.size || 0
  }
}

function controller() {
  const document = eventTarget()
  const form = eventTarget()
  const PasswordVisibility = vm.runInNewContext(source
    .replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.PasswordVisibility = class"), { Controller: class {}, document })
  const attributes = {}
  let focused = 0
  const instance = Object.assign(new PasswordVisibility(), {
    inputTarget: { type: "password", form, focus: () => { focused += 1 } },
    buttonTarget: { title: "", setAttribute: (name, value) => { attributes[name] = value } },
    showIconTarget: { classList: classList() },
    hideIconTarget: { classList: classList(["hidden"]) },
    showLabelValue: "Show password",
    hideLabelValue: "Hide password"
  })
  return { instance, attributes, document, form, focusCount: () => focused }
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

test("re-masks a revealed password before Turbo caches the page", () => {
  const { instance, attributes, document } = controller()
  instance.connect()
  instance.toggle()
  assert.equal(instance.inputTarget.type, "text")

  document.dispatch("turbo:before-cache")
  assert.equal(instance.inputTarget.type, "password")
  assert.equal(attributes["aria-pressed"], "false")
  assert.equal(instance.hideIconTarget.classList.contains("hidden"), true)
})

test("re-masks a revealed password when the form is submitted", () => {
  const { instance, form } = controller()
  instance.connect()
  instance.toggle()

  form.dispatch("submit")
  assert.equal(instance.inputTarget.type, "password")
})

test("removes its listeners on disconnect", () => {
  const { instance, document, form } = controller()
  instance.connect()
  assert.equal(document.count("turbo:before-cache"), 1)
  assert.equal(form.count("submit"), 1)

  instance.disconnect()
  assert.equal(document.count("turbo:before-cache"), 0)
  assert.equal(form.count("submit"), 0)
})
