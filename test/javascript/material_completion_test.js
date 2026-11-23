// Runs without Rails: node --test test/javascript/material_completion_test.js
const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function setup(fetch, { window = {}, elementIds = [], elements = {} } = {}) {
  let Controller
  const context = {
    Controller: class {}, fetch, window, URL,
    document: {
      querySelector: () => ({ content: "csrf-token" }),
      createElement: () => ({ style: {}, setAttribute() {} }),
      getElementById: (id) => elements[id] ?? (elementIds.includes(id) ? {} : null)
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
  controller.dispatch = (event, options) => {
    controller.event = event
    controller.eventDetail = options?.detail
  }
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

function loadController(path, globals = {}) {
  const context = { Controller: class {}, URL, ...globals }
  vm.runInNewContext(fs.readFileSync(path, "utf8")
    .replace(/^import .*$/m, "")
    .replace("export default class", "globalThis.TestController = class"), context)
  return new context.TestController()
}

test("scroller uses the same completion request and records the completed slide", async () => {
  const completion = setup(async () => ({ ok: true, json: async () => ({ acknowledged: true, quiz_unlocked: true }) }))
  const scroller = loadController("app/javascript/controllers/material_scroller_controller.js")
  const slide = {
    dataset: { materialScrollerAcknowledgeUrl: "/materials/1/acknowledge" },
    querySelector: () => ({}),
    removeAttribute: () => { delete slide.dataset.materialScrollerAcknowledgeUrl }
  }
  scroller.slideTargets = [slide]
  scroller.currentIndex = 0
  scroller.application = { getControllerForElementAndIdentifier: () => completion }
  completion.dispatch = (_name, { detail }) => scroller.materialCompleted({ target: { closest: () => slide }, detail })

  assert.equal(await scroller.completeCurrentMaterial(), true)
  assert.equal(scroller.quizUnlocked, true)
  assert.equal(slide.dataset.materialScrollerAcknowledgeUrl, undefined)
  assert.equal(await scroller.completeCurrentMaterial(), false)
})

function lastSlideScroller({ quizUnlocked }) {
  const calls = { reloads: 0, finished: 0 }
  const window = {
    location: { href: "http://localhost/courses/algebra/lessons/1", reload: () => { calls.reloads += 1 } },
    sessionStorage: { setItem() {} },
    history: { replaceState() {} }
  }
  const scroller = loadController("app/javascript/controllers/material_scroller_controller.js", { window })
  scroller.slideTargets = [{}]
  scroller.currentIndex = 0
  scroller.nextTarget = {}
  scroller.leaveCurrentMaterial = () => {}
  scroller.clearStatus = () => {}
  scroller.updateControls = () => {}
  scroller.completeCurrentMaterial = async () => {
    if (quizUnlocked) scroller.quizUnlocked = true
    return true
  }
  scroller.finish = () => { calls.finished += 1 }
  return { scroller, calls }
}

test("scroller reloads the lesson on the last slide only when the quiz was unlocked", async () => {
  const { scroller, calls } = lastSlideScroller({ quizUnlocked: true })
  await scroller.next()
  assert.equal(calls.reloads, 1)
  assert.equal(calls.finished, 0)
})

test("scroller keeps an already-open quiz on the page after the last slide", async () => {
  const { scroller, calls } = lastSlideScroller({ quizUnlocked: false })
  await scroller.next()
  assert.equal(calls.reloads, 0)
  assert.equal(calls.finished, 1)
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

function turboWindow() {
  const visits = []
  return {
    visits,
    location: { href: "http://localhost/courses/algebra/lessons/1" },
    Turbo: { visit: (url, options) => visits.push({ url, options }) }
  }
}

function statusFrame(src = null) {
  const frame = {
    reloads: 0,
    attributes: src ? { src } : {},
    getAttribute: (name) => frame.attributes[name] ?? null,
    setAttribute: (name, value) => { frame.attributes[name] = value },
    reload: () => { frame.reloads += 1 }
  }
  return frame
}

const respond = (body) => async () => ({ ok: true, json: async () => ({ acknowledged: true, ...body }) })
const unlockResponse = respond({ quiz_unlocked: true, progress_changed: true })

test("stacked materials reload the lesson at the quiz when it unlocks", async () => {
  const window = turboWindow()
  const frame = statusFrame()
  const controller = setup(unlockResponse, { window, elementIds: ["lesson-quiz", "lesson-status"], elements: { "lesson-status-frame": frame } })
  controller.reloadOnQuizUnlockValue = true
  await controller.submit({ preventDefault() {} })
  assert.equal(window.visits.length, 1)
  assert.equal(window.visits[0].url, "http://localhost/courses/algebra/lessons/1#lesson-quiz")
  assert.equal(window.visits[0].options.action, "replace")
  assert.equal(frame.getAttribute("src"), null)
  assert.equal(controller.eventDetail.quizUnlocked, true)
})

test("a lesson without a quiz reloads at the lesson status", async () => {
  const window = turboWindow()
  const controller = setup(unlockResponse, { window, elementIds: ["lesson-status"] })
  controller.reloadOnQuizUnlockValue = true
  await controller.submit({ preventDefault() {} })
  assert.equal(window.visits[0].url, "http://localhost/courses/algebra/lessons/1#lesson-status")
})

test("progress without a quiz unlock refreshes only the status frame, keeping quiz answers", async () => {
  const window = turboWindow()
  window.location.href = "http://localhost/courses/algebra/lessons/1#lesson-quiz"
  const frame = statusFrame()
  const controller = setup(respond({ quiz_unlocked: false, progress_changed: true }), {
    window, elementIds: ["lesson-quiz"], elements: { "lesson-status-frame": frame }
  })
  controller.reloadOnQuizUnlockValue = true

  await controller.submit({ preventDefault() {} })
  assert.deepEqual(window.visits, [])
  assert.equal(frame.getAttribute("src"), "http://localhost/courses/algebra/lessons/1")
  assert.equal(frame.reloads, 0)
  assert.equal(controller.eventDetail.quizUnlocked, false)
})

test("a status frame already pointing at the lesson is reloaded", async () => {
  const frame = statusFrame("http://localhost/courses/algebra/lessons/1")
  const controller = setup(respond({ quiz_unlocked: false, progress_changed: true }), {
    window: turboWindow(), elements: { "lesson-status-frame": frame }
  })
  await controller.submit({ preventDefault() {} })
  assert.equal(frame.reloads, 1)
})

test("an acknowledgement that changes nothing leaves the page alone", async () => {
  const window = turboWindow()
  const frame = statusFrame()
  const controller = setup(respond({ quiz_unlocked: false, progress_changed: false }), {
    window, elementIds: ["lesson-quiz"], elements: { "lesson-status-frame": frame }
  })
  controller.reloadOnQuizUnlockValue = true
  await controller.submit({ preventDefault() {} })
  assert.equal(controller.event, "completed")
  assert.deepEqual(window.visits, [])
  assert.equal(frame.getAttribute("src"), null)
})

test("scroller slides leave the quiz reload to the scroller and refresh only the status", async () => {
  const window = turboWindow()
  const frame = statusFrame()
  const controller = setup(unlockResponse, { window, elementIds: ["lesson-quiz"], elements: { "lesson-status-frame": frame } })
  controller.reloadOnQuizUnlockValue = false
  await controller.submit({ preventDefault() {} })
  assert.deepEqual(window.visits, [])
  assert.equal(frame.getAttribute("src"), "http://localhost/courses/algebra/lessons/1")
  assert.equal(controller.eventDetail.quizUnlocked, true)
})
