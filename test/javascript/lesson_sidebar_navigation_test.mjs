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

function progressElement(key, label) {
  const element = {
    dataset: { lessonSidebarProgress: key },
    label,
    replaceWith(next) { element.replacedBy = next }
  }
  return element
}

function sidebarForProgress(incomingElements) {
  const parsedFrom = []
  const context = vm.createContext({
    document: { importNode: (node) => ({ ...node, imported: true }) },
    DOMParser: class {
      parseFromString(html) {
        parsedFrom.push(html)
        return { getElementById: (id) => (id === "lesson-course-sidebar" ? { querySelectorAll: () => incomingElements } : null) }
      }
    },
    Controller: class {}
  })
  const Sidebar = vm.runInContext(controllerSource
    .replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.Sidebar = class"), context)
  const course = progressElement("course", "old course")
  const lesson = progressElement("lesson-7", "old lesson")
  const sidebar = Object.assign(new Sidebar(), {
    overlayTarget: { id: "lesson-course-sidebar" },
    panelTarget: { querySelectorAll: () => [course, lesson] }
  })
  return { sidebar, course, lesson, parsedFrom }
}

const frameRender = (id, html = "<html></html>") => ({
  target: { id },
  detail: { fetchResponse: { responseHTML: Promise.resolve(html) } }
})

test("a lesson status frame refresh updates the sidebar's course and lesson progress in place", async () => {
  const { sidebar, course, lesson } = sidebarForProgress([
    progressElement("course", "new course"),
    progressElement("lesson-7", "new lesson")
  ])

  await sidebar.refreshProgress(frameRender("lesson-status-frame"))

  assert.equal(course.replacedBy.label, "new course")
  assert.equal(course.replacedBy.imported, true)
  assert.equal(lesson.replacedBy.label, "new lesson")
})

test("other frame renders leave the sidebar alone", async () => {
  const { sidebar, course, parsedFrom } = sidebarForProgress([progressElement("course", "new course")])

  await sidebar.refreshProgress(frameRender("some-other-frame"))

  assert.equal(course.replacedBy, undefined)
  assert.deepEqual(parsedFrom, [])
})
