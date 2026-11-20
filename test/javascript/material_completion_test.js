// Runs without Rails: node --test test/javascript/material_completion_test.js
const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function setup(fetch) {
  let Controller
  const context = {
    Controller: class {}, fetch,
    document: {
      querySelector: () => ({ content: "csrf-token" }),
      createElement: () => ({ style: {}, setAttribute() {} })
    }
  }
  const source = fs.readFileSync("app/javascript/controllers/material_completion_controller.js", "utf8")
    .replace(/^import .*$/m, "")
    .replace("export default class", "globalThis.MaterialCompletion = class")
  vm.runInNewContext(source, context)
  Controller = context.MaterialCompletion
  const controller = new Controller()
  controller.hasFormTarget = true
  controller.formTarget = {
    action: "/materials/1/acknowledge",
    getBoundingClientRect: () => ({ height: 36 }),
    replaceWith: (element) => {
      controller.completed = element
      controller.hasFormTarget = false
    }
  }
  controller.buttonTarget = { disabled: false }
  controller.statusTarget = { textContent: "" }
  controller.completedValue = "✓ Marked as complete"
  controller.errorValue = "Please try again."
  controller.dispatch = (event) => { controller.event = event }
  return controller
}

test("completion posts JSON with CSRF protection and replaces only the form", async () => {
  let prevented = false
  const controller = setup(async (url, options) => {
    assert.equal(url, "/materials/1/acknowledge")
    assert.equal(options.method, "POST")
    assert.equal(options.headers.Accept, "application/json")
    assert.equal(options.headers["X-CSRF-Token"], "csrf-token")
    assert.equal(options.credentials, "same-origin")
    return { ok: true, json: async () => ({ acknowledged: true }) }
  })
  await controller.submit({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(controller.completed.textContent, "✓ Marked as complete")
  assert.equal(controller.completed.style.minHeight, "36px")
  assert.equal(controller.event, "completed")
})

test("failed and unconfirmed responses keep the button available for retry", async () => {
  for (const fetch of [
    async () => ({ ok: false, status: 422 }),
    async () => ({ ok: true, json: async () => ({ acknowledged: false }) }),
    async () => { throw new Error("offline") }
  ]) {
    const controller = setup(fetch)
    await controller.submit({ preventDefault() {} })
    assert.equal(controller.completed, undefined)
    assert.equal(controller.event, undefined)
    assert.equal(controller.statusTarget.textContent, "Please try again.")
    assert.equal(controller.buttonTarget.disabled, false)
    assert.equal(controller.completionRequest, null)
  }
})

test("button and scroller completion share one pending request", async () => {
  let resolve, requests = 0
  const controller = setup(() => {
    requests++
    return new Promise((done) => { resolve = done })
  })
  const first = controller.submit({ preventDefault() {} })
  const scrollerCompletion = controller.complete()
  assert.equal(controller.buttonTarget.disabled, true)
  assert.equal(requests, 1)
  resolve({ ok: true, json: async () => ({ acknowledged: true }) })
  await first
  assert.equal(await scrollerCompletion, true)
  assert.equal(controller.event, "completed")
  assert.equal(await controller.complete(), false)
  assert.equal(requests, 1)
})

test("a failed request can be retried successfully", async () => {
  let requests = 0
  const controller = setup(async () => {
    requests++
    return { ok: requests > 1, status: 503, json: async () => ({ acknowledged: true }) }
  })
  await controller.submit({ preventDefault() {} })
  assert.equal(controller.statusTarget.textContent, "Please try again.")
  await controller.submit({ preventDefault() {} })
  assert.equal(requests, 2)
  assert.equal(controller.statusTarget.textContent, "")
  assert.equal(controller.event, "completed")
})

function loadController(path) {
  const context = { Controller: class {} }
  vm.runInNewContext(fs.readFileSync(path, "utf8")
    .replace(/^import .*$/m, "")
    .replace("export default class", "globalThis.TestController = class"), context)
  return new context.TestController()
}

test("scroller uses the same completion request and records the completed slide", async () => {
  const completion = setup(async () => ({ ok: true, json: async () => ({ acknowledged: true }) }))
  const scroller = loadController("app/javascript/controllers/material_scroller_controller.js")
  const slide = {
    dataset: { materialScrollerAcknowledgeUrl: "/materials/1/acknowledge" },
    querySelector: () => ({}),
    removeAttribute: () => { delete slide.dataset.materialScrollerAcknowledgeUrl }
  }
  scroller.slideTargets = [slide]
  scroller.currentIndex = 0
  scroller.application = { getControllerForElementAndIdentifier: () => completion }
  completion.dispatch = () => scroller.materialCompleted({ target: { closest: () => slide } })

  assert.equal(await scroller.completeCurrentMaterial(), true)
  assert.equal(scroller.completionChanged, true)
  assert.equal(slide.dataset.materialScrollerAcknowledgeUrl, undefined)
  assert.equal(await scroller.completeCurrentMaterial(), false)
})

test("completion collapses the material through the existing persisted state mechanism", () => {
  const collapsible = loadController("app/javascript/controllers/collapsible_controller.js")
  const classes = new Set()
  collapsible.contentTarget = { classList: { add: (value) => classes.add(value) } }
  collapsible.hasIconTarget = false
  let event, saved = false
  collapsible.dispatch = (value) => { event = value }
  collapsible.saveState = () => { saved = classes.has("hidden") }
  collapsible.complete()
  assert.equal(classes.has("hidden"), true)
  assert.equal(event, "collapsed")
  assert.equal(saved, true)
})
