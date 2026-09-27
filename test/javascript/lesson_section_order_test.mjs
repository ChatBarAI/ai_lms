import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/lesson_section_order_controller.js", import.meta.url), "utf8")
const context = vm.createContext({ Controller: class {} })
const SectionOrder = vm.runInContext(source
  .replace(/^import .*\n/gm, "")
  .replace("export default class", "globalThis.SectionOrder = class"), context)
const defaultOrder = ["introduction", "ai_tutor", "materials", "progress", "quiz_results", "quiz", "rating"]

function editor(order = defaultOrder) {
  const list = {
    children: [],
    insertBefore(item, reference) {
      if (item === reference) return
      this.children.splice(this.children.indexOf(item), 1)
      const index = reference ? this.children.indexOf(reference) : this.children.length
      this.children.splice(index, 0, item)
    },
    appendChild(item) { this.insertBefore(item, null) }
  }
  let focused
  list.children = order.map(key => {
    const classes = new Set()
    const item = {
      dataset: { sectionKey: key, sectionLabel: key },
      draggable: false,
      number: { textContent: "" },
      classList: {
        add: value => classes.add(value),
        remove: value => classes.delete(value),
        contains: value => classes.has(value)
      },
      closest() { return this },
      getBoundingClientRect: () => ({ top: 0, height: 40 }),
      get nextSibling() { return list.children[list.children.indexOf(this) + 1] || null },
      querySelector(selector) {
        if (selector === "[data-section-number]") return this.number
        return this.buttons[selector.includes("'up'") ? "up" : "down"]
      }
    }
    item.buttons = Object.fromEntries(["up", "down"].map(direction => [direction, {
      dataset: { direction },
      closest: () => item,
      focus() { focused = this }
    }]))
    return item
  })
  const controller = Object.assign(new SectionOrder(), {
    listTarget: list,
    statusTarget: { textContent: "" },
    defaultOrderValue: defaultOrder,
    movedMessageValue: "%{section}: position %{position} of %{count}.",
    resetMessageValue: "Default order restored. Save the lesson to apply it."
  })
  Object.defineProperty(controller, "itemTargets", { get: () => [...list.children] })
  controller.connect()
  return {
    controller,
    order: () => list.children.map(item => item.dataset.sectionKey),
    row: key => list.children.find(item => item.dataset.sectionKey === key),
    focused: () => focused,
    move(key, direction) { controller.move({ currentTarget: this.row(key).buttons[direction] }) }
  }
}

function dragEvent(target, clientY = 0) {
  return {
    target,
    currentTarget: target,
    clientY,
    preventDefault() { this.prevented = true },
    dataTransfer: { setData() {} }
  }
}

test("arrow controls move Progress to the top and AI Tutor to the bottom", () => {
  const ui = editor()
  for (let index = 0; index < 3; index++) ui.move("progress", "up")
  for (let index = 0; index < 5; index++) ui.move("ai_tutor", "down")

  assert.deepEqual(ui.order(), ["progress", "introduction", "materials", "quiz_results", "quiz", "rating", "ai_tutor"])
  assert.equal(ui.row("progress").buttons.up.disabled, true)
  assert.equal(ui.row("ai_tutor").buttons.down.disabled, true)
  assert.equal(ui.focused(), ui.row("ai_tutor").buttons.up)
  assert.equal(ui.controller.statusTarget.textContent, "ai_tutor: position 7 of 7.")
  assert.deepEqual(ui.controller.itemTargets.map(item => item.number.textContent), ["1.", "2.", "3.", "4.", "5.", "6.", "7."])

  ui.move("progress", "up")
  ui.move("ai_tutor", "down")
  assert.equal(ui.order()[0], "progress")
  assert.equal(ui.order()[6], "ai_tutor")
})

test("reset restores the default order after editing a saved custom layout", () => {
  const ui = editor([...defaultOrder].reverse())
  ui.controller.reset()

  assert.deepEqual(ui.order(), defaultOrder)
  assert.equal(ui.row("introduction").buttons.up.disabled, true)
  assert.equal(ui.row("rating").buttons.down.disabled, true)
  assert.match(ui.controller.statusTarget.textContent, /Default order restored/)
})

test("dropping a dragged row commits its position and clears drag state", () => {
  const ui = editor()
  const progress = ui.row("progress")
  ui.controller.armDrag(dragEvent(progress))
  ui.controller.startDrag(dragEvent(progress))
  ui.controller.dragOver(dragEvent(ui.row("introduction")))
  ui.controller.drop(dragEvent(ui.row("introduction")))
  ui.controller.endDrag()

  assert.deepEqual(ui.order(), ["progress", "introduction", "ai_tutor", "materials", "quiz_results", "quiz", "rating"])
  assert.equal(progress.draggable, false)
  assert.equal(progress.classList.contains("opacity-50"), false)
  assert.equal(ui.controller.statusTarget.textContent, "progress: position 1 of 7.")
})

test("a cancelled drag restores the order from before dragging", () => {
  const ui = editor()
  const tutor = ui.row("ai_tutor")
  ui.controller.armDrag(dragEvent(tutor))
  ui.controller.startDrag(dragEvent(tutor))
  ui.controller.dragOver(dragEvent(ui.row("rating"), 30))
  assert.equal(ui.order().at(-1), "ai_tutor")
  ui.controller.endDrag()

  assert.deepEqual(ui.order(), defaultOrder)
  assert.equal(tutor.draggable, false)
  assert.equal(tutor.classList.contains("opacity-50"), false)
})

test("disconnect cancels an active drag and reconnect keeps the controls usable", () => {
  const ui = editor()
  const progress = ui.row("progress")
  ui.controller.armDrag(dragEvent(progress))
  ui.controller.startDrag(dragEvent(progress))
  ui.controller.dragOver(dragEvent(ui.row("introduction")))
  ui.controller.disconnect()
  ui.controller.connect()
  ui.move("progress", "up")

  assert.deepEqual(ui.order(), ["introduction", "ai_tutor", "progress", "materials", "quiz_results", "quiz", "rating"])
  assert.equal(progress.draggable, false)
})

test("dragging requires the handle and releasing it without dragging disarms the row", () => {
  const ui = editor()
  const progress = ui.row("progress")
  const event = dragEvent(progress)
  ui.controller.startDrag(event)
  assert.equal(event.prevented, true)
  assert.deepEqual(ui.order(), defaultOrder)

  ui.controller.armDrag(dragEvent(progress))
  ui.controller.disarmDrag()
  assert.equal(progress.draggable, false)
})
